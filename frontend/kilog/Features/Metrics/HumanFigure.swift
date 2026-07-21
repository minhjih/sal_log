import SwiftUI

/// 해부학 스타일 근육 자극도 피규어 (앞/뒤).
/// 회색 인체 실루엣 위에 개별 근육 셰이프를 그리고,
/// 근육 그룹별 강도(0~1)만큼 멤버 색으로 칠한다.
///
/// 좌표는 100×220 정규 공간에서 작성했고 렌더 시 스케일된다.
/// 근육 셰이프는 그룹으로 묶여 색이 결정된다:
///   앞면: 어깨(삼각근) 가슴(대흉근) 팔(이두·전완) 복근(복직근·사근)
///         대퇴(대퇴사두) 종아리(정강이)
///   뒷면: 등(승모·광배·기립근) 어깨(후면삼각근) 팔(삼두·전완)
///         둔근 햄스트링 종아리(비복근)
struct MuscleFigure: View {
    enum Side { case front, back }

    let side: Side
    let color: Color
    let intensity: (String) -> Double
    let cardio: Bool

    // ── 렌더 ──────────────────────────────────────────────
    var body: some View {
        Canvas { context, size in
            let sx = size.width / 100
            let sy = size.height / 220

            func scaled(_ pts: [(CGFloat, CGFloat)]) -> [CGPoint] {
                pts.map { CGPoint(x: $0.0 * sx, y: $0.1 * sy) }
            }
            func mirroredPts(_ pts: [(CGFloat, CGFloat)]) -> [(CGFloat, CGFloat)] {
                pts.map { (100 - $0.0, $0.1) }
            }

            // 유산소 글로우
            if cardio {
                let glow = Path(ellipseIn: CGRect(x: size.width * -0.15, y: size.height * 0.1,
                                                  width: size.width * 1.3, height: size.height * 0.85))
                context.fill(glow, with: .radialGradient(
                    Gradient(colors: [color.opacity(0.22), .clear]),
                    center: CGPoint(x: size.width / 2, y: size.height / 2),
                    startRadius: 0, endRadius: size.width
                ))
            }

            // 1) 인체 실루엣 (회색 베이스)
            let bodyPath = Self.blob(scaled(Self.bodyOutline))
            context.fill(bodyPath, with: .color(Color(white: 0.24)))

            // 2) 근육 셰이프
            let muscles = side == .front ? Self.frontMuscles : Self.backMuscles
            for muscle in muscles {
                let variants = muscle.mirrored
                    ? [muscle.points, mirroredPts(muscle.points)]
                    : [muscle.points]
                let level = min(1, max(0, intensity(muscle.group)))

                for pts in variants {
                    let path = Self.blob(scaled(pts))
                    // 미자극: 실루엣보다 살짝 밝은 회색으로 근육 윤곽만
                    context.fill(path, with: .color(Color(white: 0.34)))
                    if level > 0.01 {
                        context.fill(path, with: .color(color.opacity(0.2 + 0.8 * level)))
                    }
                }
            }
        }
        .aspectRatio(100 / 220, contentMode: .fit)
    }

    // ── 부드러운 폐곡선 (중점 quad 스무딩) ─────────────────
    static func blob(_ pts: [CGPoint]) -> Path {
        var path = Path()
        guard pts.count > 2 else { return path }
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
        path.move(to: mid(pts[pts.count - 1], pts[0]))
        for i in 0..<pts.count {
            let next = pts[(i + 1) % pts.count]
            path.addQuadCurve(to: mid(pts[i], next), control: pts[i])
        }
        path.closeSubpath()
        return path
    }

    // ═══════════════════════════════════════════════════════
    // 셰이프 데이터 (100×220, 오른쪽 절반은 mirrored로 복제)
    // ═══════════════════════════════════════════════════════

    struct MuscleShape {
        let group: String
        let points: [(CGFloat, CGFloat)]
        let mirrored: Bool
    }

