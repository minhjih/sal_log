import Foundation
import Vision
import UIKit

/// 인바디 검사지 OCR — 레이아웃 템플릿 기반 추출.
///
/// InBody 검사지는 섹션 구조가 고정되어 있으므로,
/// "어떤 섹션의 어떤 행에서, 행의 어느 영역에 있는 값을 가져온다"를
/// 템플릿으로 선언하고 엔진이 그대로 수행한다:
///
///   1. 섹션 앵커(체성분분석/골격근·지방분석/비만분석/…) 헤더를 찾아
///      페이지를 세로 밴드로 분할
///   2. 지정된 섹션 밴드 안에서 행 라벨(체중/골격근량/체지방률)을 찾음
///   3. 행 라벨 기준 값 영역(오른쪽, 왼쪽 표 컬럼 폭 이내, 라벨 아래
///      행 높이만큼)에서 측정값을 추출 — 눈금·이력처럼 숫자가 많은
///      줄은 배제하고, 가장 크게 인쇄된 숫자를 채택
///
/// 템플릿 매칭 실패(다른 양식·비스듬한 사진) 시에만 일반 휴리스틱으로 폴백.
enum InBodyOCR {

    struct Result: Equatable {
        var weight: Double?          // kg
        var skeletalMuscle: Double?  // kg
        var bodyFat: Double?         // %

        var isEmpty: Bool { weight == nil && skeletalMuscle == nil && bodyFat == nil }
    }

    enum OCRError: LocalizedError {
        case badImage
        case recognitionFailed

        var errorDescription: String? {
            switch self {
            case .badImage: return "이미지를 읽지 못했어요. 다시 촬영해 주세요."
            case .recognitionFailed: return "검사지에서 숫자를 찾지 못했어요. 직접 입력해 주세요."
            }
        }
    }

    // ═══════════════════════════════════════════════════════
    // 템플릿 선언
    // ═══════════════════════════════════════════════════════

    enum Metric { case weight, skeletalMuscle, bodyFatPct }

    /// "이 섹션의 이 행에서 값을 가져온다"는 선언
    struct FieldSpec {
        let metric: Metric
        let section: String                  // 섹션 앵커 이름 (한글 정규화 비교)
        let rowLabels: [String]              // 행 라벨 후보
        let range: ClosedRange<Double>       // 유효 값 범위
    }

    struct SheetTemplate {
        let name: String
        /// 페이지에 위에서 아래로 나타나는 섹션 헤더들 (세로 밴드 분할 기준)
        let sectionAnchors: [String]
        /// 표 컬럼 폭 (섹션 앵커 시작점부터의 정규화 폭) — 오른쪽 패널 침범 방지
        let columnWidth: CGFloat
        let fields: [FieldSpec]
    }

    /// InBody 표준 결과지 (270/370/570/770 공통 섹션 구조)
    static let inbodyStandard = SheetTemplate(
        name: "inbody-standard",
        sectionAnchors: ["체성분분석", "골격근지방분석", "비만분석", "부위별근육분석", "신체변화"],
        columnWidth: 0.62,
        fields: [
            FieldSpec(metric: .weight, section: "골격근지방분석",
                      rowLabels: ["체중"], range: 30...200),
            FieldSpec(metric: .skeletalMuscle, section: "골격근지방분석",
                      rowLabels: ["골격근량"], range: 10...70),
            FieldSpec(metric: .bodyFatPct, section: "비만분석",
                      rowLabels: ["체지방률", "체지방율"], range: 3...60),
        ]
    )

    // ═══════════════════════════════════════════════════════
    // OCR 라인
    // ═══════════════════════════════════════════════════════

    private struct Line {
        let text: String
        let korean: String         // 한글만 남긴 정규화 텍스트 (라벨 비교용)
        let box: CGRect            // Vision 정규화 좌표 (원점 좌하단, y 위로 증가)
        let numbers: [Double]      // 괄호·물결 범위 제거 후 숫자
        let rawNumberCount: Int    // 제거 전 숫자 개수 (눈금/이력 줄 판별용)
    }

