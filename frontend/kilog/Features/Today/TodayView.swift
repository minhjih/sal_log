import SwiftUI
import AVFoundation
import Foundation

/// 오늘 탭: 연속 브이로그 + 지금 찍기 + 변화 그래프 + 오늘의 컷 + 지난 컷
struct TodayView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var theater = TheaterModel()
    let onCapture: () -> Void

    @State private var clipToDelete: TaggedClip?
    @State private var pastClips: [TaggedClip] = []
    @State private var playingClip: TaggedClip?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                TheaterView(model: theater, onCapture: onCapture)

                recordCTA

                StreakCard(logs: app.recentLogs)

                todaysCuts

                pastCuts

                Text("운동 칼로리는 Compendium MET × 체중, 기초대사량은 인바디 스캔 수치 기반 Katch-McArdle 공식으로 자동 계산돼요.")
                    .font(.system(size: 11))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .refreshable {
            await app.reloadFeed()
            await loadPastClips()
        }
        .task { await loadPastClips() }
        .fullScreenCover(item: $playingClip) { clip in
            PastClipPlayerView(clip: clip, member: app.member(for: clip.userId))
        }
        .onAppear { syncTheater() }
        .onChange(of: app.feed.clips) { syncTheater() }
        .onChange(of: app.videoCache) { syncTheater() }
        .onDisappear { if theater.playing { theater.togglePlay() } }
        .confirmationDialog(
            "이 클립을 삭제할까요?",
            isPresented: .init(
                get: { clipToDelete != nil },
                set: { if !$0 { clipToDelete = nil } }
            ),
            presenting: clipToDelete
        ) { clip in
            Button("삭제", role: .destructive) {
                Task { await delete(clip) }
            }
            Button("취소", role: .cancel) {}
        } message: { clip in
            Text("‘\(clip.caption)’ 영상과 태그된 기록이 함께 삭제돼요.")
        }
    }

    private func delete(_ clip: TaggedClip) async {
        do {
            try await ClipService.deleteClip(clip.clip)
            await app.reloadFeed()
            await loadPastClips()
        } catch {
            app.errorMessage = "클립을 삭제하지 못했어요. 다시 시도해 주세요."
        }
    }

    private func loadPastClips() async {
        guard let group = app.group else { return }
        if let clips = try? await ClipService.fetchPastClips(groupId: group.id) {
            pastClips = clips
        }
    }

    // ── 지난 컷 (7일 뒤 자동 삭제 전까지 다시 보기) ────────
    @ViewBuilder
    private var pastCuts: some View {
        if !pastClips.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("지난 컷").font(.system(size: 13, weight: .bold))
                    Spacer()
                    Text("7일까지 보관돼요")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.faint)
                }
                ForEach(pastByDay, id: \.label) { day in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(day.label)
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(Theme.muted)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(day.clips) { clip in
                                    pastChip(clip)
                                }
                            }
                        }
                    }
                }
            }
            .padding(12)
            .card(radius: 16)
        }
    }

    private var pastByDay: [(label: String, clips: [TaggedClip])] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M.d E"
        let grouped = Dictionary(grouping: pastClips) {
            Calendar.current.startOfDay(for: $0.recordedAt)
        }
        return grouped.keys.sorted(by: >).map { day in
            (formatter.string(from: day),
             grouped[day]!.sorted { $0.recordedAt < $1.recordedAt })
        }
    }

    private func pastChip(_ clip: TaggedClip) -> some View {
        let member = app.member(for: clip.userId)
        let hasVideo = clip.clip.videoKey != nil
        return Button {
            if hasVideo { playingClip = clip }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(member.map { Color(hex: $0.colorHex) } ?? Theme.faint)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(clip.recordedAt, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.muted)
                    Text(clip.caption)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                }
                if hasVideo {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Theme.bg)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
        }
    }

    // ── 오늘의 컷 (내 클립은 삭제 가능) ────────────────────
    @ViewBuilder
    private var todaysCuts: some View {
        if !app.feed.clips.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("오늘의 컷").font(.system(size: 13, weight: .bold))
                    Spacer()
                    Text("클립은 7일 뒤 자동 정리돼요 · 기록은 남아요")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.faint)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(app.feed.clips) { clip in
                            cutChip(clip)
                        }
                    }
                }
            }
            .padding(12)
            .card(radius: 16)
        }
    }

    private func cutChip(_ clip: TaggedClip) -> some View {
        let member = app.member(for: clip.userId)
        let isMine = clip.userId == app.myId
        return HStack(spacing: 8) {
            Circle()
                .fill(member.map { Color(hex: $0.colorHex) } ?? Theme.faint)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(clip.recordedAt, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.muted)
                Text(clip.caption)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            if let tag = clip.tag {
                Text("\(tag.isMove ? "−" : "+")\(tag.kcal)")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(tag.isMove ? Theme.green : Theme.muted)
            }
            if isMine {
                Button {
                    clipToDelete = clip
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 24, height: 24)
                        .background(Theme.surface2)
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Theme.bg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
    }

    private func syncTheater() {
        theater.update(
            clips: app.feed.clips,
            topUserId: app.myId,
            bottomUserId: app.partner?.userId,
            localFiles: app.videoCache
        )
    }

    // ── 지난 컷 전체화면 재생 ─────────────────────────────
    struct PastClipPlayerView: View {
        let clip: TaggedClip
        let member: MemberOverview?
        @Environment(\.dismiss) private var dismiss

        @State private var player: AVPlayer?
        @State private var loadFailed = false
        @State private var looper: Any?

        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()

                if let player {
                    PlayerLayerView(player: player, gravity: .resizeAspect)
                        .ignoresSafeArea()
                } else if loadFailed {
                    Text("영상을 불러오지 못했어요.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                } else {
                    ProgressView().tint(.white)
                }

                VStack {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member?.displayName ?? "")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(member.map { Color(hex: $0.colorHex) } ?? .white)
                            Text(clip.recordedAt.formatted(.dateTime.month().day().hour(.twoDigits(amPM: .omitted)).minute()))
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(.white.opacity(0.15))
                                .clipShape(Circle())
                        }
                    }
                    .padding(16)
                    Spacer()
                    Text(clip.caption)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.8), radius: 7)
                        .padding(.bottom, 40)
                }
            }
            .task {
                do {
                    guard let url = try await ClipService.cachedVideoURL(for: clip.clip) else {
                        loadFailed = true; return
                    }
                    let queue = AVPlayer(url: url)
                    queue.isMuted = false
                    // 끝나면 처음부터 반복
                    looper = NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime,
                        object: queue.currentItem, queue: .main
                    ) { _ in
                        queue.seek(to: .zero)
                        queue.play()
                    }
                    player = queue
                    queue.play()
                } catch {
                    loadFailed = true
                }
            }
            .onDisappear {
                player?.pause()
                if let looper { NotificationCenter.default.removeObserver(looper) }
            }
            .onTapGesture { dismiss() }
        }
    }

    // ── 지금 찍기 ─────────────────────────────────────────
    private var recordCTA: some View {
        Button(action: onCapture) {
            HStack(spacing: 14) {
                let color = app.myMember.map { Color(hex: $0.colorHex) } ?? Theme.me
                Circle()
                    .stroke(color, lineWidth: 2.5)
                    .frame(width: 42, height: 42)
                    .overlay(Circle().fill(color).padding(6))

                VStack(alignment: .leading, spacing: 2) {
                    Text("지금 찍기")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text("먹을 때, 움직일 때 · 시간은 나중에 맞출 수 있어요")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
            }
            .padding(.vertical, 13).padding(.horizontal, 16)
        }
        .card(radius: 18)
    }

}
