import Foundation

public enum GoogleOAuthScope {
    public static let calendarReadOnly = "https://www.googleapis.com/auth/calendar.readonly"
    public static let calendarEvents = "https://www.googleapis.com/auth/calendar.events"
    public static let tasks = "https://www.googleapis.com/auth/tasks"
}

public enum GoogleCalendarAccessLevel: Sendable, Equatable {
    case none
    case readOnly
    case readWrite

    public static func from(grantedScopes: [String]) -> GoogleCalendarAccessLevel {
        if grantedScopes.contains(GoogleOAuthScope.calendarEvents) {
            return .readWrite
        }
        if grantedScopes.contains(GoogleOAuthScope.calendarReadOnly) {
            return .readOnly
        }
        return .none
    }

    public var canRead: Bool {
        self != .none
    }

    public var canWrite: Bool {
        self == .readWrite
    }
}
