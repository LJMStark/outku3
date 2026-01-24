import Foundation
import Supabase

// MARK: - Supabase Client

/// Supabase 客户端配置和数据操作
public actor SupabaseService {
    public static let shared = SupabaseService()

    // TODO: 从环境变量或配置文件读取
    private let supabaseURL = "https://your-project.supabase.co"
    private let supabaseKey = "your-anon-key"

    private lazy var client: SupabaseClient = {
        SupabaseClient(
            supabaseURL: URL(string: supabaseURL)!,
            supabaseKey: supabaseKey
        )
    }()

    private init() {}

    // MARK: - Configuration

    /// 配置 Supabase（使用自定义 URL 和 Key）
    public func configure(url: String, key: String) {
        // 重新创建 client 需要特殊处理
        // 在生产环境中，应该在 App 启动时配置一次
    }

    // MARK: - Auth

    /// 使用 Apple ID Token 登录 Supabase
    public func signInWithApple(idToken: String) async throws -> SupabaseUser {
        let response = try await client.auth.signInWithIdToken(
            credentials: .init(
                provider: .apple,
                idToken: idToken
            )
        )

        return SupabaseUser(
            id: response.user.id.uuidString,
            email: response.user.email,
            createdAt: response.user.createdAt
        )
    }

    /// 使用 Google ID Token 登录 Supabase
    public func signInWithGoogle(idToken: String, accessToken: String) async throws -> SupabaseUser {
        let response = try await client.auth.signInWithIdToken(
            credentials: .init(
                provider: .google,
                idToken: idToken,
                accessToken: accessToken
            )
        )

        return SupabaseUser(
            id: response.user.id.uuidString,
            email: response.user.email,
            createdAt: response.user.createdAt
        )
    }

    /// 登出
    public func signOut() async throws {
        try await client.auth.signOut()
    }

    /// 获取当前用户
    public func getCurrentUser() async -> SupabaseUser? {
        guard let user = try? await client.auth.user() else {
            return nil
        }

        return SupabaseUser(
            id: user.id.uuidString,
            email: user.email,
            createdAt: user.createdAt
        )
    }

    // MARK: - Pet Data

    /// 保存宠物数据
    public func savePet(_ pet: Pet, userId: String) async throws {
        let petRecord = PetRecord(
            userId: userId,
            name: pet.name,
            pronouns: pet.pronouns.rawValue,
            adventuresCount: pet.adventuresCount,
            age: pet.age,
            status: pet.status.rawValue,
            mood: pet.mood.rawValue,
            scene: pet.scene.rawValue,
            stage: pet.stage.rawValue,
            progress: pet.progress,
            weight: pet.weight,
            height: pet.height,
            tailLength: pet.tailLength,
            currentForm: pet.currentForm.rawValue,
            lastInteraction: pet.lastInteraction
        )

        try await client
            .from("pets")
            .upsert(petRecord, onConflict: "user_id")
            .execute()
    }

    /// 获取宠物数据
    public func getPet(userId: String) async throws -> Pet? {
        let response: [PetRecord] = try await client
            .from("pets")
            .select()
            .eq("user_id", value: userId)
            .limit(1)
            .execute()
            .value

        guard let record = response.first else {
            return nil
        }

        return Pet(
            name: record.name,
            pronouns: PetPronouns(rawValue: record.pronouns) ?? .theyThem,
            adventuresCount: record.adventuresCount,
            age: record.age,
            status: PetStatus(rawValue: record.status) ?? .happy,
            mood: PetMood(rawValue: record.mood) ?? .happy,
            scene: PetScene(rawValue: record.scene) ?? .indoor,
            stage: PetStage(rawValue: record.stage) ?? .baby,
            progress: record.progress,
            weight: record.weight,
            height: record.height,
            tailLength: record.tailLength,
            currentForm: PetForm(rawValue: record.currentForm) ?? .cat,
            lastInteraction: record.lastInteraction
        )
    }

    // MARK: - Streak Data

    /// 保存连续打卡数据
    public func saveStreak(_ streak: Streak, userId: String) async throws {
        let streakRecord = StreakRecord(
            userId: userId,
            currentStreak: streak.currentStreak,
            longestStreak: streak.longestStreak,
            lastActiveDate: streak.lastActiveDate
        )

        try await client
            .from("streaks")
            .upsert(streakRecord, onConflict: "user_id")
            .execute()
    }

    /// 获取连续打卡数据
    public func getStreak(userId: String) async throws -> Streak? {
        let response: [StreakRecord] = try await client
            .from("streaks")
            .select()
            .eq("user_id", value: userId)
            .limit(1)
            .execute()
            .value

        guard let record = response.first else {
            return nil
        }

        return Streak(
            currentStreak: record.currentStreak,
            longestStreak: record.longestStreak,
            lastActiveDate: record.lastActiveDate
        )
    }

    // MARK: - Sync State

    /// 保存同步状态
    public func saveSyncState(_ state: SyncState, userId: String) async throws {
        let syncRecord = SyncStateRecord(
            userId: userId,
            lastSyncTime: state.lastSyncTime,
            calendarSyncToken: state.calendarSyncToken,
            tasksSyncToken: state.tasksSyncToken,
            pendingChanges: state.pendingChanges,
            status: state.status.rawValue
        )

        try await client
            .from("sync_state")
            .upsert(syncRecord, onConflict: "user_id")
            .execute()
    }

    /// 获取同步状态
    public func getSyncState(userId: String) async throws -> SyncState? {
        let response: [SyncStateRecord] = try await client
            .from("sync_state")
            .select()
            .eq("user_id", value: userId)
            .limit(1)
            .execute()
            .value

        guard let record = response.first else {
            return nil
        }

        return SyncState(
            lastSyncTime: record.lastSyncTime,
            calendarSyncToken: record.calendarSyncToken,
            tasksSyncToken: record.tasksSyncToken,
            pendingChanges: record.pendingChanges,
            status: SyncStatus(rawValue: record.status) ?? .synced
        )
    }
}

// MARK: - Supabase User

public struct SupabaseUser: Sendable {
    public let id: String
    public let email: String?
    public let createdAt: Date
}

// MARK: - Database Records

private struct PetRecord: Codable {
    let userId: String
    let name: String
    let pronouns: String
    let adventuresCount: Int
    let age: Int
    let status: String
    let mood: String
    let scene: String
    let stage: String
    let progress: Double
    let weight: Double
    let height: Double
    let tailLength: Double
    let currentForm: String
    let lastInteraction: Date

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name, pronouns
        case adventuresCount = "adventures_count"
        case age, status, mood, scene, stage, progress, weight, height
        case tailLength = "tail_length"
        case currentForm = "current_form"
        case lastInteraction = "last_interaction"
    }
}

private struct StreakRecord: Codable {
    let userId: String
    let currentStreak: Int
    let longestStreak: Int
    let lastActiveDate: Date?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case currentStreak = "current_streak"
        case longestStreak = "longest_streak"
        case lastActiveDate = "last_active_date"
    }
}

private struct SyncStateRecord: Codable {
    let userId: String
    let lastSyncTime: Date?
    let calendarSyncToken: String?
    let tasksSyncToken: String?
    let pendingChanges: Int
    let status: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case lastSyncTime = "last_sync_time"
        case calendarSyncToken = "calendar_sync_token"
        case tasksSyncToken = "tasks_sync_token"
        case pendingChanges = "pending_changes"
        case status
    }
}
