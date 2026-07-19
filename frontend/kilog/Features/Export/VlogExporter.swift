import Foundation
import AVFoundation
import UIKit
import SwiftUI

/// 하루의 클립들을 16:9(960×540) 한 편의 브이로그로 합성.
/// JSX의 canvas + MediaRecorder 내보내기를 AVFoundation으로 재구현:
///  · 인트로(1.4s) → 세그먼트(위/아래 두 줄 분할) → 아웃트로(2.2s)
///  · 실제 영상은 AVMutableComposition 트랙에 배치하고 transform/crop으로 줄에 맞춤
///  · 텍스트/그라데이션/칩 오버레이는 CoreAnimationTool의 CALayer로 렌더
final class VlogExporter {

    // 캔버스 규격 (JSX와 동일)
    static let width: CGFloat = 960
    static let height: CGFloat = 540
    static let introSec = 1.4
    static let outroSec = 2.2

    struct Row {
        let member: MemberOverview
        let stats: HealthMath.DailyStats
    }

    struct Input {
        let segments: [Segment]
        /// clipId → 로컬 임시 파일 (signed URL에서 다운로드해 둔 것)
        let localFiles: [UUID: URL]
        /// clipId → 실제 길이(초)
        let durations: [UUID: Double]
        let topRow: Row
        let bottomRow: Row?
        let dateLabel: String
    }

    enum ExportError: LocalizedError {
        case noSegments, exportFailed
        var errorDescription: String? {
            switch self {
            case .noSegments: return "내보낼 클립이 없어요."
            case .exportFailed: return "영상 합성에 실패했어요."
            }
        }
    }

    // ── 진입점 ────────────────────────────────────────────
    func export(_ input: Input, progress: @escaping (Double) -> Void) async throws -> URL {
        guard !input.segments.isEmpty else { throw ExportError.noSegments }

        // 세그먼트 경계 계산
        let segDurations = input.segments.map {
            Timeline.duration(of: $0, durations: input.durations)
        }
        let totalSec = Self.introSec + segDurations.reduce(0, +) + Self.outroSec
        var bounds: [Double] = [Self.introSec]
        for d in segDurations { bounds.append(bounds.last! + d) }

        // 1) 베이스(배경) 트랙 — 전체 길이를 덮는 무지 배경 영상
        let baseURL = try await Self.makeBackgroundVideo(duration: totalSec)
        let composition = AVMutableComposition()
        let baseAsset = AVURLAsset(url: baseURL)
        guard
            let baseVideoTrack = try await baseAsset.loadTracks(withMediaType: .video).first,
            let baseTrack = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ExportError.exportFailed }
        let baseRange = CMTimeRange(start: .zero,
                                    duration: CMTime(seconds: totalSec, preferredTimescale: 600))
        try baseTrack.insertTimeRange(baseRange, of: baseVideoTrack, at: .zero)

        // 2) 위/아래 줄 트랙에 클립 배치
        let rows: [(row: Row, y: CGFloat)] = [(input.topRow, 0)]
            + (input.bottomRow.map { [($0, Self.height / 2)] } ?? [])

