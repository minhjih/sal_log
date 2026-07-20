import SwiftUI
import Foundation
import Charts

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

                TrendChartCard()

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

// ═══════════════════════════════════════════════════════════
// 변화 추이 그래프 — 체중/체지방률/골격근량 토글, 멤버별 라인
// ═══════════════════════════════════════════════════════════
struct TrendChartCard: View {
    @EnvironmentObject private var app: AppState

    enum Metric: String, CaseIterable {
        case bodyFat = "체지방률"
        case muscle = "골격근량"
        case weight = "체중"

        var unit: String {
            self == .bodyFat ? "%" : "kg"
        }
    }

    @State private var metric: Metric = .bodyFat

    struct Point: Identifiable {
        let id: UUID
        let date: Date
        let value: Double
    }

    private func points(for member: MemberOverview) -> [Point] {
        member.measurements
            .sorted { $0.measuredAt < $1.measuredAt }
            .compactMap { m in
                let value: Double?
                switch metric {
                case .bodyFat: value = m.bodyFat
                case .muscle: value = m.skeletalMuscle
                case .weight: value = m.weight
                }
                guard let value else { return nil }
                return Point(id: m.id, date: m.measuredAt, value: value)
            }
    }

    private var membersWithData: [(MemberOverview, [Point])] {
        app.members.compactMap { member in
            let pts = points(for: member)
            return pts.isEmpty ? nil : (member, pts)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                // 지표 토글이 곧 헤더 — 별도 타이틀 없이 깔끔하게
                HStack(spacing: 0) {
                    ForEach(Metric.allCases, id: \.self) { m in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { metric = m }
                        } label: {
                            Text(m.rawValue)
                                .font(.system(size: 11, weight: metric == m ? .bold : .regular))
                                .foregroundStyle(metric == m ? Theme.text : Theme.muted)
                                .padding(.horizontal, 9).padding(.vertical, 6)
                                .background(metric == m ? Theme.surface2 : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(2)
                .background(Theme.bg)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
            }

            if membersWithData.isEmpty {
                Text("아직 \(metric.rawValue) 기록이 없어요.\n바디 탭에서 인바디를 스캔하면 여기에 변화가 그려져요.")
                    .font(.system(size: 12))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 22)
            } else {
                chart

                // 범례 + 최근 변화량
                HStack(spacing: 14) {
                    ForEach(membersWithData, id: \.0.userId) { member, pts in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color(hex: member.colorHex))
                                .frame(width: 7, height: 7)
                            Text(member.displayName)
                                .font(.system(size: 11, weight: .semibold))
                            Text(deltaLabel(pts))
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(deltaColor(pts))
                        }
                    }
                    Spacer()
                }
            }
        }
        .padding(12)
        .card(radius: 16)
    }

    private var chart: some View {
        Chart {
            ForEach(membersWithData, id: \.0.userId) { member, pts in
                ForEach(pts) { p in
                    LineMark(
                        x: .value("날짜", p.date),
                        y: .value(metric.rawValue, p.value),
                        series: .value("멤버", member.userId.uuidString)
                    )
                    .foregroundStyle(Color(hex: member.colorHex))
                    .interpolationMethod(.monotone)
                    .lineStyle(.init(lineWidth: 2.5, lineCap: .round))

                    PointMark(
                        x: .value("날짜", p.date),
                        y: .value(metric.rawValue, p.value)
                    )
                    .foregroundStyle(Color(hex: member.colorHex))
                    .symbolSize(28)
                }
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.faint)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Theme.line.opacity(0.6))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(v, specifier: "%.0f")\(metric.unit)")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.faint)
                    }
                }
            }
        }
        .frame(height: 150)
    }

    private var yDomain: ClosedRange<Double> {
        let values = membersWithData.flatMap { $0.1.map(\.value) }
        guard let min = values.min(), let max = values.max() else { return 0...1 }
        let pad = Swift.max((max - min) * 0.25, 1)
        return (min - pad)...(max + pad)
    }

    private func deltaLabel(_ pts: [Point]) -> String {
        guard let first = pts.first?.value, let last = pts.last?.value, pts.count >= 2 else {
            return ""
        }
        let delta = ((last - first) * 10).rounded() / 10
        if delta == 0 { return "유지" }
        return "\(delta > 0 ? "▲" : "▼") \(String(format: "%.1f", abs(delta)))\(metric.unit)"
    }

    private func deltaColor(_ pts: [Point]) -> Color {
        guard let first = pts.first?.value, let last = pts.last?.value, pts.count >= 2 else {
            return Theme.faint
        }
        let down = last < first
        // 체지방·체중은 감소가 좋고, 골격근량은 증가가 좋음
        let good = metric == .muscle ? !down : down
        return last == first ? Theme.faint : (good ? Theme.green : Theme.me)
    }
}
