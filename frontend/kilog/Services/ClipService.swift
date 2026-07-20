import Foundation
import Supabase
import PostgREST
import Storage
import Realtime

/// 클립 + 식사/운동 로그 CRUD, 영상 업로드, signed URL 캐시, 실시간 구독
enum ClipService {

    // ── 하루치 로드 ───────────────────────────────────────
    struct DayFeed {
        var clips: [TaggedClip]
        var foods: [FoodLog]
        var workouts: [WorkoutLog]
    }

    static func fetchDay(groupId: UUID, date: Date) async throws -> DayFeed {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!

        async let clipsReq: [Clip] = Supa.client.from("clips")
            .select()
            .eq("group_id", value: groupId)
            .gte("recorded_at", value: start)
            .lt("recorded_at", value: end)
            .order("recorded_at")
            .execute().value

        async let foodsReq: [FoodLog] = Supa.client.from("food_logs")
            .select()
            .eq("group_id", value: groupId)
            .gte("logged_at", value: start)
            .lt("logged_at", value: end)
            .execute().value

        async let workoutsReq: [WorkoutLog] = Supa.client.from("workout_logs")
            .select()
            .eq("group_id", value: groupId)
            .gte("logged_at", value: start)
            .lt("logged_at", value: end)
            .execute().value

        let (clips, foods, workouts) = try await (clipsReq, foodsReq, workoutsReq)

        let foodByClip = Dictionary(grouping: foods.filter { $0.clipId != nil },
                                    by: { $0.clipId! })
        let workoutByClip = Dictionary(grouping: workouts.filter { $0.clipId != nil },
                                       by: { $0.clipId! })

        let tagged = clips.map { clip -> TaggedClip in
            var tag: ClipTag?
            if let f = foodByClip[clip.id]?.first {
                tag = .food(name: f.foodName, kcal: f.calories)
            } else if let ws = workoutByClip[clip.id], !ws.isEmpty {
                if ws.count == 1 {
                    let w = ws[0]
                    tag = .move(name: w.exerciseName, kcal: w.calories,
                                minutes: w.durationMinutes, part: w.bodyPart)
                } else {
                    // 한 클립에 여러 운동: 합산해서 표시
                    tag = .move(
                        name: "\(ws[0].exerciseName) 외 \(ws.count - 1)",
                        kcal: ws.reduce(0) { $0 + $1.calories },
                        minutes: ws.reduce(0) { $0 + $1.durationMinutes },
                        part: nil
                    )
                }
            }
            return TaggedClip(clip: clip, tag: tag)
        }
        return DayFeed(clips: tagged, foods: foods, workouts: workouts)
    }

    // ── 클립 저장 (영상 업로드 → 행 삽입 → 태그 로그) ──────
    /// 클립 저장 + 태그 기록들. 운동은 한 세션에 여러 개를 함께 남길 수 있다.
    static func saveClip(
        groupId: UUID,
        userId: UUID,
        videoFileURL: URL?,
        caption: String,
        recordedAt: Date,
        tags: [ClipTag]
    ) async throws -> Clip {
        let clipId = UUID()
        var videoKey: String?

        if let fileURL = videoFileURL {
            // 경로는 소문자 UUID로 통일 (Storage 정책의 auth.uid() 표기와 일치)
            let key = "\(groupId.uuidString.lowercased())/\(userId.uuidString.lowercased())/\(clipId.uuidString.lowercased()).mp4"
            let data = try Data(contentsOf: fileURL)
            try await Supa.client.storage.from("clips").upload(
                key, data: data,
                options: FileOptions(contentType: "video/mp4")
            )
            videoKey = key
        }

        struct ClipRow: Encodable {
            let id: UUID
            let user_id: UUID
            let group_id: UUID
            let video_key: String?
            let caption: String
            let recorded_at: Date
            let processing_status: String
        }
        let inserted: Clip = try await Supa.client.from("clips")
            .insert(ClipRow(
                id: clipId, user_id: userId, group_id: groupId,
                video_key: videoKey,
                caption: caption,
                recorded_at: recordedAt,
                processing_status: "ready"   // 업로드 완료 후에 행을 만들므로 항상 ready
            ))
            .select().single()
            .execute().value

        struct FoodRow: Encodable {
            let user_id: UUID; let group_id: UUID; let clip_id: UUID
            let food_name: String; let calories: Int; let logged_at: Date
        }
        struct WorkoutRow: Encodable {
            let user_id: UUID; let group_id: UUID; let clip_id: UUID
            let exercise_name: String; let calories: Int
            let duration_minutes: Int; let body_part: String?; let logged_at: Date
        }

        let foodRows = tags.compactMap { tag -> FoodRow? in
            guard case .food(let name, let kcal) = tag else { return nil }
            return FoodRow(user_id: userId, group_id: groupId, clip_id: clipId,
                           food_name: name, calories: kcal, logged_at: recordedAt)
        }
        let workoutRows = tags.compactMap { tag -> WorkoutRow? in
            guard case .move(let name, let kcal, let minutes, let part) = tag else { return nil }
            return WorkoutRow(user_id: userId, group_id: groupId, clip_id: clipId,
                              exercise_name: name, calories: kcal,
                              duration_minutes: minutes, body_part: part,
                              logged_at: recordedAt)
        }
        if !foodRows.isEmpty {
            try await Supa.client.from("food_logs").insert(foodRows).execute()
        }
        if !workoutRows.isEmpty {
            try await Supa.client.from("workout_logs").insert(workoutRows).execute()
        }

        return inserted
    }

