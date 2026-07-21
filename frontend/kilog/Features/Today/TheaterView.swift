import SwiftUI
import AVKit
import Combine
import AVFoundation
import UIKit
import Foundation

/// 위(나)/아래(파트너) 두 줄로 하루를 연속 재생하는 플레이어 — JSX theater 이식
@MainActor
final class TheaterModel: ObservableObject {
    @Published var segments: [Segment] = []
    @Published var index = 0
    @Published var playing = true
    /// 오늘 클립을 전부 봤을 때: 새 영상 올려달라는 안내 표시
    @Published var showUploadPrompt = false

    let topPlayer = AVPlayer()
    let bottomPlayer = AVPlayer()

    private var durations: [UUID: Double] = [:]   // clipId → 실제 영상 길이(초)
    private var itemCache: [UUID: AVPlayerItem] = [:]
    private var advanceTask: Task<Void, Never>?
    /// 이미 본 클립 id — 다음에 열 때 안 본 것부터 재생
    private var watched: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: "kilog.watchedClips") ?? [])

    var topUserId: UUID?
    var bottomUserId: UUID?

    var currentDuration: Double {
        guard index < segments.count else { return Timeline.defaultSegmentSec }
        return Timeline.duration(of: segments[index], durations: durations)
    }

    func update(
        clips: [TaggedClip], topUserId: UUID?, bottomUserId: UUID?,
        localFiles: [UUID: URL] = [:]
    ) {
        self.topUserId = topUserId
        self.bottomUserId = bottomUserId
        let next = Timeline.buildSegments(clips)
        // 클립 구성이 실제로 바뀌었을 때만 리셋 (캐시가 새로 생긴 경우는 반영)
        let old = segments.map(\.clips).map { Set($0.values.map(\.id)) }
        let new = next.map(\.clips).map { Set($0.values.map(\.id)) }
        let newCache = clips.contains { itemCache[$0.id] == nil && localFiles[$0.id] != nil }
        guard old != new || newCache else { return }
        let compositionChanged = old != new
        segments = next

        if compositionChanged {
            // 지난 클립 id는 정리 (클립은 7일 뒤 삭제되므로 오늘 것만 유지)
            let todayIds = Set(next.flatMap { $0.clips.values.map(\.id.uuidString) })
            watched.formIntersection(todayIds)
            persistWatched()

            if allClipsWatched {
                // 전부 본 상태로 열림 → 빈 슬레이트 (왼쪽 탭이 마지막 영상으로 가도록 index는 끝에)
                index = max(0, segments.count - 1)
                playing = false
                showUploadPrompt = true
            } else {
                // 안 본 첫 세그먼트부터
                index = firstUnwatchedIndex ?? 0
                if showUploadPrompt { playing = true }   // 안내 중 새 클립 도착 → 바로 재생
                showUploadPrompt = false
            }
        } else {
            index = min(index, max(0, segments.count - 1))
        }
        Task { await preload(clips: clips, localFiles: localFiles) }
        schedule()
    }

    // ── 시청 기록 ─────────────────────────────────────────
    private var allClipsWatched: Bool {
        let ids = segments.flatMap { $0.clips.values.map(\.id.uuidString) }
        return !ids.isEmpty && ids.allSatisfy(watched.contains)
    }

    private var firstUnwatchedIndex: Int? {
        segments.firstIndex {
            $0.clips.values.contains { !watched.contains($0.id.uuidString) }
        }
    }

    private func persistWatched() {
        UserDefaults.standard.set(Array(watched), forKey: "kilog.watchedClips")
    }

    // ── 좌/우 탭 이동 ─────────────────────────────────────
    /// 빈 슬레이트(다 본 상태)에서 왼쪽 탭 → 마지막 영상 다시, 오른쪽 탭 → 처음부터
    func next() {
        if showUploadPrompt { go(to: 0); return }
        go(to: index + 1)
    }

    func previous() {
        if showUploadPrompt {
            showUploadPrompt = false
            playing = true
            schedule()
            return
        }
        go(to: index - 1)
    }

    private func go(to i: Int) {
        guard !segments.isEmpty else { return }
        index = (i + segments.count) % segments.count
        playing = true
        showUploadPrompt = false
        schedule()
    }

    /// 새 클립 저장 직후: 해당 세그먼트로 점프
    func jump(to clipId: UUID) {
        if let i = segments.firstIndex(where: { $0.clips.values.contains { $0.id == clipId } }) {
            index = i
            playing = true
            showUploadPrompt = false
            schedule()
        }
    }

    func togglePlay() {
        playing.toggle()
        if playing { schedule() } else { pauseAll() }
    }

    private func pauseAll() {
        advanceTask?.cancel()
        topPlayer.pause()
        bottomPlayer.pause()
    }

    /// 현재 세그먼트 로드/재생 후 duration 뒤 다음 세그먼트로
    func schedule() {
        advanceTask?.cancel()
        guard playing, !segments.isEmpty, index < segments.count else { return }

        applyTrack(player: topPlayer, userId: topUserId)
        applyTrack(player: bottomPlayer, userId: bottomUserId)

        // 지금 보고 있는 세그먼트의 클립은 시청 처리
        for clip in segments[index].clips.values {
            watched.insert(clip.id.uuidString)
        }
        persistWatched()

        let duration = currentDuration
        advanceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, !Task.isCancelled else { return }
            let nextIndex = (self.index + 1) % max(1, self.segments.count)
            if nextIndex == 0, self.allClipsWatched {
                // 한 바퀴 다 봤음 → 새 영상 올려달라는 안내
                self.playing = false
                self.topPlayer.pause()
                self.bottomPlayer.pause()
                self.showUploadPrompt = true
            } else {
                self.index = nextIndex
                self.schedule()
            }
        }
    }

    private func applyTrack(player: AVPlayer, userId: UUID?) {
        guard let userId else { player.replaceCurrentItem(with: nil); return }
        let side = Timeline.sideAt(segments, index: index, userId: userId)
        guard let clip = side.clip, clip.clip.videoKey != nil,
              let item = itemCache[clip.id] else {
            player.replaceCurrentItem(with: nil)
            return
        }
        if player.currentItem !== item {
            player.replaceCurrentItem(with: item)
        }
        player.isMuted = true
        if side.active {
            player.seek(to: .zero)
            player.play()
        } else {
            player.pause()
        }
    }

    /// AVPlayerItem 준비 + 실제 길이 로드.
    /// 스플래시에서 받아둔 로컬 캐시가 있으면 그걸 사용해 즉시 재생.
    private func preload(clips: [TaggedClip], localFiles: [UUID: URL]) async {
        for clip in clips {
            guard clip.clip.videoKey != nil, itemCache[clip.id] == nil else { continue }
            do {
                let url: URL
                if let local = localFiles[clip.id] {
                    url = local
                } else if let key = clip.clip.videoKey {
                    url = try await ClipService.signedVideoURL(for: key)
                } else {
                    continue
                }
                let asset = AVURLAsset(url: url)
                itemCache[clip.id] = AVPlayerItem(asset: asset)
                if let seconds = try? await asset.load(.duration).seconds,
                   seconds.isFinite, seconds > 0 {
                    durations[clip.id] = seconds
                }
            } catch {
                // 로드 실패 시 캡션 placeholder로 표시
            }
        }
        // 새 아이템이 준비되면 현재 세그먼트 다시 적용
        schedule()
    }
}

