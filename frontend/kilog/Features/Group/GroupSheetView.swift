import SwiftUI
import UIKit
import Foundation

/// 그룹 관리 시트: 멤버 목록 · 초대 토큰 발급/공유 · 그룹 확장 · 내 공유 설정
struct GroupSheetView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var inviteToken: String?
    @State private var copied = false
    @State private var busy = false
    @State private var error: String?
    @State private var mySharing = SharingPreferences()

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                memberList
                inviteBox

                if let group = app.group,
                   group.type == .couple,
                   group.ownerId == app.myId {
                    Button {
                        Task { await expand() }
                    } label: {
                        Text("친구도 초대할 수 있게 그룹 확장")
                    }
                    .buttonStyle(DuoButtonStyle())
                    .disabled(busy)
                }

                sharingBox

                if let error {
                    Text(error).font(.system(size: 12)).foregroundStyle(Theme.me)
                }

                Text("초대 토큰은 서버에서 해시로만 보관되는 1회성·만료형(7일)이에요. 새 토큰을 발급하면 이전 토큰은 즉시 폐기됩니다.")
                    .font(.system(size: 10))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button("로그아웃") {
                    Task { await app.signOut() }
                }
                .buttonStyle(GhostButtonStyle())
            }
            .padding(18)
        }
        .background(Theme.bg)
        .onAppear {
            if let group = app.group {
                inviteToken = InviteTokenStore.load(groupId: group.id)
            }
            mySharing = app.myMember?.sharing ?? SharingPreferences()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(app.group?.type == .couple ? "커플 그룹" : "친구 그룹")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(Theme.lover)
                Text(app.group?.name ?? "")
                    .font(.system(size: 20, weight: .bold))
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

    private var memberList: some View {
        VStack(spacing: 8) {
            ForEach(app.members) { member in
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color(hex: member.colorHex))
                        .frame(width: 34, height: 34)
                        .overlay(Text(member.initial)
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(Color(hex: "#101016")))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.nickname).font(.system(size: 12.5, weight: .semibold))
                        Text(memberSubtitle(member))
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Text(member.status == .active ? "참여 중" : "대기")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted)
                }
                .padding(10)
                .card(radius: 13)
            }

            if let group = app.group {
                Text("\(app.members.count) / \(group.maxMembers)명")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.faint)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func memberSubtitle(_ member: MemberOverview) -> String {
        let role = member.role == .owner ? "방장" : "멤버"
        let share = (member.sharing?.shareBody ?? false) ? "신체 정보 공유" : "성과만 공유"
        return "\(role) · \(share)"
    }

    // ── 초대 ──────────────────────────────────────────────
    private var inviteBox: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("초대 링크").font(.system(size: 10.5)).foregroundStyle(Theme.muted)

            if let token = inviteToken {
                Text("https://sal-log.app/join/\(token)")
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1).truncationMode(.middle)

                HStack(spacing: 8) {
                    Button {
                        UIPasteboard.general.string = "https://sal-log.app/join/\(token)"
                        copied = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.2))
                            copied = false
                        }
                    } label: {
                        Text(copied ? "복사됨" : "링크 복사")
                    }
                    .buttonStyle(DuoButtonStyle())

                    ShareLink(item: URL(string: "https://sal-log.app/join/\(token)")!) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .frame(width: 46, height: 46)
                            .background(Theme.surface2)
                            .clipShape(RoundedRectangle(cornerRadius: 13))
                    }
                }
            } else {
                Text("이 기기에서 발급한 초대 토큰이 없어요. 토큰은 보안을 위해 서버에 저장되지 않으니 새로 발급해 주세요.")
                    .font(.system(size: 11.5))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.muted)
            }

            Button {
                Task { await rotate() }
            } label: {
                if busy { ProgressView() } else {
                    Text(inviteToken == nil ? "초대 토큰 발급" : "새 토큰으로 교체 (이전 폐기)")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .buttonStyle(GhostButtonStyle())
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .card(radius: 14)
    }

    // ── 공유 설정 ─────────────────────────────────────────
    private var sharingBox: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("내 공유 설정").font(.system(size: 12, weight: .bold))
            Text("끄면 다른 멤버에게 해당 항목이 보이지 않아요 (서버에서 차단).")
                .font(.system(size: 10.5)).foregroundStyle(Theme.muted)

            toggle("인바디 전체 (골격근·이력 포함)", $mySharing.shareBody)
            toggle("체중", $mySharing.shareWeight)
            toggle("체지방률", $mySharing.shareBodyFat)
            toggle("식사 기록", $mySharing.shareFood)
            toggle("운동 기록", $mySharing.shareWorkout)
            toggle("칼로리 수지", $mySharing.shareCalorieBalance)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 13))
    }

    private func toggle(_ label: String, _ binding: Binding<Bool>) -> some View {
        Toggle(label, isOn: binding)
            .font(.system(size: 12.5))
            .tint(Theme.green)
            .onChange(of: binding.wrappedValue) {
                Task { await saveSharing() }
            }
    }

    // ── 서버 호출 ─────────────────────────────────────────
    private func rotate() async {
        guard let group = app.group else { return }
        busy = true; defer { busy = false }
        do {
            let issued = try await GroupService.rotateInvite(groupId: group.id)
            inviteToken = issued.inviteToken
            error = nil
        } catch {
            self.error = "토큰 발급에 실패했어요."
        }
    }

    private func expand() async {
        guard let group = app.group else { return }
        busy = true; defer { busy = false }
        do {
            try await GroupService.expandGroup(groupId: group.id)
            await app.refreshBootstrap()
        } catch {
            self.error = "그룹 확장에 실패했어요."
        }
    }

    private func saveSharing() async {
        guard let group = app.group, let myId = app.myId else { return }
        do {
            try await GroupService.updateSharing(
                groupId: group.id, userId: myId, prefs: mySharing
            )
        } catch {
            self.error = "공유 설정 저장에 실패했어요."
        }
    }
}
