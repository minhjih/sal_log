import Foundation
import Supabase
import PostgREST

/// 계정 공개 신원(users 테이블) 관련
enum UserService {
    static func updateNickname(userId: UUID, nickname: String) async throws {
        let trimmed = String(nickname.trimmingCharacters(in: .whitespaces).prefix(12))
        try await Supa.client.from("users")
            .update(["nickname": trimmed])
            .eq("id", value: userId)
            .execute()
    }
}
