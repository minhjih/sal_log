import SwiftUI
import Foundation

/// sal-log 다크 팔레트 (JSX 디자인 시스템 이식)
enum Theme {
    static let bg       = Color(hex: "#0B0B0F")
    static let surface  = Color(hex: "#15151B")
    static let surface2 = Color(hex: "#1D1D25")
    static let line     = Color(hex: "#26262E")
    static let text     = Color(hex: "#F4F2ED")
    static let muted    = Color(hex: "#8C8C97")
    static let faint    = Color(hex: "#55555F")
    static let me       = Color(hex: "#FF7A9E")
    static let lover    = Color(hex: "#6FC3FF")
    static let green    = Color(hex: "#7BE3A0")

    /// 시그니처 듀오 그라데이션 (나 → 파트너)
    static let duo = LinearGradient(
        colors: [me, lover], startPoint: .leading, endPoint: .trailing
    )

    static let memberPalette = ["#FF7A9E", "#6FC3FF", "#7BE3A0", "#C7A6FF", "#FFD36F", "#87E0D1"]
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

// ── 공용 카드/버튼 스타일 ──────────────────────────────────
struct CardBackground: ViewModifier {
    var radius: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Theme.line, lineWidth: 1)
            )
    }
}

extension View {
    func card(radius: CGFloat = 16) -> some View { modifier(CardBackground(radius: radius)) }
}

/// 듀오 그라데이션 주요 CTA 버튼
struct DuoButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color(hex: "#14060C"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.duo)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(Theme.muted)
            .padding(7)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
