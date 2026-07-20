import Foundation

/// 세부 근육 그룹 정의 + 큰 부위 → 기본 분포 (서버 시드와 동일한 규칙)
enum MuscleMap {
    /// 인체 모형에 그리는 9개 근육 그룹
    static let all = ["가슴", "등", "어깨", "팔", "복근", "둔근", "대퇴", "햄스트링", "종아리"]

    static let front = ["가슴", "어깨", "팔", "복근", "대퇴", "종아리"]
    static let back  = ["등", "어깨", "팔", "둔근", "햄스트링", "종아리"]

    /// muscle_loads가 없는 기록(과거 데이터·직접 입력)의 큰 부위 → 기본 분포
    static func defaultLoads(bodyPart: String?) -> [String: Double] {
        switch bodyPart {
        case "유산소":
            return ["대퇴": 0.4, "종아리": 0.3, "햄스트링": 0.2, "둔근": 0.1]
        case "하체":
            return ["대퇴": 0.5, "둔근": 0.3, "햄스트링": 0.2]
        case "상체":
            return ["가슴": 0.3, "등": 0.3, "어깨": 0.2, "팔": 0.2]
        case "코어":
            return ["복근": 1.0]
        default: // 전신 포함
            return ["대퇴": 0.2, "가슴": 0.15, "등": 0.15,
                    "어깨": 0.15, "복근": 0.2, "둔근": 0.15]
        }
    }

    /// 운동 기록들 → 근육별 소모 kcal 합산
    static func loads(from workouts: [WorkoutLog]) -> [String: Double] {
        var result: [String: Double] = [:]
        for log in workouts {
            let distribution = log.muscleLoads ?? defaultLoads(bodyPart: log.bodyPart)
            for (muscle, ratio) in distribution where all.contains(muscle) {
                result[muscle, default: 0] += Double(log.calories) * ratio
            }
        }
        return result
    }
}
