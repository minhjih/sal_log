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

    let topPlayer = AVPlayer()
    let bottomPlayer = AVPlayer()

    private var durations: [UUID: Double] = [:]   // clipId → 실제 영상 길이(초)
    private var itemCache: [UUID: AVPlayerItem] = [:]
    private var advanceTask: Task<Void, Never>?

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
        segments = next
        index = min(index, max(0, segments.count - 1))
        Task { await preload(clips: clips, localFiles: localFiles) }
        schedule()
    }

    /// 새 클립 저장 직후: 해당 세그먼트로 점프
    func jump(to clipId: UUID) {
        if let i = segments.firstIndex(where: { $0.clips.values.contains { $0.id == clipId } }) {
            index = i
            playing = true
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

        let duration = currentDuration
        advanceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, !Task.isCancelled else { return }
            self.index = (self.index + 1) % max(1, self.segments.count)
            self.schedule()
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

    var body: some View {
        GeometryReader { geo in
            let stripH = geo.size.height / 2
            ZStack {
                VStack(spacing: 0) {
                    strip(userId: model.topUserId, player: model.topPlayer, height: stripH)
                    strip(userId: model.bottomUserId, player: model.bottomPlayer, height: stripH)
                }

                // 중앙 이음선 (시그니처 그라데이션)
                Rectangle()
                    .fill(Theme.duo)
                    .frame(height: 2)

                // 시간 칩
                if model.index < model.segments.count {
                    VStack {
                        Text(model.segments[model.index].timeLabel)
                            .font(.system(size: 11.5, weight: .bold))
                            .kerning(0.8)
                            .padding(.horizontal, 11).padding(.vertical, 4)
                            .background(.black.opacity(0.55))
                            .clipShape(Capsule())
                            .padding(.top, 10)
                        Spacer()
                    }
                }

                if !model.playing {
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

                if model.segments.isEmpty {
                    Text("아직 오늘의 영상이 없어요.\n첫 장면을 찍어볼까요?")
                        .font(.system(size: 13.5))
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .aspectRatio(4 / 5, contentMode: .fit)
        .background(Color(hex: "#101016"))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line))
        .contentShape(Rectangle())
        .onTapGesture { model.togglePlay() }
    }

    // ── 한 줄(트랙) ───────────────────────────────────────
    @ViewBuilder
    private func strip(userId: UUID?, player: AVPlayer, height: CGFloat) -> some View {
        let side: (clip: TaggedClip?, active: Bool) = {
            guard let userId, model.index < model.segments.count else { return (nil, false) }
            return Timeline.sideAt(model.segments, index: model.index, userId: userId)
        }()
        let member = userId.flatMap { app.member(for: $0) }

        ZStack {
            if let clip = side.clip, clip.clip.videoKey != nil {
                PlayerLayerView(player: player)
                    .opacity(side.active ? 1 : 0.45)
            } else if let clip = side.clip {
                Text(clip.caption)
                    .font(.system(size: 13, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .foregroundStyle(side.active ? Theme.text : Theme.faint)
                    .padding(14)
            } else {
                Text(member?.initial ?? "·")
                    .font(.system(size: 42, weight: .bold))
                    .foregroundStyle(member.map { Color(hex: $0.colorHex) } ?? Theme.faint)
                    .opacity(0.22)
            }

            // 이름 (좌하단) · 태그 kcal (우상단)
            VStack {
                HStack {
                    Spacer()
                    if side.active, let tag = side.clip?.tag {
                        Text("\(tag.isMove ? "−" : "+")\(tag.kcal)")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(tag.isMove ? Theme.green : .white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.black.opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .padding(10)
                    }
                }
                Spacer()
                HStack {
                    if side.active, let member {
                        Text(member.displayName)
                            .font(.system(size: 10.5, weight: .bold))
                            .kerning(0.5)
                            .foregroundStyle(Color(hex: member.colorHex))
                            .shadow(color: .black.opacity(0.7), radius: 6)
                            .padding(.leading, 12).padding(.bottom, 12)
                    }
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
    }

    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(Array(model.segments.enumerated()), id: \.element.id) { i, _ in
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(i < model.index ? 0.85 : 0.28))
                        if i == model.index {
                            SegmentFillBar(duration: model.currentDuration,
                                           playing: model.playing,
                                           width: geo.size.width)
                        }
                    }
                }
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

/// AVPlayerLayer(aspect-fill) 래퍼 — VideoPlayer는 컨트롤이 붙어서 직접 래핑
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    final class LayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }
}
