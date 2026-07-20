import Foundation

// ═══════════════════════════════════════════════════════════
// 도메인 모델 — backend 스키마(users/profiles/groups/…)와 1:1
// ═══════════════════════════════════════════════════════════

enum GroupType: String, Codable { case couple, friends }
enum MemberRole: String, Codable { case owner, member }
enum MemberStatus: String, Codable { case active, pending, left }
enum ProfileVisibility: String, Codable { case `private`, members }
enum ClipStatus: String, Codable { case uploading, ready, failed }
enum Sex: String, Codable, CaseIterable { case M, F }

// ── users ────────────────────────────────────────────────
struct AppUser: Codable, Identifiable, Hashable {
    let id: UUID
    var nickname: String
    var avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, nickname
        case avatarUrl = "avatar_url"
    }
}

// ── profiles (신체 프로필) ────────────────────────────────
struct BodyProfile: Codable, Hashable {
    var height: Double?
    var weight: Double?
    var bodyFat: Double?
    var skeletalMuscle: Double?
    var visibility: ProfileVisibility?
    var sex: Sex?
    var age: Int?
    var activityFactor: Double?

    enum CodingKeys: String, CodingKey {
        case height, weight, visibility, sex, age
        case bodyFat = "body_fat"
        case skeletalMuscle = "skeletal_muscle"
        case activityFactor = "activity_factor"
    }

    static let empty = BodyProfile()
    init(height: Double? = nil, weight: Double? = nil, bodyFat: Double? = nil,
         skeletalMuscle: Double? = nil, visibility: ProfileVisibility? = .private,
         sex: Sex? = nil, age: Int? = nil, activityFactor: Double? = 1.38) {
        self.height = height; self.weight = weight; self.bodyFat = bodyFat
        self.skeletalMuscle = skeletalMuscle; self.visibility = visibility
        self.sex = sex; self.age = age; self.activityFactor = activityFactor
    }
}

// ── groups ───────────────────────────────────────────────
struct SalGroup: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var type: GroupType
    var ownerId: UUID
    var maxMembers: Int

    enum CodingKeys: String, CodingKey {
        case id, name, type
        case ownerId = "owner_id"
        case maxMembers = "max_members"
    }
}

// ── sharing_preferences ──────────────────────────────────
struct SharingPreferences: Codable, Hashable {
    var shareBody = false
    var shareWeight = false
    var shareBodyFat = false
    var shareFood = true
    var shareWorkout = true
    var shareCalorieBalance = true

    enum CodingKeys: String, CodingKey {
        case shareBody = "share_body"
        case shareWeight = "share_weight"
        case shareBodyFat = "share_body_fat"
        case shareFood = "share_food"
        case shareWorkout = "share_workout"
        case shareCalorieBalance = "share_calorie_balance"
    }
}

// ── body_measurements ────────────────────────────────────
struct BodyMeasurement: Codable, Identifiable, Hashable {
    let id: UUID
    var weight: Double
    var bodyFat: Double?
    var skeletalMuscle: Double?
    var measuredAt: Date

    enum CodingKeys: String, CodingKey {
        case id, weight
        case bodyFat = "body_fat"
        case skeletalMuscle = "skeletal_muscle"
        case measuredAt = "measured_at"
    }
}

// ── get_bootstrap이 내려주는 멤버 뷰 (동의 반영된 스냅샷) ──
struct MemberOverview: Codable, Identifiable, Hashable {
    let userId: UUID
    var nickname: String
    var avatarUrl: String?
    var role: MemberRole
    var status: MemberStatus
    var colorHex: String
    var sharing: SharingPreferences?
    var profile: BodyProfile?
    var measurements: [BodyMeasurement]

    var id: UUID { userId }
    var initial: String {
        nickname.isEmpty ? "?" : String(nickname.prefix(1)).uppercased()
    }
    var displayName: String { nickname.isEmpty ? "이름 없음" : nickname }

    enum CodingKeys: String, CodingKey {
        case nickname, role, status, sharing, profile, measurements
        case userId = "user_id"
        case avatarUrl = "avatar_url"
        case colorHex = "color_hex"
    }
}

struct InviteMeta: Codable, Hashable {
    let id: UUID
    var expiresAt: Date
    var maxUses: Int
    var usedCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case expiresAt = "expires_at"
        case maxUses = "max_uses"
        case usedCount = "used_count"
    }
}

