import SwiftUI
import Charts
import Foundation

/// 지표 탭: 서로의 건강 지표를 확인·비교
///  · 변화 그래프 (체지방률/골격근량/체중 토글)
///  · 데이 스트레이크 (운동·식단 기록 연속 일수)
///  · 인체 모형 부위 비교 (최근 7일 운동 부위별 강도)
struct MetricsView: View {
    @EnvironmentObject private var app: AppState
    @State private var recentLogs = ClipService.RecentLogs(foods: [], workouts: [])

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("지표").font(.system(size: 19, weight: .bold))
                    Spacer()
                    Text("서로의 변화, 한눈에")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 2)

                TrendChartCard()

                StreakCard(logs: recentLogs)

                PartComparisonCard(workouts: recentWeekWorkouts)

                Text("파트너의 기록은 공유 설정(운동·식단)에 동의한 범위까지만 보여요.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var recentWeekWorkouts: [WorkoutLog] {
        let weekAgo = Calendar.current.date(
            byAdding: .day, value: -7,
            to: Calendar.current.startOfDay(for: Date())
        )!
        return recentLogs.workouts.filter { $0.loggedAt >= weekAgo }
    }

    private func load() async {
        guard let group = app.group else { return }
        recentLogs = (try? await ClipService.fetchRecentLogs(groupId: group.id, days: 30))
            ?? ClipService.RecentLogs(foods: [], workouts: [])
    }
}

// ═══════════════════════════════════════════════════════════
// 변화 추이 그래프 — 체지방률/골격근량/체중 토글, 멤버별 라인
// ═══════════════════════════════════════════════════════════
struct TrendChartCard: View {
    @EnvironmentObject private var app: AppState

    enum Metric: String, CaseIterable {
        case bodyFat = "체지방률"
        case muscle = "골격근량"
        case weight = "체중"

        var unit: String { self == .bodyFat ? "%" : "kg" }
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
        let good = metric == .muscle ? !down : down
        return last == first ? Theme.faint : (good ? Theme.green : Theme.me)
    }
}

// ═══════════════════════════════════════════════════════════
// 데이 스트레이크 — 운동·식단 기록 연속 일수 + 최근 7일 점
// ═══════════════════════════════════════════════════════════
struct StreakCard: View {
    @EnvironmentObject private var app: AppState
    let logs: ClipService.RecentLogs

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("스트레이크").font(.system(size: 13, weight: .bold))
                Spacer()
                Text("기록이 이어진 날들")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.faint)
            }

            ForEach(app.members) { member in
                memberStreaks(member)
            }
        }
        .padding(12)
        .card(radius: 16)
    }

    private func memberStreaks(_ member: MemberOverview) -> some View {
        let calendar = Calendar.current
        let workoutDays = Set(
            logs.workouts.filter { $0.userId == member.userId }
                .map { calendar.startOfDay(for: $0.loggedAt) }
        )
        let foodDays = Set(
            logs.foods.filter { $0.userId == member.userId }
                .map { calendar.startOfDay(for: $0.loggedAt) }
        )

        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: member.colorHex))
                    .frame(width: 22, height: 22)
                    .overlay(Text(member.initial)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Color(hex: "#101016")))
                Text(member.displayName)
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
            }

            streakRow(icon: "figure.run", label: "운동", days: workoutDays)
            streakRow(icon: "fork.knife", label: "식단", days: foodDays)
        }
        .padding(10)
        .background(Theme.bg)
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.line))
    }

    private func streakRow(icon: String, label: String, days: Set<Date>) -> some View {
        let streak = currentStreak(days: days)
        let week = lastSevenDays()

        return HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.muted)
                .frame(width: 28, alignment: .leading)

            // 최근 7일 점 (왼쪽 = 6일 전, 오른쪽 = 오늘)
            HStack(spacing: 4) {
                ForEach(week, id: \.self) { day in
                    Circle()
                        .fill(days.contains(day) ? Theme.green : Theme.surface2)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(
                            Calendar.current.isDateInToday(day) ? Theme.lover : .clear,
                            lineWidth: 1))
                }
            }

            Spacer()

            if streak > 0 {
                Text("🔥 \(streak)일")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.text)
            } else {
                Text("오늘 시작!")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.faint)
            }
        }
    }

    // ── 계산 ──────────────────────────────────────────────
    /// 오늘(또는 아직 오늘 기록 전이면 어제)부터 거꾸로 이어진 연속 일수
    private func currentStreak(days: Set<Date>) -> Int {
        let calendar = Calendar.current
        var cursor = calendar.startOfDay(for: Date())
        if !days.contains(cursor) {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        var count = 0
        while days.contains(cursor) {
            count += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        return count
    }

    private func lastSevenDays() -> [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }
    }
}

// ═══════════════════════════════════════════════════════════
// 인체 모형 부위 비교 — 최근 7일 운동 부위별 강도를 실루엣에 표시
// ═══════════════════════════════════════════════════════════
struct PartComparisonCard: View {
    @EnvironmentObject private var app: AppState
    let workouts: [WorkoutLog]

