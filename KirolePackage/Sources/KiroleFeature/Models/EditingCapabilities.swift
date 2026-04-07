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
                guidance: "Google Tasks 不支持优先级，截止时间只会保存日期。"
            )
        case .notion:
            return TaskEditCapabilities(
                isEditable: false,
                supportsTitle: false,
                supportsPriority: false,
                dueDatePrecision: .unsupported,
                supportsNotes: false,
                guidance: "Notion 任务当前在 Kirole 中为只读，请在 Notion 中编辑。"
            )
        case .taskade:
            return TaskEditCapabilities(
                isEditable: false,
                supportsTitle: false,
                supportsPriority: false,
                dueDatePrecision: .unsupported,
                supportsNotes: false,
                guidance: "Taskade 任务当前在 Kirole 中为只读，请在 Taskade 中编辑。"
            )
        case .todoist:
            return TaskEditCapabilities(
                isEditable: false,
                supportsTitle: false,
                supportsPriority: false,
                dueDatePrecision: .unsupported,
                supportsNotes: false,
                guidance: "当前版本暂不支持从 Kirole 回写 Todoist，请在原平台中编辑。"
            )
        }
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
                    guidance: "Google Calendar 当前只有读取权限，请重新连接 Google Calendar 后再编辑。"
                )
            }
            return EventEditCapabilities(isEditable: true)
        case .todoist, .notion, .taskade:
            return EventEditCapabilities(
                isEditable: false,
                guidance: "当前版本请在 \(source.rawValue) 中编辑该日程。"
            )
        }
    }
}
