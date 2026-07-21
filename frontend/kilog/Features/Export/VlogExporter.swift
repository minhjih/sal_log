import Foundation
import AVFoundation
import UIKit
import SwiftUI

/// 하루의 클립들을 인스타 스토리용 세로(9:16) 브이로그 한 편으로 합성.
///
///  · 캔버스: 1080×1920 (스토리 규격)
///  · 콘텐츠: 캔버스 전체를 위/아래 두 줄로 세로 스택 (레터박스 없음)
///  · 인트로(1.4s) → 세그먼트 → 아웃트로(4s)
///  · 실제 영상은 AVMutableComposition 트랙에 배치하고 transform/crop으로 줄에 맞춤
///  · 텍스트/그라데이션/칩 오버레이는 CoreAnimationTool의 CALayer로 렌더
final class VlogExporter {

    /// 스토리 캔버스 (9:16)
    static let canvasSize = CGSize(width: 1080, height: 1920)
    /// 콘텐츠 영역 — 캔버스 전체 (두 줄 세로 스택)
    static let contentSize = CGSize(width: 1080, height: 1920)

    static let introSec = 1.4
    static let outroSec = 4.0   // 근육 부하·체중 비교까지 보여줄 시간

    var size: CGSize { Self.canvasSize }
    /// 콘텐츠(4:5) 블록의 세로 시작 위치 (위아래 레터박스 여백)
    var contentTop: CGFloat { (size.height - Self.contentSize.height) / 2 }
    var stripHeight: CGFloat { Self.contentSize.height / 2 }
    /// 레이아웃 상수 스케일 (기준 폭 960의 배수)
    var fs: CGFloat { Self.contentSize.width / 960 }

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
        /// 아웃트로 요약 이미지 (ExportView에서 ImageRenderer로 렌더)
        var muscleImage: CGImage?
        var weightImage: CGImage?
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

        // 1) 베이스(배경) 트랙 — 검은 레터박스 + 콘텐츠 영역 배경색
        let baseURL = try await Self.makeBackgroundVideo(
            duration: totalSec, size: size,
            contentRect: CGRect(x: 0, y: contentTop,
                                width: Self.contentSize.width,
                                height: Self.contentSize.height)
        )
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

        // 2) 콘텐츠 영역 안에 위/아래 줄 트랙 배치
        let rows: [(row: Row, y: CGFloat)] = [(input.topRow, contentTop)]
            + (input.bottomRow.map { [($0, contentTop + stripHeight)] } ?? [])

        var rowTracks: [Int: AVMutableCompositionTrack] = [:]
        for (i, _) in rows.enumerated() {
            rowTracks[i] = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        }

        struct Placement {
            let track: AVMutableCompositionTrack
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
                                       width: size.width, height: stripHeight)
                let natural = try await videoTrack.load(.naturalSize)
                let preferred = try await videoTrack.load(.preferredTransform)
                let (transform, crop) = Self.aspectFill(
                    naturalSize: natural, preferredTransform: preferred, into: stripRect
                )
                placements.append(Placement(
                    track: track, transform: transform, crop: crop,
                    range: CMTimeRange(start: at,
                                       duration: CMTime(seconds: segDur, preferredTimescale: 600))
                ))
            }
        }

        // 클립이 하나도 배치되지 않은 줄 트랙은 제거
        // (한 명만 올린 날 — 빈 비디오 트랙이 남아 있으면 내보내기가 실패한다)
        for (i, track) in Array(rowTracks) {
            if !placements.contains(where: { $0.track === track }) {
                composition.removeTrack(track)
                rowTracks[i] = nil
            }
        }

        // 3) videoComposition 인스트럭션
        let mainInstruction = AVMutableVideoCompositionInstruction()
        mainInstruction.timeRange = baseRange

        var layerInstructions: [AVMutableVideoCompositionLayerInstruction] = []
        for (_, track) in rowTracks.sorted(by: { $0.key < $1.key }) {
            let li = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            for p in placements where p.track === track {
                li.setTransform(p.transform, at: p.range.start)
                li.setCropRectangle(p.crop, at: p.range.start)
                li.setOpacity(1, at: p.range.start)
                li.setOpacity(0, at: p.range.end)
            }
            layerInstructions.append(li)
        }
        layerInstructions.append(
            AVMutableVideoCompositionLayerInstruction(assetTrack: baseTrack)
        )
        mainInstruction.layerInstructions = layerInstructions

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = size
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [mainInstruction]

        // 4) 오버레이 레이어 (인트로/세그먼트 HUD/아웃트로/진행바)
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: size)
        let parentLayer = CALayer()
        parentLayer.frame = videoLayer.frame
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(overlayLayer(
            input: input, bounds: bounds, segDurations: segDurations,
            totalSec: totalSec, rows: rows.map(\.row)
        ))

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer, in: parentLayer
        )

        // 5) 내보내기 — renderSize(1080×1920)를 그대로 살리기 위해 HighestQuality
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("kilog-\(UUID().uuidString).mp4")
        guard let session = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetHighestQuality
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
        let rect = CGRect(origin: .zero, size: naturalSize)
            .applying(preferredTransform)
        let displaySize = CGSize(width: abs(rect.width), height: abs(rect.height))

        let scale = max(target.width / displaySize.width,
                        target.height / displaySize.height)

        let visibleW = target.width / scale
        let visibleH = target.height / scale
        let cropInDisplay = CGRect(
            x: (displaySize.width - visibleW) / 2,
            y: (displaySize.height - visibleH) / 2,
            width: visibleW, height: visibleH
        )

        var t = preferredTransform
        t.tx = rect.minX < 0 ? -rect.minX : t.tx
        t.ty = rect.minY < 0 ? -rect.minY : t.ty

        let full = t
            .concatenating(CGAffineTransform(
                translationX: -cropInDisplay.minX, y: -cropInDisplay.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(
                translationX: target.minX, y: target.minY))

        let cropInSource = cropInDisplay.applying(t.inverted())
        return (full, cropInSource.standardized)
    }

    // ── 배경(무지) 영상 생성 ──────────────────────────────
    /// 캔버스 전체는 검은색(레터박스), 콘텐츠 영역만 앱 배경색으로 채운다.
    static func makeBackgroundVideo(
        duration: Double, size: CGSize, contentRect: CGRect
    ) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bg-\(UUID().uuidString).mp4")

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
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
            width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) {
            ctx.setFillColor(UIColor.black.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            // CGContext는 좌하단 원점이라 y 반전
            let flipped = CGRect(
                x: contentRect.minX,
                y: size.height - contentRect.maxY,
                width: contentRect.width, height: contentRect.height
            )
            ctx.setFillColor(UIColor(Theme.bg).cgColor)
            ctx.fill(flipped)
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
