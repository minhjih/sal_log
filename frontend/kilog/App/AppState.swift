import Foundation
import SwiftUI
import Supabase
import Combine
import Auth
import Realtime
import AVFoundation

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
    private var remindersScheduled = false

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
                    // 첫 진입: 스플래시에선 앞쪽 몇 개만 받고, 나머지는 백그라운드로 미룸
                    await reloadFeed()
                    launchProgress = 0.4
                    await preloadVideos(limit: Self.splashPreloadLimit) { [weak self] fraction in
                        self?.launchProgress = 0.4 + 0.6 * fraction
                    }
                    launchProgress = 1
                    // 캐싱 우선순위: 당일 클립 먼저, 그 다음 릴(vlog)을 자기들끼리 큐로
                    Task {
                        await cacheRemainingInBackground()
                        await cacheReelsInBackground()
                    }
                } else {
                    await reloadFeed()
                }
                phase = .ready
                await subscribeRealtime()

                // 아침·점심·저녁 식사 영상 리마인더 (세션당 1회 등록)
                if !remindersScheduled {
                    remindersScheduled = true
                    Task { await NotificationService.scheduleMealReminders() }
                }

                // 지난 날의 개별 클립을 합성본으로 아카이브 (백그라운드)
                Task { await archivePastDays() }
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
            // 실시간으로 새로 올라온 클립·미완료분은 백그라운드 스택에서 캐시
            Task { await self.cacheRemainingInBackground() }
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

    /// 스플래시에서 한 번에 받을 최대 개수 — 나머지는 백그라운드로 미룬다
    private static let splashPreloadLimit = 5
    private var backgroundCaching = false

    /// 오늘 피드 영상 캐시. limit이 있으면 앞에서 그만큼만(스플래시용).
    private func preloadVideos(limit: Int? = nil, onProgress: ((Double) -> Void)?) async {
        var pending = feed.clips.filter {
            $0.clip.videoKey != nil && videoCache[$0.id] == nil
        }
        if let limit { pending = Array(pending.prefix(limit)) }
        guard !pending.isEmpty else { onProgress?(1); return }

        for (index, clip) in pending.enumerated() {
            if let local = await cacheWithRetry(clip.clip) {
                videoCache[clip.id] = local
            }
            onProgress?(Double(index + 1) / Double(pending.count))
        }
    }

    /// 남은 영상을 백그라운드에서 하나씩 캐시 (중복 실행 방지).
    /// 실패분은 다음 reloadFeed/진입 때 다시 시도된다.
    func cacheRemainingInBackground() async {
        guard !backgroundCaching else { return }
        backgroundCaching = true
        defer { backgroundCaching = false }

        let pending = feed.clips.filter {
            $0.clip.videoKey != nil && videoCache[$0.id] == nil
        }
        for clip in pending where videoCache[clip.id] == nil {
            if let local = await cacheWithRetry(clip.clip) {
                videoCache[clip.id] = local
            }
        }
    }

    /// 캐시 다운로드 — 실패하면 새 signed URL로 백엔드에서 재시도.
    private func cacheWithRetry(_ clip: Clip) async -> URL? {
        if let url = try? await ClipService.cachedVideoURL(for: clip) { return url }
        return try? await ClipService.redownloadVideo(for: clip)
    }

    /// 릴(합성본) 전용 캐싱 큐 — 당일 클립 캐싱이 끝난 뒤 자기들끼리 하나씩.
    /// (당일 클립 캐시보다 항상 후순위)
    private var cachingReels = false
    func cacheReelsInBackground() async {
        guard !cachingReels, let group else { return }
        cachingReels = true
        defer { cachingReels = false }
        let reels = (try? await ReelService.fetchReels(groupId: group.id)) ?? []
        for reel in reels {
            _ = try? await ReelService.cachedReelURL(reel)
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
        NotificationService.cancelMealReminders()
        remindersScheduled = false
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

    // ── 지난 날 합성본 아카이브 ────────────────────────────
    /// 오늘 이전 최근 7일 중, 클립이 있는데 합성본이 없는 가장 오래된 하루를
    /// 한 번에 하나씩 합성 → 업로드 → 개별 클립 삭제. 부하를 위해 호출당 1일만.
    private var archiving = false
    func archivePastDays() async {
        guard !archiving, let group, let myId = me?.id, let mine = myMember else { return }
        archiving = true
        defer { archiving = false }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let reels = (try? await ReelService.fetchReels(groupId: group.id)) ?? []
        let reeled = Set(reels.map(\.reelDate))
        let weekAgo = cal.date(byAdding: .day, value: -7, to: today)!

        // 0) 이미 합성본(ready)이 있는 날인데 개별 클립이 남아 있으면 다시 삭제.
        //    (지난번 삭제 실패분·아카이브 단계 없던 이전 버전으로 만든 릴 정리)
        for reel in reels {
            guard let d = reel.date, d >= weekAgo, d < today else { continue }
            guard let feed = try? await ClipService.fetchDay(groupId: group.id, date: d),
                  feed.clips.contains(where: { $0.clip.videoKey != nil }) else { continue }
            let start = cal.startOfDay(for: d)
            let end = cal.date(byAdding: .day, value: 1, to: start)!
            do {
                try await ReelService.archiveClips(
                    groupId: group.id, reelDate: reel.reelDate, start: start, end: end)
                await reloadFeed()
            } catch {
                print("[Reel] archiveClips 재시도 실패 (\(reel.reelDate)): \(error)")
            }
        }

        for offset in stride(from: 7, through: 1, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = ReelService.dateKey(day)
            if reeled.contains(key) { continue }
            guard let feed = try? await ClipService.fetchDay(groupId: group.id, date: day)
            else { continue }
            guard feed.clips.contains(where: { $0.clip.videoKey != nil }) else { continue }
            guard await ReelService.claim(groupId: group.id, reelDate: key, userId: myId)
            else { continue }

            do {
                let local = try await buildReelVideo(day: day, feed: feed, me: mine)
                let videoKey = try await ReelService.uploadReel(
                    groupId: group.id, reelDate: key, fileURL: local)
                try await ReelService.finalize(
                    groupId: group.id, reelDate: key, videoKey: videoKey)
                let start = cal.startOfDay(for: day)
                let end = cal.date(byAdding: .day, value: 1, to: start)!
                try await ReelService.archiveClips(
                    groupId: group.id, reelDate: key, start: start, end: end)
            } catch {
                await ReelService.releaseClaim(groupId: group.id, reelDate: key)
            }
            break   // 호출당 하루만
        }

        // 서버는 DB 행만 지우므로, 남은 스토리지 파일(고아)은 여기서 정리한다.
        await ClipService.cleanupOrphanClipFiles(groupId: group.id, userId: myId)
        await ReelService.cleanupOrphanReelFiles(groupId: group.id)

        // 새로 만들어진 릴을 큐에 태워 미리 캐시 (당일 클립 뒤 후순위)
        await cacheReelsInBackground()
    }

    private func buildReelVideo(
        day: Date, feed: ClipService.DayFeed, me: MemberOverview
    ) async throws -> URL {
        var localFiles: [UUID: URL] = [:]
        var durations: [UUID: Double] = [:]
        for clip in feed.clips where clip.clip.videoKey != nil {
            guard let url = try? await ClipService.cachedVideoURL(for: clip.clip) else { continue }
            localFiles[clip.id] = url
            if let sec = try? await AVURLAsset(url: url).load(.duration).seconds,
               sec.isFinite, sec > 0 { durations[clip.id] = sec }
        }

        func dayStats(_ uid: UUID) -> HealthMath.DailyStats {
            HealthMath.dailyStats(
                userId: uid, foods: feed.foods, workouts: feed.workouts,
                profile: uid == myId ? myProfile : member(for: uid)?.profile)
        }

        let df = DateFormatter()
        df.locale = Locale(identifier: "ko_KR")
        df.dateFormat = "M.d E"

        let input = VlogExporter.Input(
            segments: Timeline.buildSegments(feed.clips),
            localFiles: localFiles,
            durations: durations,
            topRow: .init(member: me, stats: dayStats(me.userId)),
            bottomRow: partner.map { .init(member: $0, stats: dayStats($0.userId)) },
            dateLabel: df.string(from: day),
            muscleImage: nil,
            weightImage: nil
        )
        return try await VlogExporter().export(input) { _ in }
    }
}
