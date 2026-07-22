import Foundation
import AVFoundation
import CoreMedia
import AudioToolbox
import UIKit
import SwiftUI

/// 하루의 클립들을 인스타 스토리용 세로(9:16) 브이로그 한 편으로 합성.
///
///  · 캔버스: 1080×1920 (스토리 규격)
///  · 콘텐츠: 앱 오늘 탭에 보이는 그대로의 4:5(1080×1350) 두 줄 스택을
///    세로 중앙에 배치 — 나머지 위아래는 검은색 레터박스
///  · 두 줄 사이는 오늘 탭 카드처럼 검은 간격으로 분리
///  · 인트로(1.4s) → 세그먼트 → 아웃트로(4s)
///  · 실제 영상은 AVMutableComposition 트랙에 배치하고 transform/crop으로 줄에 맞춤
///  · 텍스트/그라데이션/칩 오버레이는 CoreAnimationTool의 CALayer로 렌더
///  · 마지막에 비트레이트를 낮춰 재인코딩 + 무음 오디오 트랙 추가
///    (파일 크기 축소 & 인스타그램 등 공유 호환성)
final class VlogExporter {

    /// 스토리 캔버스 (9:16)
    static let canvasSize = CGSize(width: 1080, height: 1920)
    /// 실제 콘텐츠 영역 — 앱 화면과 동일한 4:5
    static let contentSize = CGSize(width: 1080, height: 1350)

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

                // 클립이 세그먼트보다 짧으면(특히 반대편 클립이 더 길 때) 남는 구간을
                // 마지막 프레임으로 홀드한다. 안 그러면 그 칸이 빈 채로 사라져 보인다.
                if assetDuration < segDur - 0.05 {
                    let frameDur = 1.0 / 30.0
                    let lastFrameStart = max(0, useDur - frameDur)
                    let lastFrame = CMTimeRange(
                        start: CMTime(seconds: lastFrameStart, preferredTimescale: 600),
                        duration: CMTime(seconds: frameDur, preferredTimescale: 600)
                    )
                    let holdAt = CMTime(seconds: segStart + useDur, preferredTimescale: 600)
                    try track.insertTimeRange(lastFrame, of: videoTrack, at: holdAt)
                    // 1프레임을 남은 시간만큼 늘려 정지 화면(프리즈 프레임)으로
                    track.scaleTimeRange(
                        CMTimeRange(start: holdAt, duration: lastFrame.duration),
                        toDuration: CMTime(seconds: segDur - useDur, preferredTimescale: 600)
                    )
                }

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

