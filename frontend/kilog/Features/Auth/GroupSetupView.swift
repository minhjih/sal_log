import SwiftUI
import Foundation

/// 그룹 연결: 새 그룹 만들기 / 초대 코드로 참여 (실제 서버 RPC 사용)
struct GroupSetupView: View {
    @EnvironmentObject private var app: AppState

    enum Step { case choice, create, join, accept }
    @State private var step: Step = .choice

    // create
    @State private var groupType: GroupType = .couple
    @State private var groupName = "우리의 30일"

    // join
    @State private var tokenInput = ""
    @State private var preview: InvitePreview?

    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Wordmark()
                    Text("같이 기록하고, 같이 확인하는 셋로그")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                switch step {
                case .choice: choiceCard
                case .create: createCard
                case .join: joinCard
                case .accept: acceptCard
                }
            }
            .padding(20)
            .padding(.top, 38)
        }
        .background(Theme.bg.ignoresSafeArea())
        .onAppear {
            // 초대 딥링크로 진입한 경우 코드 자동 입력
            if let pending = PendingInvite.token {
                tokenInput = pending
                PendingInvite.token = nil
                step = .join
            }
        }
    }

    // ── 선택 ──────────────────────────────────────────────
    private var choiceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepLabel("2 / 3 · 그룹 연결")
            Text("누구와 함께할까요?").font(.system(size: 21, weight: .bold))

            HStack(spacing: 9) {
                choiceButton("새 그룹 만들기", "내가 방장이 되어 초대") { step = .create }
                choiceButton("초대받은 그룹 참여", "링크 또는 코드 입력") { step = .join }
            }

            noteBox("확장 가능한 구조",
                    "커플과 친구 그룹 모두 같은 그룹·멤버·초대 데이터 모델을 사용해요.")

            Button("로그아웃") { Task { await app.signOut() } }
                .buttonStyle(GhostButtonStyle())
                .frame(maxWidth: .infinity)
        }
        .padding(20)
        .card(radius: 24)
    }

    // ── 생성 ──────────────────────────────────────────────
    private var createCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepLabel("3 / 3 · 그룹 만들기")
            Text("우리 셋로그 만들기").font(.system(size: 21, weight: .bold))

            HStack(spacing: 9) {
                typeButton(.couple, "커플", "2명 · 서로의 변화 중심")
                typeButton(.friends, "친구들", "최대 12명 · 챌린지형")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("그룹 이름").font(.system(size: 11)).foregroundStyle(Theme.muted)
                TextField("우리의 30일", text: $groupName)
                    .padding(12)
                    .background(Theme.bg)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
            }

            noteBox("기본 공유 범위",
                    "오늘 기록 · 운동 성과 · 코치 추천\n체중·체지방은 멤버별 동의 후 공유")

            errorText

            Button {
                Task { await createGroup() }
            } label: {
                if busy { ProgressView().tint(.black) } else { Text("그룹 만들고 초대하기") }
            }
            .buttonStyle(DuoButtonStyle())
            .disabled(busy)

            Button("이전") { step = .choice }
                .buttonStyle(GhostButtonStyle())
                .frame(maxWidth: .infinity)
        }
        .padding(20)
        .card(radius: 24)
    }

    // ── 참여 (코드 입력) ──────────────────────────────────
    private var joinCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepLabel("3 / 3 · 초대 확인")
            Text("초대 링크 또는 코드").font(.system(size: 21, weight: .bold))
            Text("웹 초대 링크(sal-log.app/join/…)로 앱을 열면 코드가 자동 입력돼요.")
                .font(.system(size: 12.5)).foregroundStyle(Theme.muted)

            VStack(alignment: .leading, spacing: 6) {
                Text("초대 코드").font(.system(size: 11)).foregroundStyle(Theme.muted)
                TextField("SAL-XXXXXX", text: $tokenInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .padding(12)
                    .background(Theme.bg)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
            }

            errorText

            Button {
                Task { await previewInvite() }
            } label: {
                if busy { ProgressView().tint(.black) } else { Text("초대 확인") }
            }
            .buttonStyle(DuoButtonStyle())
            .disabled(busy || tokenInput.trimmingCharacters(in: .whitespaces).isEmpty)

            Button("이전") { step = .choice; error = nil }
                .buttonStyle(GhostButtonStyle())
                .frame(maxWidth: .infinity)
        }
        .padding(20)
        .card(radius: 24)
    }

    // ── 수락 ──────────────────────────────────────────────
    private var acceptCard: some View {
        VStack(spacing: 14) {
            if let preview {
                VStack(spacing: 8) {
                    ZStack {
                        Circle().fill(Theme.lover)
                            .frame(width: 44, height: 44)
                            .overlay(Text(String(preview.inviterNickname?.prefix(1) ?? "?"))
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(Color(hex: "#06243B")))
                        Circle().fill(Theme.surface2)
                            .frame(width: 44, height: 44)
                            .overlay(Text("+").foregroundStyle(Theme.muted))
                            .offset(x: 34)
                    }
                    .padding(.trailing, 34)

                    Text(preview.name).font(.system(size: 21, weight: .bold))
                    Text("\(preview.inviterNickname ?? "멤버")님이 \(preview.type == .couple ? "커플 셋로그" : "친구 셋로그")에 초대했어요.")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)

                    HStack(spacing: 7) {
                        metaChip("\(preview.memberCount) / \(preview.maxMembers)명")
                        metaChip(preview.expiresAt.formatted(date: .abbreviated, time: .omitted) + " 까지")
                    }
                }

                noteBox("참여하면 공유되는 정보",
                        "영상 기록과 운동·식단 성과\n신체 수치는 참여 후 별도로 공개 설정")

                errorText

                Button {
                    Task { await acceptInvite() }
                } label: {
                    if busy { ProgressView().tint(.black) } else { Text("초대 수락하고 참여") }
                }
                .buttonStyle(DuoButtonStyle())
                .disabled(busy)

                Button("다른 코드 입력") { step = .join; error = nil }
                    .buttonStyle(GhostButtonStyle())
            }
        }
        .padding(20)
        .card(radius: 24)
    }

    // ── 서버 호출 ─────────────────────────────────────────
    private func createGroup() async {
        busy = true; defer { busy = false }
        do {
            _ = try await GroupService.createGroup(name: groupName, type: groupType)
            await app.refreshBootstrap()
        } catch {
            self.error = "그룹을 만들지 못했어요. 다시 시도해 주세요."
        }
    }

    private func previewInvite() async {
        busy = true; defer { busy = false }
        do {
            preview = try await GroupService.previewInvite(token: tokenInput)
            error = nil
            step = .accept
        } catch {
            self.error = inviteError(error)
        }
    }

    private func acceptInvite() async {
        busy = true; defer { busy = false }
        do {
            try await GroupService.acceptInvite(token: tokenInput)
            await app.refreshBootstrap()
        } catch {
            self.error = inviteError(error)
        }
    }

    private func inviteError(_ error: Error) -> String {
        let raw = error.localizedDescription
        if raw.contains("INVITE_NOT_FOUND") { return "존재하지 않는 초대 코드예요." }
        if raw.contains("INVITE_EXPIRED") { return "만료된 초대예요. 새 코드를 요청해 주세요." }
        if raw.contains("INVITE_EXHAUSTED") { return "이미 사용된 초대예요. 새 코드를 요청해 주세요." }
        if raw.contains("GROUP_FULL") { return "그룹 정원이 가득 찼어요." }
        return "초대를 확인하지 못했어요. 코드를 다시 확인해 주세요."
    }

    // ── 소품 ──────────────────────────────────────────────
    private func stepLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .heavy))
            .kerning(1.2)
            .foregroundStyle(Theme.lover)
    }

    private var errorText: some View {
        Group {
            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(Theme.me)
            }
        }
    }

    private func choiceButton(_ title: String, _ subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13.5, weight: .bold))
                Text(subtitle).font(.system(size: 10.5)).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 15).padding(.horizontal, 12)
            .background(Theme.bg)
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(Theme.line))
        }
        .foregroundStyle(Theme.text)
    }

    private func typeButton(_ type: GroupType, _ title: String, _ subtitle: String) -> some View {
        Button {
            groupType = type
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 13.5, weight: .bold))
                Text(subtitle).font(.system(size: 10.5)).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 15).padding(.horizontal, 12)
            .background(groupType == type ? Theme.lover.opacity(0.08) : Theme.bg)
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15)
                .stroke(groupType == type ? Theme.lover : Theme.line))
        }
        .foregroundStyle(Theme.text)
    }

    private func noteBox(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12, weight: .bold))
            Text(body).font(.system(size: 10.5)).lineSpacing(3).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 13))
    }

    private func metaChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Theme.surface2)
            .clipShape(Capsule())
    }
}
