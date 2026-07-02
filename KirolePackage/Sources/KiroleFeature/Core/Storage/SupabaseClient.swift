import Foundation
import Supabase

// MARK: - Supabase Client

/// Supabase 客户端配置和数据操作
public actor SupabaseService {
    public static let shared = SupabaseService()

    private let keychainService = KeychainService.shared
    private var client: SupabaseClient?
    private var isConfigured = false
    private var didAttemptSessionRestore = false

    private init() {
        // Configuration happens lazily on first use
    }

    // MARK: - Configuration

    /// 从 Bundle 配置读取 Supabase 凭证（懒加载）
    private func ensureConfigured() {
        guard !isConfigured else { return }

        guard let configured = AppSecrets.supabaseConfig else {
            #if DEBUG
            print("[SupabaseService] Not configured - call AppSecrets.configure(...) from App shell")
            #endif
            return
        }

        let url = configured.url
        let key = configured.anonKey

        guard
              !url.contains("YOUR_PROJECT"),
              !key.contains("YOUR_SUPABASE"),
              let supabaseURL = URL(string: url) else {
            #if DEBUG
            print("[SupabaseService] Invalid configuration - verify AppSecrets injected values")
            #endif
            return
        }

        client = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: key,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
        isConfigured = true
        #if DEBUG
        print("[SupabaseService] Configured successfully")
        #endif
    }

    /// 配置 Supabase（使用自定义 URL 和 Key）
    public func configure(url: String, key: String) {
        guard let supabaseURL = URL(string: url) else {
            #if DEBUG
            print("[SupabaseService] Invalid URL: \(url)")
            #endif
            return
        }
        client = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: key,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
        isConfigured = true
    }

    /// 检查是否已配置
    public var configured: Bool {
        ensureConfigured()
        return client != nil
    }

    private func requireClient() throws -> SupabaseClient {
        ensureConfigured()
        guard let client = client else {
            throw SupabaseError.notConfigured
        }
        return client
    }

    // MARK: - Auth

    /// 使用 Apple ID Token 登录 Supabase
    public func signInWithApple(idToken: String) async throws -> SupabaseUser {
        let client = try requireClient()
        let response = try await client.auth.signInWithIdToken(
            credentials: .init(
                provider: .apple,
                idToken: idToken
            )
        )
        try persistSession(response)

        return SupabaseUser(
            id: response.user.id.uuidString,
            email: response.user.email,
            createdAt: response.user.createdAt
        )
    }

    /// 使用 Google ID Token 登录 Supabase
    public func signInWithGoogle(idToken: String, accessToken: String) async throws -> SupabaseUser {
        let client = try requireClient()
        let response = try await client.auth.signInWithIdToken(
            credentials: .init(
                provider: .google,
                idToken: idToken,
                accessToken: accessToken
            )
        )
        try persistSession(response)

        return SupabaseUser(
            id: response.user.id.uuidString,
            email: response.user.email,
            createdAt: response.user.createdAt
        )
    }

    /// 登出
    public func signOut() async throws {
        let client = try requireClient()
        defer {
            keychainService.clearSupabaseTokens()
            didAttemptSessionRestore = false
        }
        try await client.auth.signOut()
    }

    /// 获取当前用户
    public func getCurrentUser() async -> SupabaseUser? {
        await restoreSessionIfNeeded()

        guard let client = try? requireClient(),
              let user = try? await client.auth.user() else {
            return nil
        }

        return SupabaseUser(
            id: user.id.uuidString,
            email: user.email,
            createdAt: user.createdAt
        )
    }

    private func persistSession(_ session: Session) throws {
        try keychainService.saveSupabaseTokens(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken
        )
        didAttemptSessionRestore = true
    }

    private func restoreSessionIfNeeded() async {
        guard !didAttemptSessionRestore else { return }
        didAttemptSessionRestore = true

        guard let client = try? requireClient() else { return }
        guard client.auth.currentSession == nil else { return }
        guard let accessToken = keychainService.getSupabaseAccessToken(),
              let refreshToken = keychainService.getSupabaseRefreshToken() else {
            return
        }

        do {
            let session = try await client.auth.setSession(
                accessToken: accessToken,
                refreshToken: refreshToken
            )
            try persistSession(session)
        } catch let error as AuthError {
            // 只有服务器明确拒绝凭证（refresh token 失效 / JWT 异常）才清 Keychain。
            // 5xx 是服务器故障（Zeabur 自托管现实概率），不代表凭证失效，保留待下次重试。
            if case let .api(_, _, _, response) = error, response.statusCode >= 500 {
                #if DEBUG
                print("[SupabaseService] Session restore hit server error \(response.statusCode), keeping tokens")
                #endif
            } else {
                keychainService.clearSupabaseTokens()
                #if DEBUG
                print("[SupabaseService] Persisted session rejected, clearing tokens: \(error.localizedDescription)")
                #endif
            }
        } catch {
            // 网络/瞬时错误（典型：离线启动）不清凭证——原实现任意错误都清，导致断网开
            // App 就丢登录态。didAttemptSessionRestore 保证每次启动只试一次，不会循环。
            #if DEBUG
            print("[SupabaseService] Session restore failed transiently, keeping tokens: \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - Pet Data

    /// 保存宠物数据
    public func savePet(_ pet: Pet, userId: String) async throws {
        let client = try requireClient()
        let petRecord = PetRecord(
            userId: userId,
            name: pet.name,
            pronouns: pet.pronouns.rawValue,
            adventuresCount: pet.adventuresCount,
            age: pet.age,
            status: pet.status.rawValue,
            mood: pet.mood.rawValue,
            scene: pet.scene.rawValue,
            lastInteraction: pet.lastInteraction,
            points: pet.points
        )

        try await client
            .from("pets")
            .upsert(petRecord, onConflict: "user_id")
            .execute()
    }

    /// 获取宠物数据
    public func getPet(userId: String) async throws -> Pet? {
        let client = try requireClient()
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
            lastInteraction: record.lastInteraction,
            points: record.points
        )
    }

    // MARK: - Sync State

    /// 保存同步状态
    public func saveSyncState(_ state: SyncState, userId: String) async throws {
        let client = try requireClient()
        let syncRecord = SyncStateRecord(
            userId: userId,
            lastSyncTime: state.lastSyncTime,
            calendarSyncToken: state.calendarSyncToken,
            tasksSyncToken: state.tasksSyncToken,
            pendingChanges: state.pendingChanges,
            status: state.status.rawValue,
            energyBottles: state.energyBottles
        )

        try await client
            .from("sync_state")
            .upsert(syncRecord, onConflict: "user_id")
            .execute()
    }

    /// 获取同步状态
    public func getSyncState(userId: String) async throws -> SyncState? {
        let client = try requireClient()
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
            status: SyncStatus(rawValue: record.status) ?? .synced,
            energyBottles: record.energyBottles ?? 0
        )
    }
}

// MARK: - Supabase Error

public enum SupabaseError: Error, LocalizedError {
    case notConfigured

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Supabase is not configured. Please inject credentials via AppSecrets.configure(...)"
        }
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
    let lastInteraction: Date
    let points: Int

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name, pronouns
        case adventuresCount = "adventures_count"
        case age, status, mood, scene
        case lastInteraction = "last_interaction"
        case points
    }
}

private struct SyncStateRecord: Codable {
    let userId: String
    let lastSyncTime: Date?
    let calendarSyncToken: String?
    let tasksSyncToken: String?
    let pendingChanges: Int
    let status: String
    // Optional so decode tolerates deployments where the energy_bottles column
    // hasn't been added yet (graceful no-op until the Zeabur migration is run).
    let energyBottles: Int?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case lastSyncTime = "last_sync_time"
        case calendarSyncToken = "calendar_sync_token"
        case tasksSyncToken = "tasks_sync_token"
        case pendingChanges = "pending_changes"
        case status
        case energyBottles = "energy_bottles"
    }
}
