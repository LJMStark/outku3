import Foundation

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

    public init(
        id: String,
        summary: String?,
        description: String?,
        location: String?,
        start: GoogleDateTime,
        end: GoogleDateTime,
        attendees: [GoogleAttendee]?,
        status: String?,
        updated: String?
    ) {
        self.id = id
        self.summary = summary
        self.description = description
        self.location = location
        self.start = start
        self.end = end
        self.attendees = attendees
        self.status = status
        self.updated = updated
    }
}

public struct GoogleDateTime: Codable, Sendable {
    public let dateTime: String?
    public let date: String?
    public let timeZone: String?

    public init(dateTime: String? = nil, date: String? = nil, timeZone: String? = nil) {
        self.dateTime = dateTime
        self.date = date
        self.timeZone = timeZone
    }

    // 解析为 Date 对象
    public var asDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let dateTime = dateTime {
            return formatter.date(from: dateTime) ?? ISO8601DateFormatter().date(from: dateTime)
        }

        if let date = date {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            return dateFormatter.date(from: date)
        }

        return nil
    }
}

public struct GoogleAttendee: Codable, Sendable {
    public let email: String?
    public let displayName: String?
    public let responseStatus: String?

    public init(email: String?, displayName: String?, responseStatus: String?) {
        self.email = email
        self.displayName = displayName
        self.responseStatus = responseStatus
    }
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

    public init(
        id: String,
        title: String?,
        notes: String?,
        status: String?,
        due: String?,
        completed: String?,
        updated: String?,
        position: String?
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.status = status
        self.due = due
        self.completed = completed
        self.updated = updated
        self.position = position
    }

    public var isCompleted: Bool {
        status == "completed"
    }

    public var dueDate: Date? {
        guard let due = due else { return nil }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: due)
    }
}

public struct GoogleTaskList: Codable, Sendable {
    public let id: String
    public let title: String?
    public let updated: String?

    public init(id: String, title: String?, updated: String?) {
        self.id = id
        self.title = title
        self.updated = updated
    }
}

public struct GoogleTaskListResponse: Codable, Sendable {
    public let items: [GoogleTask]?
    public let nextPageToken: String?

    public init(items: [GoogleTask]?, nextPageToken: String?) {
        self.items = items
        self.nextPageToken = nextPageToken
    }
}

public struct GoogleTaskListsResponse: Codable, Sendable {
    public let items: [GoogleTaskList]?
    public let nextPageToken: String?

    public init(items: [GoogleTaskList]?, nextPageToken: String?) {
        self.items = items
        self.nextPageToken = nextPageToken
    }
}

// MARK: - Google Task Update Request

public struct GoogleTaskUpdateRequest: Codable, Sendable {
    public let status: String?
    public let completed: String?

    public init(status: String?, completed: String?) {
        self.status = status
        self.completed = completed
    }

    public static func markCompleted() -> GoogleTaskUpdateRequest {
        let formatter = ISO8601DateFormatter()
        return GoogleTaskUpdateRequest(
            status: "completed",
            completed: formatter.string(from: Date())
        )
    }

    public static func markIncomplete() -> GoogleTaskUpdateRequest {
        GoogleTaskUpdateRequest(status: "needsAction", completed: nil)
    }
}
