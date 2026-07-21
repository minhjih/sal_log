import Foundation
import Supabase
import PostgREST
import Storage

/// 신체 프로필·인바디 측정 기록
enum BodyService {

    /// 인바디 스캔/수동 입력 결과 저장.
    /// 서버 트리거가 최신 측정이면 profiles(weight/body_fat/skeletal_muscle)에 자동 반영.
    static func addMeasurement(
        userId: UUID,
        weight: Double,
        bodyFat: Double?,
        skeletalMuscle: Double?,
        scanImageData: Data? = nil
    ) async throws -> BodyMeasurement {
        // 검사지 원본 보관 (본인 전용 버킷)
        if let data = scanImageData {
            let key = "\(userId.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
            try? await Supa.client.storage.from("inbody").upload(
                key, data: data,
                options: FileOptions(contentType: "image/jpeg")
            )
        }

        struct Row: Encodable {
            let user_id: UUID
            let weight: Double
            let body_fat: Double?
            let skeletal_muscle: Double?
            let measured_at: Date
        }
        return try await Supa.client.from("body_measurements")
            .insert(Row(user_id: userId, weight: weight, body_fat: bodyFat,
                        skeletal_muscle: skeletalMuscle, measured_at: Date()))
            .select().single()
            .execute().value
    }

    /// 온보딩에서 성별/나이/키/활동계수 저장
    static func updateProfile(
        userId: UUID,
        sex: Sex?, age: Int?, height: Double?,
        activityFactor: Double?, visibility: ProfileVisibility?
    ) async throws {
        struct Patch: Encodable {
            let sex: String?
            let age: Int?
            let height: Double?
            let activity_factor: Double?
            let visibility: String?
        }
        try await Supa.client.from("profiles")
            .update(Patch(sex: sex?.rawValue, age: age, height: height,
                          activity_factor: activityFactor,
                          visibility: visibility?.rawValue))
            .eq("user_id", value: userId)
            .execute()
    }

    /// 측정 기록 삭제 (RLS: 본인 것만).
    /// 최신 기록을 지우면 서버 트리거가 profiles를 남은 최신 값으로 재동기화.
    static func deleteMeasurement(id: UUID) async throws {
        try await Supa.client.from("body_measurements")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    static func history(userId: UUID, limit: Int = 24) async throws -> [BodyMeasurement] {
        try await Supa.client.from("body_measurements")
            .select()
            .eq("user_id", value: userId)
            .order("measured_at", ascending: true)
            .limit(limit)
            .execute().value
    }
}