    struct PartLoad {
        var upper = 0     // 상체 kcal
        var lower = 0     // 하체
        var core = 0      // 코어
        var cardio = 0    // 유산소
        var total: Int { upper + lower + core + cardio }
    }

    private func load(for userId: UUID) -> PartLoad {
        var result = PartLoad()
        for log in workouts where log.userId == userId {
            switch log.bodyPart {
            case "상체": result.upper += log.calories
            case "하체": result.lower += log.calories
            case "코어": result.core += log.calories
            case "유산소": result.cardio += log.calories
            case "전신":
                // 전신은 세 부위에 균등 배분
                result.upper += log.calories / 3
                result.lower += log.calories / 3
                result.core += log.calories / 3
            default:
                result.cardio += log.calories
            }
        }
        return result
    }

    /// 두 사람을 같은 스케일로 비교하기 위한 최대값
    private var maxPartKcal: Int {
        let loads = app.members.map { load(for: $0.userId) }
        return max(loads.flatMap { [$0.upper, $0.lower, $0.core] }.max() ?? 1, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("이번 주 운동 부위").font(.system(size: 13, weight: .bold))
                Spacer()
                Text("최근 7일 · 진할수록 많이 씀")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.faint)
            }

            HStack(alignment: .top, spacing: 12) {
                ForEach(app.members.prefix(2)) { member in
                    figureColumn(member)
                }
            }
        }
        .padding(12)
        .card(radius: 16)
    }

    private func figureColumn(_ member: MemberOverview) -> some View {
        let partLoad = load(for: member.userId)
        let maxKcal = Double(maxPartKcal)
        let color = Color(hex: member.colorHex)

        return VStack(spacing: 8) {
            BodyFigure(
                color: color,
                upper: Double(partLoad.upper) / maxKcal,
                lower: Double(partLoad.lower) / maxKcal,
                core: Double(partLoad.core) / maxKcal,
                cardio: partLoad.cardio > 0 ? 1 : 0
            )
            .frame(width: 96, height: 168)

            Text(member.displayName)
                .font(.system(size: 12, weight: .semibold))

            if partLoad.total == 0 {
                Text("이번 주 기록 없음")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.faint)
            } else {
                VStack(spacing: 3) {
                    partChip("상체", partLoad.upper)
                    partChip("하체", partLoad.lower)
                    partChip("코어", partLoad.core)
                    partChip("유산소", partLoad.cardio)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func partChip(_ label: String, _ kcal: Int) -> some View {
        HStack {
            Text(label).font(.system(size: 10.5)).foregroundStyle(Theme.muted)
            Spacer()
            Text(kcal > 0 ? "−\(kcal)" : "·")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(kcal > 0 ? Theme.green : Theme.faint)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Theme.bg)
        .clipShape(Capsule())
    }
}

/// 사람 실루엣 — 부위별 강도(0~1)에 따라 진하게 칠한다.
/// 유산소는 실루엣 뒤 글로우로 표현.
struct BodyFigure: View {
    let color: Color
    let upper: Double    // 팔·어깨
    let lower: Double    // 다리
    let core: Double     // 몸통
    let cardio: Double   // 0 또는 1

    private func fill(_ intensity: Double) -> Color {
        color.opacity(0.14 + 0.78 * min(1, max(0, intensity)))
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // 유산소 글로우
                if cardio > 0 {
                    RadialGradient(
                        colors: [color.opacity(0.35), .clear],
                        center: .center, startRadius: 0, endRadius: w * 0.85
                    )
                }

                // 머리 (중립 색)
                Circle()
                    .fill(color.opacity(0.3))
                    .frame(width: w * 0.24, height: w * 0.24)
                    .position(x: w * 0.5, y: h * 0.09)

                // 몸통 = 코어
                RoundedRectangle(cornerRadius: w * 0.09)
                    .fill(fill(core))
                    .frame(width: w * 0.34, height: h * 0.34)
                    .position(x: w * 0.5, y: h * 0.36)

                // 팔 = 상체 (좌/우)
                Capsule()
                    .fill(fill(upper))
                    .frame(width: w * 0.13, height: h * 0.32)
                    .rotationEffect(.degrees(14))
                    .position(x: w * 0.22, y: h * 0.36)
                Capsule()
                    .fill(fill(upper))
                    .frame(width: w * 0.13, height: h * 0.32)
                    .rotationEffect(.degrees(-14))
                    .position(x: w * 0.78, y: h * 0.36)

                // 다리 = 하체 (좌/우)
                Capsule()
                    .fill(fill(lower))
                    .frame(width: w * 0.15, height: h * 0.42)
                    .position(x: w * 0.4, y: h * 0.76)
                Capsule()
                    .fill(fill(lower))
                    .frame(width: w * 0.15, height: h * 0.42)
                    .position(x: w * 0.6, y: h * 0.76)
            }
        }
    }
}