    /// 클립 + 영상 파일 + 클립에 태그된 식사/운동 기록까지 삭제.
    /// (7일 자동 만료와 달리, 직접 삭제는 잘못 올린 기록 정정이므로 로그도 함께 지운다)
    static func deleteClip(_ clip: Clip) async throws {
        if let key = clip.videoKey {
            try? await Supa.client.storage.from("clips").remove(paths: [key])
        }
        try await Supa.client.from("food_logs").delete()
            .eq("clip_id", value: clip.id).execute()
        try await Supa.client.from("workout_logs").delete()
            .eq("clip_id", value: clip.id).execute()
        try await Supa.client.from("clips").delete()
            .eq("id", value: clip.id).execute()
    }

    // ── 영상 로컬 캐시 (스플래시 프리로딩·즉시 재생용) ──────
    private static var cacheDir: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("clip-videos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 클립 영상을 캐시 디렉터리에 내려받고 로컬 URL 반환. 이미 있으면 재사용.
    static func cachedVideoURL(for clip: Clip) async throws -> URL? {
        guard let key = clip.videoKey else { return nil }
        let local = cacheDir.appendingPathComponent("\(clip.id.uuidString).mp4")
        if FileManager.default.fileExists(atPath: local.path) { return local }

        let signed = try await signedVideoURL(for: key)
        let (tmp, _) = try await URLSession.shared.download(from: signed)
        try? FileManager.default.removeItem(at: local)
        try FileManager.default.moveItem(at: tmp, to: local)
        return local
    }

    // ── signed URL (재생용) — 만료 10분 전까지 캐시 ─────────
    private static var urlCache: [String: (url: URL, expiry: Date)] = [:]
    private static let cacheLock = NSLock()

    static func signedVideoURL(for key: String) async throws -> URL {
        cacheLock.lock()
        if let hit = urlCache[key], hit.expiry > Date().addingTimeInterval(600) {
            cacheLock.unlock()
            return hit.url
        }
        cacheLock.unlock()

        let url = try await Supa.client.storage.from("clips")
            .createSignedURL(path: key, expiresIn: 3600)

        cacheLock.lock()
        urlCache[key] = (url, Date().addingTimeInterval(3600))
        cacheLock.unlock()
        return url
    }

    // ── 실시간: 그룹 내 새 기록이 올라오면 콜백 ────────────
    static func subscribe(
        groupId: UUID, onChange: @escaping @Sendable () -> Void
    ) async -> RealtimeChannelV2 {
        let channel = Supa.client.channel("group-\(groupId.uuidString)")

        for table in ["clips", "food_logs", "workout_logs", "group_members"] {
            let changes = channel.postgresChange(
                AnyAction.self, schema: "public", table: table,
                filter: "group_id=eq.\(groupId.uuidString)"
            )
            Task {
                for await _ in changes { onChange() }
            }
        }
        await channel.subscribe()
        return channel
    }
}
