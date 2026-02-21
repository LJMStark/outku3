import Foundation

private nonisolated(unsafe) let iso8601Formatter = ISO8601DateFormatter()

public struct CalendarEvent: Identifiable, Sendable, Codable {
    public let id: String
    public var localId: UUID
    public var googleEventId: String?
    public var appleEventId: String?
    public var appleCalendarId: String?
    public var title: String
    public var startTime: Date
    public var endTime: Date
    public var source: EventSource
    public var participants: [Participant]
    public var description: String?
    public var location: String?
    public var isAllDay: Bool
    public var syncStatus: SyncStatus
    public var lastModified: Date

    public init(
        id: String = UUID().uuidString,
        localId: UUID = UUID(),
        googleEventId: String? = nil,
        appleEventId: String? = nil,
        appleCalendarId: String? = nil,
        title: String,
        startTime: Date,
        endTime: Date,
        source: EventSource = .apple,
        participants: [Participant] = [],
        description: String? = nil,
        location: String? = nil,
        isAllDay: Bool = false,
        syncStatus: SyncStatus = .synced,
        lastModified: Date = Date()
    ) {
        self.id = id
        self.localId = localId
        self.googleEventId = googleEventId
        self.appleEventId = appleEventId
        self.appleCalendarId = appleCalendarId
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.source = source
        self.participants = participants
        self.description = description
        self.location = location
        self.isAllDay = isAllDay
        self.syncStatus = syncStatus
        self.lastModified = lastModified
    }

    public var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    public var durationText: String {
        let hours = Int(duration / 3600)
        let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
        if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(minutes)m"
    }

    // 从 Google API 响应创建
    public static func from(googleEvent: GoogleCalendarEvent, source: EventSource = .google) -> CalendarEvent? {
        guard let startDate = googleEvent.start.asDate,
              let endDate = googleEvent.end.asDate else {
            return nil
        }

        let participants = googleEvent.attendees?.compactMap { attendee -> Participant? in
            guard let name = attendee.displayName ?? attendee.email else { return nil }
            return Participant(name: name)
        } ?? []

        let remoteUpdated = googleEvent.updated.flatMap { iso8601Formatter.date(from: $0) }

        return CalendarEvent(
            id: googleEvent.id,
            googleEventId: googleEvent.id,
            title: googleEvent.summary ?? "Untitled Event",
            startTime: startDate,
            endTime: endDate,
            source: source,
            participants: participants,
            description: googleEvent.description,
            location: googleEvent.location,
            isAllDay: googleEvent.start.date != nil,
            syncStatus: .synced,
            lastModified: remoteUpdated ?? Date()
        )
    }
}

public enum EventSource: String, Sendable, Codable {
    case apple = "Apple Calendar"
    case google = "Google Calendar"
    case todoist = "Todoist"

    public var iconName: String {
        switch self {
        case .apple: return "apple.logo"
        case .google: return "g.circle.fill"
        case .todoist: return "checkmark.circle.fill"
        }
    }
}

public struct Participant: Identifiable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var avatarURL: URL?
    public var initials: String

    public init(id: UUID = UUID(), name: String, avatarURL: URL? = nil) {
        self.id = id
        self.name = name
        self.avatarURL = avatarURL
        let components = name.split(separator: " ")
        if components.count >= 2 {
            self.initials = String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        } else {
            self.initials = String(name.prefix(2)).uppercased()
        }
    }
}
