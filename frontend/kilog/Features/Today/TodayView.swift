import SwiftUI
import Foundation

/// 오늘 탭: 연속 브이로그 + 지금 찍기 + 멤버별 수지 카드
struct TodayView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var theater = TheaterModel()
    let onCapture: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                TheaterView(model: theater)

                recordCTA

                duoStats

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
        .onDisappear { if theater.playing { theater.togglePlay() } }
    }

    private func syncTheater() {
        theater.update(
            clips: app.feed.clips,
            topUserId: app.myId,
            bottomUserId: app.partner?.userId
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

    // ── 멤버별 카드 ───────────────────────────────────────
    private var duoStats: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(app.members) { member in
                let stats = app.stats(for: member.userId)
                let isMe = member.userId == app.myId
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(Color(hex: member.colorHex))
                            .frame(width: 24, height: 24)
                            .overlay(Text(member.initial)
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(Color(hex: "#101016")))
                        Text(member.nickname)
                            .font(.system(size: 12.5, weight: .semibold))
                        Spacer()
                        Text(isMe ? "내 계정" : "공유됨")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.faint)
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        statCell("체지방", bodyFatText(member, isMe: isMe))
                        statCell("운동", "−\(stats.burn)", color: Theme.green)
                        statCell("섭취", "+\(stats.intake)")
                        statCell("수지",
                                 "\(stats.balance > 0 ? "+" : "")\(stats.balance)",
                                 color: stats.balance <= 0 ? Theme.green : Theme.me)
                    }
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isMe ? Theme.surface2 : Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line))
            }
        }
    }

    private func bodyFatText(_ member: MemberOverview, isMe: Bool) -> String {
        let profile = isMe ? app.myProfile : member.profile
        if let fat = profile?.bodyFat { return String(format: "%.0f%%", fat) }
        return isMe ? "—" : "비공개"
    }

    private func statCell(_ label: String, _ value: String, color: Color = Theme.text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9.5)).foregroundStyle(Theme.muted)
            Text(value).font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
