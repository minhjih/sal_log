import SwiftUI
import PhotosUI

/// 인바디 검사지 스캔 → OCR → 확인/수정 → 저장
/// firstTime = 온보딩(신체 정보 최초 입력, 성별·나이·키 포함)
struct ScanFlowView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    let firstTime: Bool

    enum Step { case scan, analyzing, confirm }
    @State private var step: Step = .scan

    @State private var pickedItem: PhotosPickerItem?
    @State private var scanImage: UIImage?

    // 인식/입력 값
    @State private var weight: Double?
    @State private var smm: Double?
    @State private var bodyFat: Double?

    // 온보딩 전용 기본 정보
    @State private var sex: Sex = .F
    @State private var age = 26
    @State private var height: Double = 162

    @State private var saving = false
    @State private var error: String?

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()

            VStack(spacing: 12) {
                switch step {
                case .scan: scanStage
                case .analyzing: analyzingStage
                case .confirm: confirmStage
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 22)
            .frame(maxWidth: 340)
            .background(Theme.bg)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.line))
        }
        .onChange(of: pickedItem) {
            Task { await analyze() }
        }
    }

    // ── 1) 업로드 ─────────────────────────────────────────
    private var scanStage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("인바디 검사지 스캔")
                .font(.system(size: 17, weight: .bold))
            Text("검사지 사진을 올리면 체중·골격근량·체지방률을 읽어와 기초대사량 계산에 바로 사용해요.")
                .font(.system(size: 12.5))
                .lineSpacing(4)
                .foregroundStyle(Theme.muted)

            PhotosPicker(selection: $pickedItem, matching: .images) {
                VStack(spacing: 7) {
                    Text("⌞ ⌝")
                        .font(.system(size: 22))
                        .kerning(4)
                        .foregroundStyle(Theme.muted)
                    Text("검사지 촬영 / 업로드")
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text("인바디 결과지 전체가 보이게 찍어주세요")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.faint)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Theme.line, style: .init(lineWidth: 1.5, dash: [6]))
                )
            }

            Button(firstTime ? "나중에 할게요 — 직접 입력" : "직접 입력할게요") {
                weight = app.myProfile?.weight
                smm = app.myProfile?.skeletalMuscle
                bodyFat = app.myProfile?.bodyFat
                step = .confirm
            }
            .buttonStyle(GhostButtonStyle())
            .frame(maxWidth: .infinity)

            if !firstTime {
                Button("닫기") { dismiss() }
                    .buttonStyle(GhostButtonStyle())
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // ── 2) 분석 중 ────────────────────────────────────────
    private var analyzingStage: some View {
        VStack(spacing: 10) {
            if let scanImage {
                Image(uiImage: scanImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 110, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
            }
            ProgressView().tint(Theme.me)
            Text("검사지 읽는 중…").font(.system(size: 14, weight: .bold))
            Text("체중 · 골격근량 · 체지방률 인식")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 8)
    }

    // ── 3) 확인/수정 ──────────────────────────────────────
    private var confirmStage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(scanImage == nil ? "신체 수치 입력" : "인식 결과 확인")
                .font(.system(size: 17, weight: .bold))
            Text("숫자가 다르면 바로 수정할 수 있어요.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.muted)

            if firstTime { basicsRow }

            HStack(spacing: 8) {
                numberField("체중", value: $weight, unit: "kg")
                numberField("골격근량", value: $smm, unit: "kg")
                numberField("체지방률", value: $bodyFat, unit: "%")
            }

            if let bmr = previewBMR {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("기초대사량")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.muted)
                        Text("\(bmr) kcal")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    Text("Katch-McArdle · 제지방량 기반")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.faint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .card(radius: 12)
            }

            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(Theme.me)
            }

            Button {
                Task { await save() }
            } label: {
                if saving { ProgressView().tint(.black) }
                else { Text(firstTime ? "이 수치로 시작하기" : "저장") }
            }
            .buttonStyle(DuoButtonStyle())
            .disabled(saving || weight == nil)

            if !firstTime {
                Button("취소") { dismiss() }
                    .buttonStyle(GhostButtonStyle())
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var basicsRow: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                Text("성별").font(.system(size: 11)).foregroundStyle(Theme.muted)
                Picker("", selection: $sex) {
                    Text("여").tag(Sex.F)
                    Text("남").tag(Sex.M)
                }
                .pickerStyle(.segmented)
            }
            numberField("나이", value: .init(
                get: { Double(age) }, set: { age = Int($0 ?? 26) }
            ), unit: "세", integer: true)
            numberField("키", value: .init(
                get: { height }, set: { height = $0 ?? 162 }
            ), unit: "cm")
        }
    }

    private var previewBMR: Int? {
        HealthMath.bmr(BodyProfile(
            height: firstTime ? height : app.myProfile?.height,
            weight: weight, bodyFat: bodyFat, skeletalMuscle: smm,
            sex: firstTime ? sex : app.myProfile?.sex,
            age: firstTime ? age : app.myProfile?.age
        ))
    }

    private func numberField(
        _ label: String, value: Binding<Double?>, unit: String, integer: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                TextField("—", value: value,
                          format: integer ? .number.precision(.fractionLength(0))
                                          : .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad)
                    .font(.system(size: 15, weight: .semibold))
                Text(unit).font(.system(size: 11)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
        }
    }

    // ── OCR 실행 ──────────────────────────────────────────
    private func analyze() async {
        guard let item = pickedItem,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else { return }

        scanImage = image
        step = .analyzing
        do {
            let result = try await InBodyOCR.scan(image: image)
            weight = result.weight ?? app.myProfile?.weight
            smm = result.skeletalMuscle ?? app.myProfile?.skeletalMuscle
            bodyFat = result.bodyFat ?? app.myProfile?.bodyFat
            step = .confirm
        } catch {
            self.error = error.localizedDescription
            weight = app.myProfile?.weight
            smm = app.myProfile?.skeletalMuscle
            bodyFat = app.myProfile?.bodyFat
            step = .confirm
        }
    }

    // ── 저장 ──────────────────────────────────────────────
    private func save() async {
        guard let myId = app.myId, let weight else { return }
        saving = true; defer { saving = false }
        do {
            if firstTime {
                try await BodyService.updateProfile(
                    userId: myId, sex: sex, age: age, height: height,
                    activityFactor: 1.38, visibility: nil
                )
            }
            _ = try await BodyService.addMeasurement(
                userId: myId, weight: weight, bodyFat: bodyFat, skeletalMuscle: smm,
                scanImageData: scanImage?.jpegData(compressionQuality: 0.8)
            )
            app.needsOnboardingScan = false
            await app.refreshBootstrap()
            dismiss()
        } catch {
            self.error = "저장에 실패했어요. 다시 시도해 주세요."
        }
    }
}