        var instructions: [AVMutableVideoCompositionInstruction] = []
        let baseLayerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: baseTrack)

        var rowTracks: [Int: AVMutableCompositionTrack] = [:]
        for (i, _) in rows.enumerated() {
            rowTracks[i] = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        }

        // 세그먼트마다: 각 줄에 활성 클립 삽입 + 변환 기록
        struct Placement {
            let trackIndex: Int
            let track: AVMutableCompositionTrack
            let assetTrack: AVAssetTrack
            let transform: CGAffineTransform
            let crop: CGRect
            let range: CMTimeRange
        }
        var placements: [Placement] = []

        for (si, segment) in input.segments.enumerated() {
            let segStart = bounds[si]
            let segDur = segDurations[si]
            let at = CMTime(seconds: segStart, preferredTimescale: 600)

            for (ri, rowInfo) in rows.enumerated() {
                guard
                    let clip = segment.clips[rowInfo.row.member.userId],
                    let fileURL = input.localFiles[clip.id],
                    let track = rowTracks[ri]
                else { continue }

                let asset = AVURLAsset(url: fileURL)
                guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first
                else { continue }

                let assetDuration = (try? await asset.load(.duration).seconds) ?? segDur
                let useDur = min(assetDuration, segDur)
                let sourceRange = CMTimeRange(
                    start: .zero,
                    duration: CMTime(seconds: useDur, preferredTimescale: 600)
                )
                try track.insertTimeRange(sourceRange, of: videoTrack, at: at)

                let stripRect = CGRect(x: 0, y: rowInfo.y,
                                       width: Self.width, height: Self.height / 2)
                let natural = try await videoTrack.load(.naturalSize)
                let preferred = try await videoTrack.load(.preferredTransform)
                let (transform, crop) = Self.aspectFill(
                    naturalSize: natural, preferredTransform: preferred, into: stripRect
                )
                placements.append(Placement(
                    trackIndex: ri, track: track, assetTrack: videoTrack,
                    transform: transform, crop: crop,
                    range: CMTimeRange(start: at,
                                       duration: CMTime(seconds: segDur, preferredTimescale: 600))
                ))
            }
        }

        // 3) videoComposition 인스트럭션 — 전체를 하나로 (트랙별 램프 없음, 상시 레이어)
        let mainInstruction = AVMutableVideoCompositionInstruction()
        mainInstruction.timeRange = baseRange

        var layerInstructions: [AVMutableVideoCompositionLayerInstruction] = []
        for (_, track) in rowTracks.sorted(by: { $0.key < $1.key }) {
            let li = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            // 트랙 안의 각 배치 구간에 변환 적용
            for p in placements where p.track === track {
                li.setTransform(p.transform, at: p.range.start)
                li.setCropRectangle(p.crop, at: p.range.start)
                // 구간 밖에서는 투명 처리해 배경이 보이게
                li.setOpacity(1, at: p.range.start)
                li.setOpacity(0, at: p.range.end)
            }
            layerInstructions.append(li)
        }
        layerInstructions.append(baseLayerInstruction)
        mainInstruction.layerInstructions = layerInstructions
        instructions.append(mainInstruction)

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(width: Self.width, height: Self.height)
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = instructions

        // 4) 오버레이 레이어 (인트로/세그먼트 HUD/아웃트로/진행바)
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(x: 0, y: 0, width: Self.width, height: Self.height)
        let parentLayer = CALayer()
        parentLayer.frame = videoLayer.frame
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(Self.overlayLayer(
            input: input, bounds: bounds, segDurations: segDurations,
            totalSec: totalSec, rows: rows.map(\.row)
        ))

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer, in: parentLayer
        )

        // 5) 내보내기
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sal-log-\(UUID().uuidString).mp4")
        guard let session = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPreset960x540
        ) else { throw ExportError.exportFailed }
        session.outputURL = outURL
        session.outputFileType = .mp4
        session.videoComposition = videoComposition

        let progressTask = Task {
            while !Task.isCancelled {
                progress(Double(session.progress))
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        defer { progressTask.cancel() }

        await session.export()
        guard session.status == .completed else { throw ExportError.exportFailed }
        progress(1)
        return outURL
    }

    // ── aspect-fill 변환 계산 ─────────────────────────────
    /// 원본(natural + preferredTransform 적용 후)을 target 스트립에 꽉 채우는
    /// transform과, 넘치는 부분을 잘라낼 crop(소스 좌표) 계산
    static func aspectFill(
        naturalSize: CGSize, preferredTransform: CGAffineTransform, into target: CGRect
    ) -> (CGAffineTransform, CGRect) {
        // 회전 반영된 표시 크기
        let rect = CGRect(origin: .zero, size: naturalSize)
            .applying(preferredTransform)
        let displaySize = CGSize(width: abs(rect.width), height: abs(rect.height))

        let scale = max(target.width / displaySize.width,
                        target.height / displaySize.height)

        // 소스(표시 좌표)에서 보여줄 영역
        let visibleW = target.width / scale
        let visibleH = target.height / scale
        let cropInDisplay = CGRect(
            x: (displaySize.width - visibleW) / 2,
            y: (displaySize.height - visibleH) / 2,
            width: visibleW, height: visibleH
        )

        // preferredTransform 정규화(원점 보정) 후 스케일·이동
        var t = preferredTransform
        t.tx = rect.minX < 0 ? -rect.minX : t.tx
        t.ty = rect.minY < 0 ? -rect.minY : t.ty

        let full = t
            .concatenating(CGAffineTransform(
                translationX: -cropInDisplay.minX, y: -cropInDisplay.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(
                translationX: target.minX, y: target.minY))

        // crop은 소스 원좌표 기준
        let cropInSource = cropInDisplay.applying(t.inverted())
        return (full, cropInSource.standardized)
    }

    // ── 배경(무지) 영상 생성 ──────────────────────────────
    /// AVMutableComposition은 빈 구간을 검정으로 두지만 인트로/아웃트로 동안
    /// 프레임이 없는 문제를 피하려고 배경색 프레임을 저프레임레이트로 생성한다.
    static func makeBackgroundVideo(duration: Double) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bg-\(UUID().uuidString).mp4")

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(width),
            AVVideoHeightKey: Int(height),
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(width),
                kCVPixelBufferHeightKey as String: Int(height),
            ]
        )
        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        guard let pool = adaptor.pixelBufferPool else { throw ExportError.exportFailed }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let pixelBuffer = buffer else { throw ExportError.exportFailed }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: Int(width), height: Int(height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) {
            ctx.setFillColor(UIColor(Theme.bg).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        // 2fps면 충분 (정지 배경)
        let fps: Double = 2
        let frames = Int((duration * fps).rounded(.up)) + 1
        for i in 0..<frames {
            while !writerInput.isReadyForMoreMediaData {
                try? await Task.sleep(for: .milliseconds(10))
            }
            let time = CMTime(seconds: Double(i) / fps, preferredTimescale: 600)
            adaptor.append(pixelBuffer, withPresentationTime: time)
        }
        writerInput.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw ExportError.exportFailed }
        return url
    }
}
