import AVFoundation
import UIKit
import Combine
import Foundation

/// 전면 카메라 홀드-투-레코드 클립 녹화(최대 5초) — AVCaptureSession + MovieFileOutput
@MainActor
final class CameraModel: NSObject, ObservableObject {
    @Published var isAuthorized = true
    @Published var isRecording = false
    @Published var elapsed: Double = 0
    @Published var recordedURL: URL?

    let session = AVCaptureSession()
    private let output = AVCaptureMovieFileOutput()
    private var timer: Timer?
    private let sessionQueue = DispatchQueue(label: "kilog.camera")
    /// 기기 기울기에 맞는 영상 회전각 제공 — 가로로 찍으면 가로 영상으로 저장됨
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?

    /// Info.plist에 권한 문구가 없는 상태로 장치에 접근하면 iOS가 앱을 즉시
    /// 종료시키므로(TCC 크래시), 문구 존재 여부를 먼저 확인한다.
    private static func hasUsageDescription(_ key: String) -> Bool {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String)?.isEmpty == false
    }

    func configure() async {
        guard Self.hasUsageDescription("NSCameraUsageDescription") else {
            assertionFailure("Info.plist에 NSCameraUsageDescription이 없습니다 — 카메라 접근 시 크래시 방지를 위해 비활성화")
            isAuthorized = false; return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                isAuthorized = false; return
            }
        default:
            isAuthorized = false; return
        }

        sessionQueue.async { [self] in
            session.beginConfiguration()
            session.sessionPreset = .high

            guard
                let camera = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                     for: .video, position: .front),
                let videoInput = try? AVCaptureDeviceInput(device: camera),
                session.canAddInput(videoInput)
            else {
                session.commitConfiguration()
                Task { @MainActor in self.isAuthorized = false }
                return
            }
            session.addInput(videoInput)
            Task { @MainActor in
                self.rotationCoordinator = AVCaptureDevice.RotationCoordinator(
                    device: camera, previewLayer: nil
                )
            }

            // 마이크는 권한 문구가 있을 때만 붙인다 — 없으면 무음 녹화로 진행
            // (NSMicrophoneUsageDescription 누락 시 여기서 TCC 크래시가 났었음)
            if Self.hasUsageDescription("NSMicrophoneUsageDescription"),
               let mic = AVCaptureDevice.default(for: .audio),
               let audioInput = try? AVCaptureDeviceInput(device: mic),
               session.canAddInput(audioInput) {
                session.addInput(audioInput)
            }

            if session.canAddOutput(output) {
                session.addOutput(output)
                output.maxRecordedDuration = CMTime(
                    seconds: Timeline.maxClipSec, preferredTimescale: 600
                )
            }
            session.commitConfiguration()
            session.startRunning()
        }
    }

    func stop() {
        timer?.invalidate()
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func startRecording() {
        guard !isRecording, session.isRunning else { return }

        // 녹화 시작 시점의 기기 방향을 영상 회전 메타데이터에 반영
        if let connection = output.connection(with: .video) {
            let angle = rotationCoordinator?.videoRotationAngleForHorizonLevelCapture ?? 90
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip-\(UUID().uuidString).mp4")
        output.startRecording(to: url, recordingDelegate: self)
        isRecording = true
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.elapsed += 0.1
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        output.stopRecording()   // 최대 길이 도달 시에는 델리게이트가 알아서 호출됨
    }
}

extension CameraModel: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        // maxRecordedDuration 도달로 끝난 경우도 파일은 유효함
        Task { @MainActor in
            self.timer?.invalidate()
            let held = self.elapsed
            self.isRecording = false
            // 홀드가 너무 짧으면(실수로 스친 탭) 폐기
            if held >= 0.3 {
                self.recordedURL = outputFileURL
            } else {
                try? FileManager.default.removeItem(at: outputFileURL)
                self.elapsed = 0
            }
        }
    }
}
