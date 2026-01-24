import Foundation

// MARK: - Sync Status

public enum SyncStatus: String, Codable, Sendable {
    case synced = "synced"
    case pending = "pending"
    case conflict = "conflict"
    case error = "error"
}

// MARK: - Sync State

public struct SyncState: Codable, Sendable {
    public var lastSyncTime: Date?
    public var calendarSyncToken: String?
    public var tasksSyncToken: String?
    public var pendingChanges: Int
    public var status: SyncStatus

    public init(
        lastSyncTime: Date? = nil,
        calendarSyncToken: String? = nil,
        tasksSyncToken: String? = nil,
        pendingChanges: Int = 0,
        status: SyncStatus = .synced
    ) {
        self.lastSyncTime = lastSyncTime
        self.calendarSyncToken = calendarSyncToken
        self.tasksSyncToken = tasksSyncToken
        self.pendingChanges = pendingChanges
        self.status = status
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
