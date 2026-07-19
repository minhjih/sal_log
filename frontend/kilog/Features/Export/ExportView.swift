import SwiftUI
import AVKit
import AVFoundation
import Foundation

/// 내보내기 화면: 클립 다운로드 → 합성 → 미리보기 → 공유/저장
struct ExportView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    enum Stage: Equatable {
        case preparing        // 클립 다운로드
        case rendering(Double)
        case done(URL)
        case failed(String)
    }
    @State private var stage: Stage = .preparing
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: 12) {
                // 미리보기 캔버스 (16:9)
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Theme.bg)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line))

                    switch stage {
                    case .preparing:
                        VStack(spacing: 10) {
                            ProgressView().tint(Theme.me)
                            Text("클립 모으는 중…")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.muted)
                        }
                    case .rendering(let p):
                        VStack(spacing: 10) {
                            ProgressView(value: p).tint(Theme.me)
                                .frame(width: 180)
                            Text("한 편으로 합치는 중… \(Int(p * 100))%")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.muted)
                        }
                    case .done:
                        if let player {
                            PlayerLayerView(player: player)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                    case .failed(let message):
                        Text(message)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)

                // 하단 바
                HStack(spacing: 8) {
                    barButton("닫기") { dismiss() }
                    barButton("↺ 다시") { Task { await run() } }

                    if case .done(let url) = stage {
                        ShareLink(item: url,
                                  preview: SharePreview("sal-log 브이로그")) {
                            Text("브이로그 공유")
                                .font(.system(size: 13.5, weight: .bold))
                                .foregroundStyle(Color(hex: "#14060C"))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Theme.duo)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Text("합치는 중…")
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(Color(hex: "#14060C").opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.duo.opacity(0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(16)
        }
        .task { await run() }
        .onDisappear { player?.pause() }
    }

    private func barButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
        }
    }

    // ── 파이프라인 ────────────────────────────────────────
    private func run() async {
        guard let myMember = app.myMember else {
            stage = .failed("멤버 정보를 불러오지 못했어요.")
            return
        }
        let clips = app.feed.clips
        guard !clips.isEmpty else {
            stage = .failed("오늘 찍은 클립이 아직 없어요.\n첫 장면부터 찍어볼까요?")
            return
        }

        stage = .preparing
        player = nil

        do {
            // 1) 영상 클립 로컬 다운로드 + 길이 측정
            var localFiles: [UUID: URL] = [:]
            var durations: [UUID: Double] = [:]
            for clip in clips {
                guard let key = clip.clip.videoKey else { continue }
                let signed = try await ClipService.signedVideoURL(for: key)
                let (data, _) = try await URLSession.shared.data(from: signed)
                let local = FileManager.default.temporaryDirectory
                    .appendingPathComponent("export-\(clip.id.uuidString).mp4")
                try data.write(to: local)
                localFiles[clip.id] = local
                let asset = AVURLAsset(url: local)
                if let sec = try? await asset.load(.duration).seconds,
                   sec.isFinite, sec > 0 {
                    durations[clip.id] = sec
                }
            }

            // 2) 합성
            stage = .rendering(0)
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "ko_KR")
            dateFormatter.dateFormat = "M.d E"

            let input = VlogExporter.Input(
                segments: Timeline.buildSegments(clips),
                localFiles: localFiles,
                durations: durations,
                topRow: .init(member: myMember, stats: app.stats(for: myMember.userId)),
                bottomRow: app.partner.map {
                    .init(member: $0, stats: app.stats(for: $0.userId))
                },
                dateLabel: dateFormatter.string(from: Date())
            )

            let output = try await VlogExporter().export(input) { p in
                Task { @MainActor in
                    if case .rendering = stage { stage = .rendering(p) }
                }
            }

            // 3) 미리보기 재생
            let queue = AVQueuePlayer(url: output)
            queue.isMuted = false
            player = queue
            queue.play()
            stage = .done(output)
        } catch {
            stage = .failed((error as? LocalizedError)?.errorDescription
                            ?? "영상 합성에 실패했어요. 다시 시도해 주세요.")
        }
    }
}