struct TheaterView: View {
    @EnvironmentObject private var app: AppState
    @ObservedObject var model: TheaterModel
    var onCapture: () -> Void = {}

    var body: some View {
        GeometryReader { geo in
            let stripH = (geo.size.height - 6) / 2
            ZStack {
                // 멤버 카드 두 장 (레퍼런스처럼 분리된 라운드 카드)
                VStack(spacing: 6) {
                    strip(userId: model.topUserId, player: model.topPlayer, height: stripH)
                    strip(userId: model.bottomUserId, player: model.bottomPlayer, height: stripH)
                }

                if !model.playing, !model.showUploadPrompt, !model.segments.isEmpty {
                    Image(systemName: "play.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(radius: 12)
                }

                // 진행 바
                VStack {
                    Spacer()
                    progressBar
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                }

                // 탭 존: 왼쪽 = 이전 · 중앙 = 재생/일시정지 · 오른쪽 = 다음
                if !model.segments.isEmpty {
                    HStack(spacing: 0) {
                        Color.clear.contentShape(Rectangle())
                            .onTapGesture { model.previous() }
                        Color.clear.contentShape(Rectangle())
                            .frame(width: geo.size.width * 0.34)
                            .onTapGesture { model.togglePlay() }
                        Color.clear.contentShape(Rectangle())
                            .onTapGesture { model.next() }
                    }
                }

                // 카드 위 알약 버튼 (탭 존보다 위 레이어)
                VStack(spacing: 6) {
                    cardActions(userId: model.topUserId, height: stripH)
                    cardActions(userId: model.bottomUserId, height: stripH)
                }
            }
        }
        .aspectRatio(4 / 5, contentMode: .fit)
        .background(Color(hex: "#101016"))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    // ── 카드별 액션 알약 ──────────────────────────────────
    /// 내 카드: 내 영상이 없는 자리(워터마크 아래)나 다 본 뒤 빈 슬레이트에 "눌러서 촬영"
    @ViewBuilder
    private func cardActions(userId: UUID?, height: CGFloat) -> some View {
        let isMe = userId != nil && userId == app.myId
        let myClipMissing: Bool = {
            guard let userId, model.index < model.segments.count else {
                return model.segments.isEmpty
            }
            return model.segments[model.index].clips[userId] == nil
        }()

        ZStack {
            if isMe, model.showUploadPrompt || myClipMissing {
                pill("눌러서 촬영") { onCapture() }
                    .offset(y: model.showUploadPrompt ? 0 : 18)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    private func pill(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 20).padding(.vertical, 11)
                .background(.white.opacity(0.14))
                .background(.black.opacity(0.5))
                .clipShape(Capsule())
        }
    }

    // ── 멤버 카드 한 장 ───────────────────────────────────
    @ViewBuilder
    private func strip(userId: UUID?, player: AVPlayer, height: CGFloat) -> some View {
        let side: (clip: TaggedClip?, active: Bool) = {
            guard let userId, model.index < model.segments.count else { return (nil, false) }
            return Timeline.sideAt(model.segments, index: model.index, userId: userId)
        }()
        let member = userId.flatMap { app.member(for: $0) }
        let timeLabel = model.index < model.segments.count
            ? model.segments[model.index].timeLabel : nil

        ZStack {
            Color(hex: "#17171f")

            if model.showUploadPrompt {
                // 다 본 뒤의 빈 슬레이트 — 아무것도 그리지 않음 (내 카드엔 알약만)
                EmptyView()
            } else if let clip = side.clip, clip.clip.videoKey != nil {
                PlayerLayerView(player: player)
                    .opacity(side.active ? 1 : 0.45)

                // 시간 + 캡션 — 영상 정중앙 (시간은 각자 클립의 실제 촬영 시각)
                VStack(spacing: 5) {
                    Text(clip.recordedAt,
                         format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())
                        .font(.system(size: 11.5, weight: .bold))
                        .kerning(0.8)
                        .foregroundStyle(.white.opacity(0.8))
                    Text(clip.caption)
                        .font(.system(size: 15, weight: .bold))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .foregroundStyle(.white)
                }
                .shadow(color: .black.opacity(0.85), radius: 7)
                .padding(.horizontal, 16)
                .opacity(side.active ? 1 : 0.5)
            } else if let clip = side.clip {
                VStack(spacing: 5) {
                    Text(clip.recordedAt,
                         format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())
                        .font(.system(size: 11, weight: .bold))
                        .kerning(0.8)
                        .foregroundStyle(Theme.faint)
                    Text(clip.caption)
                        .font(.system(size: 13, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .foregroundStyle(side.active ? Theme.text : Theme.faint)
                }
                .padding(14)
            } else if let timeLabel {
                // 빈 자리: 시간 워터마크 (레퍼런스의 14:00 느낌)
                Text(timeLabel)
                    .font(.system(size: 38, weight: .heavy))
                    .kerning(2)
                    .foregroundStyle(.white.opacity(0.1))
                    .offset(y: -16)
            }

            // 헤더 (좌상단 아바타+이름) · kcal (우상단)
            VStack {
                HStack {
                    if let member {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(Color(hex: member.colorHex))
                                .frame(width: 22, height: 22)
                                .overlay(Text(member.initial)
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundStyle(Color(hex: "#101016")))
                            Text(member.displayName)
                                .font(.system(size: 11.5, weight: .bold))
                                .kerning(0.4)
                                .foregroundStyle(.white.opacity(0.88))
                                .shadow(color: .black.opacity(0.7), radius: 5)
                        }
                    }
                    Spacer()
                    if !model.showUploadPrompt, side.active, let tag = side.clip?.tag {
                        Text("\(tag.isMove ? "−" : "+")\(tag.kcal)")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(tag.isMove ? Theme.green : .white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.black.opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(10)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(Array(model.segments.enumerated()), id: \.element.id) { i, _ in
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(
                            model.showUploadPrompt || i < model.index ? 0.85 : 0.28))
                        if i == model.index, !model.showUploadPrompt {
                            SegmentFillBar(duration: model.currentDuration,
                                           playing: model.playing,
                                           width: geo.size.width)
                        }
                    }
                }
                .frame(height: 3)
            }

            // 빈 슬레이트(눌러서 촬영) 칸 — 항상 +1
            if !model.segments.isEmpty {
                Capsule()
                    .fill(.white.opacity(model.showUploadPrompt ? 0.85 : 0.28))
                    .frame(height: 3)
            }
        }
    }
}

/// 현재 세그먼트 진행 애니메이션 바
private struct SegmentFillBar: View {
    let duration: Double
    let playing: Bool
    let width: CGFloat
    @State private var progress: CGFloat = 0

    var body: some View {
        Capsule()
            .fill(.white)
            .frame(width: width * progress)
            .onAppear { animate() }
            .onChange(of: playing) { animate() }
    }

    private func animate() {
        progress = 0
        guard playing else { progress = 0.4; return }
        withAnimation(.linear(duration: duration)) { progress = 1 }
    }
}

/// AVPlayerLayer 래퍼 — VideoPlayer는 컨트롤이 붙어서 직접 래핑.
/// gravity: .resizeAspectFill(꽉 채움·크롭) 또는 .resizeAspect(전체 보임·레터박스)
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    var gravity: AVLayerVideoGravity = .resizeAspectFill

    final class LayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = gravity
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
        view.playerLayer.videoGravity = gravity
    }
}
