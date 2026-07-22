import SwiftUI
import Charts
import Foundation

/// 내보내기 아웃트로용 요약 카드 — ImageRenderer로 이미지화해 CALayer에 얹는다.

/// 오늘의 근육 부하 비교 (두 멤버, 앞/뒤 피규어)
struct ExportMuscleCard: View {
    let members: [MemberOverview]
    let workouts: [WorkoutLog]

    private var maxKcal: Double {
        let all = members.flatMap { member in
            MuscleMap.loads(from: workouts.filter { $0.userId == member.userId }).values
        }
        return max(all.max() ?? 1, 1)
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("오늘의 근육 부하")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.muted)

            HStack(alignment: .top, spacing: 40) {
                ForEach(members.prefix(2)) { member in
                    let loads = MuscleMap.loads(
                        from: workouts.filter { $0.userId == member.userId })
                    let cardio = workouts.contains {
                        $0.userId == member.userId && $0.bodyPart == "유산소"
                    }
                    let color = Color(hex: member.colorHex)

                    VStack(spacing: 7) {
                        HStack(spacing: 8) {
                            MuscleFigure(side: .front, color: color,
                                         intensity: { (loads[$0] ?? 0) / maxKcal },
                                         cardio: cardio)
                                .frame(width: 74, height: 163)
                            MuscleFigure(side: .back, color: color,
                                         intensity: { (loads[$0] ?? 0) / maxKcal },
                                         cardio: cardio)
                                .frame(width: 74, height: 163)
                        }
                        Text(member.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(color)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// 체중 추이 비교 (두 멤버, 한 차트)
struct ExportWeightCard: View {
    let members: [MemberOverview]

    private var series: [(member: MemberOverview, points: [BodyMeasurement])] {
        members.prefix(2).compactMap { member in
            let sorted = member.measurements.sorted { $0.measuredAt < $1.measuredAt }
            return sorted.count >= 2 ? (member, sorted) : nil
        }
    }

    private var yDomain: ClosedRange<Double> {
        let values = series.flatMap { $0.points.map(\.weight) }
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        return (lo - 1)...(hi + 1)
    }

    var body: some View {
        VStack(spacing: 10) {
            Text("체중 추이")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.muted)

            Chart {
                ForEach(series, id: \.member.userId) { member, points in
                    ForEach(points) { record in
                        LineMark(
                            x: .value("날짜", record.measuredAt),
                            y: .value("체중", record.weight),
                            series: .value("멤버", member.userId.uuidString)
                        )
                        .foregroundStyle(Color(hex: member.colorHex))
                        .lineStyle(.init(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                        PointMark(
                            x: .value("날짜", record.measuredAt),
                            y: .value("체중", record.weight)
                        )
                        .foregroundStyle(Color(hex: member.colorHex))
                        .symbolSize(22)
                    }
                }
            }
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                        .font(.system(size: 8.5))
                        .foregroundStyle(Theme.faint)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.system(size: 8.5))
                        .foregroundStyle(Theme.faint)
                }
            }
            .frame(height: 135)

            // 범례
            HStack(spacing: 16) {
                ForEach(series, id: \.member.userId) { member, points in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: member.colorHex))
                            .frame(width: 8, height: 8)
                        Text("\(member.displayName) \(String(format: "%.1f", points.last?.weight ?? 0))kg")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
