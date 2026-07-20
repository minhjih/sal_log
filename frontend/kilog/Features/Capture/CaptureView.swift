import SwiftUI
import AVKit
import PhotosUI
import AVFoundation
import UIKit
import Foundation

/// 촬영 → 메타(캡션·시간·태그) → 저장 플로우
struct CaptureView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var catalogs: Catalogs
    @Environment(\.dismiss) private var dismiss

    enum Step { case record, meta }
    @State private var step: Step = .record

    @StateObject private var camera = CameraModel()
    @State private var pickedItem: PhotosPickerItem?

    // 메타
    @State private var videoURL: URL?
    @State private var caption = ""
    @State private var recordedAt = Date()
    @State private var tagMode: TagMode = .none
    @State private var selectedFood: FoodItem?
    @State private var selectedMove: ExerciseItem?
    @State private var minutes = 30
    @State private var saving = false
    @State private var error: String?

    enum TagMode: String, CaseIterable {
        case none = "그냥 일상"
        case food = "먹었어요"
        case move = "움직였어요"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch step {
            case .record: recordStage
            case .meta: metaStage
            }
        }
        .task {
            await camera.configure()
            selectedFood = catalogs.foods.first
            selectedMove = catalogs.exercises.first { $0.name == "러닝 8km/h" } ?? catalogs.exercises.first
        }
        .onDisappear { camera.stop() }
        .onChange(of: camera.recordedURL) {
            if let url = camera.recordedURL {
                videoURL = url
                camera.stop()
                step = .meta
            }
        }
        .onChange(of: pickedItem) {
            Task { await importPicked() }
        }
    }

    // ── 1) 촬영 ───────────────────────────────────────────
    private var recordStage: some View {
        VStack(spacing: 0) {
            ZStack {
                if camera.isAuthorized {
                    CameraPreview(session: camera.session)
                        .ignoresSafeArea(edges: .top)
                } else {
                    VStack(spacing: 8) {
                        Text("카메라를 사용할 수 없어요.\n영상을 올려서 기록해 주세요.")
                            .multilineTextAlignment(.center)
                            .font(.system(size: 14))
                            .lineSpacing(5)
                            .foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                VStack(spacing: 6) {
                    Text(Date(), format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())
                        .font(.system(size: 26, weight: .bold))
                        .kerning(1)
                        .shadow(color: .black.opacity(0.6), radius: 10)

                    Text(camera.isRecording
                         ? String(format: "● %.1fs / %.0fs", camera.elapsed, Timeline.maxClipSec)
                         : "버튼을 꾹 누르는 동안 찍혀요 · 최대 5초")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(.black.opacity(0.4))
                        .clipShape(Capsule())

                    Spacer()
                }
                .padding(.top, 56)
            }

            // 하단 바
            HStack {
                PhotosPicker(selection: $pickedItem, matching: .videos) {
                    Text("올리기")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 56)
                }

                Spacer()

                // 홀드-투-레코드 셔터: 누르는 동안 녹화, 떼면 종료 (최대 5초 자동 종료)
                ZStack {
                    let color = app.myMember.map { Color(hex: $0.colorHex) } ?? Theme.me

                    Circle()
                        .stroke(.white.opacity(camera.isRecording ? 0.35 : 1), lineWidth: 3.5)
                        .frame(width: 70, height: 70)

                    // 5초 진행 링
                    Circle()
                        .trim(from: 0, to: camera.isRecording
                              ? min(1, camera.elapsed / Timeline.maxClipSec) : 0)
                        .stroke(color, style: .init(lineWidth: 3.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 70, height: 70)
                        .animation(.linear(duration: 0.1), value: camera.elapsed)

                    Circle()
                        .fill(color)
                        .frame(width: camera.isRecording ? 40 : 54,
                               height: camera.isRecording ? 40 : 54)
                        .animation(.easeInOut(duration: 0.18), value: camera.isRecording)
                }
                .scaleEffect(camera.isRecording ? 1.12 : 1)
                .animation(.easeInOut(duration: 0.18), value: camera.isRecording)
                .contentShape(Circle().inset(by: -12))
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if !camera.isRecording { camera.startRecording() }
                        }
                        .onEnded { _ in
                            camera.stopRecording()
                        }
                )
                .disabled(!camera.isAuthorized)
                .opacity(camera.isAuthorized ? 1 : 0.35)

                Spacer()

                Button("취소") { dismiss() }
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 56)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 34)
            .padding(.top, 18)
            .padding(.bottom, 40)
            .background(.black)
        }
    }

    // ── 2) 메타 입력 ──────────────────────────────────────
    private var metaStage: some View {
        VStack(spacing: 0) {
            if let videoURL {
                LoopingPlayerView(url: videoURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    TextField("한 줄 캡션 (선택)", text: $caption)
                        .padding(12)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
                        .onChange(of: caption) {
                            caption = String(caption.prefix(24))
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("영상 시간").font(.system(size: 10)).foregroundStyle(Theme.muted)
                        DatePicker("", selection: $recordedAt, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .colorScheme(.dark)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
                }

                // 태그 토글
                HStack(spacing: 0) {
                    ForEach(TagMode.allCases, id: \.self) { mode in
                        Button {
                            tagMode = mode
                        } label: {
                            Text(mode.rawValue)
                                .font(.system(size: 13, weight: tagMode == mode ? .semibold : .regular))
                                .foregroundStyle(tagMode == mode ? Theme.text : Theme.muted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(tagMode == mode ? Theme.surface2 : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(3)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.line))

                if tagMode == .food { foodPicker }
                if tagMode == .move { movePicker }

                if let error {
                    Text(error).font(.system(size: 12)).foregroundStyle(Theme.me)
                }

                Button {
                    Task { await save() }
                } label: {
                    if saving { ProgressView().tint(.black) } else { Text("오늘 영상에 넣기") }
                }
                .buttonStyle(DuoButtonStyle())
                .disabled(saving)
            }
            .padding(16)
            .padding(.bottom, 22)
            .background(Theme.bg)
        }
        .ignoresSafeArea(edges: .top)
    }

    private var foodPicker: some View {
        FlowChips(items: catalogs.foods, isOn: { $0.id == selectedFood?.id }) { item in
            selectedFood = item
        } label: { item in
            (item.name, "+\(item.kcal)")
        }
    }

    private var movePicker: some View {
        VStack(spacing: 10) {
            ScrollView {
                FlowChips(items: catalogs.exercises, isOn: { $0.id == selectedMove?.id }) { item in
                    selectedMove = item
                } label: { item in
                    (item.name, item.bodyPart)
                }
            }
            .frame(maxHeight: 112)

            HStack(spacing: 12) {
                Slider(value: .init(
                    get: { Double(minutes) },
                    set: { minutes = Int($0 / 5) * 5 }
                ), in: 5...120)
                .tint(Theme.green)
                Text("\(minutes)분")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 44, alignment: .trailing)
            }

            if let move = selectedMove {
                let kcal = HealthMath.metKcal(met: move.met,
                                              weightKg: app.myProfile?.weight,
                                              minutes: minutes)
                VStack(alignment: .leading, spacing: 3) {
                    Text("−\(kcal) kcal 자동 계산")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.green)
                    Text("MET \(move.met, specifier: "%.1f") × \(Int(app.myProfile?.weight ?? 60))kg × \(minutes)분 · Compendium 기반")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .card(radius: 12)
            }
        }
    }

    // ── 저장 ──────────────────────────────────────────────
    private func save() async {
        guard let group = app.group, let myId = app.myId else { return }
        saving = true; defer { saving = false }

        var tag: ClipTag?
        switch tagMode {
        case .none: tag = nil
        case .food:
            if let f = selectedFood { tag = .food(name: f.name, kcal: f.kcal) }
        case .move:
            if let m = selectedMove {
                let kcal = HealthMath.metKcal(met: m.met,
                                              weightKg: app.myProfile?.weight,
                                              minutes: minutes)
                tag = .move(name: m.name, kcal: kcal, minutes: minutes, part: m.bodyPart)
            }
        }

        // "영상 시간"은 오늘 날짜 + 선택한 시각으로
        let calendar = Calendar.current
        let hm = calendar.dateComponents([.hour, .minute], from: recordedAt)
        let takenAt = calendar.date(
            bySettingHour: hm.hour ?? 0, minute: hm.minute ?? 0, second: 0, of: Date()
        ) ?? Date()

        let finalCaption = caption.trimmingCharacters(in: .whitespaces).isEmpty
            ? (tag?.name ?? "지금 이 순간")
            : caption.trimmingCharacters(in: .whitespaces)

        do {
            _ = try await ClipService.saveClip(
                groupId: group.id, userId: myId,
                videoFileURL: videoURL,
                caption: finalCaption,
                recordedAt: takenAt,
                tag: tag
            )
            await app.reloadFeed()
            dismiss()
        } catch {
            self.error = "업로드에 실패했어요. 네트워크를 확인해 주세요."
        }
    }

    private func importPicked() async {
        guard let item = pickedItem else { return }
        if let movie = try? await item.loadTransferable(type: PickedMovie.self) {
            videoURL = movie.url
            camera.stop()
            step = .meta
        }
    }
}

/// PhotosPicker에서 영상 파일 URL로 복사해오는 Transferable
struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("picked-\(UUID().uuidString).mp4")
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedMovie(url: dest)
        }
    }
}

