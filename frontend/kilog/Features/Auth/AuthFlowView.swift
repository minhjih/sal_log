import SwiftUI
import AuthenticationServices
import Auth

/// 웰컴 → 로그인/회원가입 (이메일·Apple·Google·Kakao)
struct AuthFlowView: View {
    @EnvironmentObject private var app: AppState

    enum Step { case welcome, login }
    @State private var step: Step = .welcome

    @State private var isSignUp = true
    @State private var email = ""
    @State private var password = ""
    @State private var nickname = ""
    @State private var busy = false
    @State private var error: String?
    @State private var appleNonce = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                brand
                switch step {
                case .welcome: welcomeCard
                case .login: loginCard
                }
            }
            .padding(20)
            .padding(.top, 38)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(authBackground)
    }

    private var brand: some View {
        VStack(alignment: .leading, spacing: 5) {
            Wordmark()
            Text("같이 기록하고, 같이 확인하는 셋로그")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // ── 웰컴 ─────────────────────────────────────────────
    private var welcomeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("COUPLE FIRST · GROUP READY")
                .font(.system(size: 10.5, weight: .heavy))
                .kerning(1.2)
                .foregroundStyle(Theme.lover)

            Text("혼자 하는 다이어트를\n우리의 기록으로.")
                .font(.system(size: 28, weight: .bold))
                .lineSpacing(4)

            Text("커플로 시작하고, 친구들과도 초대 링크 하나로 같은 셋로그를 만들 수 있어요.")
                .font(.system(size: 12.5))
                .lineSpacing(4)
                .foregroundStyle(Theme.muted)

            Button("시작하기") { step = .login }
                .buttonStyle(DuoButtonStyle())

            Button("초대 링크로 들어왔어요") { step = .login }
                .buttonStyle(GhostButtonStyle())
                .frame(maxWidth: .infinity)
        }
        .padding(20)
        .card(radius: 24)
        .padding(.top, 60)
    }

    // ── 로그인 ────────────────────────────────────────────
    private var loginCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("1 / 3 · 로그인")
                .font(.system(size: 10.5, weight: .heavy))
                .kerning(1.2)
                .foregroundStyle(Theme.lover)

            Text(isSignUp ? "내 계정 만들기" : "다시 만나서 반가워요")
                .font(.system(size: 21, weight: .bold))

            Text("그룹이 바뀌어도 내 운동·식단·인바디 기록은 내 계정에 안전하게 남아요.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.muted)

            // 소셜 로그인
            SignInWithAppleButton(.signIn) { request in
                appleNonce = AuthService.randomNonce()
                request.requestedScopes = [.fullName, .email]
                request.nonce = AuthService.sha256(appleNonce)
            } onCompletion: { result in
                Task { await handleApple(result) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 11))

            HStack(spacing: 7) {
                socialButton("Google") { await tryAuth { try await AuthService.signInWithOAuth(provider: .google) } }
                socialButton("카카오") { await tryAuth { try await AuthService.signInWithOAuth(provider: .kakao) } }
            }

            divider

            if isSignUp {
                field("앱에서 사용할 이름", text: $nickname, prompt: "민지")
            }
            field("이메일", text: $email, prompt: "you@example.com")
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
            secureField("비밀번호 (6자 이상)", text: $password)

            if let error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.me)
            }

            Button {
                Task { await submitEmail() }
            } label: {
                if busy { ProgressView().tint(.black) }
                else { Text(isSignUp ? "가입하고 계속" : "로그인") }
            }
            .buttonStyle(DuoButtonStyle())
            .disabled(busy || email.isEmpty || password.count < 6 || (isSignUp && nickname.isEmpty))

            Button(isSignUp ? "이미 계정이 있어요" : "새 계정 만들기") {
                isSignUp.toggle()
                error = nil
            }
            .buttonStyle(GhostButtonStyle())
            .frame(maxWidth: .infinity)
        }
        .padding(20)
        .card(radius: 24)
    }

    private var divider: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Theme.line).frame(height: 1)
            Text("또는 이메일로")
                .font(.system(size: 11))
                .foregroundStyle(Theme.faint)
                .fixedSize()
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }

    private func socialButton(_ title: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Theme.bg)
                .clipShape(RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.line))
        }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.muted)
            TextField(prompt, text: text)
                .padding(12)
                .background(Theme.bg)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
        }
    }

    private func secureField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.muted)
            SecureField("••••••", text: text)
                .padding(12)
                .background(Theme.bg)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
        }
    }

    // ── 액션 ──────────────────────────────────────────────
    private func submitEmail() async {
        await tryAuth {
            if isSignUp {
                try await AuthService.signUp(email: email, password: password, nickname: nickname)
            } else {
                try await AuthService.signIn(email: email, password: password)
            }
        }
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) async {
        guard
            case .success(let auth) = result,
            let credential = auth.credential as? ASAuthorizationAppleIDCredential
        else { return }
        await tryAuth {
            try await AuthService.signInWithApple(credential: credential, nonce: appleNonce)
        }
    }

    private func tryAuth(_ op: @escaping () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do {
            try await op()
            error = nil
            // authStateChanges 스트림이 phase 전환을 담당
        } catch {
            self.error = friendlyMessage(error)
        }
    }

    private func friendlyMessage(_ error: Error) -> String {
        let raw = error.localizedDescription
        if raw.localizedCaseInsensitiveContains("invalid login") {
            return "이메일 또는 비밀번호가 맞지 않아요."
        }
        if raw.localizedCaseInsensitiveContains("already registered") {
            return "이미 가입된 이메일이에요. 로그인해 주세요."
        }
        return "로그인에 실패했어요. 잠시 후 다시 시도해 주세요."
    }
}

/// sal—log 워드마크 (가운데 대시에 듀오 그라데이션)
struct Wordmark: View {
    var size: CGFloat = 25
    var body: some View {
        HStack(spacing: 0) {
            Text("sal").font(.system(size: size, weight: .light))
            Text("—")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Theme.duo)
            Text("log").font(.system(size: size, weight: .light))
        }
        .kerning(1)
    }
}

private var authBackground: some View {
    ZStack {
        Theme.bg
        RadialGradient(colors: [Theme.lover.opacity(0.15), .clear],
                       center: .init(x: 0.85, y: 0), startRadius: 0, endRadius: 280)
        RadialGradient(colors: [Theme.me.opacity(0.16), .clear],
                       center: .init(x: 0.1, y: 0.2), startRadius: 0, endRadius: 260)
    }
    .ignoresSafeArea()
}
