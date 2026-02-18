import Foundation

// MARK: - Cached Formatters

private enum CachedFormatters {
    nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) static let iso8601NoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

// MARK: - Google Calendar API Models

public struct GoogleCalendarEvent: Codable, Sendable {
    public let id: String
    public let summary: String?
    public let description: String?
    public let location: String?
    public let start: GoogleDateTime
    public let end: GoogleDateTime
    public let attendees: [GoogleAttendee]?
    public let status: String?
    public let updated: String?
    public let etag: String?
}

public struct GoogleDateTime: Codable, Sendable {
    public let dateTime: String?
    public let date: String?
    public let timeZone: String?

    /// Parse to Date object
    public var asDate: Date? {
        if let dateTime = dateTime {
            return CachedFormatters.iso8601.date(from: dateTime)
                ?? CachedFormatters.iso8601NoFractional.date(from: dateTime)
        }

        if let date = date {
            return CachedFormatters.dateOnly.date(from: date)
        }

        return nil
    }
}

public struct GoogleAttendee: Codable, Sendable {
    public let email: String?
    public let displayName: String?
    public let responseStatus: String?
}

public struct GoogleCalendarListResponse: Codable, Sendable {
    public let items: [GoogleCalendarEvent]?
    public let nextPageToken: String?
    public let nextSyncToken: String?

    public init(items: [GoogleCalendarEvent]?, nextPageToken: String?, nextSyncToken: String?) {
        self.items = items
        self.nextPageToken = nextPageToken
        self.nextSyncToken = nextSyncToken
    }
}

// MARK: - Google Tasks API Models

public struct GoogleTask: Codable, Sendable {
    public let id: String
    public let title: String?
    public let notes: String?
    public let status: String?
    public let due: String?
    public let completed: String?
    public let updated: String?
    public let position: String?
    public let etag: String?
    public let deleted: Bool?

    public var isCompleted: Bool {
        status == "completed"
    }

    public var dueDate: Date? {
        guard let due = due else { return nil }
        return CachedFormatters.iso8601NoFractional.date(from: due)
            ?? CachedFormatters.iso8601.date(from: due)
    }
}

public struct GoogleTaskList: Codable, Sendable {
    public let id: String
    public let title: String?
    public let updated: String?
}

public struct GoogleTaskListResponse: Codable, Sendable {
    public let items: [GoogleTask]?
    public let nextPageToken: String?
}

public struct GoogleTaskListsResponse: Codable, Sendable {
    public let items: [GoogleTaskList]?
    public let nextPageToken: String?
}

// MARK: - Google Task Update Request

public struct GoogleTaskUpdateRequest: Codable, Sendable {
    public let status: String?
    public let completed: String?

    public static func markCompleted() -> GoogleTaskUpdateRequest {
        GoogleTaskUpdateRequest(
            status: "completed",
            completed: CachedFormatters.iso8601NoFractional.string(from: Date())
        )
    }

    public static func markIncomplete() -> GoogleTaskUpdateRequest {
        GoogleTaskUpdateRequest(status: "needsAction", completed: nil)
    }
}

// MARK: - Google Task Create Request

public struct GoogleTaskCreateRequest: Codable, Sendable {
    public let title: String
    public let notes: String?
    public let due: String?
    public let status: String?

    public init(title: String, notes: String? = nil, due: String? = nil, status: String? = nil) {
        self.title = title
        self.notes = notes
        self.due = due
        self.status = status
    }
}