struct Bootstrap: Codable {
    var user: AppUser
    var profile: BodyProfile?
    var group: SalGroup?
    var members: [MemberOverview]
    var invite: InviteMeta?
}

struct InvitePreview: Codable, Hashable {
    let groupId: UUID
    var name: String
    var type: GroupType
    var maxMembers: Int
    var memberCount: Int
    var inviterNickname: String?
    var expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case name, type
        case groupId = "group_id"
        case maxMembers = "max_members"
        case memberCount = "member_count"
        case inviterNickname = "inviter_nickname"
        case expiresAt = "expires_at"
    }
}

struct IssuedInvite: Codable, Hashable {
    var inviteToken: String
    var inviteUrl: String

    enum CodingKeys: String, CodingKey {
        case inviteToken = "invite_token"
        case inviteUrl = "invite_url"
    }
}

struct CreatedGroup: Codable, Hashable {
    var groupId: UUID
    var inviteToken: String
    var inviteUrl: String

    enum CodingKeys: String, CodingKey {
        case groupId = "group_id"
        case inviteToken = "invite_token"
        case inviteUrl = "invite_url"
    }
}

// ── clips + logs ─────────────────────────────────────────
struct Clip: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    let groupId: UUID
    var videoKey: String?
    var thumbnailKey: String?
    var caption: String
    var recordedAt: Date
    var processingStatus: ClipStatus

    enum CodingKeys: String, CodingKey {
        case id, caption
        case userId = "user_id"
        case groupId = "group_id"
        case videoKey = "video_key"
        case thumbnailKey = "thumbnail_key"
        case recordedAt = "recorded_at"
        case processingStatus = "processing_status"
    }
}

struct FoodLog: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    let groupId: UUID
    var clipId: UUID?
    var foodName: String
    var calories: Int
    var loggedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, calories
        case userId = "user_id"
        case groupId = "group_id"
        case clipId = "clip_id"
        case foodName = "food_name"
        case loggedAt = "logged_at"
    }
}

struct WorkoutLog: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    let groupId: UUID
    var clipId: UUID?
    var exerciseName: String
    var calories: Int
    var durationMinutes: Int
    var bodyPart: String?
    var muscleLoads: [String: Double]?
    var loggedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, calories
        case userId = "user_id"
        case groupId = "group_id"
        case clipId = "clip_id"
        case exerciseName = "exercise_name"
        case durationMinutes = "duration_minutes"
        case bodyPart = "body_part"
        case muscleLoads = "muscle_loads"
        case loggedAt = "logged_at"
    }
}

// ── 클립 + 연결된 태그를 묶은 화면용 모델 ──────────────────
enum ClipTag: Hashable {
    case food(name: String, kcal: Int)
    case move(name: String, kcal: Int, minutes: Int, part: String?,
              muscles: [String: Double]?)

    var kcal: Int {
        switch self {
        case .food(_, let k): return k
        case .move(_, let k, _, _, _): return k
        }
    }
    var isMove: Bool { if case .move = self { return true } else { return false } }
    var name: String {
        switch self {
        case .food(let n, _): return n
        case .move(let n, _, _, _, _): return n
        }
    }
}

struct TaggedClip: Identifiable, Hashable {
    var clip: Clip
    var tag: ClipTag?
    var id: UUID { clip.id }
    var userId: UUID { clip.userId }
    var recordedAt: Date { clip.recordedAt }
    var caption: String { clip.caption }
}

// ── 카탈로그 ─────────────────────────────────────────────
struct ExerciseItem: Codable, Identifiable, Hashable {
    let id: Int
    var name: String
    var met: Double
    var bodyPart: String
    /// "time"(분 슬라이더) | "strength"(무게×횟수×세트)
    var mode: String?
    /// 세부 근육별 부하 비율 (합 1.0) — 예: {"가슴":0.6,"어깨":0.2,"팔":0.2}
    var muscleLoads: [String: Double]?

    var isStrength: Bool { mode == "strength" }

    init(id: Int, name: String, met: Double, bodyPart: String,
         mode: String? = nil, muscleLoads: [String: Double]? = nil) {
        self.id = id; self.name = name; self.met = met
        self.bodyPart = bodyPart; self.mode = mode; self.muscleLoads = muscleLoads
    }

    enum CodingKeys: String, CodingKey {
        case id, name, met, mode
        case bodyPart = "body_part"
        case muscleLoads = "muscle_loads"
    }
}

struct FoodItem: Codable, Identifiable, Hashable {
    let id: Int
    var name: String
    var kcal: Int
}
