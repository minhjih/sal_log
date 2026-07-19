import Foundation
import SwiftUI
import Supabase

/// 앱 전역 상태: 세션 → 그룹 → 오늘 피드
@MainActor
final class AppState: ObservableObject {

    enum Phase: Equatable {
        case loading          // 세션 확인 중
        case signedOut        // 로그인 필요
        case needsGroup       // 로그인 됨, 그룹 없음
        case ready            // 그룹까지 연결 완료
    }

    @Published var phase: Phase = .loading
    @Published var me: AppUser?
    @Published var myProfile: BodyProfile?
    @Published var group: SalGroup?
    @Published var members: [MemberOverview] = []
    @Published var invite: InviteMeta?

    @Published var feed = ClipService.DayFeed(clips: [], foods: [], workouts: [])
    @Published var needsOnboardingScan = false
    @Published var errorMessage: String?

    let catalogs = Catalogs()
    private var realtimeChannel: RealtimeChannelV2?
    private var authTask: Task<Void, Never>?

    var myId: UUID? { me?.id }

    /// 나 자신의 멤버 오버뷰
    var myMember: MemberOverview? {
        members.first { $0.userId == myId }
    }

    /// 파트너(couple) 또는 나 외 첫 멤버 — 듀얼 플레이어의 아래 트랙
    var partner: MemberOverview? {
        members.first { $0.userId != myId }
    }

    func member(for userId: UUID) -> MemberOverview? {
        members.first { $0.userId == userId }
    }

    // ── 라이프사이클 ──────────────────────────────────────
    func start() {
        authTask?.cancel()
        authTask = Task {
            for await (event, session) in Supa.client.auth.authStateChanges {
                switch event {
                case .initialSession, .signedIn, .tokenRefreshed:
                    if session != nil {
                        await refreshBootstrap()
                    } else {
                        phase = .signedOut
                    }
                case .signedOut:
                    reset()
                default:
                    break
                }
            }
        }
        Task { await catalogs.load() }
    }

    func refreshBootstrap() async {
        do {
            let boot = try await GroupService.bootstrap()
            me = boot.user
            myProfile = boot.profile
            group = boot.group
            members = boot.members
            invite = boot.invite

            if boot.group == nil {
                phase = .needsGroup
            } else {
                phase = .ready
                // 신체 수치가 아직 없으면 온보딩 스캔 유도
                needsOnboardingScan = (boot.profile?.weight == nil)
                await reloadFeed()
                await subscribeRealtime()
            }
        } catch {
            if AuthService.currentUserId == nil {
                phase = .signedOut
            } else {
                errorMessage = "데이터를 불러오지 못했어요. 네트워크를 확인해 주세요."
            }
        }
    }

    func reloadFeed(date: Date = Date()) async {
        guard let group else { return }
        do {
            feed = try await ClipService.fetchDay(groupId: group.id, date: date)
        } catch {
            errorMessage = "오늘 기록을 불러오지 못했어요."
        }
    }

    private func subscribeRealtime() async {
        guard let group, realtimeChannel == nil else { return }
        realtimeChannel = await ClipService.subscribe(groupId: group.id) { [weak self] in
            Task { @MainActor in
                await self?.reloadFeed()
            }
        }
    }

    func signOut() async {
        await AuthService.signOut()
        reset()
    }

    private func reset() {
        if let channel = realtimeChannel {
            Task { await channel.unsubscribe() }
        }
        realtimeChannel = nil
        me = nil; myProfile = nil; group = nil
        members = []; invite = nil
        feed = ClipService.DayFeed(clips: [], foods: [], workouts: [])
        phase = .signedOut
    }

    // ── 통계 ──────────────────────────────────────────────
    func stats(for userId: UUID) -> HealthMath.DailyStats {
        HealthMath.dailyStats(
            userId: userId,
            foods: feed.foods,
            workouts: feed.workouts,
            profile: userId == myId ? myProfile : member(for: userId)?.profile
        )
    }
}