    /// 인체 실루엣 (정면 기준, 뒷면 공용) — 머리부터 시계방향
    static let bodyOutline: [(CGFloat, CGFloat)] = [
        // 머리 (오른쪽)
        (50, 2), (57, 4), (60, 11), (57, 19), (53, 23),
        // 목·어깨
        (55, 26), (65, 29), (74, 34), (78, 41),
        // 팔 바깥 (오른쪽)
        (81, 52), (81, 66), (78, 82), (76, 95), (71, 101),
        // 손끝 → 팔 안쪽으로
        (67, 97), (68, 84), (69, 68), (66, 52), (63, 45),
        // 몸통 옆 (겨드랑이→허리→골반)
        (64, 52), (62, 64), (61, 76), (63, 86), (66, 95),
        // 다리 바깥 (오른쪽)
        (67, 106), (66, 124), (63, 144), (61, 162), (62, 180), (60, 196), (64, 206),
        // 발 → 다리 안쪽
        (55, 207), (54, 196), (53, 178), (52, 158), (51, 136), (50, 116), (50, 106),
        // ↑ 가랑이 중심 — 왼쪽 다리 안쪽 (미러)
        (50, 116), (49, 136), (48, 158), (47, 178), (46, 196), (45, 207),
        (36, 206), (40, 196), (38, 180), (39, 162), (37, 144), (34, 124), (33, 106),
        // 몸통 왼쪽
        (34, 95), (37, 86), (39, 76), (38, 64), (36, 52), (37, 45),
        // 팔 안쪽 왼쪽 → 손 → 팔 바깥
        (34, 52), (31, 68), (32, 84), (33, 97), (29, 101), (24, 95), (22, 82), (19, 66), (19, 52),
        // 왼쪽 어깨 → 목 → 머리
        (22, 41), (26, 34), (35, 29), (45, 26),
        (47, 23), (43, 19), (40, 11), (43, 4),
    ]

    /// 앞면 근육
    static let frontMuscles: [MuscleShape] = [
        // 삼각근
        .init(group: "어깨", points: [(57, 29), (66, 31), (71, 37), (68, 44), (60, 41)], mirrored: true),
        // 대흉근 (흉골 쪽 1pt 갭)
        .init(group: "가슴", points: [(51, 33), (62, 35), (65, 43), (60, 51), (52, 53)], mirrored: true),
        // 이두근
        .init(group: "팔", points: [(65, 47), (71, 49), (73, 60), (69, 66), (65, 57)], mirrored: true),
        // 전완근
        .init(group: "팔", points: [(69, 69), (74, 68), (77, 80), (73, 92), (69, 82)], mirrored: true),
        // 복직근 (중앙 기둥)
        .init(group: "복근", points: [(44, 56), (56, 56), (58, 72), (56, 88), (50, 95), (44, 88), (42, 72)], mirrored: false),
        // 외복사근
        .init(group: "복근", points: [(58, 58), (62, 61), (63, 74), (60, 84), (58, 72)], mirrored: true),
        // 대퇴사두근
        .init(group: "대퇴", points: [(52, 104), (61, 102), (65, 120), (62, 140), (55, 147), (52, 130)], mirrored: true),
        // 정강이 (전경골근)
        .init(group: "종아리", points: [(54, 152), (60, 150), (62, 168), (60, 186), (55, 191), (53, 170)], mirrored: true),
    ]

    /// 뒷면 근육
    static let backMuscles: [MuscleShape] = [
        // 승모근 (다이아몬드)
        .init(group: "등", points: [(50, 24), (60, 28), (64, 34), (50, 55), (36, 34), (40, 28)], mirrored: false),
        // 후면 삼각근
        .init(group: "어깨", points: [(57, 29), (66, 31), (71, 37), (68, 44), (60, 41)], mirrored: true),
        // 광배근
        .init(group: "등", points: [(52, 45), (63, 47), (65, 58), (59, 71), (52, 77), (51, 60)], mirrored: true),
        // 척추기립근 (허리)
        .init(group: "등", points: [(45, 74), (55, 74), (57, 87), (50, 93), (43, 87)], mirrored: false),
        // 삼두근
        .init(group: "팔", points: [(65, 47), (72, 49), (74, 61), (70, 67), (65, 57)], mirrored: true),
        // 전완근
        .init(group: "팔", points: [(69, 69), (74, 68), (77, 80), (73, 92), (69, 82)], mirrored: true),
        // 둔근
        .init(group: "둔근", points: [(51, 96), (62, 94), (65, 105), (60, 115), (52, 115)], mirrored: true),
        // 햄스트링
        .init(group: "햄스트링", points: [(52, 119), (62, 117), (64, 134), (60, 147), (54, 149), (51, 133)], mirrored: true),
        // 비복근 (종아리)
        .init(group: "종아리", points: [(53, 153), (61, 151), (63, 168), (59, 185), (54, 189), (51, 168)], mirrored: true),
    ]
}
