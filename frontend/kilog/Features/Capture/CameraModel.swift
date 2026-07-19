import AVFoundation
import UIKit

/// 전면 카메라 6초 클립 녹화 — AVCaptureSession + MovieFileOutput
@MainActor
final class CameraModel: NSObject, ObservableObject {
    @Published var isAuthorized = true
    @Published var isRecording = false
    @Published var elapsed: Double = 0
    @Published var recordedURL: URL?

    let session = AVCaptureSession()
    private let output = AVCaptureMovieFileOutput()
    private var timer: Timer?
    private let sessionQueue = DispatchQueue(label: "sal-log.camera")

    func configure() async {
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

            if let mic = AVCaptureDevice.default(for: .audio),
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
            self.isRecording = false
            self.recordedURL = outputFileURL
        }
    }
}
