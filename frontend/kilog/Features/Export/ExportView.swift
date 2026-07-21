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
                Text("인스타 스토리 규격(9:16) · 화면 그대로 + 검은 여백")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)

                // 미리보기 캔버스 (9:16)
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
                .aspectRatio(9 / 16, contentMode: .fit)
                .frame(maxHeight: 520)

                // 하단 바
                HStack(spacing: 8) {
                    barButton("닫기") { dismiss() }
                    barButton("↺ 다시") { Task { await run() } }

                    if case .done(let url) = stage {
                        ShareLink(item: url,
                                  preview: SharePreview("Kilog 브이로그")) {
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

    /// 요약 카드를 CGImage로 렌더 (아웃트로 배경색과 같은 배경을 깔아 불투명 렌더)
    private func renderCard<V: View>(_ view: V) -> CGImage? {
        let renderer = ImageRenderer(content: view.background(Theme.bg))
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.cgImage
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
            // 1) 영상 클립 준비 — 스플래시에서 받아둔 캐시를 우선 사용
            var localFiles: [UUID: URL] = [:]
            var durations: [UUID: Double] = [:]
            for clip in clips {
                guard clip.clip.videoKey != nil else { continue }
                let local: URL?
                if let cached = app.videoCache[clip.id] {
                    local = cached
                } else {
                    local = try? await ClipService.cachedVideoURL(for: clip.clip)
                }
                guard let local else { continue }
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

            // 아웃트로 요약 이미지 — 오늘의 근육 부하 + 체중 추이 비교
            let members = [myMember] + (app.partner.map { [$0] } ?? [])
            let muscleImage = app.feed.workouts.isEmpty ? nil : renderCard(
                ExportMuscleCard(members: members, workouts: app.feed.workouts)
                    .frame(width: 440, height: 200)
            )
            let weightImage = members.contains(where: { $0.measurements.count >= 2 })
                ? renderCard(ExportWeightCard(members: members)
                    .frame(width: 440, height: 180))
                : nil

            let input = VlogExporter.Input(
                segments: Timeline.buildSegments(clips),
                localFiles: localFiles,
                durations: durations,
                topRow: .init(member: myMember, stats: app.stats(for: myMember.userId)),
                bottomRow: app.partner.map {
                    .init(member: $0, stats: app.stats(for: $0.userId))
                },
                dateLabel: dateFormatter.string(from: Date()),
                muscleImage: muscleImage,
                weightImage: weightImage
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
