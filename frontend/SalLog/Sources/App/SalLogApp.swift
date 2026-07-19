import SwiftUI

@main
struct SalLogApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(app.catalogs)
                .preferredColorScheme(.dark)
                .tint(Theme.me)
                .onAppear { app.start() }
                .onOpenURL { url in
                    // OAuth(app.sallog://auth-callback) + 초대 딥링크(/join/SAL-XXXXXX)
                    AuthService.handleOpenURL(url)
                    if url.path.hasPrefix("/join/") {
                        PendingInvite.token = url.lastPathComponent
                    }
                }
        }
    }
}

/// 초대 링크로 앱이 열렸을 때 로그인 후 자동 입력할 토큰
enum PendingInvite {
    static var token: String?
}

struct RootView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            switch app.phase {
            case .loading:
                ProgressView()
                    .tint(Theme.me)
            case .signedOut:
                AuthFlowView()
            case .needsGroup:
                GroupSetupView()
            case .ready:
                HomeView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: app.phase)
        .alert("알림", isPresented: .init(
            get: { app.errorMessage != nil },
            set: { if !$0 { app.errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(app.errorMessage ?? "")
        }
    }
}
