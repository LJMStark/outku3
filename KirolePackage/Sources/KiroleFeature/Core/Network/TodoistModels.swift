import Foundation

public struct TodoistDue: Codable, Sendable, Equatable {
    public let date: String
    public let timezone: String?
    public let string: String?
    public let language: String?
    public let isRecurring: Bool

    public init(
        date: String,
        timezone: String? = nil,
        string: String? = nil,
        language: String? = nil,
        isRecurring: Bool = false
    ) {
        self.date = date
        self.timezone = timezone
        self.string = string
        self.language = language
        self.isRecurring = isRecurring
    }

    enum CodingKeys: String, CodingKey {
        case date, timezone, string
        case language = "lang"
        case isRecurring = "is_recurring"
    }

    public var resolvedDate: Date? {
        ProviderDateParser.parse(date, timeZoneIdentifier: timezone)
    }
}

public struct TodoistItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let projectID: String
    public let parentID: String?
    public let content: String
    public let description: String
    public let checked: Bool
    public let isDeleted: Bool
    public let priority: Int
    public let due: TodoistDue?
    public let updatedAt: String?

    public init(
        id: String,
        projectID: String,
        parentID: String?,
        content: String,
        description: String,
        checked: Bool,
        isDeleted: Bool,
        priority: Int,
        due: TodoistDue?,
        updatedAt: String?
    ) {
        self.id = id
        self.projectID = projectID
        self.parentID = parentID
        self.content = content
        self.description = description
        self.checked = checked
        self.isDeleted = isDeleted
        self.priority = priority
        self.due = due
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, content, description, checked, priority, due
        case projectID = "project_id"
        case parentID = "parent_id"
        case isDeleted = "is_deleted"
        case updatedAt = "updated_at"
    }

    public var isRootTask: Bool { parentID == nil }
    public var remoteUpdatedAt: Date? { updatedAt.flatMap(ProviderDateParser.parse) }

    public func taskItem(accountID: String) -> TaskItem {
        let reference = ProviderItemReference(
            provider: .todoist,
            accountID: accountID,
            containerID: projectID,
            itemID: id,
            remoteStatus: checked ? "completed" : "open",
            allowsContentModifications: true
        )
        return TaskItem(
            id: reference.stableLocalID,
            externalReference: reference,
            title: content,
            isCompleted: checked,
            dueDate: due?.resolvedDate,
            source: .todoist,
            priority: Self.taskPriority(priority),
            syncStatus: isDeleted ? .deleted : .synced,
            lastModified: remoteUpdatedAt ?? Date(),
            remoteUpdatedAt: remoteUpdatedAt,
            notes: description.isEmpty ? nil : description
        )
    }

    private static func taskPriority(_ rawValue: Int) -> TaskPriority {
        switch rawValue {
        case 4: .high
        case 1: .low
        default: .medium
        }
    }
}

public struct TodoistProject: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let isDeleted: Bool
    public let isArchived: Bool

    public init(id: String, name: String, isDeleted: Bool, isArchived: Bool) {
        self.id = id
        self.name = name
        self.isDeleted = isDeleted
        self.isArchived = isArchived
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case isDeleted = "is_deleted"
        case isArchived = "is_archived"
    }
}

public struct TodoistUser: Codable, Sendable, Equatable, Identifiable {
    public let id: String

    public init(id: String) {
        self.id = id
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let id = try? container.decode(String.self) {
            self.id = id
            return
        }
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        if let id = try? keyed.decode(String.self, forKey: .id) {
            self.id = id
            return
        }
        self.id = String(try keyed.decode(Int64.self, forKey: .id))
    }

    private enum CodingKeys: String, CodingKey {
        case id
    }
}

public struct TodoistSyncResponse: Decodable, Sendable, Equatable {
    public let syncToken: String
    public let fullSync: Bool
    public let items: [TodoistItem]
    public let projects: [TodoistProject]
    public let user: TodoistUser?
    public let syncStatus: [String: TodoistCommandResult]

