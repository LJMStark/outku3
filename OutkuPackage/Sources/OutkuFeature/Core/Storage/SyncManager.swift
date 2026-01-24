import Foundation

// MARK: - Sync Manager

/// 协调本地数据与远程服务的同步
public actor SyncManager {
    public static let shared = SyncManager()

    private let localStorage = LocalStorage.shared
    private let supabaseService = SupabaseService.shared

    private var syncState = SyncState()
    private var isSyncing = false

    private init() {}

    // MARK: - Initialize

    /// 初始化同步管理器，加载本地同步状态
    public func initialize() async {
        if let state = try? await localStorage.loadSyncState() {
            syncState = state
        }
    }

    // MARK: - Full Sync

    /// 执行完整同步
    public func performFullSync(userId: String) async -> SyncResult {
        guard !isSyncing else {
            return .failure(SyncError.alreadySyncing)
        }

        isSyncing = true
        defer { isSyncing = false }

        var syncedCount = 0
        var failedCount = 0

        // 同步宠物数据
        do {
            try await syncPet(userId: userId)
            syncedCount += 1
        } catch {
            failedCount += 1
        }

        // 同步连续打卡数据
        do {
            try await syncStreak(userId: userId)
            syncedCount += 1
        } catch {
            failedCount += 1
        }

        // 更新同步状态
        syncState.lastSyncTime = Date()
        syncState.status = failedCount == 0 ? .synced : .pending
        syncState.pendingChanges = 0

        try? await localStorage.saveSyncState(syncState)
        try? await supabaseService.saveSyncState(syncState, userId: userId)

        if failedCount == 0 {
            return .success(itemsSynced: syncedCount)
        } else {
            return .partial(synced: syncedCount, failed: failedCount)
        }
    }

    // MARK: - Pet Sync

    /// 同步宠物数据
    private func syncPet(userId: String) async throws {
        // 获取本地数据
        let localPet = try await localStorage.loadPet()

        // 获取远程数据
        let remotePet = try await supabaseService.getPet(userId: userId)

        // 冲突解决：Last-Write-Wins
        if let local = localPet, let remote = remotePet {
            if local.lastInteraction > remote.lastInteraction {
                // 本地更新，推送到远程
                try await supabaseService.savePet(local, userId: userId)
            } else {
                // 远程更新，保存到本地
                try await localStorage.savePet(remote)
            }
        } else if let local = localPet {
            // 只有本地数据，推送到远程
            try await supabaseService.savePet(local, userId: userId)
        } else if let remote = remotePet {
            // 只有远程数据，保存到本地
            try await localStorage.savePet(remote)
        }
    }

    /// 同步连续打卡数据
    private func syncStreak(userId: String) async throws {
        let localStreak = try await localStorage.loadStreak()
        let remoteStreak = try await supabaseService.getStreak(userId: userId)

        // 冲突解决：取较大的 streak 值
        if let local = localStreak, let remote = remoteStreak {
            let merged = Streak(
                currentStreak: max(local.currentStreak, remote.currentStreak),
                longestStreak: max(local.longestStreak, remote.longestStreak),
                lastActiveDate: [local.lastActiveDate, remote.lastActiveDate]
                    .compactMap { $0 }
                    .max()
            )
            try await localStorage.saveStreak(merged)
            try await supabaseService.saveStreak(merged, userId: userId)
        } else if let local = localStreak {
            try await supabaseService.saveStreak(local, userId: userId)
        } else if let remote = remoteStreak {
            try await localStorage.saveStreak(remote)
        }
    }

    // MARK: - Save with Sync

    /// 保存宠物数据并标记待同步
    public func savePet(_ pet: Pet, userId: String?) async throws {
        // 先保存到本地
        try await localStorage.savePet(pet)

        // 如果有用户 ID，尝试同步到远程
        if let userId = userId {
            do {
                try await supabaseService.savePet(pet, userId: userId)
            } catch {
                // 同步失败，标记待同步
                syncState.pendingChanges += 1
                syncState.status = .pending
                try await localStorage.saveSyncState(syncState)
            }
        }
    }

    /// 保存连续打卡数据并标记待同步
    public func saveStreak(_ streak: Streak, userId: String?) async throws {
        try await localStorage.saveStreak(streak)

        if let userId = userId {
            do {
                try await supabaseService.saveStreak(streak, userId: userId)
            } catch {
                syncState.pendingChanges += 1
                syncState.status = .pending
                try await localStorage.saveSyncState(syncState)
            }
        }
    }

    // MARK: - Load Data

    /// 加载宠物数据（优先本地，后台同步）
    public func loadPet(userId: String?) async -> Pet? {
        // 先返回本地数据
        let localPet = try? await localStorage.loadPet()

        // 后台同步
        if let userId = userId {
            Task {
                try? await syncPet(userId: userId)
            }
        }

        return localPet
    }

    /// 加载连续打卡数据
    public func loadStreak(userId: String?) async -> Streak? {
        let localStreak = try? await localStorage.loadStreak()

        if let userId = userId {
            Task {
                try? await syncStreak(userId: userId)
            }
        }

        return localStreak
    }

    // MARK: - Sync State

    /// 获取当前同步状态
    public func getSyncState() -> SyncState {
        syncState
    }

    /// 是否有待同步的更改
    public func hasPendingChanges() -> Bool {
        syncState.pendingChanges > 0
    }
}

// MARK: - Sync Error

public enum SyncError: LocalizedError, Sendable {
    case alreadySyncing
    case networkError
    case conflictError
    case unauthorized

    public var errorDescription: String? {
        switch self {
        case .alreadySyncing:
            return "Sync already in progress"
        case .networkError:
            return "Network error occurred"
        case .conflictError:
            return "Data conflict detected"
        case .unauthorized:
            return "Not authorized to sync"
        }
    }
}
