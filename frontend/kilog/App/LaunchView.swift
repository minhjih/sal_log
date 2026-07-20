import SwiftUI

/// 앱 시작 랜딩 화면 — KL 로고를 보여주는 동안
/// 백엔드 부트스트랩 + 오늘 피드 + 영상 프리로드가 진행된다.
struct LaunchView: View {
    let progress: Double
    @State private var appeared = false

    var body: some View {
        ZStack {
            // 앱 아이콘과 같은 배경 (다크 + 듀오 글로우)
            Theme.bg.ignoresSafeArea()
            RadialGradient(colors: [Theme.me.opacity(0.16), .clear],
                           center: .init(x: 0.15, y: 0.2), startRadius: 0, endRadius: 300)
                .ignoresSafeArea()
            RadialGradient(colors: [Theme.lover.opacity(0.14), .clear],
                           center: .init(x: 0.9, y: 0.85), startRadius: 0, endRadius: 320)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer()

                KLMark()
                    .frame(width: 96, height: 96)
                    .scaleEffect(appeared ? 1 : 0.85)
                    .opacity(appeared ? 1 : 0)

                VStack(spacing: 8) {
                    Wordmark(size: 30)
                    Text("같이 기록하고, 같이 확인하는 셋로그")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.muted)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)

                Spacer()

                // 프리로딩 진행 바
                VStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.surface2)
                            Capsule()
                                .fill(Theme.duo)
                                .frame(width: geo.size.width * max(0.04, progress))
                                .animation(.easeOut(duration: 0.3), value: progress)
                        }
                    }
                    .frame(width: 180, height: 4)

                    Text(statusText)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.faint)
                        .animation(.none, value: statusText)
                }
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            withAnimation(.spring(duration: 0.6)) { appeared = true }
        }
    }

    private var statusText: String {
        switch progress {
        case ..<0.25: return "연결하는 중…"
        case ..<0.4:  return "오늘 기록 불러오는 중…"
        case ..<1:    return "브이로그 준비 중…"
        default:      return "완료!"
        }
    }
}

/// KL 레터마크 (앱 아이콘과 동일한 형태를 SwiftUI Path로)
struct KLMark: View {
    var body: some View {
        Canvas { context, size in
            let s = size.width / 100
            var path = Path()
            // K 기둥
            path.move(to: CGPoint(x: 25 * s, y: 28 * s))
            path.addLine(to: CGPoint(x: 25 * s, y: 72 * s))
            // K 화살
            path.move(to: CGPoint(x: 46 * s, y: 28 * s))
            path.addLine(to: CGPoint(x: 27 * s, y: 50 * s))
            path.addLine(to: CGPoint(x: 46 * s, y: 72 * s))
            // L
            path.move(to: CGPoint(x: 60 * s, y: 28 * s))
            path.addLine(to: CGPoint(x: 60 * s, y: 72 * s))
            path.addLine(to: CGPoint(x: 78 * s, y: 72 * s))

            context.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [Theme.me, Theme.lover]),
                    startPoint: CGPoint(x: 20 * s, y: 26 * s),
                    endPoint: CGPoint(x: 80 * s, y: 74 * s)
                ),
                style: StrokeStyle(lineWidth: 9.5 * s, lineCap: .round, lineJoin: .round)
            )
        }
    }
}
