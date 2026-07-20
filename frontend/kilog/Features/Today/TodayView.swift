import SwiftUI
import Foundation

/// 오늘 탭: 연속 브이로그 + 지금 찍기 + 변화 그래프 + 오늘의 컷
struct TodayView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var theater = TheaterModel()
    let onCapture: () -> Void

    @State private var clipToDelete: TaggedClip?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                TheaterView(model: theater)

                recordCTA

                todaysCuts

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
        .refreshable { await app.reloadFeed() }
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
        } catch {
            app.errorMessage = "클립을 삭제하지 못했어요. 다시 시도해 주세요."
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
