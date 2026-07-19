import Foundation
import Vision
import UIKit

/// 인바디 검사지 OCR — JSX의 setTimeout 데모를 Vision 텍스트 인식으로 대체.
///
/// 전략:
///  1. VNRecognizeTextRequest(ko-KR)로 전체 텍스트 + 위치 인식
///  2. "체중/골격근량/체지방률" 키워드를 찾고, 같은 줄(세로로 근접)의
///     숫자 중 항목별 유효 범위에 드는 값을 매칭
///  3. 키워드 매칭 실패 시, 유효 범위 기반 휴리스틱으로 폴백
enum InBodyOCR {

    struct Result: Equatable {
        var weight: Double?          // kg (20~300)
        var skeletalMuscle: Double?  // kg (5~80)
        var bodyFat: Double?         // % (1~70)

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

        let lines: [(text: String, box: CGRect)] = observations.compactMap { obs in
            guard let top = obs.topCandidates(1).first else { return nil }
            return (top.string, obs.boundingBox)
        }
        guard !lines.isEmpty else { throw OCRError.recognitionFailed }

        var result = Result()
        result.weight = value(near: ["체중", "Weight", "몸무게"], in: lines, range: 20...300)
        result.skeletalMuscle = value(near: ["골격근량", "골격근", "SMM", "Skeletal"], in: lines, range: 5...80)
        result.bodyFat = value(near: ["체지방률", "체지방율", "PBF", "Percent Body Fat"], in: lines, range: 1...70)

        // 키워드 매칭 실패분은 범위 휴리스틱으로 보충
        if result.isEmpty {
            fallbackByRange(lines: lines, into: &result)
        }
        guard !result.isEmpty else { throw OCRError.recognitionFailed }
        return result
    }

    // ── 키워드 주변 숫자 매칭 ─────────────────────────────
    private static func value(
        near keywords: [String],
        in lines: [(text: String, box: CGRect)],
        range: ClosedRange<Double>
    ) -> Double? {
        for (text, box) in lines {
            guard keywords.contains(where: { text.localizedCaseInsensitiveContains($0) }) else { continue }

            // 같은 텍스트 안에 숫자가 붙어있는 경우 ("체중 54.0")
            if let n = numbers(in: text).first(where: { range.contains($0) }) {
                return n
            }
            // 세로로 같은 줄(중심 y 근접)에 있는 다른 블록의 숫자
            let cy = box.midY
            let sameRow = lines
                .filter { abs($0.box.midY - cy) < max(box.height, 0.02) }
                .sorted { $0.box.minX < $1.box.minX }
            for other in sameRow {
                if let n = numbers(in: other.text).first(where: { range.contains($0) }) {
                    return n
                }
            }
        }
        return nil
    }

    /// 키워드 인식이 전부 실패한 경우: 소수점 숫자들을 항목별 범위로 분류
    private static func fallbackByRange(
        lines: [(text: String, box: CGRect)], into result: inout Result
    ) {
        let decimals = lines
            .flatMap { numbers(in: $0.text) }
            .filter { $0.truncatingRemainder(dividingBy: 1) != 0 }  // 인바디 수치는 대부분 소수 1자리

        result.weight = result.weight ?? decimals.first { (35...150).contains($0) }
        result.skeletalMuscle = result.skeletalMuscle ?? decimals.first {
            (15...50).contains($0) && $0 != result.weight
        }
        result.bodyFat = result.bodyFat ?? decimals.first {
            (5...55).contains($0) && $0 != result.weight && $0 != result.skeletalMuscle
        }
    }

    private static func numbers(in text: String) -> [Double] {
        let pattern = /(\d{1,3}(?:\.\d{1,2})?)/
        return text.matches(of: pattern).compactMap { Double($0.1) }
    }
}
