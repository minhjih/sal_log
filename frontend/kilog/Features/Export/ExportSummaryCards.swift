import SwiftUI
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

/// 체중 변화 (절대 수치 대신 지난 기록 대비 증감 %만 공개)
struct ExportWeightCard: View {
    let members: [MemberOverview]

    /// 측정이 2개 이상인 멤버만 — 마지막 두 기록으로 증감률 계산
    private var changes: [(member: MemberOverview, pct: Double)] {
        members.prefix(2).compactMap { member in
            let sorted = member.measurements.sorted { $0.measuredAt < $1.measuredAt }
            guard sorted.count >= 2 else { return nil }
            let last = sorted[sorted.count - 1].weight
            let prev = sorted[sorted.count - 2].weight
            guard prev > 0 else { return nil }
            return (member, (last - prev) / prev * 100)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("지난 기록 대비 체중 변화")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.muted)

            HStack(alignment: .top, spacing: 44) {
                ForEach(changes, id: \.member.userId) { member, pct in
                    let down = pct < -0.05
                    let up = pct > 0.05
                    let color = Color(hex: member.colorHex)
                    let tint = down ? Theme.green : (up ? Theme.me : Theme.muted)

                    VStack(spacing: 5) {
                        Text(member.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(color)
                        HStack(spacing: 3) {
                            Image(systemName: down ? "arrow.down.right"
                                  : (up ? "arrow.up.right" : "minus"))
                                .font(.system(size: 17, weight: .bold))
                            Text(String(format: "%.1f%%", abs(pct)))
                                .font(.system(size: 32, weight: .light))
                        }
                        .foregroundStyle(tint)
                        Text(down ? "감소" : (up ? "증가" : "유지"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