    // ── 진입점 ────────────────────────────────────────────
    static func scan(image: UIImage) async throws -> Result {
        guard let cgImage = image.cgImage else { throw OCRError.badImage }
        let lines = try await recognizeLines(cgImage: cgImage)
        guard !lines.isEmpty else { throw OCRError.recognitionFailed }

        // 1) 템플릿 기반 추출
        var result = extract(template: inbodyStandard, from: lines)

        // 2) 템플릿이 못 채운 값만 일반 휴리스틱으로 폴백
        if result.weight == nil {
            result.weight = genericValue(
                in: lines, keywords: ["체중", "Weight", "몸무게"],
                bannedContext: ["조절", "적정", "목표", "표준", "분석", "평가", "기준"],
                range: 30...200)
        }
        if result.skeletalMuscle == nil {
            result.skeletalMuscle = genericValue(
                in: lines, keywords: ["골격근량", "SMM"],
                bannedContext: ["분석", "평가", "조절"],
                range: 10...70)
        }
        if result.bodyFat == nil {
            result.bodyFat = genericValue(
                in: lines, keywords: ["체지방률", "체지방율", "PBF"],
                bannedContext: ["분석", "평가", "복부", "내장"],
                range: 3...60)
        }

        // 3) 교차 검증: 골격근량은 체중의 15~65%가 정상
        if let w = result.weight, let s = result.skeletalMuscle,
           s >= w * 0.65 || s < w * 0.15 {
            result.skeletalMuscle = nil
        }

        guard !result.isEmpty else { throw OCRError.recognitionFailed }
        return result
    }

    // ═══════════════════════════════════════════════════════
    // 템플릿 엔진
    // ═══════════════════════════════════════════════════════

    private static func extract(template: SheetTemplate, from lines: [Line]) -> Result {
        // 1) 섹션 앵커 → 세로 밴드
        let bands = sectionBands(template: template, lines: lines)
        var result = Result()

        for field in template.fields {
            guard let band = bands[field.section] else { continue }

            // 2) 섹션 밴드 안에서 행 라벨 찾기
            //    (라벨은 표 왼쪽 컬럼에 있음 — 밴드 x 시작 근처)
            let rowLabel = lines.first { line in
                band.contains(y: line.box.midY)
                    && line.box.minX <= band.minX + 0.22
                    && field.rowLabels.contains { line.korean.hasPrefix($0) }
            }
            guard let label = rowLabel else { continue }

            // 3) 행의 값 영역: 라벨 오른쪽 ~ 컬럼 끝, 라벨 높이 기준 위 1줄 ~ 아래 4.5줄
            let h = max(label.box.height, 0.012)
            let area = CGRect(
                x: label.box.maxX - 0.01,
                y: label.box.midY - 4.5 * h,          // 아래(작은 y)로 4.5줄
                width: (band.minX + template.columnWidth) - label.box.maxX,
                height: 5.7 * h                        // 위로 1.2줄 여유 포함
            )

            let value = measuredValue(in: area, lines: lines, range: field.range)
            switch field.metric {
            case .weight: result.weight = value
            case .skeletalMuscle: result.skeletalMuscle = value
            case .bodyFatPct: result.bodyFat = value
            }
        }
        return result
    }

    private struct Band {
        let top: CGFloat       // Vision y (큰 값)
        let bottom: CGFloat    // Vision y (작은 값)
        let minX: CGFloat
        func contains(y: CGFloat) -> Bool { y <= top && y >= bottom }
    }

    /// 섹션 헤더들을 찾아 [섹션명: 세로 밴드]로 반환.
    /// 밴드는 해당 헤더부터 다음으로 발견된 헤더 직전까지.
    private static func sectionBands(
        template: SheetTemplate, lines: [Line]
    ) -> [String: Band] {
        // 앵커 이름 → 헤더 라인 (한글 정규화 prefix 매칭)
        var anchors: [(name: String, line: Line)] = []
        for name in template.sectionAnchors {
            if let line = lines.first(where: { $0.korean.hasPrefix(name) }) {
                anchors.append((name, line))
            }
        }
        // 페이지 위 → 아래 순으로 정렬 (Vision y 내림차순)
        anchors.sort { $0.line.box.midY > $1.line.box.midY }

        var bands: [String: Band] = [:]
        for (index, anchor) in anchors.enumerated() {
            let bottom = index + 1 < anchors.count
                ? anchors[index + 1].line.box.midY
                : max(0, anchor.line.box.midY - 0.25)
            bands[anchor.name] = Band(
                top: anchor.line.box.midY,
                bottom: bottom,
                minX: anchor.line.box.minX
            )
        }
        return bands
    }

