import Foundation
import Supabase

/// 그룹·초대·공유 설정 — 다중 행 변경은 전부 서버 RPC(security definer)로 수행
enum GroupService {

    static func bootstrap() async throws -> Bootstrap {
        try await Supa.client.rpc("get_bootstrap").execute().value
    }

    /// 그룹 생성. 초대 토큰 원문은 이 응답에서만 받을 수 있으므로
    /// 호출부에서 로컬(UserDefaults)에 보관한다.
    static func createGroup(name: String, type: GroupType) async throws -> CreatedGroup {
        struct Params: Encodable {
            let p_name: String
            let p_type: String
        }
        let created: CreatedGroup = try await Supa.client
            .rpc("create_group", params: Params(p_name: name, p_type: type.rawValue))
            .execute().value
        InviteTokenStore.save(created.inviteToken, groupId: created.groupId)
        return created
    }

    /// 초대 토큰 재발급(기존 토큰 폐기)
    static func rotateInvite(groupId: UUID) async throws -> IssuedInvite {
        struct Params: Encodable { let p_group_id: UUID }
        let issued: IssuedInvite = try await Supa.client
            .rpc("create_invite", params: Params(p_group_id: groupId))
            .execute().value
        InviteTokenStore.save(issued.inviteToken, groupId: groupId)
        return issued
    }

    static func previewInvite(token: String) async throws -> InvitePreview {
        struct Params: Encodable { let p_token: String }
        return try await Supa.client
            .rpc("preview_invite", params: Params(p_token: token))
            .execute().value
    }

    static func acceptInvite(token: String) async throws {
        struct Params: Encodable { let p_token: String }
        try await Supa.client
            .rpc("accept_invite", params: Params(p_token: token))
            .execute()
    }

    static func expandGroup(groupId: UUID) async throws {
        struct Params: Encodable { let p_group_id: UUID }
        try await Supa.client
            .rpc("expand_group", params: Params(p_group_id: groupId))
            .execute()
    }

    static func leaveGroup(groupId: UUID) async throws {
        struct Params: Encodable { let p_group_id: UUID }
        try await Supa.client
            .rpc("leave_group", params: Params(p_group_id: groupId))
            .execute()
    }

    static func updateSharing(
        groupId: UUID, userId: UUID, prefs: SharingPreferences
    ) async throws {
        struct Row: Encodable {
            let group_id: UUID
            let user_id: UUID
            let share_body: Bool
            let share_weight: Bool
            let share_body_fat: Bool
            let share_food: Bool
            let share_workout: Bool
            let share_calorie_balance: Bool
        }
        try await Supa.client.from("sharing_preferences")
            .upsert(Row(
                group_id: groupId, user_id: userId,
                share_body: prefs.shareBody,
                share_weight: prefs.shareWeight,
                share_body_fat: prefs.shareBodyFat,
                share_food: prefs.shareFood,
                share_workout: prefs.shareWorkout,
                share_calorie_balance: prefs.shareCalorieBalance
            ))
            .execute()
    }

    static func rename(groupId: UUID, name: String) async throws {
        try await Supa.client.from("groups")
            .update(["name": name])
            .eq("id", value: groupId)
            .execute()
    }
}

/// 초대 토큰 원문은 서버에 해시로만 저장되므로,
/// 발급받은 쪽에서 공유 UI용으로 로컬에만 보관한다.
enum InviteTokenStore {
    private static func key(_ groupId: UUID) -> String { "invite_token_\(groupId.uuidString)" }

    static func save(_ token: String, groupId: UUID) {
        UserDefaults.standard.set(token, forKey: key(groupId))
    }
    static func load(groupId: UUID) -> String? {
        UserDefaults.standard.string(forKey: key(groupId))
    }
}
