import Foundation

private nonisolated(unsafe) let iso8601Formatter = ISO8601DateFormatter()

public struct TaskItem: Identifiable, Sendable, Codable {
    public let id: String
    public var localId: UUID
    public var googleTaskId: String?
    public var googleTaskListId: String?
    public var appleReminderId: String?
    public var appleExternalId: String?
    public var appleListId: String?
    public var title: String
    public var isCompleted: Bool
    public var dueDate: Date?
    public var source: EventSource
    public var priority: TaskPriority
    public var syncStatus: SyncStatus
    public var lastModified: Date
    public var microActions: [MicroAction]?
    public var remoteUpdatedAt: Date?
    public var remoteEtag: String?
    public var notes: String?

    public init(
        id: String = UUID().uuidString,
        localId: UUID = UUID(),
        googleTaskId: String? = nil,
        googleTaskListId: String? = nil,
        appleReminderId: String? = nil,
        appleExternalId: String? = nil,
        appleListId: String? = nil,
        title: String,
        isCompleted: Bool = false,
        dueDate: Date? = nil,
        source: EventSource = .apple,
        priority: TaskPriority = .medium,
        syncStatus: SyncStatus = .synced,
        lastModified: Date = Date(),
        microActions: [MicroAction]? = nil,
        remoteUpdatedAt: Date? = nil,
        remoteEtag: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.localId = localId
        self.googleTaskId = googleTaskId
        self.googleTaskListId = googleTaskListId
        self.appleReminderId = appleReminderId
        self.appleExternalId = appleExternalId
        self.appleListId = appleListId
        self.title = title
        self.isCompleted = isCompleted
        self.dueDate = dueDate
        self.source = source
        self.priority = priority
        self.syncStatus = syncStatus
        self.lastModified = lastModified
        self.microActions = microActions
        self.remoteUpdatedAt = remoteUpdatedAt
        self.remoteEtag = remoteEtag
        self.notes = notes
    }

    // 从 Google API 响应创建
    public static func from(googleTask: GoogleTask, taskListId: String) -> TaskItem {
        let remoteUpdated = googleTask.updated.flatMap { iso8601Formatter.date(from: $0) }

        return TaskItem(
            id: googleTask.id,
            googleTaskId: googleTask.id,
            googleTaskListId: taskListId,
            title: googleTask.title ?? "Untitled Task",
            isCompleted: googleTask.isCompleted,
            dueDate: googleTask.dueDate,
            source: .google,
            priority: .medium,
            syncStatus: .synced,
            lastModified: remoteUpdated ?? Date(),
            remoteUpdatedAt: remoteUpdated,
            remoteEtag: googleTask.etag
        )
    }
}

public enum TaskPriority: Int, Sendable, CaseIterable, Codable {
    case low = 0
    case medium = 1
    case high = 2

    public var color: String {
        switch self {
        case .low: return "7CB342"
        case .medium: return "FFB300"
        case .high: return "FF5252"
        }
    }
}

public enum TaskCategory: String, CaseIterable, Identifiable {
    case today = "Today"
    case upcoming = "Upcoming"
    case noDueDate = "No Due Dates"

    public var id: String { rawValue }
}
