import Foundation

// MARK: - Notion API Response Models

// MARK: Search

public struct NotionSearchResponse: Codable, Sendable {
    public let results: [NotionObject]
    public let nextCursor: String?
    public let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case results
        case nextCursor = "next_cursor"
        case hasMore = "has_more"
    }
}

public struct NotionObject: Codable, Sendable {
    public let object: String
    public let id: String
    public let title: [NotionRichText]?

    enum CodingKeys: String, CodingKey {
        case object, id, title
    }
}

// MARK: Database Query

public struct NotionQueryResponse: Codable, Sendable {
    public let results: [NotionPage]
    public let nextCursor: String?
    public let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case results
        case nextCursor = "next_cursor"
        case hasMore = "has_more"
    }
}

// MARK: Page

public struct NotionPage: Codable, Sendable {
    public let id: String
    public let createdTime: String
    public let lastEditedTime: String
    public let archived: Bool
    public let properties: [String: NotionPropertyValue]

    enum CodingKeys: String, CodingKey {
        case id
        case createdTime = "created_time"
        case lastEditedTime = "last_edited_time"
        case archived
        case properties
    }

    /// Heuristic title extraction: find the first "title" type property
    public var extractedTitle: String? {
        for (_, value) in properties {
            if case .title(let texts) = value.typed {
                return texts.map(\.plainText).joined()
            }
        }
        return nil
    }

    /// Heuristic completion extraction: find the first checkbox property
    public var extractedIsCompleted: Bool {
        for (_, value) in properties {
            if case .checkbox(let checked) = value.typed {
                return checked
            }
        }
        return false
    }

    /// Heuristic due date extraction: find the first date property
    public var extractedDueDate: Date? {
        for (_, value) in properties {
            if case .date(let dateValue) = value.typed {
                return dateValue?.startDate
            }
        }
        return nil
    }
}

// MARK: Property Value

public struct NotionPropertyValue: Codable, Sendable {
    public let id: String?
    public let type: String

    // Backing storage for different types
    public let title: [NotionRichText]?
    public let richText: [NotionRichText]?
    public let checkbox: Bool?
    public let date: NotionDateValue?
    public let select: NotionSelectValue?
    public let status: NotionSelectValue?

    enum CodingKeys: String, CodingKey {
        case id, type, title, checkbox, date, select, status
        case richText = "rich_text"
    }

    public var typed: NotionPropertyTyped {
        switch type {
        case "title":
            return .title(title ?? [])
        case "rich_text":
            return .richText(richText ?? [])
        case "checkbox":
            return .checkbox(checkbox ?? false)
        case "date":
            return .date(date)
        case "select":
            return .select(select)
        case "status":
            return .status(status)
        default:
            return .unsupported
        }
    }
}

public enum NotionPropertyTyped: Sendable {
    case title([NotionRichText])
    case richText([NotionRichText])
    case checkbox(Bool)
    case date(NotionDateValue?)
    case select(NotionSelectValue?)
    case status(NotionSelectValue?)
    case unsupported
}

// MARK: Rich Text

public struct NotionRichText: Codable, Sendable {
    public let plainText: String
    public let type: String

    enum CodingKeys: String, CodingKey {
        case plainText = "plain_text"
        case type
    }
}

// MARK: Date Value

public struct NotionDateValue: Codable, Sendable {
    public let start: String?
    public let end: String?

    private nonisolated(unsafe) static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    public var startDate: Date? {
        guard let start else { return nil }
        return Self.dateFormatter.date(from: start) ?? Self.dateOnlyFormatter.date(from: start)
    }
}

// MARK: Select Value

public struct NotionSelectValue: Codable, Sendable {
    public let id: String?
    public let name: String?
}

// MARK: Request Models

struct NotionSearchRequest: Encodable {
    let filter: NotionSearchFilter?
    let startCursor: String?
    let pageSize: Int

    enum CodingKeys: String, CodingKey {
        case filter
        case startCursor = "start_cursor"
        case pageSize = "page_size"
    }
}

struct NotionSearchFilter: Encodable {
    let value: String
    let property: String
}

struct NotionQueryRequest: Encodable {
    let startCursor: String?
    let pageSize: Int

    enum CodingKeys: String, CodingKey {
        case startCursor = "start_cursor"
        case pageSize = "page_size"
    }
}

struct NotionUpdatePageRequest: Encodable {
    let properties: [String: NotionUpdatePropertyValue]
}

struct NotionUpdatePropertyValue: Encodable {
    let checkbox: Bool?

    init(checkbox: Bool) {
        self.checkbox = checkbox
    }
}

// MARK: - TaskItem Mapping

extension TaskItem {
    public static func from(notionPage page: NotionPage, databaseId: String) -> TaskItem {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        let remoteUpdated = dateFormatter.date(from: page.lastEditedTime)

        return TaskItem(
            id: page.id,
            notionPageId: page.id,
            notionDatabaseId: databaseId,
            title: page.extractedTitle ?? "Untitled",
            isCompleted: page.extractedIsCompleted,
            dueDate: page.extractedDueDate,
            source: .notion,
            priority: .medium,
            syncStatus: .synced,
            lastModified: remoteUpdated ?? Date(),
            remoteUpdatedAt: remoteUpdated
        )
    }
}
