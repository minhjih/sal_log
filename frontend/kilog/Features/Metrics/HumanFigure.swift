import SwiftUI
import UIKit

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

            // 2) 근육 셰이프 — 불투명 보간 색으로 채워
            //    셰이프가 겹쳐도 이음선(이중 칠)이 생기지 않는다
            var mr: CGFloat = 0, mg: CGFloat = 0, mb: CGFloat = 0, ma: CGFloat = 0
            UIColor(color).getRed(&mr, &mg, &mb, alpha: &ma)
            func fillColor(_ level: Double) -> Color {
                let t = level <= 0.01 ? 0 : CGFloat(0.2 + 0.8 * level)
                let base: CGFloat = 0.34
                return Color(red: base + (mr - base) * t,
                             green: base + (mg - base) * t,
                             blue: base + (mb - base) * t)
            }

            let muscles = side == .front ? Self.frontMuscles : Self.backMuscles
            for muscle in muscles {
                let variants = muscle.mirrored
                    ? [muscle.points, mirroredPts(muscle.points)]
                    : [muscle.points]
                let level = min(1, max(0, intensity(muscle.group)))
                let fill = fillColor(level)

                for pts in variants {
                    context.fill(Self.blob(scaled(pts)), with: .color(fill))
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

    /// 인체 실루엣 (정면 기준, 뒷면 공용) — 정수리부터 시계방향.
    /// 턱선·목·처진 어깨·미튼 손·잘록한 허리·가랑이 V·다리 슬릿·발까지
    /// 실제 사람 비율을 따른다. (오른쪽 절반 정의 후 미러해 생성한 전체 좌표)
    static let bodyOutline: [(CGFloat, CGFloat)] = [
        (50, 2), (55, 3.5), (58, 8), (58.5, 13), (56.5, 18), (53.5, 21.5),
        (53.8, 24), (54.5, 27), (60, 29), (67, 31.5), (73, 34.5), (76.5, 38),
        (78, 43), (78, 48), (77, 55), (75.8, 63), (75, 70), (73.5, 79),
        (71.5, 88), (70.5, 93), (71.5, 97), (70.5, 103), (68, 106.5), (65.8, 103.5),
        (65.3, 98), (65.3, 92), (65.5, 80), (65.5, 70), (64.5, 57), (63, 48),
        (61.2, 46), (60.5, 51), (59.5, 60), (57.5, 70), (58.5, 79), (61.5, 87),
        (64, 94), (65.5, 102), (65.5, 112), (64, 126), (62, 140), (60.5, 148),
        (60.8, 153), (62.5, 161), (61.5, 172), (58, 183), (56.5, 190), (56.5, 196),
        (60.5, 200), (63.5, 204), (59.5, 207), (54.5, 206.5), (53.2, 202), (53, 197),
        (52.5, 190), (52.4, 183), (52, 172), (52.2, 161), (52.6, 152), (52.6, 146),
        (52.5, 136), (52.2, 122), (51.8, 110), (50, 103), (48.2, 110), (47.8, 122),
        (47.5, 136), (47.4, 146), (47.4, 152), (47.8, 161), (48, 172), (47.6, 183),
        (47.5, 190), (47, 197), (46.8, 202), (45.5, 206.5), (40.5, 207), (36.5, 204),
        (39.5, 200), (43.5, 196), (43.5, 190), (42, 183), (38.5, 172), (37.5, 161),
        (39.2, 153), (39.5, 148), (38, 140), (36, 126), (34.5, 112), (34.5, 102),
        (36, 94), (38.5, 87), (41.5, 79), (42.5, 70), (40.5, 60), (39.5, 51),
        (38.8, 46), (37, 48), (35.5, 57), (34.5, 70), (34.5, 80), (34.7, 92),
        (34.7, 98), (34.2, 103.5), (32, 106.5), (29.5, 103), (28.5, 97), (29.5, 93),
        (28.5, 88), (26.5, 79), (25, 70), (24.200000000000003, 63), (23, 55), (22, 48),
        (22, 43), (23.5, 38), (27, 34.5), (33, 31.5), (40, 29), (45.5, 27),
        (46.2, 24), (46.5, 21.5), (43.5, 18), (41.5, 13), (42, 8), (45, 3.5),
    ]

    /// 앞면 근육 — 몸을 타일처럼 채워 실루엣 빈 곳을 최소화
    static let frontMuscles: [MuscleShape] = [
        // 목 (흉쇄유돌근)
        .init(group: "등", points: [(50.8, 22), (53.3, 21.5), (54, 27), (50.8, 28)], mirrored: false),
        .init(group: "등", points: [(46.7, 21.5), (49.2, 22), (49.2, 28), (46, 27)], mirrored: false),
        // 승모 상부
        .init(group: "등", points: [(54, 28.5), (62, 30), (68, 33), (60, 35), (55, 32.5)], mirrored: true),
        // 삼각근
        .init(group: "어깨", points: [(60, 33), (68, 33.5), (74.5, 38), (75.5, 45), (69.5, 48.5), (64, 42), (61, 36)], mirrored: true),
        // 대흉근
        .init(group: "가슴", points: [(50.8, 34), (60, 35.5), (64, 41), (63, 48), (57, 53.5), (51.5, 54.5), (50.8, 44)], mirrored: true),
        // 이두근
        .init(group: "팔", points: [(65, 50), (70, 51), (71.5, 59), (70.5, 67), (67, 64), (65, 56)], mirrored: true),
        // 전완근
        .init(group: "팔", points: [(66.5, 68), (71.5, 66.5), (73, 76), (71.5, 86), (69, 94), (66.8, 84), (66.5, 75)], mirrored: true),
        // 복직근 — 식스팩 (좌우 × 3단)
        .init(group: "복근", points: [(50.7, 56.5), (55.2, 57.5), (55.7, 62.5), (50.7, 61.5)], mirrored: false),
        .init(group: "복근", points: [(44.8, 57.5), (49.3, 56.5), (49.3, 61.5), (44.3, 62.5)], mirrored: false),
        .init(group: "복근", points: [(50.7, 63.5), (55.7, 64.5), (55.7, 69.5), (50.7, 68.5)], mirrored: false),
        .init(group: "복근", points: [(44.3, 64.5), (49.3, 63.5), (49.3, 68.5), (44.3, 69.5)], mirrored: false),
        .init(group: "복근", points: [(50.7, 70.5), (55.5, 71.5), (55.2, 77), (50.7, 76)], mirrored: false),
        .init(group: "복근", points: [(44.5, 71.5), (49.3, 70.5), (49.3, 76), (44.8, 77)], mirrored: false),
        // 하복부 V존
        .init(group: "복근", points: [(44.8, 78.5), (55.2, 78.5), (54.5, 85), (50, 90.5), (45.5, 85)], mirrored: false),
        // 외복사근 — 갈비 옆까지
        .init(group: "복근", points: [(56.5, 56), (60.5, 60), (61.5, 71), (60, 81), (57, 87), (56.5, 74), (56.3, 64)], mirrored: true),
        // 전거근 (겨드랑이 아래)
        .init(group: "가슴", points: [(58, 54.5), (61.5, 52), (61, 58), (58.5, 56.5)], mirrored: true),
        // 고관절 굴곡근 (하복부 V 옆)
        .init(group: "대퇴", points: [(56.5, 89), (61, 91), (63, 97), (58, 99), (55.5, 94)], mirrored: true),
        // 대퇴 — 외측광근 / 대퇴직근 / 내측광근
        .init(group: "대퇴", points: [(58.5, 101), (63.5, 106), (64.5, 120), (62.5, 134), (59.5, 128), (58.3, 114)], mirrored: true),
        .init(group: "대퇴", points: [(52.5, 100.5), (57.5, 102.5), (58.2, 118), (57, 134), (53.8, 141), (53, 120)], mirrored: true),
        .init(group: "대퇴", points: [(53, 130), (55.8, 135), (56.2, 144.5), (53.5, 146.5), (52.9, 138)], mirrored: true),
        // 무릎
        .init(group: "대퇴", points: [(53.5, 143), (57.5, 142), (58, 149), (54, 150)], mirrored: true),
        // 전경골근 + 비복근 안쪽 머리
        .init(group: "종아리", points: [(53.2, 152), (57, 151), (59.2, 162), (58.2, 176), (55.2, 189), (53.4, 172), (52.9, 160)], mirrored: true),
        .init(group: "종아리", points: [(58.5, 154), (61, 159), (61, 170), (58.8, 166)], mirrored: true),
    ]

    /// 뒷면 근육
    static let backMuscles: [MuscleShape] = [
        // 목
        .init(group: "등", points: [(48, 21.5), (52, 21.5), (52.8, 27), (50, 28.5), (47.2, 27)], mirrored: false),
        // 승모 상부 다이아몬드
        .init(group: "등", points: [(50, 26), (58, 28.5), (65.5, 32), (57, 37.5), (50, 39.5), (43, 37.5), (34.5, 32), (42, 28.5)], mirrored: false),
        // 승모 중하부 (능형근 영역까지 넓게)
        .init(group: "등", points: [(50, 40.5), (59.5, 38.5), (61.5, 44), (55.5, 52), (50, 59), (44.5, 52), (38.5, 44), (40.5, 38.5)], mirrored: false),
        // 후면 삼각근
        .init(group: "어깨", points: [(60, 33), (68, 33.5), (74.5, 38), (75.5, 45), (69.5, 48.5), (64, 42), (61, 36)], mirrored: true),
        // 광배근 — 허리까지 넓게
        .init(group: "등", points: [(56, 44), (62.5, 47), (63.5, 56), (60.5, 68), (55, 78), (52.5, 68), (54, 52)], mirrored: true),
        // 척추기립근 두 줄 — 골반까지
        .init(group: "등", points: [(50.8, 60), (54.5, 63), (54.5, 78), (51.5, 90), (50.8, 78)], mirrored: false),
        .init(group: "등", points: [(45.5, 63), (49.2, 60), (49.2, 78), (48.5, 90), (45.5, 78)], mirrored: false),
        // 요방형근 (허리 옆)
        .init(group: "등", points: [(55, 79), (59.5, 81.5), (58.5, 90), (53.5, 89)], mirrored: true),
        // 삼두근
        .init(group: "팔", points: [(65, 49), (70.5, 50), (72, 58), (71, 66.5), (67, 68.5), (65.5, 60), (65, 53)], mirrored: true),
        // 전완근
        .init(group: "팔", points: [(66.5, 69.5), (71.5, 67.5), (73, 76), (71.5, 86), (69, 94), (66.8, 84), (66.5, 75)], mirrored: true),
        // 둔근 — 중둔근 + 대둔근
        .init(group: "둔근", points: [(51.5, 91.5), (58, 89.5), (62.5, 93.5), (60.5, 99), (53.5, 98)], mirrored: true),
        .init(group: "둔근", points: [(50.8, 99), (58.5, 97.5), (63.5, 103), (63.5, 111), (58, 116.5), (52, 115.5), (50.2, 107)], mirrored: true),
        // 햄스트링 — 대퇴이두 + 반건양근
        .init(group: "햄스트링", points: [(57, 118.5), (62.5, 119.5), (63.5, 132), (61, 145), (57.8, 148.5), (56.8, 132)], mirrored: true),
        .init(group: "햄스트링", points: [(52.4, 118), (56, 119.5), (56, 136), (55, 147.5), (53.2, 143), (52.6, 128)], mirrored: true),
        // 오금 (무릎 뒤)
        .init(group: "햄스트링", points: [(53.5, 147), (58, 146.5), (58.5, 152.5), (54, 153)], mirrored: true),
        // 비복근 — 안/바깥 두 머리
        .init(group: "종아리", points: [(55.8, 154.5), (60.2, 156.5), (61, 166), (59, 177), (55.8, 171), (55, 161)], mirrored: true),
        .init(group: "종아리", points: [(52.8, 155.5), (55.2, 157), (55.2, 171), (54, 177), (52.6, 166)], mirrored: true),
        // 아킬레스/발목
        .init(group: "종아리", points: [(53.2, 179), (56.8, 179), (56.2, 190), (53.6, 190)], mirrored: true),
    ]
}
