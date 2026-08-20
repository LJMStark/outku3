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
    case appleCalendar = "Apple Calendar"
    case appleReminders = "Apple Reminders"
    case googleTasks = "Google Tasks"

    public var iconName: String {
        switch self {
        case .googleCalendar: return "g.circle.fill"
        case .googleTasks: return "checkmark.circle.fill"
        case .appleCalendar: return "calendar"
        case .appleReminders: return "checklist"
        }
    }

    public static var displayOrder: [IntegrationType] {
        [.googleCalendar, .appleCalendar, .appleReminders, .googleTasks]
    }
}
