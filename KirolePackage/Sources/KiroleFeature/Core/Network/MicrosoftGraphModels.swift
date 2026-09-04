import Foundation

// MARK: - Generic Graph paging

struct MicrosoftGraphPage<Item: Decodable & Sendable>: Decodable, Sendable {
    let value: [Item]
    let nextLink: String?
    let deltaLink: String?

    enum CodingKeys: String, CodingKey {
        case value
        case nextLink = "@odata.nextLink"
        case deltaLink = "@odata.deltaLink"
    }
}

struct MicrosoftGraphRemoved: Decodable, Sendable {
    let reason: String?
}

// MARK: - Graph date/time

struct MicrosoftGraphDateTimeTimeZone: Codable, Sendable, Equatable {
    let dateTime: String
    let timeZone: String

    /// Graph is requested with `outlook.timezone="UTC"`, but the value remains self-describing:
    /// defensive parsing still honors the returned zone if a tenant or stored delta response
    /// supplies another supported Windows/IANA identifier.
    var date: Date? {
        Self.parse(dateTime, graphTimeZone: timeZone)
    }

    nonisolated static func parse(_ value: String, graphTimeZone: String) -> Date? {
        let hasExplicitOffset = value.hasSuffix("Z") || value.dropFirst(10).contains("+")
            || value.dropFirst(10).contains("-")
        if hasExplicitOffset {
            let withFractionalSeconds = ISO8601DateFormatter()
            withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = withFractionalSeconds.date(from: value) {
                return date
            }

            let withoutFractionalSeconds = ISO8601DateFormatter()
            withoutFractionalSeconds.formatOptions = [.withInternetDateTime]
            return withoutFractionalSeconds.date(from: value)
        }

        guard let zone = MicrosoftGraphTimeZoneResolver.resolve(graphTimeZone) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = zone
        formatter.dateFormat = value.contains(".")
            ? "yyyy-MM-dd'T'HH:mm:ss.SSSSSSS"
            : "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: value)
    }
}

// MARK: - Outlook Calendar

struct MicrosoftOutlookEvent: Decodable, Sendable {
    let id: String
    let etag: String?
    let subject: String?
    let bodyPreview: String?
    let start: MicrosoftGraphDateTimeTimeZone?
    let end: MicrosoftGraphDateTimeTimeZone?
    let location: MicrosoftGraphLocation?
    let attendees: [MicrosoftGraphAttendee]?
    let isAllDay: Bool?
    let isCancelled: Bool?
    let lastModifiedDateTime: String?
    let removed: MicrosoftGraphRemoved?

    enum CodingKeys: String, CodingKey {
        case id
        case etag = "@odata.etag"
        case subject
        case bodyPreview
        case start
        case end
        case location
        case attendees
        case isAllDay
        case isCancelled
        case lastModifiedDateTime
        case removed = "@removed"
    }

    var lastModified: Date? {
        lastModifiedDateTime.flatMap(Self.parseISO8601)
    }

    var isDeleted: Bool {
        removed != nil || isCancelled == true
    }

    private nonisolated static func parseISO8601(_ value: String) -> Date? {
        MicrosoftGraphDateTimeTimeZone.parse(value, graphTimeZone: "UTC")
    }
}

struct MicrosoftGraphLocation: Decodable, Sendable {
    let displayName: String?
}

struct MicrosoftGraphAttendee: Decodable, Sendable {
    let emailAddress: MicrosoftGraphEmailAddress
}

struct MicrosoftGraphEmailAddress: Decodable, Sendable {
    let name: String?
    let address: String?
}

// MARK: - Microsoft To Do

struct MicrosoftTodoList: Decodable, Sendable {
    let id: String
    let displayName: String?
    let isOwner: Bool?
    let isShared: Bool?
    let wellknownListName: String?
    let removed: MicrosoftGraphRemoved?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case isOwner
        case isShared
        case wellknownListName
        case removed = "@removed"
    }
}

struct MicrosoftTodoTask: Decodable, Sendable {
    let id: String
    let etag: String?
    let title: String?
    let status: MicrosoftTodoStatus?
    let importance: MicrosoftTodoImportance?
    let body: MicrosoftTodoBody?
    let dueDateTime: MicrosoftGraphDateTimeTimeZone?
    let lastModifiedDateTime: String?
    let removed: MicrosoftGraphRemoved?

    enum CodingKeys: String, CodingKey {
        case id
        case etag = "@odata.etag"
        case title
        case status
        case importance
        case body
        case dueDateTime
        case lastModifiedDateTime
        case removed = "@removed"
    }

    var isCompleted: Bool { status == .completed }

    var lastModified: Date? {
        lastModifiedDateTime.flatMap {
            MicrosoftGraphDateTimeTimeZone.parse($0, graphTimeZone: "UTC")
        }
    }
}

struct MicrosoftTodoBody: Decodable, Sendable {
    let content: String?
    let contentType: String?
}

/// A forward-compatible Graph enum. Unknown server values survive decoding and persistence.
struct MicrosoftTodoStatus: RawRepresentable, Codable, Sendable, Hashable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let notStarted = Self(rawValue: "notStarted")
    static let inProgress = Self(rawValue: "inProgress")
    static let completed = Self(rawValue: "completed")
    static let waitingOnOthers = Self(rawValue: "waitingOnOthers")
    static let deferred = Self(rawValue: "deferred")

    static func targetStatus(
        isCompleted: Bool,
        previousRemoteStatus: String?
    ) -> MicrosoftTodoStatus {
        if isCompleted { return .completed }
        guard let previousRemoteStatus,
              previousRemoteStatus != completed.rawValue else {
            return .notStarted
        }
        return Self(rawValue: previousRemoteStatus)
    }
}

struct MicrosoftTodoImportance: RawRepresentable, Codable, Sendable, Hashable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let low = Self(rawValue: "low")
    static let normal = Self(rawValue: "normal")
    static let high = Self(rawValue: "high")
}

struct MicrosoftTodoTaskPatch: Encodable, Sendable {
    let status: String
}
