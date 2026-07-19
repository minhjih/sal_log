import Foundation

/// 운동/음식 카탈로그.
/// 서버 exercise_catalog / food_catalog에서 로드하고, 네트워크 이전·실패 시
/// 동일한 시드 데이터로 폴백한다 (2011 Compendium 기반).
@MainActor
final class Catalogs: ObservableObject {
    @Published var exercises: [ExerciseItem] = Catalogs.fallbackExercises
    @Published var foods: [FoodItem] = Catalogs.fallbackFoods

    static let parts = ["하체", "상체", "코어", "유산소"]

    /// 부위별 대표 추천 운동 (JSX PART_PICK)
    static let partPick: [String: (exercise: String, minutes: Int)] = [
        "하체": ("스쿼트·런지", 30),
        "상체": ("웨이트 (보통)", 40),
        "코어": ("플랭크·복근", 20),
        "유산소": ("러닝 8km/h", 30),
    ]

    struct FoodRec { let name: String; let kcal: Int; let note: String }

    static let surplusRecs = (
        why: "오늘 수지가 흑자(+)예요. 내일은 가볍고 단백질 위주로 가볼까요?",
        items: [
            FoodRec(name: "닭가슴살 샐러드", kcal: 350, note: "단백질 30g"),
            FoodRec(name: "두부 포케", kcal: 420, note: "포만감 좋고 가벼움"),
            FoodRec(name: "그릭요거트 볼", kcal: 280, note: "아침 대용 추천"),
        ]
    )

    static let deficitRecs = (
        why: "오늘 수지가 적자(−)예요. 근손실 방지를 위해 단백질을 챙겨요.",
        items: [
            FoodRec(name: "연어 스테이크 정식", kcal: 550, note: "오메가3 + 단백질"),
            FoodRec(name: "소고기 미역국 정식", kcal: 600, note: "회복식으로 좋음"),
            FoodRec(name: "닭가슴살 리조또", kcal: 520, note: "운동 후 한 끼"),
        ]
    )

    func load() async {
        do {
            async let ex: [ExerciseItem] = Supa.client
                .from("exercise_catalog").select().order("sort").execute().value
            async let fd: [FoodItem] = Supa.client
                .from("food_catalog").select("id, name, kcal").order("sort").execute().value
            let (e, f) = try await (ex, fd)
            if !e.isEmpty { exercises = e }
            if !f.isEmpty { foods = f }
        } catch {
            // 오프라인/미인증 시 시드 폴백 유지
        }
    }

    static let fallbackExercises: [ExerciseItem] = [
        .init(id: 1, name: "걷기 (보통)", met: 3.5, bodyPart: "유산소"),
        .init(id: 2, name: "걷기 (빠르게)", met: 4.3, bodyPart: "유산소"),
        .init(id: 3, name: "러닝 8km/h", met: 8.3, bodyPart: "유산소"),
        .init(id: 4, name: "러닝 10km/h", met: 9.8, bodyPart: "유산소"),
        .init(id: 5, name: "자전거", met: 7.5, bodyPart: "하체"),
        .init(id: 6, name: "실내 사이클", met: 6.8, bodyPart: "하체"),
        .init(id: 7, name: "웨이트 (보통)", met: 3.5, bodyPart: "상체"),
        .init(id: 8, name: "웨이트 (고강도)", met: 6.0, bodyPart: "상체"),
        .init(id: 9, name: "스쿼트·런지", met: 5.0, bodyPart: "하체"),
        .init(id: 10, name: "수영 (자유형)", met: 5.8, bodyPart: "전신"),
        .init(id: 11, name: "요가", met: 2.5, bodyPart: "코어"),
        .init(id: 12, name: "필라테스", met: 3.0, bodyPart: "코어"),
        .init(id: 13, name: "등산", met: 6.0, bodyPart: "하체"),
        .init(id: 14, name: "계단 오르기", met: 4.0, bodyPart: "하체"),
        .init(id: 15, name: "줄넘기", met: 11.8, bodyPart: "유산소"),
        .init(id: 16, name: "홈트 (맨몸)", met: 3.8, bodyPart: "전신"),
        .init(id: 17, name: "플랭크·복근", met: 3.8, bodyPart: "코어"),
        .init(id: 18, name: "배드민턴", met: 5.5, bodyPart: "전신"),
    ]

    static let fallbackFoods: [FoodItem] = [
        .init(id: 1, name: "샐러드", kcal: 250),
        .init(id: 2, name: "아메리카노", kcal: 5),
        .init(id: 3, name: "편의점 도시락", kcal: 650),
        .init(id: 4, name: "라면", kcal: 550),
        .init(id: 5, name: "마라탕", kcal: 950),
        .init(id: 6, name: "삼겹살 1인분", kcal: 600),
        .init(id: 7, name: "치킨 반 마리", kcal: 800),
        .init(id: 8, name: "김밥 한 줄", kcal: 480),
        .init(id: 9, name: "과자 한 봉", kcal: 320),
    ]
}
