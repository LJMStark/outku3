import Foundation

// MARK: - Outbox

public enum OutboxAction: String, Codable, Sendable {
    case updateStatus
    case create
    case delete
}

public struct OutboxEntry: Codable, Sendable, Identifiable {
    public let id: UUID
    public let taskItem: TaskItem
    public let action: OutboxAction
    public let createdAt: Date
    public var retryCount: Int

    public init(taskItem: TaskItem, action: OutboxAction) {
        self.id = UUID()
        self.taskItem = taskItem
        self.action = action
        self.createdAt = Date()
        self.retryCount = 0
    }
}

// MARK: - Sync Metadata

public struct GoogleSyncMetadata: Codable, Sendable {
    public var calendarSyncToken: String?
    public var lastTasksSyncTime: Date?
    public var lastFullSyncTime: Date?

    public init() {}
}