/// 무음 루프 미리보기 플레이어
struct LoopingPlayerView: View {
    let url: URL
    @State private var player = AVQueuePlayer()
    @State private var looper: AVPlayerLooper?

    var body: some View {
        PlayerLayerView(player: player)
            .onAppear {
                let item = AVPlayerItem(url: url)
                looper = AVPlayerLooper(player: player, templateItem: item)
                player.isMuted = true
                player.play()
            }
            .onDisappear { player.pause() }
    }
}

/// 카메라 프리뷰 레이어
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}
}

/// 칩 그리드 (음식/운동 선택)
struct FlowChips<Item: Identifiable & Hashable>: View {
    let items: [Item]
    let isOn: (Item) -> Bool
    let action: (Item) -> Void
    let label: (Item) -> (String, String)

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 7)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 7) {
            ForEach(items) { item in
                let (title, sub) = label(item)
                Button { action(item) } label: {
                    HStack(spacing: 4) {
                        Text(title).font(.system(size: 13, weight: isOn(item) ? .semibold : .regular))
                        Text(sub).font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                    .lineLimit(1)
                    .padding(.horizontal, 13).padding(.vertical, 7)
                    .background(isOn(item) ? Theme.surface2 : Theme.surface)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(isOn(item) ? Theme.text : Theme.line))
                }
                .foregroundStyle(Theme.text)
            }
        }
    }
}
