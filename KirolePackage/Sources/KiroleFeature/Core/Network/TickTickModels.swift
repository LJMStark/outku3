import Foundation

public enum TickTickRegion: String, Codable, Sendable, CaseIterable {
    case international
    case china

    public var apiBaseURL: URL {
        switch self {
        case .international: URL(string: "https://api.ticktick.com/open/v1")!
        case .china: URL(string: "https://api.dida365.com/open/v1")!
        }
    }

    public var authorizationEndpoint: URL {
        switch self {
        case .international: URL(string: "https://ticktick.com/oauth/authorize")!
        case .china: URL(string: "https://dida365.com/oauth/authorize")!
        }
    }

    public var externalRegion: ExternalProviderRegion {
        switch self {
        case .international: .international
        case .china: .china
        }
    }
}

public struct TickTickProject: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let color: String?
    public let sortOrder: Int64?
    public let closed: Bool?
    public let groupID: String?
    public let viewMode: String?
    public let permission: String?

    public init(
        id: String,
        name: String,
        color: String?,
        sortOrder: Int64?,
        closed: Bool?,
        groupID: String?,
        viewMode: String?,
        permission: String?
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.sortOrder = sortOrder
        self.closed = closed
        self.groupID = groupID
        self.viewMode = viewMode
        self.permission = permission
    }

    enum CodingKeys: String, CodingKey {
        case id, name, color, sortOrder, closed, viewMode, permission
        case groupID = "groupId"
    }
}

public struct TickTickTask: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let projectID: String
    public let title: String
    public let content: String?
    public let description: String?
    public let isAllDay: Bool?
    public let startDate: String?
    public let dueDate: String?
    public let timeZone: String?
    public let repeatFlag: String?
    public let priority: Int
    public let status: Int
    public let sortOrder: Int64?
    public let modifiedTime: String?
    public let etag: String?

    public init(
        id: String,
        projectID: String,
        title: String,
        content: String?,
        description: String?,
        isAllDay: Bool?,
        startDate: String?,
        dueDate: String?,
        timeZone: String?,
        repeatFlag: String?,
        priority: Int,
        status: Int,
        sortOrder: Int64?,
        modifiedTime: String?,
        etag: String?
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.content = content
        self.description = description
        self.isAllDay = isAllDay
        self.startDate = startDate
        self.dueDate = dueDate
        self.timeZone = timeZone
        self.repeatFlag = repeatFlag
        self.priority = priority
        self.status = status
        self.sortOrder = sortOrder
        self.modifiedTime = modifiedTime
        self.etag = etag
    }

    enum CodingKeys: String, CodingKey {
        case id, title, content, desc, isAllDay, startDate, dueDate, timeZone
        case repeatFlag, priority, status, sortOrder, modifiedTime, etag
        case projectID = "projectId"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        projectID = try container.decode(String.self, forKey: .projectID)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        description = try container.decodeIfPresent(String.self, forKey: .desc)
        isAllDay = try container.decodeIfPresent(Bool.self, forKey: .isAllDay)
        startDate = try container.decodeIfPresent(String.self, forKey: .startDate)
        dueDate = try container.decodeIfPresent(String.self, forKey: .dueDate)
        timeZone = try container.decodeIfPresent(String.self, forKey: .timeZone)
        repeatFlag = try container.decodeIfPresent(String.self, forKey: .repeatFlag)
        priority = try container.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        status = try container.decodeIfPresent(Int.self, forKey: .status) ?? 0
        sortOrder = try container.decodeIfPresent(Int64.self, forKey: .sortOrder)
        modifiedTime = try container.decodeIfPresent(String.self, forKey: .modifiedTime)
        etag = try container.decodeIfPresent(String.self, forKey: .etag)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(projectID, forKey: .projectID)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(content, forKey: .content)
        try container.encodeIfPresent(description, forKey: .desc)
        try container.encodeIfPresent(isAllDay, forKey: .isAllDay)
        try container.encodeIfPresent(startDate, forKey: .startDate)
        try container.encodeIfPresent(dueDate, forKey: .dueDate)
        try container.encodeIfPresent(timeZone, forKey: .timeZone)
        try container.encodeIfPresent(repeatFlag, forKey: .repeatFlag)
        try container.encode(priority, forKey: .priority)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(sortOrder, forKey: .sortOrder)
        try container.encodeIfPresent(modifiedTime, forKey: .modifiedTime)
        try container.encodeIfPresent(etag, forKey: .etag)
    }

    public var isCompleted: Bool { status == 2 }
    public var resolvedDueDate: Date? {
        dueDate.flatMap { ProviderDateParser.parse($0, timeZoneIdentifier: timeZone) }
    }
    public var remoteUpdatedAt: Date? { modifiedTime.flatMap(ProviderDateParser.parse) }

    public func taskItem(accountID: String, region: TickTickRegion) -> TaskItem {
        let reference = ProviderItemReference(
            provider: .tickTick,
            accountID: accountID,
            containerID: projectID,
            itemID: id,
            region: region.externalRegion,
            etag: etag,
            remoteStatus: String(status),
            allowsContentModifications: false
        )
        return TaskItem(
            id: reference.stableLocalID,
            externalReference: reference,
            title: title,
            isCompleted: isCompleted,
            dueDate: resolvedDueDate,
            source: .tickTick,
            priority: Self.taskPriority(priority),
            syncStatus: .synced,
            lastModified: remoteUpdatedAt ?? .distantPast,
            remoteUpdatedAt: remoteUpdatedAt,
            remoteEtag: etag,
            notes: Self.notes(content: content, description: description)
        )
    }

    private static func taskPriority(_ rawValue: Int) -> TaskPriority {
        switch rawValue {
        case 5: .high
        case 0: .low
        default: .medium
        }
    }

    private static func notes(content: String?, description: String?) -> String? {
        [content, description]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: "\n")
            .nilIfEmpty
    }
}

public struct TickTickColumn: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let projectID: String?
    public let name: String?
    public let sortOrder: Int64?

    enum CodingKeys: String, CodingKey {
        case id, name, sortOrder
        case projectID = "projectId"
    }
}

public struct TickTickProjectData: Codable, Sendable, Equatable {
    public let project: TickTickProject
    public let tasks: [TickTickTask]
    public let columns: [TickTickColumn]

    public init(project: TickTickProject, tasks: [TickTickTask], columns: [TickTickColumn]) {
        self.project = project
        self.tasks = tasks
        self.columns = columns
    }
}

public enum TickTickConditionalProjectData: Sendable, Equatable {
    case modified(data: TickTickProjectData, etag: String?)
    case notModified
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
