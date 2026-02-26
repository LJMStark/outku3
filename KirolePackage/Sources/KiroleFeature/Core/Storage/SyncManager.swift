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
        }

        do {
            try await syncStreak(userId: userId)
            syncedCount += 1
        } catch {
            failedCount += 1
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

    private func syncStreak(userId: String) async throws {
        let localStreak = try await localStorage.loadStreak()
        let remoteStreak = try await supabaseService.getStreak(userId: userId)

        if let local = localStreak, let remote = remoteStreak {
            let merged = Streak(
                currentStreak: max(local.currentStreak, remote.currentStreak),
                longestStreak: max(local.longestStreak, remote.longestStreak),
                lastActiveDate: [local.lastActiveDate, remote.lastActiveDate].compactMap { $0 }.max()
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

    public func loadPet(userId: String?) async -> Pet? {
        do {
            let localPet = try await localStorage.loadPet()

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

    public func loadStreak(userId: String?) async -> Streak? {
        do {
            let localStreak = try await localStorage.loadStreak()

            if let userId = userId {
                Task {
                    do {
                        try await syncStreak(userId: userId)
                    } catch {
                        ErrorReporter.log(
                            .sync(component: "Streak", underlying: error.localizedDescription),
                            context: "SyncManager.loadStreak.backgroundSync"
                        )
                    }
                }
            }

            return localStreak
        } catch {
            ErrorReporter.log(
                .persistence(operation: "load", target: "streak.json", underlying: error.localizedDescription),
                context: "SyncManager.loadStreak"
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
