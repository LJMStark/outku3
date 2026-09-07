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
    public var iCalUID: String? = nil
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
            // All-day events carry a floating `yyyy-MM-dd` with no time or zone. Build the
            // Date from components via `Calendar.current` (read fresh on every access) rather
            // than a cached `DateFormatter`, whose time zone is snapshotted at creation and
            // would resolve the wrong calendar day after the user changes time zones.
            let parts = date.split(separator: "-")
            if parts.count == 3,
               let year = Int(parts[0]),
               let month = Int(parts[1]),
               let day = Int(parts[2]) {
                var components = DateComponents()
                components.year = year
                components.month = month
                components.day = day
                if let resolved = Calendar.current.date(from: components) {
                    return resolved
                }
            }
            // Fallback for unexpected formats.
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

/// Encode-only: this is a PATCH body and is never decoded. `NetworkClient.patch` needs the
/// body to be `Encodable` alone.
///
/// Google Tasks reads an omitted key as "leave this field unchanged", while Swift's synthesized
/// encoder drops every nil via `encodeIfPresent`. A whole-task write therefore has to send
/// `notes` and `due` as explicit JSON null, or clearing them round-trips as a no-op and the
/// response hands back the value the user just removed. Partial writes must keep omitting them
/// so they never wipe a field they were not given.
public struct GoogleTaskUpdateRequest: Encodable, Sendable {
    public let title: String?
    public let notes: String?
    public let due: String?
    public let status: String?
    public let completed: String?
    /// `true` only for a whole-task write, where a nil `notes`/`due` means the user cleared it.
    private let writesClearedFields: Bool

    public init(
        title: String? = nil,
        notes: String? = nil,
        due: String? = nil,
        status: String? = nil,
        completed: String? = nil,
        writesClearedFields: Bool = false
    ) {
        self.title = title
        self.notes = notes
        self.due = due
        self.status = status
        self.completed = completed
        self.writesClearedFields = writesClearedFields
    }

    private enum CodingKeys: String, CodingKey {
        case title, notes, due, status, completed
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Never nil on a whole-task write, and absent on the completion-only writes below.
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(status, forKey: .status)
        // Google clears `completed` itself when `status` becomes needsAction, so a null here
        // would be redundant rather than corrective.
        try container.encodeIfPresent(completed, forKey: .completed)

        for (value, key) in [(notes, CodingKeys.notes), (due, CodingKeys.due)] {
            if let value {
                try container.encode(value, forKey: key)
            } else if writesClearedFields {
                try container.encodeNil(forKey: key)
            }
        }
    }

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

// MARK: - Google Calendar Event Patch Request

public struct GoogleCalendarEventPatchRequest: Codable, Sendable {
    public let summary: String?
    public let location: String?
    public let description: String?
    public let start: GoogleDateTimePatch?
    public let end: GoogleDateTimePatch?

    public init(
        summary: String? = nil,
        location: String? = nil,
        description: String? = nil,
        start: GoogleDateTimePatch? = nil,
        end: GoogleDateTimePatch? = nil
    ) {
        self.summary = summary
        self.location = location
        self.description = description
        self.start = start
        self.end = end
    }
}

public struct GoogleDateTimePatch: Codable, Sendable {
    public let dateTime: String?
    public let date: String?

    /// For timed events — sends RFC 3339 dateTime
    public static func timed(_ date: Date) -> GoogleDateTimePatch {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return GoogleDateTimePatch(dateTime: formatter.string(from: date), date: nil)
    }

    /// For all-day events — sends date-only string (Google Calendar API requirement)
    public static func allDay(_ date: Date) -> GoogleDateTimePatch {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return GoogleDateTimePatch(dateTime: nil, date: formatter.string(from: date))
    }

    private init(dateTime: String?, date: String?) {
        self.dateTime = dateTime
        self.date = date
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
