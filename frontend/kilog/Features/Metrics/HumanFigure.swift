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

    /// 인체 실루엣 (정면 기준, 뒷면 공용) — 머리부터 시계방향.
    /// 어깨 슬로프·잘록한 허리·무릎·종아리 볼록 등 실제 비율을 따른다.
    static let bodyOutline: [(CGFloat, CGFloat)] = [
        // 머리 (오른쪽부터 시계방향)
        (50, 2), (56, 4), (59, 10), (57, 17), (53, 21),
        // 목 → 승모 슬로프 → 어깨
        (54, 24), (55, 27), (64, 30), (72, 34),
        // 삼각근 볼록
        (77, 39), (79, 46),
        // 팔 바깥: 상완 → 팔꿈치 → 전완 → 손목 → 손
        (80, 55), (79, 64), (78, 72), (76, 82), (73, 93), (71, 101),
        // 손 안쪽 → 팔 안쪽 위로
        (66, 99), (67, 88), (66, 76), (65, 62), (63, 50), (62, 46),
        // 겨드랑이 → 몸통 옆: 가슴 → 허리(잘록) → 골반
        (61, 50), (60, 60), (58, 70), (59, 80), (62, 89), (64, 97),
        // 다리 바깥: 허벅지 → 무릎 → 종아리 볼록 → 발목 → 발
        (66, 106), (65, 122), (63, 138), (60, 150), (62, 160), (61, 172),
        (57, 186), (57, 196), (61, 203),
        // 발바닥 → 안쪽
        (53, 205), (52, 196), (52, 186),
        // 다리 안쪽: 발목 → 종아리 → 무릎 → 허벅지 안 → 가랑이
        (51, 172), (51, 160), (51, 149), (52, 136), (51, 120), (50, 108),
        // ── 왼쪽 미러 ──
        (49, 120), (48, 136), (49, 149), (49, 160), (49, 172),
        (48, 186), (48, 196), (47, 205),
        (39, 203), (43, 196), (43, 186),
        (39, 172), (38, 160), (40, 150), (37, 138), (35, 122), (34, 106),
        (36, 97), (38, 89), (41, 80), (42, 70), (40, 60), (39, 50),
        (38, 46), (37, 50), (35, 62), (34, 76), (33, 88), (34, 99),
        (29, 101), (27, 93), (24, 82), (22, 72), (21, 64), (20, 55),
        (21, 46), (23, 39),
        (28, 34), (36, 30), (45, 27), (46, 24),
        (47, 21), (43, 17), (41, 10), (44, 4),
    ]

    /// 앞면 근육
    static let frontMuscles: [MuscleShape] = [
        // 승모 상부 (목 옆 슬로프)
        .init(group: "등", points: [(53, 27), (61, 29), (67, 32), (60, 34), (54, 31)], mirrored: true),
        // 삼각근 (둥근 어깨 캡)
        .init(group: "어깨", points: [(60, 32), (68, 33), (75, 38), (76, 45), (70, 48), (64, 42), (61, 36)], mirrored: true),
        // 대흉근 (쇄골 라인 → 겨드랑이로 흐르는 부채꼴)
        .init(group: "가슴", points: [(51, 34), (60, 35), (64, 41), (63, 48), (57, 53), (52, 54), (51, 44)], mirrored: true),
        // 이두근
        .init(group: "팔", points: [(63, 50), (68, 51), (70, 59), (69, 66), (65, 62), (63, 55)], mirrored: true),
        // 전완근 (브라키오 + 굴근)
        .init(group: "팔", points: [(66, 70), (72, 68), (75, 76), (74, 86), (71, 94), (68, 84), (66, 76)], mirrored: true),
        // 복직근 — 식스팩 (좌우 × 3단)
        .init(group: "복근", points: [(50.7, 56), (55, 57), (55.5, 62), (50.7, 61)], mirrored: false),
        .init(group: "복근", points: [(45, 57), (49.3, 56), (49.3, 61), (44.5, 62)], mirrored: false),
        .init(group: "복근", points: [(50.7, 63.5), (55.5, 64), (55.5, 69), (50.7, 68.5)], mirrored: false),
        .init(group: "복근", points: [(44.5, 64), (49.3, 63.5), (49.3, 68.5), (44.5, 69)], mirrored: false),
        .init(group: "복근", points: [(50.7, 70.5), (55.3, 71), (55, 76), (50.7, 75.5)], mirrored: false),
        .init(group: "복근", points: [(44.7, 71), (49.3, 70.5), (49.3, 75.5), (45, 76)], mirrored: false),
        // 하복부 (V존)
        .init(group: "복근", points: [(45, 78), (55, 78), (54, 84), (50, 89), (46, 84)], mirrored: false),
        // 외복사근 (옆구리)
        .init(group: "복근", points: [(56.5, 58), (60, 62), (61, 72), (59, 80), (56.5, 72), (56.5, 64)], mirrored: true),
        // 대퇴 — 외측광근 / 대퇴직근 / 내측광근 / 내전근
        .init(group: "대퇴", points: [(58, 102), (63, 106), (64, 120), (62, 134), (59, 128), (58, 114)], mirrored: true),
        .init(group: "대퇴", points: [(52, 101), (57, 103), (58, 118), (57, 134), (53, 140), (52, 120)], mirrored: true),
        .init(group: "대퇴", points: [(52, 130), (55, 135), (55.5, 144), (52.5, 146), (51, 138)], mirrored: true),
        .init(group: "대퇴", points: [(48.5, 100), (51.5, 100), (51, 114), (50, 124), (49, 114)], mirrored: false),
        // 전경골근 (정강이)
        .init(group: "종아리", points: [(53, 152), (57, 151), (59, 162), (58, 176), (55, 188), (53, 172), (52, 160)], mirrored: true),
        // 비복근 안쪽 머리 (앞에서 살짝 보임)
        .init(group: "종아리", points: [(59, 155), (61, 160), (61, 170), (59, 166)], mirrored: true),
    ]

    /// 뒷면 근육
    static let backMuscles: [MuscleShape] = [
        // 승모 상부 (다이아몬드 상단)
        .init(group: "등", points: [(50, 25), (58, 28), (65, 32), (56, 37), (50, 39), (44, 37), (35, 32), (42, 28)], mirrored: false),
        // 승모 중하부 (척추 따라 내려오는 삼각)
        .init(group: "등", points: [(50, 40), (57, 38), (54, 52), (50, 58), (46, 52), (43, 38)], mirrored: false),
        // 후면 삼각근
        .init(group: "어깨", points: [(60, 32), (68, 33), (75, 38), (76, 45), (70, 48), (64, 42), (61, 36)], mirrored: true),
        // 광배근 (겨드랑이 → 허리로 V자)
        .init(group: "등", points: [(57, 44), (62, 48), (63, 56), (59, 68), (54, 76), (52, 66), (53, 52)], mirrored: true),
        // 척추기립근 (허리 두 줄)
        .init(group: "등", points: [(50.8, 62), (54, 64), (54, 78), (51, 88), (50.8, 76)], mirrored: false),
        .init(group: "등", points: [(46, 64), (49.2, 62), (49.2, 76), (49, 88), (46, 78)], mirrored: false),
        // 삼두근 (장두+외측두)
        .init(group: "팔", points: [(63, 49), (69, 50), (71, 58), (70, 66), (66, 68), (64, 60), (63, 53)], mirrored: true),
        // 전완근
        .init(group: "팔", points: [(66, 70), (72, 68), (75, 76), (74, 86), (71, 94), (68, 84), (66, 76)], mirrored: true),
        // 둔근 — 중둔근(위) + 대둔근(아래 볼록)
        .init(group: "둔근", points: [(52, 92), (58, 90), (62, 94), (60, 99), (54, 98)], mirrored: true),
        .init(group: "둔근", points: [(51, 99), (58, 98), (63, 103), (63, 111), (58, 116), (52, 115), (50, 107)], mirrored: true),
        // 햄스트링 — 대퇴이두(바깥) + 반건양근(안)
        .init(group: "햄스트링", points: [(57, 119), (62, 120), (63, 132), (61, 144), (58, 148), (57, 132)], mirrored: true),
        .init(group: "햄스트링", points: [(51, 118), (55, 120), (55, 136), (54, 147), (51, 142), (50, 128)], mirrored: true),
        // 비복근 — 안/바깥 두 머리
        .init(group: "종아리", points: [(56, 154), (60, 156), (61, 166), (59, 176), (56, 170), (55, 160)], mirrored: true),
        .init(group: "종아리", points: [(51, 155), (54, 157), (54, 170), (52, 176), (50, 166)], mirrored: true),
    ]
}
