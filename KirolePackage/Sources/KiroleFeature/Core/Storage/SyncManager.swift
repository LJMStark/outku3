import Foundation

// MARK: - Sync Manager

public actor SyncManager {
    public static let shared = SyncManager()

    private let localStorage = LocalStorage.shared
    private let supabaseService = SupabaseService.shared

    private var syncState = SyncState()
    private var isSyncing = false

    private init() {}

    // MARK: - Initialize

    public func initialize() async {
        do {
            if let state = try await localStorage.loadSyncState() {
                syncState = state
            }
        } catch {
            ErrorReporter.log(
                .persistence(operation: "load", target: "sync_state.json", underlying: error.localizedDescription),
                context: "SyncManager.initialize"
            )
        }
    }

    // MARK: - Full Sync

    public func performFullSync(userId: String) async -> SyncResult {
        guard !isSyncing else {
            return .failure(SyncError.alreadySyncing)
        }

        isSyncing = true
        defer { isSyncing = false }

        var syncedCount = 0
        var failedCount = 0

        do {
            try await syncPet(userId: userId)
            syncedCount += 1
        } catch {
            failedCount += 1
            // 只计数不留痕的话，上层只看得到 "Some data failed to sync"，根因永久丢失。
            ErrorReporter.log(
                .sync(component: "SyncManager.syncPet", underlying: error.localizedDescription),
                context: "SyncManager.performFullSync"
            )
        }

        do {
            try await syncEnergyBottles(userId: userId)
            syncedCount += 1
        } catch {
            failedCount += 1
            ErrorReporter.log(
                .sync(component: "SyncManager.syncEnergyBottles", underlying: error.localizedDescription),
                context: "SyncManager.performFullSync"
            )
        }

        syncState.lastSyncTime = Date()
        syncState.status = failedCount == 0 ? .synced : .pending
        syncState.pendingChanges = 0

        do {
            try await localStorage.saveSyncState(syncState)
        } catch {
            ErrorReporter.log(
                .persistence(operation: "save", target: "sync_state.json", underlying: error.localizedDescription),
                context: "SyncManager.performFullSync"
            )
        }

        do {
            try await supabaseService.saveSyncState(syncState, userId: userId)
        } catch {
            ErrorReporter.log(
                .sync(component: "Supabase", underlying: error.localizedDescription),
                context: "SyncManager.performFullSync"
            )
        }

        return failedCount == 0
            ? .success(itemsSynced: syncedCount)
            : .partial(synced: syncedCount, failed: failedCount)
    }

    // MARK: - Pet Sync

    private func syncPet(userId: String) async throws {
        let localPet = try await localStorage.loadPet()
        let remotePet = try await supabaseService.getPet(userId: userId)

        if let local = localPet, let remote = remotePet {
            if local.lastInteraction > remote.lastInteraction {
                try await supabaseService.savePet(local, userId: userId)
            } else {
                try await localStorage.savePet(remote)
            }
        } else if let local = localPet {
            try await supabaseService.savePet(local, userId: userId)
        } else if let remote = remotePet {
            try await localStorage.savePet(remote)
        }
    }

    // MARK: - Energy Bottles Sync

    /// 合并本地与云端能量瓶子（取较大值，防换机/重装清零或互相覆盖），回写本地，
    /// 并暂存进 syncState —— 由 performFullSync 末尾的 saveSyncState 统一上推到云端。
    private func syncEnergyBottles(userId: String) async throws {
        let local = await localStorage.loadEnergyBottles()
        let remote = (try await supabaseService.getSyncState(userId: userId))?.energyBottles ?? 0
        let merged = max(local, remote)
        if merged != local {
            await localStorage.saveEnergyBottles(merged)
        }
        syncState.energyBottles = merged
    }

    // MARK: - Save with Sync

    public func savePet(_ pet: Pet, userId: String?) async throws {
        try await localStorage.savePet(pet)

        if let userId = userId {
            do {
                try await supabaseService.savePet(pet, userId: userId)
            } catch {
                syncState.pendingChanges += 1
                syncState.status = .pending
                try await localStorage.saveSyncState(syncState)
            }
        }
    }

    // MARK: - Load Data

    /// 加载 Pet 数据
    /// - Note: 后台同步是 fire-and-forget 模式，同步失败会记录但不阻塞返回
    /// - Parameter userId: 云端用户 ID，如果提供则触发后台同步
    /// - Returns: 本地 Pet 数据，如果加载失败返回 nil
    public func loadPet(userId: String?) async -> Pet? {
        do {
            let localPet = try await localStorage.loadPet()

            // Fire-and-forget background sync: errors are logged but don't block
            if let userId = userId {
                Task {
                    do {
                        try await syncPet(userId: userId)
                    } catch {
                        ErrorReporter.log(
                            .sync(component: "Pet", underlying: error.localizedDescription),
                            context: "SyncManager.loadPet.backgroundSync"
                        )
                    }
                }
            }

            return localPet
        } catch {
            ErrorReporter.log(
                .persistence(operation: "load", target: "pet.json", underlying: error.localizedDescription),
                context: "SyncManager.loadPet"
            )
            return nil
        }
    }

    // MARK: - Sync State

    public func getSyncState() -> SyncState {
        syncState
    }

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
        case .alreadySyncing: return "Sync already in progress"
        case .networkError: return "Network error occurred"
        case .conflictError: return "Data conflict detected"
        case .unauthorized: return "Not authorized to sync"
        }
    }
}
