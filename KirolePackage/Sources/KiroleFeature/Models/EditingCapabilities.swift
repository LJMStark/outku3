import Foundation

public enum TaskDueDateEditPrecision: Sendable, Equatable {
    case unsupported
    case dateOnly
    case dateAndTime
}

public struct TaskEditCapabilities: Sendable, Equatable {
    public let isEditable: Bool
    public let supportsTitle: Bool
    public let supportsPriority: Bool
    public let dueDatePrecision: TaskDueDateEditPrecision
    public let supportsNotes: Bool
    public let guidance: String?

    public init(
        isEditable: Bool,
        supportsTitle: Bool,
        supportsPriority: Bool,
        dueDatePrecision: TaskDueDateEditPrecision,
        supportsNotes: Bool,
        guidance: String? = nil
    ) {
        self.isEditable = isEditable
        self.supportsTitle = supportsTitle
        self.supportsPriority = supportsPriority
        self.dueDatePrecision = dueDatePrecision
        self.supportsNotes = supportsNotes
        self.guidance = guidance
    }
}

public struct EventEditCapabilities: Sendable, Equatable {
    public let isEditable: Bool
    public let guidance: String?

    public init(isEditable: Bool, guidance: String? = nil) {
        self.isEditable = isEditable
        self.guidance = guidance
    }
}

extension TaskItem {
    /// Whether Kirole may change this provider item's completion state.
    ///
    /// Providers that expose a read-only calendar or list set `allowsContentModifications` to
    /// false; both App and hardware completion paths honor that flag.
    public var allowsCompletionChanges: Bool {
        externalReference?.allowsContentModifications != false
    }

    public var editCapabilities: TaskEditCapabilities {
        switch source {
        case .apple:
            guard externalReference?.allowsContentModifications != false else {
                return TaskEditCapabilities(
                    isEditable: false,
                    supportsTitle: false,
                    supportsPriority: false,
                    dueDatePrecision: .unsupported,
                    supportsNotes: false,
                    guidance: "This reminder list is read-only. Edit it in Apple Reminders."
                )
            }
            return TaskEditCapabilities(
                isEditable: true,
                supportsTitle: true,
                supportsPriority: true,
                dueDatePrecision: .dateAndTime,
                supportsNotes: true
            )
        case .google:
            return TaskEditCapabilities(
                isEditable: true,
                supportsTitle: true,
                supportsPriority: false,
                dueDatePrecision: .dateOnly,
                supportsNotes: true,
                guidance: "Google Tasks doesn't support priority, and due dates save the date only."
            )
        }
    }
}

extension CalendarEvent {
    public func editCapabilities(googleCalendarWriteAccess: Bool) -> EventEditCapabilities {
        switch source {
        case .apple:
            guard externalReference?.allowsContentModifications != false else {
                return EventEditCapabilities(
                    isEditable: false,
                    guidance: "This calendar is read-only. Edit it in the source calendar."
                )
            }
            return EventEditCapabilities(isEditable: true)
        case .google:
            guard googleCalendarWriteAccess else {
                return EventEditCapabilities(
                    isEditable: false,
                    guidance: "Google Calendar is read-only. Reconnect Google Calendar to edit."
                )
            }
            return EventEditCapabilities(isEditable: true)
        }
    }
}
