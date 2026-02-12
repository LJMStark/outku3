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
}

public struct GoogleDateTime: Codable, Sendable {
    public let dateTime: String?
    public let date: String?
    public let timeZone: String?

    /// Parse to Date object
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
}

public struct GoogleCalendarListResponse: Codable, Sendable {
    public let items: [GoogleCalendarEvent]?
    public let nextPageToken: String?
    public let nextSyncToken: String?
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