        // 5) 내보내기 — 해상도(1080×1920, renderSize)는 유지하되 비트레이트는
        //    표준 1080p 수준으로. HighestQuality는 비트레이트가 과해 파일이 너무 컸음.
        //    (videoComposition.renderSize가 실제 출력 크기를 결정하므로 세로 비율 유지)
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("kilog-\(UUID().uuidString).mp4")
        guard let session = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPreset1920x1080
        ) else { throw ExportError.exportFailed }
        session.outputURL = outURL
        session.outputFileType = .mp4
        session.videoComposition = videoComposition

        let progressTask = Task {
            while !Task.isCancelled {
                progress(Double(session.progress) * 0.65)
                try? await Task.sleep(for: .milliseconds(200))
            }
        }

        await session.export()
        progressTask.cancel()
        guard session.status == .completed else { throw ExportError.exportFailed }

        // 6) 마무리 패스: 비트레이트를 낮춰 파일 크기 축소 + 무음 오디오 트랙 추가.
        //    (오디오가 없는 영상은 인스타그램 등에서 "지원 안 함"으로 거부됨)
        //    실패해도 원본(overlay) 결과를 그대로 쓰도록 best-effort.
        progress(0.7)
        if let finalURL = try? await Self.finalize(outURL, duration: totalSec) {
            try? FileManager.default.removeItem(at: outURL)
            progress(1)
            return finalURL
        }
        progress(1)
        return outURL
    }

    // ── 마무리 패스: 비트레이트 축소 + 무음 오디오 ──────────
    /// 오버레이 합성 결과를 다시 인코딩한다.
    ///  · 비디오: H.264 High, 평균 3.5Mbps (HighestQuality 대비 파일 대폭 축소)
    ///  · 오디오: 무음 AAC 트랙 추가 (오디오 없는 mp4는 일부 앱이 거부)
    static func finalize(_ source: URL, duration: Double) async throws -> URL {
        let asset = AVURLAsset(url: source)
        guard let vTrack = try await asset.loadTracks(withMediaType: .video).first
        else { throw ExportError.exportFailed }
        let natural = try await vTrack.load(.naturalSize)

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("kilog-final-\(UUID().uuidString).mp4")

        let reader = try AVAssetReader(asset: asset)
        let vOut = AVAssetReaderTrackOutput(
            track: vTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            ]
        )
        guard reader.canAdd(vOut) else { throw ExportError.exportFailed }
        reader.add(vOut)

        let writer = try AVAssetWriter(outputURL: outURL, fileType: .mp4)
        let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(natural.width),
            AVVideoHeightKey: Int(natural.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 3_500_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 60,
            ],
        ])
        vIn.expectsMediaDataInRealTime = false
        guard writer.canAdd(vIn) else { throw ExportError.exportFailed }
        writer.add(vIn)

        let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 44_100,
            AVEncoderBitRateKey: 64_000,
        ])
        aIn.expectsMediaDataInRealTime = false
        if writer.canAdd(aIn) { writer.add(aIn) }

        guard reader.startReading(), writer.startWriting() else {
            throw ExportError.exportFailed
        }
        writer.startSession(atSourceTime: .zero)

        // 비디오: 리더 → 라이터
        let vQueue = DispatchQueue(label: "kilog.finalize.v")
        async let videoDone: Void = withCheckedContinuation { cont in
            var resumed = false
            vIn.requestMediaDataWhenReady(on: vQueue) {
                while vIn.isReadyForMoreMediaData {
                    if let sb = vOut.copyNextSampleBuffer() {
                        vIn.append(sb)
                    } else {
                        if !resumed { resumed = true; vIn.markAsFinished(); cont.resume() }
                        return
                    }
                }
            }
        }

        // 오디오: 무음 LPCM 샘플을 만들어 AAC로 인코딩
        let aQueue = DispatchQueue(label: "kilog.finalize.a")
        async let audioDone: Void = Self.appendSilentAudio(
            to: aIn, duration: duration, queue: aQueue
        )

        _ = await (videoDone, audioDone)
        await writer.finishWriting()
        guard writer.status == .completed else { throw ExportError.exportFailed }
        return outURL
    }

    /// 무음 오디오(16-bit LPCM)를 만들어 AAC 라이터 입력에 채운다.
    private static func appendSilentAudio(
        to input: AVAssetWriterInput, duration: Double, queue: DispatchQueue
    ) async {
        let sampleRate: Double = 44_100
        var asbd = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
            mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0
        )
        var format: CMFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil,
            formatDescriptionOut: &format
        ) == noErr, let format else {
            input.markAsFinished(); return
        }

        let chunk = 4096
        let totalFrames = Int(duration * sampleRate)
        var written = 0

        await withCheckedContinuation { cont in
            var resumed = false
            func finish() {
                if !resumed { resumed = true; input.markAsFinished(); cont.resume() }
            }
            input.requestMediaDataWhenReady(on: queue) {
                while input.isReadyForMoreMediaData {
                    if written >= totalFrames { finish(); return }
                    let n = min(chunk, totalFrames - written)
                    let bytes = n * 2
                    var block: CMBlockBuffer?
                    guard CMBlockBufferCreateWithMemoryBlock(
                        allocator: kCFAllocatorDefault, memoryBlock: nil,
                        blockLength: bytes, blockAllocator: kCFAllocatorDefault,
                        customBlockSource: nil, offsetToData: 0, dataLength: bytes,
                        flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block
                    ) == noErr, let block else { finish(); return }
                    CMBlockBufferFillDataBytes(
                        with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes
                    )
                    var sb: CMSampleBuffer?
                    let pts = CMTime(value: CMTimeValue(written),
                                     timescale: CMTimeScale(sampleRate))
                    guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                        allocator: kCFAllocatorDefault, dataBuffer: block,
                        formatDescription: format, sampleCount: CMItemCount(n),
                        presentationTimeStamp: pts, packetDescriptions: nil,
                        sampleBufferOut: &sb
                    ) == noErr, let sb else { finish(); return }
                    input.append(sb)
                    written += n
                }
            }
        }
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
