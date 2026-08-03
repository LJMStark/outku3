import Foundation

public enum TaskDueDateEditPrecision: Sendable, Equatable {
    case unsupported
    case dateOnly
    case dateAndTime
}

public struct TaskEditingContext: Sendable, Equatable {
    public let isDeviceConnected: Bool
    public let activeFocusTaskID: String?

    public init(isDeviceConnected: Bool, activeFocusTaskID: String?) {
        self.isDeviceConnected = isDeviceConnected
        self.activeFocusTaskID = activeFocusTaskID
    }

    public func locksEditing(of taskID: String) -> Bool {
        isDeviceConnected && activeFocusTaskID == taskID
    }
}

public enum TaskEditingError: LocalizedError, Sendable, Equatable {
    case activeOnConnectedDevice

    public var errorDescription: String? {
        switch self {
        case .activeOnConnectedDevice:
            return "This task is active on your Kirole device. End focus or disconnect the device before editing it."
        }
    }
}

public struct TaskEditCapabilities: Sendable, Equatable {
    public let isEditable: Bool
    public let isFocusLocked: Bool
    public let supportsTitle: Bool
    public let supportsPriority: Bool
    public let dueDatePrecision: TaskDueDateEditPrecision
    public let supportsNotes: Bool
    public let guidance: String?

    public init(
        isEditable: Bool,
        isFocusLocked: Bool = false,
        supportsTitle: Bool,
        supportsPriority: Bool,
        dueDatePrecision: TaskDueDateEditPrecision,
        supportsNotes: Bool,
        guidance: String? = nil
    ) {
        self.isEditable = isEditable
        self.isFocusLocked = isFocusLocked
        self.supportsTitle = supportsTitle
        self.supportsPriority = supportsPriority
        self.dueDatePrecision = dueDatePrecision
        self.supportsNotes = supportsNotes
        self.guidance = guidance
    }

    public var accessibilityStatus: String {
        if isFocusLocked {
            return "Editing locked. \(guidance ?? "End focus or disconnect the device before editing this task.")"
        }

        if isEditable {
            let status = "Editing unlocked. You can edit this task."
            return guidance.map { "\(status) \($0)" } ?? status
        }

        let status = "Editing unavailable."
        return guidance.map { "\(status) \($0)" } ?? status
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
    public var editCapabilities: TaskEditCapabilities {
        switch source {
        case .apple:
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
        case .notion:
            return TaskEditCapabilities(
                isEditable: false,
                supportsTitle: false,
                supportsPriority: false,
                dueDatePrecision: .unsupported,
                supportsNotes: false,
                guidance: "Notion tasks are read-only in Kirole. Edit them in Notion."
            )
        case .taskade:
            return TaskEditCapabilities(
                isEditable: false,
                supportsTitle: false,
                supportsPriority: false,
                dueDatePrecision: .unsupported,
                supportsNotes: false,
                guidance: "Taskade tasks are read-only in Kirole. Edit them in Taskade."
            )
        case .todoist:
            return TaskEditCapabilities(
                isEditable: false,
                supportsTitle: false,
                supportsPriority: false,
                dueDatePrecision: .unsupported,
                supportsNotes: false,
                guidance: "Writing back to Todoist isn't supported yet. Edit it in Todoist."
            )
        }
    }

    public func editCapabilities(in context: TaskEditingContext) -> TaskEditCapabilities {
        let sourceCapabilities = editCapabilities
        guard sourceCapabilities.isEditable else {
            return sourceCapabilities
        }
        guard context.locksEditing(of: id) else {
            return sourceCapabilities
        }
        return TaskEditCapabilities(
            isEditable: false,
            isFocusLocked: true,
            supportsTitle: sourceCapabilities.supportsTitle,
            supportsPriority: sourceCapabilities.supportsPriority,
            dueDatePrecision: sourceCapabilities.dueDatePrecision,
            supportsNotes: sourceCapabilities.supportsNotes,
            guidance: TaskEditingError.activeOnConnectedDevice.errorDescription
        )
    }
}

extension CalendarEvent {
    public func editCapabilities(googleCalendarWriteAccess: Bool) -> EventEditCapabilities {
        switch source {
        case .apple:
            return EventEditCapabilities(isEditable: true)
        case .google:
            guard googleCalendarWriteAccess else {
                return EventEditCapabilities(
                    isEditable: false,
                    guidance: "Google Calendar is read-only. Reconnect Google Calendar to edit."
                )
            }
            return EventEditCapabilities(isEditable: true)
        case .todoist, .notion, .taskade:
            return EventEditCapabilities(
                isEditable: false,
                guidance: "Edit this event in \(source.rawValue) for now."
            )
        }
    }
}
