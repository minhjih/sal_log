import Foundation
import Supabase
import PostgREST
import Storage

/// 하루 합성본(day_reels) — 지난 날짜의 개별 클립을 하나의 브이로그로 합쳐 보관.
enum ReelService {

    struct DayReel: Codable, Identifiable, Hashable {
        let id: UUID
        let reelDate: String       // "yyyy-MM-dd" (date 컬럼)
        var videoKey: String?
        var status: String

        enum CodingKeys: String, CodingKey {
            case id
            case reelDate = "reel_date"
            case videoKey = "video_key"
            case status
        }

        var date: Date? { ReelService.dateParser.date(from: reelDate) }
    }

    static let dateParser: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dateKey(_ date: Date) -> String { dateParser.string(from: date) }

    // ── 조회 ──────────────────────────────────────────────
    static func fetchReels(groupId: UUID, limit: Int = 30) async throws -> [DayReel] {
        try await Supa.client.from("day_reels")
            .select()
            .eq("group_id", value: groupId)
            .eq("status", value: "ready")
            .order("reel_date", ascending: false)
            .limit(limit)
            .execute().value
    }

    // ── 점유(claim): building 행 먼저 삽입. 이미 있으면(충돌) false ──
    static func claim(groupId: UUID, reelDate: String, userId: UUID) async -> Bool {
        struct Row: Encodable {
            let group_id: UUID; let reel_date: String
            let created_by: UUID; let status: String
        }
        do {
            try await Supa.client.from("day_reels")
                .insert(Row(group_id: groupId, reel_date: reelDate,
                            created_by: userId, status: "building"))
                .execute()
            return true
        } catch {
            return false   // unique 충돌 = 다른 멤버가 이미 맡음
        }
    }

    static func finalize(groupId: UUID, reelDate: String, videoKey: String) async throws {
        struct Patch: Encodable { let video_key: String; let status: String; let updated_at: Date }
        try await Supa.client.from("day_reels")
            .update(Patch(video_key: videoKey, status: "ready", updated_at: Date()))
            .eq("group_id", value: groupId)
            .eq("reel_date", value: reelDate)
            .execute()
    }

    /// 합성 실패 시 building 점유 해제 (다음에 재시도 가능하도록)
    static func releaseClaim(groupId: UUID, reelDate: String) async {
        try? await Supa.client.from("day_reels").delete()
            .eq("group_id", value: groupId)
            .eq("reel_date", value: reelDate)
            .eq("status", value: "building")
            .execute()
    }

    /// 합성본이 ready인 날의 개별 클립 일괄 삭제 (서버 RPC — 상대 클립까지)
    static func archiveClips(
        groupId: UUID, reelDate: String, start: Date, end: Date
    ) async throws {
        struct Params: Encodable {
            let p_group_id: UUID; let p_date: String
            let p_start: Date; let p_end: Date
        }
        try await Supa.client.rpc(
            "archive_day_clips",
            params: Params(p_group_id: groupId, p_date: reelDate, p_start: start, p_end: end)
        ).execute()
    }

    // ── 업로드 ────────────────────────────────────────────
    static func uploadReel(groupId: UUID, reelDate: String, fileURL: URL) async throws -> String {
        let key = "\(groupId.uuidString.lowercased())/\(reelDate).mp4"
        let data = try Data(contentsOf: fileURL)
        try await Supa.client.storage.from("reels").upload(
            key, data: data,
            options: FileOptions(contentType: "video/mp4", upsert: true)
        )
        return key
    }

    // ── 재생용 로컬 캐시 ──────────────────────────────────
    private static var cacheDir: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("reel-videos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func cachedReelURL(_ reel: DayReel) async throws -> URL? {
        guard let key = reel.videoKey else { return nil }
        let local = cacheDir.appendingPathComponent("\(reel.id.uuidString).mp4")
        if FileManager.default.fileExists(atPath: local.path) { return local }
        let signed = try await Supa.client.storage.from("reels")
            .createSignedURL(path: key, expiresIn: 3600)
        let (tmp, _) = try await URLSession.shared.download(from: signed)
        try? FileManager.default.removeItem(at: local)
        try FileManager.default.moveItem(at: tmp, to: local)
        return local
    }
}