    /// 값 영역 안에서 측정값 추출:
    ///  · 숫자가 3개 넘는 줄(막대 눈금·이력·임피던스)은 배제
    ///  · 유효 범위 내 숫자 중 가장 크게 인쇄된 것(측정값은 큰 폰트) 채택,
    ///    같으면 영역 중심에 가까운 것
    private static func measuredValue(
        in area: CGRect, lines: [Line], range: ClosedRange<Double>
    ) -> Double? {
        var best: (value: Double, glyphHeight: CGFloat, distance: CGFloat)?

        for line in lines {
            guard line.rawNumberCount <= 3, !line.numbers.isEmpty else { continue }
            let center = CGPoint(x: line.box.midX, y: line.box.midY)
            guard area.contains(CGPoint(x: line.box.minX, y: center.y)) else { continue }

            for value in line.numbers where range.contains(value) {
                let distance = abs(center.y - area.midY)
                if best == nil
                    || line.box.height > best!.glyphHeight + 0.002
                    || (abs(line.box.height - best!.glyphHeight) <= 0.002
                        && distance < best!.distance) {
                    best = (value, line.box.height, distance)
                }
            }
        }
        return best?.value
    }

    // ═══════════════════════════════════════════════════════
    // 폴백: 일반 휴리스틱 (템플릿이 안 맞는 양식용)
    // ═══════════════════════════════════════════════════════

    private static func genericValue(
        in lines: [Line],
        keywords: [String],
        bannedContext: [String],
        range: ClosedRange<Double>
    ) -> Double? {
        let labels = lines.filter { line in
            keywords.contains { line.text.localizedCaseInsensitiveContains($0) }
                && !bannedContext.contains { line.text.contains($0) }
        }
        guard !labels.isEmpty else { return nil }

        var best: (value: Double, score: Double)?
        for label in labels {
            let h = max(label.box.height, 0.012)
            for candidate in lines {
                guard candidate.rawNumberCount <= 3, !candidate.numbers.isEmpty else { continue }
                let dy = label.box.midY - candidate.box.midY
                guard dy >= -1.2 * h, dy <= 4.5 * h else { continue }
                guard candidate.box.minX >= label.box.minX - 0.03,
                      candidate.box.minX <= label.box.maxX + 0.45 else { continue }

                for value in candidate.numbers where range.contains(value) {
                    let score = Double(candidate.box.height) * 250
                        + 2.0 * (1 - Double(abs(dy)) / Double(4.5 * h))
                        + Double(label.box.midY) * 1.5
                    if best == nil || score > best!.score {
                        best = (value, score)
                    }
                }
            }
        }
        return best?.value
    }

    // ═══════════════════════════════════════════════════════
    // OCR + 텍스트 유틸
    // ═══════════════════════════════════════════════════════

    private static func recognizeLines(cgImage: CGImage) async throws -> [Line] {
        let observations: [VNRecognizedTextObservation] = try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(
                        returning: (request.results as? [VNRecognizedTextObservation]) ?? []
                    )
                }
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ko-KR", "en-US"]
            request.usesLanguageCorrection = false

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: cgImage, options: [:])
                        .perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        return observations.compactMap { obs in
            guard let top = obs.topCandidates(1).first else { return nil }
            let raw = top.string
            return Line(
                text: raw,
                korean: koreanOnly(raw),
                box: obs.boundingBox,
                numbers: numbers(in: stripRanges(raw)),
                rawNumberCount: numbers(in: raw).count
            )
        }
    }

    /// 한글만 남긴다 — "골격근·지방분석 Muscle-Fat" → "골격근지방분석"
    private static func koreanOnly(_ text: String) -> String {
        String(text.unicodeScalars.filter { ("가"..."힣").contains(String($0)) })
    }

    /// "(57.9~78.3)" 같은 괄호 범위와 "49.2~60.2" 같은 물결 범위 제거
    private static func stripRanges(_ text: String) -> String {
        var cleaned = text.replacingOccurrences(
            of: #"\([^)]*\)"#, with: " ", options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"\d{1,3}(?:\.\d{1,2})?\s*~\s*\d{1,3}(?:\.\d{1,2})?"#,
            with: " ", options: .regularExpression
        )
        return cleaned
    }

    private static func numbers(in text: String) -> [Double] {
        let pattern = /(\d{1,3}(?:\.\d{1,2})?)/
        return text.matches(of: pattern).compactMap { Double($0.1) }
    }
}
