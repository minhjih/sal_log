import Foundation
import Supabase
import PostgREST

/// 직접 입력한 음식/운동의 개인 즐겨찾기.
/// 사용할 때마다 bump되어 자주 쓴 순으로 정렬된다.
struct FavoriteEntry: Codable, Identifiable, Hashable {
    let userId: UUID
    var kind: String          // "food" | "workout"
    var name: String
    var kcal: Int
    var minutes: Int?
    var bodyPart: String?
    var useCount: Int

    var id: String { "\(kind)-\(name)" }

    enum CodingKeys: String, CodingKey {
        case kind, name, kcal, minutes
        case userId = "user_id"
        case bodyPart = "body_part"
        case useCount = "use_count"
    }
}

enum FavoritesService {
    enum Kind: String { case food, workout }

    static func fetch(kind: Kind, limit: Int = 8) async throws -> [FavoriteEntry] {
        try await Supa.client.from("favorite_entries")
            .select()
            .eq("kind", value: kind.rawValue)
            .order("use_count", ascending: false)
            .order("last_used_at", ascending: false)
            .limit(limit)
            .execute().value
    }

    /// upsert + use_count 증가. 실패해도 클립 저장 흐름을 막지 않도록 호출부에서 try? 사용.
    static func bump(
        kind: Kind, name: String, kcal: Int,
        minutes: Int? = nil, bodyPart: String? = nil
    ) async throws {
        struct Params: Encodable {
            let p_kind: String
            let p_name: String
            let p_kcal: Int
            let p_minutes: Int?
            let p_body_part: String?
        }
        try await Supa.client.rpc("bump_favorite", params: Params(
            p_kind: kind.rawValue, p_name: name, p_kcal: kcal,
            p_minutes: minutes, p_body_part: bodyPart
        )).execute()
    }
}
