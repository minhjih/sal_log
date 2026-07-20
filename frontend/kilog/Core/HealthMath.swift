import Foundation

/// 대사량·운동 칼로리 계산 (JSX의 calcBMR/calcTDEE/metKcal 이식)
enum HealthMath {

    /// 기초대사량.
    /// 체지방률이 있으면 Katch-McArdle(제지방량 기반, 인바디 최적),
    /// 없으면 Mifflin-St Jeor로 폴백.
    static func bmr(_ p: BodyProfile) -> Int? {
        guard let weight = p.weight else { return nil }
        if let bodyFat = p.bodyFat, bodyFat > 0 {
            let lbm = weight * (1 - bodyFat / 100)
            return Int((370 + 21.6 * lbm).rounded())
        }
        guard let height = p.height, let age = p.age, let sex = p.sex else { return nil }
        let s: Double = sex == .M ? 5 : -161
        return Int((10 * weight + 6.25 * height - 5 * Double(age) + s).rounded())
    }

    static func tdee(_ p: BodyProfile) -> Int? {
        guard let bmr = bmr(p) else { return nil }
        return Int((Double(bmr) * (p.activityFactor ?? 1.375)).rounded())
    }

    /// MET 기반 소모 칼로리: MET × 3.5 × 체중(kg) / 200 × 분
    static func metKcal(met: Double, weightKg: Double?, minutes: Int) -> Int {
        Int(((met * 3.5 * (weightKg ?? 60)) / 200 * Double(minutes)).rounded())
    }

    /// 하루 칼로리 밸런스: 섭취 − (기초대사 + 운동 소모)
    struct DailyStats {
        var intake = 0
        var burn = 0
        var bmr = 0
        var burnTotal: Int { bmr + burn }
        var balance: Int { intake - burnTotal }
    }

    static func dailyStats(
        userId: UUID,
        foods: [FoodLog],
        workouts: [WorkoutLog],
        profile: BodyProfile?
    ) -> DailyStats {
        var s = DailyStats()
        s.intake = foods.filter { $0.userId == userId }.reduce(0) { $0 + $1.calories }
        s.burn = workouts.filter { $0.userId == userId }.reduce(0) { $0 + $1.calories }
        s.bmr = profile.flatMap(bmr) ?? 0
        return s
    }
}
