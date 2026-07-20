import SwiftUI

/// 코치 탭: 오늘 자극한 부위 분석 → 내일 루틴 추천(MET 기반) + 밸런스 기반 메뉴 추천
struct CoachView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var catalogs: Catalogs

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("코치")
                        .font(.system(size: 19, weight: .bold))
                    Spacer()
                    Text("내일 루틴, 미리 준비해뒀어요")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 2)

                HStack {
                    Text("같이 보기").font(.system(size: 12, weight: .bold))
                    Spacer()
                    Text("서로의 내일 루틴도 볼 수 있어요")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 13).padding(.vertical, 11)
                .background(
                    LinearGradient(colors: [Theme.me.opacity(0.12), Theme.lover.opacity(0.12)],
                                   startPoint: .leading, endPoint: .trailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))

                ForEach(app.members) { member in
                    MemberCoachPanel(member: member)
                }

                Text("추천은 운동 기록·칼로리 밸런스·인바디 수치 기반 참고용이에요.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
    }
}

struct MemberCoachPanel: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var catalogs: Catalogs
    let member: MemberOverview

    private var isMe: Bool { member.userId == app.myId }
    private var profile: BodyProfile? { isMe ? app.myProfile : member.profile }
    private var stats: HealthMath.DailyStats { app.stats(for: member.userId) }

    /// 오늘 자극한 부위
    private var trainedParts: Set<String> {
        Set(app.feed.workouts
            .filter { $0.userId == member.userId }
            .compactMap { workout in
                workout.bodyPart
                    ?? catalogs.exercises.first { $0.name == workout.exerciseName }?.bodyPart
            })
    }

    struct Rec: Identifiable {
        let id = UUID()
        let part: String
        let exercise: String
        let minutes: Int
        let kcal: Int
    }

    /// 내일 추천: 안 쓴 부위 상위 2개, 전부 자극했으면 회복(요가)
    private var recommendations: [Rec] {
        let trained = trainedParts
        let untrained = Catalogs.parts.filter {
            !trained.contains($0) && !trained.contains("전신")
        }
        let weight = profile?.weight

        if untrained.isEmpty {
            let met = catalogs.exercises.first { $0.name == "요가" }?.met ?? 2.5
            return [Rec(part: "회복", exercise: "요가", minutes: 20,
                        kcal: HealthMath.metKcal(met: met, weightKg: weight, minutes: 20))]
        }
        return untrained.prefix(2).compactMap { part in
            guard let pick = Catalogs.partPick[part] else { return nil }
            let met = catalogs.exercises.first { $0.name == pick.exercise }?.met ?? 3.5
            return Rec(part: part, exercise: pick.exercise, minutes: pick.minutes,
                       kcal: HealthMath.metKcal(met: met, weightKg: weight, minutes: pick.minutes))
        }
    }

    private var foodRecs: [Catalogs.FoodRec] {
        (stats.balance > 0 ? Catalogs.surplusRecs : Catalogs.deficitRecs).items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            // 헤더
            HStack {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(hex: member.colorHex))
                        .frame(width: 34, height: 34)
                        .overlay(Text(member.initial)
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(Color(hex: "#101016")))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(member.displayName)의 코치")
                            .font(.system(size: 14, weight: .semibold))
                        Text(balanceLabel)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.muted)
                    }
                }
                Spacer()
                Text(stats.balance <= 0 ? "굿" : "오버")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(stats.balance <= 0 ? Theme.green : Theme.me)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background((stats.balance <= 0 ? Theme.green : Theme.me).opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // 부위 칩
            HStack(spacing: 7) {
                ForEach(Catalogs.parts, id: \.self) { part in
                    let hit = trainedParts.contains(part) || trainedParts.contains("전신")
                    Text(part)
                        .font(.system(size: 12.5, weight: hit ? .bold : .regular))
                        .foregroundStyle(hit ? Color(hex: "#14060C") : Theme.faint)
                        .padding(.horizontal, 13).padding(.vertical, 6)
                        .background(hit ? AnyShapeStyle(Theme.duo) : AnyShapeStyle(.clear))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(hit ? .clear : Theme.line))
                }
            }

            sectionTitle("내일 루틴")
            ForEach(recommendations) { rec in
                recRow(chip: rec.part, chipColor: Theme.lover,
                       title: rec.exercise,
                       subtitle: "\(rec.minutes)분 · \(Int(profile?.weight ?? 60))kg 기준",
                       kcal: "−\(rec.kcal)", kcalColor: Theme.green)
            }

            sectionTitle("추천 메뉴")
            ForEach(foodRecs.prefix(2), id: \.name) { food in
                recRow(chip: "밥", chipColor: Theme.me,
                       title: food.name, subtitle: food.note,
                       kcal: "+\(food.kcal)", kcalColor: Theme.text)
            }
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.line))
    }

    private var balanceLabel: String {
        let b = stats.balance
        return "오늘 밸런스 \(b > 0 ? "+" : "")\(b) kcal"
    }

    private func sectionTitle(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Theme.line).frame(height: 1)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .padding(.top, 10)
        }
    }

    private func recRow(
        chip: String, chipColor: Color, title: String,
        subtitle: String, kcal: String, kcalColor: Color
    ) -> some View {
        HStack(spacing: 11) {
            Text(chip)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(chipColor)
                .frame(width: 44)
                .padding(.vertical, 6)
                .background(Theme.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Text(kcal)
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(kcalColor)
        }
    }
}
