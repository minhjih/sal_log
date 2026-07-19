import Foundation
import Supabase
import AuthenticationServices
import CryptoKit
import Auth

/// Supabase Auth 래퍼 — 이메일/비밀번호, Apple, Google·Kakao(OAuth)
enum AuthService {

    static var currentUserId: UUID? {
        Supa.client.auth.currentSession?.user.id
    }

    // ── 이메일 ────────────────────────────────────────────
    static func signUp(email: String, password: String, nickname: String) async throws {
        try await Supa.client.auth.signUp(
            email: email,
            password: password,
            data: ["nickname": .string(String(nickname.prefix(12)))]
        )
    }

    static func signIn(email: String, password: String) async throws {
        try await Supa.client.auth.signIn(email: email, password: password)
    }

    // ── Sign in with Apple (네이티브 idToken 교환) ─────────
    static func signInWithApple(
        credential: ASAuthorizationAppleIDCredential, nonce: String
    ) async throws {
        guard
            let tokenData = credential.identityToken,
            let idToken = String(data: tokenData, encoding: .utf8)
        else { throw AuthError.missingAppleToken }

        try await Supa.client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
        )

        // 최초 가입이면 Apple이 준 이름을 닉네임으로
        if let name = credential.fullName?.givenName, !name.isEmpty {
            try? await Supa.client.from("users")
                .update(["nickname": String(name.prefix(12))])
                .eq("id", value: Supa.client.auth.currentSession!.user.id)
                .eq("nickname", value: "")
                .execute()
        }
    }

    // ── Google / Kakao (ASWebAuthenticationSession OAuth) ──
    static func signInWithOAuth(provider: Provider) async throws {
        try await Supa.client.auth.signInWithOAuth(
            provider: provider,
            redirectTo: SupabaseConfig.redirectURL
        )
    }

    static func handleOpenURL(_ url: URL) {
        Supa.client.auth.handle(url)
    }

    static func signOut() async {
        try? await Supa.client.auth.signOut()
    }

    enum AuthError: LocalizedError {
        case missingAppleToken
        var errorDescription: String? {
            "Apple 로그인 토큰을 받지 못했어요. 다시 시도해 주세요."
        }
    }

    // ── Apple 로그인 nonce 유틸 ───────────────────────────
    static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            if SecRandomCopyBytes(kSecRandomDefault, 1, &random) == errSecSuccess,
               random < charset.count {
                result.append(charset[Int(random)])
                remaining -= 1
            }
        }
        return result
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
