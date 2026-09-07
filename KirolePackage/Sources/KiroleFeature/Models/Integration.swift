import Foundation

public struct Integration: Identifiable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var iconName: String
    /// Persisted sync preference. Apple integrations also require current full EventKit access.
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
    /// Not in `displayOrder`, so it can never be switched on from Settings. It exists because
    /// `MicrosoftSyncEngine` shares one MSAL account and one state store across both Microsoft
    /// surfaces; `AppState.syncMicrosoftData()` always passes `includeTodo: false`.
    case microsoftToDo = "Microsoft To Do"

    /// Runtime release gate. Outlook Calendar stays hidden until the Azure registration and
    /// real-account acceptance behind `MICROSOFT_OAUTH_ENABLED` have passed — a client ID alone
    /// still fails every connect attempt.
    public var isAvailable: Bool {
        switch self {
        case .outlookCalendar, .microsoftToDo: AppSecrets.microsoftOAuthEnabled
        default: true
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
        }
    }

    /// Every type the app knows how to connect. `microsoftToDo` is deliberately absent — see the
    /// case comment.
    public static var displayOrder: [IntegrationType] {
        [.googleCalendar, .googleTasks, .outlookCalendar, .appleCalendar, .appleReminders]
    }

    /// Customer Settings only lists providers that passed their release gate. A gated source stays
    /// out of the list entirely instead of showing a "Coming Soon" row.
    public static var availableDisplayOrder: [IntegrationType] {
        displayOrder.filter(\.isAvailable)
    }
}
