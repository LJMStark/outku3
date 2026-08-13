import Foundation

public struct Integration: Identifiable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var iconName: String
    public var isConnected: Bool
    public var type: IntegrationType

    public init(id: UUID = UUID(), name: String, iconName: String, isConnected: Bool = false, type: IntegrationType) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.isConnected = isConnected
        self.type = type
    }
}

public enum IntegrationType: String, Sendable, Codable, CaseIterable {
    case googleCalendar = "Google Calendar"
    case outlookCalendar = "Outlook Calendar"
    case appleCalendar = "Apple Calendar"
    case appleReminders = "Apple Reminders"
    case googleTasks = "Google Tasks"
    case microsoftToDo = "Microsoft To Do"
    case todoist = "Todoist"
    case tickTick = "TickTick"
    case notion = "Notion"
    case taskade = "Taskade"
    case caldav = "CalDAV"
    case icalWebcal = "iCal/WebCal"

    public var isSupported: Bool {
        true
    }

    /// Runtime release gates keep providers hidden until their external OAuth deployment and
    /// real-account acceptance checks have passed.
    public var isAvailable: Bool {
        switch self {
        case .outlookCalendar, .microsoftToDo: AppSecrets.microsoftOAuthEnabled
        case .todoist: AppSecrets.todoistOAuthEnabled
        case .tickTick: AppSecrets.tickTickOAuthEnabled
        default: true
        }
    }

    public var connectionMode: IntegrationConnectionMode {
        switch self {
        case .caldav, .icalWebcal:
            return .appleCalendarMediated
        default:
            return .direct
        }
    }

    public var iconName: String {
        switch self {
        case .googleCalendar: return "g.circle.fill"
        case .googleTasks: return "checkmark.circle.fill"
        case .appleCalendar: return "calendar"
        case .appleReminders: return "checklist"
        case .outlookCalendar: return "calendar.badge.clock"
        case .microsoftToDo: return "checkmark.circle"
        case .todoist: return "checklist.checked"
        case .tickTick: return "checkmark.circle"
        case .notion: return "doc.text"
        case .taskade: return "list.bullet.rectangle"
        case .caldav: return "calendar"
        case .icalWebcal: return "calendar"
        }
    }

    public var isExperimental: Bool {
        self == .notion || self == .taskade
    }

    public static var displayOrder: [IntegrationType] {
        [.googleCalendar, .outlookCalendar, .appleCalendar, .appleReminders,
         .googleTasks, .microsoftToDo, .todoist, .tickTick, .notion, .taskade, .caldav, .icalWebcal]
    }
}

public enum IntegrationConnectionMode: String, Sendable, Codable {
    case direct
    case appleCalendarMediated
}
