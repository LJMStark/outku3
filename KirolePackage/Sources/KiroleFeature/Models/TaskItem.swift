import CryptoKit
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
    public var notionPageId: String?
    public var notionDatabaseId: String?
    public var taskadeTaskId: String?
    public var taskadeProjectId: String?
    public var externalReference: ProviderItemReference?
    public var title: String
    public var isCompleted: Bool
    public var dueDate: Date?
    public var source: EventSource
    public var priority: TaskPriority
    public var syncStatus: SyncStatus
    public var pendingDeletion: Bool
    public var lastModified: Date
    public var remoteUpdatedAt: Date?
    public var remoteEtag: String?
    public var notes: String?
    /// Kirole-only date marking this task for today's App and E-ink display.
    /// This is deliberately separate from `dueDate`: changing it must never write to the
    /// external task provider or alter the task's real deadline.
    public var todayDisplayDate: Date?
    /// Identifies the durable hardware completion that produced `isCompleted=true`.
    /// It lets a pending BLE operation finish a task→pet split write after a crash without
    /// awarding points twice. User-driven toggles clear it.
    public var hardwareCompletionOperationKey: String?

    public init(
        id: String = UUID().uuidString,
        localId: UUID = UUID(),
        googleTaskId: String? = nil,
        googleTaskListId: String? = nil,
        appleReminderId: String? = nil,
        appleExternalId: String? = nil,
        appleListId: String? = nil,
        notionPageId: String? = nil,
        notionDatabaseId: String? = nil,
        taskadeTaskId: String? = nil,
        taskadeProjectId: String? = nil,
        externalReference: ProviderItemReference? = nil,
        title: String,
        isCompleted: Bool = false,
        dueDate: Date? = nil,
        source: EventSource = .apple,
        priority: TaskPriority = .medium,
        syncStatus: SyncStatus = .synced,
        pendingDeletion: Bool = false,
        lastModified: Date = Date(),
        remoteUpdatedAt: Date? = nil,
        remoteEtag: String? = nil,
        notes: String? = nil,
        todayDisplayDate: Date? = nil,
        hardwareCompletionOperationKey: String? = nil
    ) {
        self.id = id
        self.localId = localId
        self.googleTaskId = googleTaskId
        self.googleTaskListId = googleTaskListId
        self.appleReminderId = appleReminderId
        self.appleExternalId = appleExternalId
        self.appleListId = appleListId
        self.notionPageId = notionPageId
        self.notionDatabaseId = notionDatabaseId
        self.taskadeTaskId = taskadeTaskId
        self.taskadeProjectId = taskadeProjectId
        self.externalReference = externalReference
        self.title = title
        self.isCompleted = isCompleted
        self.dueDate = dueDate
        self.source = source
        self.priority = priority
        self.syncStatus = syncStatus
        self.pendingDeletion = pendingDeletion
        self.lastModified = lastModified
        self.remoteUpdatedAt = remoteUpdatedAt
        self.remoteEtag = remoteEtag
        self.notes = notes
        self.todayDisplayDate = todayDisplayDate
        self.hardwareCompletionOperationKey = hardwareCompletionOperationKey
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
            pendingDeletion: false,
            lastModified: remoteUpdated ?? Date(),
            remoteUpdatedAt: remoteUpdated,
            remoteEtag: googleTask.etag,
            notes: googleTask.notes
        )
    }
}

extension TaskItem {
    /// Stable identifier used on the fixed-width BLE wire. Provider IDs are opaque and may be
    /// longer than 36 bytes or non-ASCII, so those IDs are hashed instead of silently truncated.
    public var hardwareIdentifier: String {
        let bytes = Array(id.utf8)
        if !bytes.isEmpty, bytes.count <= 36, bytes.allSatisfy({ $0 < 0x80 }) {
            return id
        }
        let digest = SHA256.hash(data: Data(bytes))
        let prefix = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        return "h-\(prefix)"
    }

    public func isNaturallyDueToday(
        on date: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        dueDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
    }

    public func isManuallySelectedForToday(
        on date: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let todayDisplayDate else { return false }
        return calendar.isDate(todayDisplayDate, inSameDayAs: date)
    }

    public func isInTodayDisplay(
        on date: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        isNaturallyDueToday(on: date, calendar: calendar)
            || isManuallySelectedForToday(on: date, calendar: calendar)
    }

    func canShowTodayDisplayAction(
        on date: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        !isCompleted && !isInTodayDisplay(on: date, calendar: calendar)
    }

    func canRemoveTodayDisplayAction(
        on date: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        isManuallySelectedForToday(on: date, calendar: calendar)
            && !isNaturallyDueToday(on: date, calendar: calendar)
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
