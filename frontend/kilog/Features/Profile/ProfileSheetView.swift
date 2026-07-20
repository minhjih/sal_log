import SwiftUI
import Foundation

/// 내 프로필 편집: 이름 · 기본 신체 정보(성별/나이/키/활동량) · 신체 정보 공개 여부
struct ProfileSheetView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var nickname = ""
    @State private var sex: Sex = .F
    @State private var age = 26
    @State private var height: Double = 162
    @State private var activityIndex = 1
    @State private var visibleToMembers = false

    @State private var saving = false
    @State private var error: String?

    /// (라벨, 계수) — Mifflin/Katch 계산의 활동 계수 프리셋
    private static let activityLevels: [(label: String, factor: Double)] = [
        ("거의 안 움직임", 1.2),
        ("가벼운 활동 (주 1~3회)", 1.38),
        ("보통 활동 (주 3~5회)", 1.55),
        ("높은 활동 (주 6~7회)", 1.73),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header

                // 아바타 미리보기
                let color = app.myMember.map { Color(hex: $0.colorHex) } ?? Theme.me
                Circle()
                    .fill(color)
                    .frame(width: 64, height: 64)
                    .overlay(
                        Text(nickname.isEmpty ? "?" : String(nickname.prefix(1)).uppercased())
                            .font(.system(size: 24, weight: .heavy))
                            .foregroundStyle(Color(hex: "#101016"))
                    )

                // 이름
                VStack(alignment: .leading, spacing: 6) {
                    Text("앱에서 사용할 이름").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    TextField("이름을 입력해 주세요", text: $nickname)
                        .padding(12)
                        .background(Theme.bg)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
                        .onChange(of: nickname) { nickname = String(nickname.prefix(12)) }
                    if let email = emailText {
                        Text(email).font(.system(size: 10.5)).foregroundStyle(Theme.faint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // 기본 신체 정보 (BMR·TDEE 계산용)
                VStack(alignment: .leading, spacing: 10) {
                    Text("기본 정보").font(.system(size: 12, weight: .bold))
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

                    Text("활동량").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    VStack(spacing: 6) {
                        ForEach(Array(Self.activityLevels.enumerated()), id: \.offset) { i, level in
                            Button {
                                activityIndex = i
                            } label: {
                                HStack {
                                    Text(level.label).font(.system(size: 12.5))
                                    Spacer()
                                    Text("×\(level.factor, specifier: "%.2f")")
                                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .background(activityIndex == i ? Theme.lover.opacity(0.08) : Theme.bg)
                                .clipShape(RoundedRectangle(cornerRadius: 11))
                                .overlay(RoundedRectangle(cornerRadius: 11)
                                    .stroke(activityIndex == i ? Theme.lover : Theme.line))
                            }
                            .foregroundStyle(Theme.text)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .card(radius: 14)

                // 신체 정보 공개
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("그룹 멤버에게 신체 정보 공개 허용", isOn: $visibleToMembers)
                        .font(.system(size: 12.5))
                        .tint(Theme.green)
                    Text("끄면 그룹의 항목별 공유 설정과 무관하게 서버가 모든 신체 수치를 차단해요. 켠 뒤 그룹 관리에서 항목별로 고를 수 있어요.")
                        .font(.system(size: 10.5)).lineSpacing(3).foregroundStyle(Theme.muted)
                }
                .padding(12)
                .background(Theme.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 13))

                if let bmr = previewBMR {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("예상 기초대사량").font(.system(size: 12)).foregroundStyle(Theme.muted)
                        Text("\(bmr) kcal").font(.system(size: 15, weight: .semibold))
                        Spacer()
                    }
                    .padding(.horizontal, 2)
                }

                if let error {
                    Text(error).font(.system(size: 12)).foregroundStyle(Theme.me)
                }

                Button {
                    Task { await save() }
                } label: {
                    if saving { ProgressView().tint(.black) } else { Text("저장") }
                }
                .buttonStyle(DuoButtonStyle())
                .disabled(saving || nickname.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(18)
        }
        .background(Theme.bg)
        .onAppear(perform: load)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("내 계정").font(.system(size: 10.5, weight: .bold)).foregroundStyle(Theme.lover)
                Text("프로필 수정").font(.system(size: 20, weight: .bold))
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 30, height: 30)
                    .background(Theme.surface)
                    .clipShape(Circle())
            }
        }
    }

    private var emailText: String? {
        Supa.client.auth.currentSession?.user.email
    }

    private var previewBMR: Int? {
        HealthMath.bmr(BodyProfile(
            height: height,
            weight: app.myProfile?.weight,
            bodyFat: app.myProfile?.bodyFat,
            sex: sex, age: age
        ))
    }

    private func load() {
        nickname = app.me?.nickname ?? ""
        let profile = app.myProfile
        sex = profile?.sex ?? .F
        age = profile?.age ?? 26
        height = profile?.height ?? 162
        visibleToMembers = profile?.visibility == .members
        if let factor = profile?.activityFactor,
           let i = Self.activityLevels.firstIndex(where: { abs($0.factor - factor) < 0.01 }) {
            activityIndex = i
        }
    }

    private func save() async {
        guard let myId = app.myId else { return }
        saving = true; defer { saving = false }
        do {
            try await UserService.updateNickname(userId: myId, nickname: nickname)
            try await BodyService.updateProfile(
                userId: myId,
                sex: sex, age: age, height: height,
                activityFactor: Self.activityLevels[activityIndex].factor,
                visibility: visibleToMembers ? .members : .private
            )
            await app.refreshBootstrap()
            dismiss()
        } catch {
            self.error = "저장에 실패했어요: \(error.localizedDescription)"
        }
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
            .background(Theme.bg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
        }
    }
}
