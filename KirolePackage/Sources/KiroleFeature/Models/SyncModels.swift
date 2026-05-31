import Foundation

// MARK: - Sync Status

public enum SyncStatus: String, Codable, Sendable {
    case synced = "synced"
    case pending = "pending"
    case conflict = "conflict"
    case error = "error"
    case deleted = "deleted"
}

// MARK: - Sync State

public struct SyncState: Codable, Sendable {
    public var lastSyncTime: Date?
    public var calendarSyncToken: String?
    public var tasksSyncToken: String?
    public var pendingChanges: Int
    public var status: SyncStatus
    /// Cumulative focus energy bottles, synced cross-device so a reinstall / new
    /// device doesn't reset the user's scene-unlock progress.
    public var energyBottles: Int

    public init(
        lastSyncTime: Date? = nil,
        calendarSyncToken: String? = nil,
        tasksSyncToken: String? = nil,
        pendingChanges: Int = 0,
        status: SyncStatus = .synced,
        energyBottles: Int = 0
    ) {
        self.lastSyncTime = lastSyncTime
        self.calendarSyncToken = calendarSyncToken
        self.tasksSyncToken = tasksSyncToken
        self.pendingChanges = pendingChanges
        self.status = status
        self.energyBottles = energyBottles
    }

    private enum CodingKeys: String, CodingKey {
        case lastSyncTime, calendarSyncToken, tasksSyncToken, pendingChanges, status, energyBottles
    }

    // Tolerant decode: older local sync_state.json predates the energyBottles field,
    // so default missing keys instead of throwing (don't lose the rest of the state).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.lastSyncTime = try c.decodeIfPresent(Date.self, forKey: .lastSyncTime)
        self.calendarSyncToken = try c.decodeIfPresent(String.self, forKey: .calendarSyncToken)
        self.tasksSyncToken = try c.decodeIfPresent(String.self, forKey: .tasksSyncToken)
        self.pendingChanges = try c.decodeIfPresent(Int.self, forKey: .pendingChanges) ?? 0
        self.status = try c.decodeIfPresent(SyncStatus.self, forKey: .status) ?? .synced
        self.energyBottles = try c.decodeIfPresent(Int.self, forKey: .energyBottles) ?? 0
    }
}

// MARK: - Sync Result

public enum SyncResult: Sendable {
    case success(itemsSynced: Int)
    case partial(synced: Int, failed: Int)
    case failure(Error)

    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

// MARK: - Conflict Resolution

public enum ConflictResolution: Sendable {
    case useLocal
    case useRemote
    case merge
}
