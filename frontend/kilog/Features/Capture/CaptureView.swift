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

    // 목록에 없는 음식 직접 입력
    @State private var useCustomFood = false
    @State private var customFoodName = ""
    @State private var customFoodKcal: Int?

    // 목록에 없는 운동 직접 입력
    @State private var useCustomMove = false
    @State private var customMoveName = ""
    @State private var customMoveKcal: Int?
    @State private var customMovePart = "전신"

    // 웨이트류(strength) 입력: 무게 × 횟수 × 세트
    @State private var strengthWeight = 40
    @State private var strengthReps = 10
    @State private var strengthSets = 3

    /// 세트당 준비·휴식 포함 약 2.5분으로 환산해 MET 계산에 사용
    private var strengthMinutes: Int {
        max(5, Int((Double(strengthSets) * 2.5).rounded()))
    }

    // 개인 즐겨찾기 (직접 입력 이력, 자주 쓴 순)
    @State private var foodFavorites: [FavoriteEntry] = []
    @State private var workoutFavorites: [FavoriteEntry] = []

    // 운동 검색·필터 (Compendium 기반 카탈로그 ~100종)
    @State private var moveQuery = ""
    @State private var moveCategory = "전체"
    private static let moveCategories = ["전체", "유산소", "하체", "상체", "코어", "전신"]

    private var filteredExercises: [ExerciseItem] {
        let query = moveQuery.trimmingCharacters(in: .whitespaces)
        return catalogs.exercises.filter { item in
            let categoryOK = moveCategory == "전체" || item.bodyPart == moveCategory
            let queryOK = query.isEmpty
                || item.name.localizedCaseInsensitiveContains(query)
            return categoryOK && queryOK
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch step {
            case .record: recordStage
            case .meta: metaStage
            }
        }
        .sheet(isPresented: .init(
            get: { step == .meta },
            set: { _ in }   // 시트 자체 닫기 방지 — 저장 또는 우상단 X로만 종료
        )) {
            tagSheet
        }
        .task {
            await camera.configure()
            selectedFood = catalogs.foods.first
            selectedMove = catalogs.exercises.first { $0.name == "러닝 8km/h" } ?? catalogs.exercises.first
            foodFavorites = (try? await FavoritesService.fetch(kind: .food)) ?? []
            workoutFavorites = (try? await FavoritesService.fetch(kind: .workout)) ?? []
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

                // 가로 촬영이 디폴트 — HUD 자체를 가로 방향으로 눕혀서
                // 자연스럽게 폰을 돌려 찍게 한다 (폰을 왼쪽으로 눕히면 글이 바로 보임)
                HStack {
                    VStack(spacing: 8) {
                        Text(Date(), format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute())
                            .font(.system(size: 26, weight: .bold))
                            .kerning(1)
                            .shadow(color: .black.opacity(0.6), radius: 10)

                        Text(camera.isRecording
                             ? String(format: "● %.1fs / %.0fs", camera.elapsed, Timeline.maxClipSec)
                             : "폰을 눕혀서, 버튼을 꾹 누르는 동안 촬영 · 최대 5초")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(.black.opacity(0.45))
                            .clipShape(Capsule())
                    }
                    .fixedSize()
                    .rotationEffect(.degrees(90))
                    Spacer()
                }
                .padding(.leading, 6)
            }

            // 하단 바 (가로로 들었을 때 읽히도록 라벨도 눕힘)
            HStack {
                PhotosPicker(selection: $pickedItem, matching: .videos) {
                    Text("올리기")
                        .font(.system(size: 14, weight: .semibold))
                        .rotationEffect(.degrees(90))
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

                Button {
                    dismiss()
                } label: {
                    Text("취소")
                        .font(.system(size: 14, weight: .semibold))
                        .rotationEffect(.degrees(90))
                        .frame(width: 56)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 34)
            .padding(.top, 18)
            .padding(.bottom, 40)
            .background(.black)
        }
    }

    // ── 2) 메타 입력 ──────────────────────────────────────
    // 촬영 확인: 영상은 화면 상단에 고정, 입력 시트가 아래를 덮는다.
    // 시트를 위로 쓸어올리면 영상까지 덮이며 입력에 집중하는 구조.
    private var metaStage: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()

                if let videoURL {
                    LoopingPlayerView(url: videoURL)
                        .frame(maxWidth: .infinity)
                        .frame(height: geo.size.height * 0.42)
                        .padding(.top, 44)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.black.opacity(0.5))
                        .clipShape(Circle())
                }
                .padding(.top, 54)
                .padding(.trailing, 18)
            }
        }
    }

    /// 인스타 댓글식 입력 시트 — 처음엔 상단 영상이 보이는 높이,
    /// 위로 쓸면 전체화면(영상이 가려짐), 내리면 다시 원위치
    private var tagSheet: some View {
        ScrollView {
            metaPanel
        }
        .scrollDismissesKeyboard(.interactively)
        .presentationDetents([.fraction(0.52), .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.52)))
        .presentationBackground(Theme.bg)
        .interactiveDismissDisabled()
    }

    private var metaPanel: some View {
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
    }

    private var foodPicker: some View {
        VStack(spacing: 10) {
            // 내 즐겨찾기 — 직접 입력 이력, 자주 쓴 순
            if !foodFavorites.isEmpty {
                favoritesRow(foodFavorites) { fav in
                    useCustomFood = true
                    customFoodName = fav.name
                    customFoodKcal = fav.kcal
                }
            }

            FlowChips(items: catalogs.foods,
                      isOn: { $0.id == selectedFood?.id && !useCustomFood }) { item in
                selectedFood = item
                useCustomFood = false
            } label: { item in
                (item.name, "+\(item.kcal)")
            }

            // 목록에 없는 음식: 직접 입력
            Button {
                useCustomFood.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: useCustomFood ? "checkmark" : "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("목록에 없어요 — 직접 입력")
                        .font(.system(size: 13, weight: useCustomFood ? .semibold : .regular))
                }
                .foregroundStyle(useCustomFood ? Theme.text : Theme.muted)
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(useCustomFood ? Theme.surface2 : Theme.surface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(useCustomFood ? Theme.text : Theme.line))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if useCustomFood {
                HStack(spacing: 8) {
                    TextField("음식 이름 (예: 엄마 김치찌개)", text: $customFoodName)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.line))

                    HStack(spacing: 4) {
                        TextField("kcal", value: $customFoodKcal, format: .number)
                            .keyboardType(.numberPad)
                            .frame(width: 56)
                        Text("kcal").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.line))
                }
                Text("칼로리를 모르면 대략으로 적어도 돼요. 한 끼 보통 500~800kcal 정도예요.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var movePicker: some View {
        VStack(spacing: 10) {
            // 내 즐겨찾기 — 직접 입력 이력, 자주 쓴 순
            if !workoutFavorites.isEmpty {
                favoritesRow(workoutFavorites) { fav in
                    useCustomMove = true
                    customMoveName = fav.name
                    customMoveKcal = fav.kcal
                    customMovePart = fav.bodyPart ?? "전신"
                    if let m = fav.minutes { minutes = m }
                }
            }

            // 검색
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.faint)
                TextField("어떤 운동 했어요?", text: $moveQuery)
                    .font(.system(size: 14))
                if !moveQuery.isEmpty {
                    Button {
                        moveQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.faint)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.line))

            // 카테고리 필터
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Self.moveCategories, id: \.self) { category in
                        Button {
                            moveCategory = category
                        } label: {
                            Text(category)
                                .font(.system(size: 12,
                                              weight: moveCategory == category ? .bold : .regular))
                                .foregroundStyle(moveCategory == category
                                                 ? Color(hex: "#14060C") : Theme.muted)
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(moveCategory == category
                                            ? AnyShapeStyle(Theme.duo)
                                            : AnyShapeStyle(Theme.surface))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(
                                    moveCategory == category ? .clear : Theme.line))
                        }
                    }
                }
            }

            // 운동 리스트 — 선택하면 예상 소모 칼로리가 바로 보임
            ScrollView {
                if filteredExercises.isEmpty {
                    Text("'\(moveQuery)' 검색 결과가 없어요.\n아래에서 직접 입력해 주세요.")
                        .font(.system(size: 12))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                } else {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredExercises) { item in
                            exerciseRow(item)
                        }
                    }
                }
            }
            .frame(height: 200)   // 고정 높이 — 키보드가 올라와도 리스트가 사라지지 않음

            // 목록에 없는 운동: 직접 입력
            Button {
                useCustomMove.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: useCustomMove ? "checkmark" : "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("목록에 없어요 — 직접 입력")
                        .font(.system(size: 13, weight: useCustomMove ? .semibold : .regular))
                }
                .foregroundStyle(useCustomMove ? Theme.text : Theme.muted)
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(useCustomMove ? Theme.surface2 : Theme.surface)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(useCustomMove ? Theme.text : Theme.line))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if useCustomMove {
                HStack(spacing: 8) {
                    TextField("운동 이름 (예: 폴댄스)", text: $customMoveName)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.line))

                    HStack(spacing: 4) {
                        TextField("kcal", value: $customMoveKcal, format: .number)
                            .keyboardType(.numberPad)
                            .frame(width: 56)
                        Text("kcal").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.line))
                }

                // 자극 부위 선택 (코치 분석에 사용)
                HStack(spacing: 7) {
                    ForEach(Catalogs.parts + ["전신"], id: \.self) { part in
                        Button {
                            customMovePart = part
                        } label: {
                            Text(part)
                                .font(.system(size: 12, weight: customMovePart == part ? .bold : .regular))
                                .foregroundStyle(customMovePart == part ? Color(hex: "#14060C") : Theme.faint)
                                .padding(.horizontal, 11).padding(.vertical, 6)
                                .background(customMovePart == part
                                            ? AnyShapeStyle(Theme.duo) : AnyShapeStyle(.clear))
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(
                                    customMovePart == part ? .clear : Theme.line))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("소모 칼로리는 대략이면 돼요. 30분 기준 가볍게 100~150, 땀나게 200~300kcal 정도예요.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 운동 유형별 입력 — 유산소류는 시간, 웨이트류는 무게×횟수×세트
            let isStrength = !useCustomMove && (selectedMove?.isStrength ?? false)

            if !isStrength {
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
            } else {
                HStack(spacing: 8) {
                    strengthStepper("무게", value: $strengthWeight,
                                    range: 0...300, step: 5, unit: "kg")
                    strengthStepper("횟수", value: $strengthReps,
                                    range: 1...50, step: 1, unit: "회")
                    strengthStepper("세트", value: $strengthSets,
                                    range: 1...15, step: 1, unit: "세트")
                }
            }

            if !useCustomMove, let move = selectedMove {
                let effectiveMinutes = isStrength ? strengthMinutes : minutes
                let kcal = HealthMath.metKcal(met: move.met,
                                              weightKg: app.myProfile?.weight,
                                              minutes: effectiveMinutes)
                VStack(alignment: .leading, spacing: 3) {
                    Text("−\(kcal) kcal 자동 계산")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.green)
                    Text(isStrength
                         ? "\(strengthWeight)kg × \(strengthReps)회 × \(strengthSets)세트 · 세트당 약 2.5분 환산"
                         : "MET \(move.met, specifier: "%.1f") × \(Int(app.myProfile?.weight ?? 60))kg × \(minutes)분 · Compendium 기반")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .card(radius: 12)
            }
        }
    }

    /// 무게/횟수/세트 입력 셀 (± 버튼)
    private func strengthStepper(
        _ label: String, value: Binding<Int>,
        range: ClosedRange<Int>, step: Int, unit: String
    ) -> some View {
        VStack(spacing: 6) {
            Text(label).font(.system(size: 10.5)).foregroundStyle(Theme.muted)
            HStack(spacing: 0) {
                Button {
                    value.wrappedValue = max(range.lowerBound, value.wrappedValue - step)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 30)
                }
                Text("\(value.wrappedValue)")
                    .font(.system(size: 15, weight: .bold))
                    .frame(minWidth: 34)
                Button {
                    value.wrappedValue = min(range.upperBound, value.wrappedValue + step)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 30)
                }
            }
            .foregroundStyle(Theme.text)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
            Text(unit).font(.system(size: 9.5)).foregroundStyle(Theme.faint)
        }
        .frame(maxWidth: .infinity)
    }

    /// 운동 리스트 행 — 이름·부위·현재 시간 기준 예상 칼로리
    private func exerciseRow(_ item: ExerciseItem) -> some View {
        let selected = item.id == selectedMove?.id && !useCustomMove
        let estimate = HealthMath.metKcal(met: item.met,
                                          weightKg: app.myProfile?.weight,
                                          minutes: minutes)
        return Button {
            selectedMove = item
            useCustomMove = false
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 13.5, weight: selected ? .bold : .medium))
                    Text("\(item.bodyPart) · MET \(item.met, specifier: "%.1f")")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Text("−\(estimate)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.green)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(selected ? Theme.lover : Theme.faint)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(selected ? Theme.surface2 : Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(selected ? Theme.lover : Theme.line))
        }
        .foregroundStyle(Theme.text)
    }

    /// 즐겨찾기 칩 한 줄 (음식/운동 공용)
    private func favoritesRow(
        _ favorites: [FavoriteEntry], onPick: @escaping (FavoriteEntry) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("내 즐겨찾기")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(Theme.lover)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(favorites) { fav in
                        Button {
                            onPick(fav)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Theme.lover)
                                Text(fav.name).font(.system(size: 13))
                                Text("\(fav.kcal)")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.muted)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Theme.surface)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Theme.lover.opacity(0.4)))
                        }
                        .foregroundStyle(Theme.text)
                    }
                }
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
            if useCustomFood {
                let name = customFoodName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, let kcal = customFoodKcal, (0...5000).contains(kcal) else {
                    error = "직접 입력한 음식의 이름과 칼로리(0~5000)를 확인해 주세요."
                    saving = false
                    return
                }
                tag = .food(name: String(name.prefix(20)), kcal: kcal)
            } else if let f = selectedFood {
                tag = .food(name: f.name, kcal: f.kcal)
            }
        case .move:
            if useCustomMove {
                let name = customMoveName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, let kcal = customMoveKcal, (0...5000).contains(kcal) else {
                    error = "직접 입력한 운동의 이름과 칼로리(0~5000)를 확인해 주세요."
                    saving = false
                    return
                }
                tag = .move(name: String(name.prefix(20)), kcal: kcal,
                            minutes: minutes, part: customMovePart)
            } else if let m = selectedMove {
                if m.isStrength {
                    // 웨이트류: 무게×횟수×세트를 이름에 담고, 시간은 세트 기준 환산
                    let kcal = HealthMath.metKcal(met: m.met,
                                                  weightKg: app.myProfile?.weight,
                                                  minutes: strengthMinutes)
                    let detail = "\(m.name) \(strengthWeight)kg×\(strengthReps)×\(strengthSets)세트"
                    tag = .move(name: detail, kcal: kcal,
                                minutes: strengthMinutes, part: m.bodyPart)
                } else {
                    let kcal = HealthMath.metKcal(met: m.met,
                                                  weightKg: app.myProfile?.weight,
                                                  minutes: minutes)
                    tag = .move(name: m.name, kcal: kcal, minutes: minutes, part: m.bodyPart)
                }
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
            // 직접 입력한 항목은 즐겨찾기에 자동 등록/카운트 증가 (실패해도 무시)
            if case .food(let name, let kcal) = tag, useCustomFood {
                try? await FavoritesService.bump(kind: .food, name: name, kcal: kcal)
            }
            if case .move(let name, let kcal, let mins, let part) = tag, useCustomMove {
                try? await FavoritesService.bump(kind: .workout, name: name, kcal: kcal,
                                                 minutes: mins, bodyPart: part)
            }

            await app.reloadFeed()
            dismiss()
        } catch {
            print("🔴 클립 저장 실패:", String(describing: error))
            self.error = uploadErrorMessage(error)
        }
    }

    /// 실제 원인이 보이도록 에러를 분류해서 표시
    private func uploadErrorMessage(_ error: Error) -> String {
        let raw = String(describing: error)
        if raw.localizedCaseInsensitiveContains("bucket not found") {
            return "저장소 버킷(clips)이 없어요. 백엔드 마이그레이션 20260719000400이 적용됐는지 확인해 주세요."
        }
        if raw.localizedCaseInsensitiveContains("row-level security")
            || raw.localizedCaseInsensitiveContains("unauthorized")
            || raw.localizedCaseInsensitiveContains("policy") {
            return "저장 권한이 거부됐어요. 그룹 멤버 상태와 Storage 정책(마이그레이션 400)을 확인해 주세요."
        }
        if raw.localizedCaseInsensitiveContains("payload too large")
            || raw.localizedCaseInsensitiveContains("exceeded the maximum") {
            return "영상 용량이 버킷 제한(50MB)을 넘었어요."
        }
        if raw.localizedCaseInsensitiveContains("mime")
            || raw.localizedCaseInsensitiveContains("content-type") {
            return "허용되지 않는 파일 형식이에요. (버킷 허용: mp4/quicktime)"
        }
        if (error as NSError).domain == NSURLErrorDomain {
            return "서버에 연결하지 못했어요. 네트워크 상태를 확인해 주세요."
        }
        return "업로드 실패: \(error.localizedDescription)"
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

/// 무음 루프 미리보기 플레이어 — 크롭 없이 전체 프레임을 보여줌 (가로 영상 확인용)
struct LoopingPlayerView: View {
    let url: URL
    @State private var player = AVQueuePlayer()
    @State private var looper: AVPlayerLooper?

    var body: some View {
        PlayerLayerView(player: player, gravity: .resizeAspect)
            .background(Color.black)
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