    public init(
        syncToken: String,
        fullSync: Bool,
        items: [TodoistItem] = [],
        projects: [TodoistProject] = [],
        user: TodoistUser? = nil,
        syncStatus: [String: TodoistCommandResult] = [:]
    ) {
        self.syncToken = syncToken
        self.fullSync = fullSync
        self.items = items
        self.projects = projects
        self.user = user
        self.syncStatus = syncStatus
    }

    enum CodingKeys: String, CodingKey {
        case syncToken = "sync_token"
        case fullSync = "full_sync"
        case items, projects, user
        case syncStatus = "sync_status"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        syncToken = try container.decode(String.self, forKey: .syncToken)
        fullSync = try container.decodeIfPresent(Bool.self, forKey: .fullSync) ?? false
        items = try container.decodeIfPresent([TodoistItem].self, forKey: .items) ?? []
        projects = try container.decodeIfPresent([TodoistProject].self, forKey: .projects) ?? []
        user = try container.decodeIfPresent(TodoistUser.self, forKey: .user)
        syncStatus = try container.decodeIfPresent(
            [String: TodoistCommandResult].self,
            forKey: .syncStatus
        ) ?? [:]
    }
}

public enum TodoistCommandResult: Decodable, Sendable, Equatable {
    case ok
    case error(code: Int?, message: String?)

    public var isSuccess: Bool {
        if case .ok = self { return true }
        return false
    }

    public init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let value = try? single.decode(String.self), value == "ok" {
            self = .ok
            return
        }
        if let detail = try? single.decode(ErrorDetail.self) {
            self = .error(code: detail.errorCode, message: detail.error)
            return
        }
        self = .error(code: nil, message: nil)
    }

    private struct ErrorDetail: Decodable {
        let errorCode: Int?
        let error: String?

        enum CodingKeys: String, CodingKey {
            case errorCode = "error_code"
            case error
        }
    }
}

public struct TodoistCommand: Codable, Sendable, Equatable {
    public let type: String
    public let uuid: String
    public let args: [String: String]

    public init(type: String, uuid: String, args: [String: String]) {
        self.type = type
        self.uuid = uuid
        self.args = args
    }
}

public struct TodoistOutboxEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let accountID: String
    public let itemID: String
    public let completed: Bool
    public let createdAt: Date
    public var retryCount: Int
    public var nextAttemptAt: Date?

    public init(
        id: UUID = UUID(),
        accountID: String,
        itemID: String,
        completed: Bool,
        createdAt: Date = Date(),
        retryCount: Int = 0,
        nextAttemptAt: Date? = nil
    ) {
        self.id = id
        self.accountID = accountID
        self.itemID = itemID
        self.completed = completed
        self.createdAt = createdAt
        self.retryCount = retryCount
        self.nextAttemptAt = nextAttemptAt
    }

    public var command: TodoistCommand {
        TodoistCommand(
            type: completed ? "item_close" : "item_uncomplete",
            uuid: id.uuidString.lowercased(),
            args: ["id": itemID]
        )
    }

    public func retrying(after date: Date, maxBackoffExponent: Int = 8) -> TodoistOutboxEntry {
        var copy = self
        let retryCap = max(1, maxBackoffExponent)
        let previousRetryCount = max(copy.retryCount, 0)
        copy.retryCount = previousRetryCount == Int.max ? Int.max : previousRetryCount + 1
        let backoffExponent = min(copy.retryCount, retryCap)
        let delay = min(pow(2, Double(backoffExponent)) * 5, 15 * 60)
        copy.nextAttemptAt = date.addingTimeInterval(delay)
        return copy
    }
}

enum ProviderDateParser {
    static func parse(_ value: String) -> Date? {
        parse(value, timeZoneIdentifier: nil)
    }

    static func parse(_ value: String, timeZoneIdentifier: String?) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if let date = standard.date(from: value) { return date }

        let formats = ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}
