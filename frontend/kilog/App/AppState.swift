import Foundation
import SwiftUI
import Supabase
import Combine
import Auth
import Realtime

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
    /// 최근 30일 로그 — 스트레이크(오늘 탭)·근육 부하 비교(지표 탭) 공용
    @Published var recentLogs = ClipService.RecentLogs(foods: [], workouts: [])
    @Published var needsOnboardingScan = false
    @Published var errorMessage: String?

    /// 스플래시 진행률 (0~1) — 부트스트랩 → 피드 → 영상 프리로드
    @Published var launchProgress: Double = 0
    /// clipId → 로컬 캐시 파일. 스플래시에서 미리 받아 즉시 재생·내보내기에 사용
    @Published var videoCache: [UUID: URL] = [:]

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
            // 카탈로그는 RLS가 로그인 전용이라 인증 후에 로드해야 전체가 내려옴
            await catalogs.load()
            let boot = try await GroupService.bootstrap()
            me = boot.user
            myProfile = boot.profile
            group = boot.group
            members = boot.members
            invite = boot.invite

            launchProgress = 0.25
            if boot.group == nil {
                phase = .needsGroup
            } else {
                // 신체 수치가 아직 없으면 온보딩 스캔 유도
                needsOnboardingScan = (boot.profile?.weight == nil)

                if phase != .ready {
                    // 첫 진입: 스플래시를 유지한 채 피드 + 영상까지 프리로드
                    await reloadFeed()
                    launchProgress = 0.4
                    await preloadVideos { [weak self] fraction in
                        self?.launchProgress = 0.4 + 0.6 * fraction
                    }
                    launchProgress = 1
                } else {
                    await reloadFeed()
                }
                phase = .ready
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
            // 실시간으로 새로 올라온 클립은 백그라운드에서 캐시
            Task { await self.preloadVideos(onProgress: nil) }
            // 스트레이크·근육 비교용 최근 로그 갱신 (백그라운드)
            Task { [groupId = group.id] in
                if let logs = try? await ClipService.fetchRecentLogs(groupId: groupId, days: 30) {
                    self.recentLogs = logs
                }
            }
        } catch {
            errorMessage = "오늘 기록을 불러오지 못했어요."
        }
    }

    /// 오늘 피드의 영상들을 로컬 캐시로 다운로드
    private func preloadVideos(onProgress: ((Double) -> Void)?) async {
        let pending = feed.clips.filter {
            $0.clip.videoKey != nil && videoCache[$0.id] == nil
        }
        guard !pending.isEmpty else { onProgress?(1); return }

        for (index, clip) in pending.enumerated() {
            if let local = try? await ClipService.cachedVideoURL(for: clip.clip) {
                videoCache[clip.id] = local
            }
            onProgress?(Double(index + 1) / Double(pending.count))
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
