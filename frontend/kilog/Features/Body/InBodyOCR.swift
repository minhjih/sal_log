import Foundation
import Vision
import UIKit

/// 인바디 검사지 OCR — Vision 텍스트 인식 + InBody 양식 구조 휴리스틱.
///
/// InBody 검사지의 함정들에 맞춘 전략:
///  · "체중"이 여러 섹션(체성분분석 헤더·골격근지방분석·체중조절·신체변화)에
///    등장 → 조절/적정/분석 등이 붙은 라벨은 배제
///  · 측정값은 라벨 오른쪽~아래(막대그래프 눈금 밑)에 큰 글씨로 인쇄
///    → 라벨 기준 공간 창에서 후보를 모으고 글자 크기·근접도로 채점
///  · 막대 눈금(55 70 85 100…)과 이력(65.0 65.0 64.7 66.1)은 숫자가 많은 줄
///    → 숫자 3개 이상인 줄은 후보에서 제외
///  · "(57.9~78.3)" 같은 정상 범위는 괄호째 제거
///  · 마지막에 교차 검증(골격근량 < 체중×0.65 등)으로 오인식 차단
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

    private struct Line {
        let text: String
        let box: CGRect            // Vision 정규화 좌표 (원점 좌하단, y 위로 증가)
        let numbers: [Double]      // 괄호 범위 제거 후 숫자
        let rawNumberCount: Int    // 제거 전 숫자 개수 (눈금/이력 줄 판별용)
    }

    // ── 진입점 ────────────────────────────────────────────
    static func scan(image: UIImage) async throws -> Result {
        guard let cgImage = image.cgImage else { throw OCRError.badImage }

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

        let lines: [Line] = observations.compactMap { obs in
            guard let top = obs.topCandidates(1).first else { return nil }
            let raw = top.string
            let cleaned = stripRanges(raw)
            return Line(
                text: raw,
                box: obs.boundingBox,
                numbers: numbers(in: cleaned),
                rawNumberCount: numbers(in: raw).count
            )
        }
        guard !lines.isEmpty else { throw OCRError.recognitionFailed }

        var result = Result()
        result.weight = bestValue(
            in: lines,
            keywords: ["체중", "Weight", "몸무게"],
            bannedContext: ["조절", "적정", "목표", "표준", "분석", "평가", "감량", "기준"],
            range: 30...200
        )
        result.skeletalMuscle = bestValue(
            in: lines,
            keywords: ["골격근량", "골격근", "SMM", "Skeletal"],
            bannedContext: ["분석", "평가", "조절"],
            range: 10...70
        )
        result.bodyFat = bestValue(
            in: lines,
            keywords: ["체지방률", "체지방율", "PBF", "Percent Body Fat"],
            bannedContext: ["분석", "평가", "복부", "내장"],
            range: 3...60
        )

        // ── 교차 검증: 관계가 비정상이면 의심 값을 버림 ────
        if let w = result.weight, let s = result.skeletalMuscle {
            // 골격근량은 체중의 15~65% 범위가 정상
            if s >= w * 0.65 || s < w * 0.15 {
                result.skeletalMuscle = nil
            }
        }

        guard !result.isEmpty else { throw OCRError.recognitionFailed }
        return result
    }

    // ── 라벨 기준 공간 탐색 + 채점 ────────────────────────
    /// 라벨 줄(키워드 포함, 금지어 미포함)마다 오른쪽~아래 창의 숫자 후보를
    /// 모아 글자 크기·근접도·페이지 위쪽 우선으로 채점해 최고점 값을 반환.
    private static func bestValue(
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
                // 눈금(55 70 85…)·이력(65.0 65.0 64.7 66.1)처럼 숫자가 많은 줄은 측정값이 아님
                guard candidate.rawNumberCount <= 3, !candidate.numbers.isEmpty else { continue }

                // 세로: 같은 줄(±1.2h) ~ 라벨 아래 4.5줄까지 (Vision y는 위로 증가 → 아래 = 작은 y)
                let dy = label.box.midY - candidate.box.midY
                guard dy >= -1.2 * h, dy <= 4.5 * h else { continue }

                // 가로: 라벨 시작점 근처부터 오른쪽 절반 창 안
                guard candidate.box.minX >= label.box.minX - 0.03,
                      candidate.box.minX <= label.box.maxX + 0.45 else { continue }

                for value in candidate.numbers where range.contains(value) {
                    // 측정값은 크게 인쇄됨 → 글자 높이 가중치가 핵심
                    let sizeScore = Double(candidate.box.height) * 250
                    let proximityScore = 2.0 * (1 - Double(abs(dy)) / Double(4.5 * h))
                    let sameRowBonus: Double = abs(dy) <= 0.8 * h ? 1.0 : 0
                    // 본 표(페이지 위쪽)가 이력(아래쪽)보다 우선
                    let topBonus = Double(label.box.midY) * 1.5
                    let score = sizeScore + proximityScore + sameRowBonus + topBonus

                    if best == nil || score > best!.score {
                        best = (value, score)
                    }
                }
            }
        }
        return best?.value
    }

    // ── 텍스트 유틸 ───────────────────────────────────────
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
