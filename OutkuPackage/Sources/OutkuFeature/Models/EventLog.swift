import Foundation

// MARK: - Event Log

/// 从 E-ink 设备接收的事件日志
public struct EventLog: Codable, Sendable, Identifiable {
    public let id: UUID
    public let eventType: EventLogType
    public let taskId: String?
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        eventType: EventLogType,
        taskId: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.eventType = eventType
        self.taskId = taskId
        self.timestamp = timestamp
    }
}

// MARK: - Event Log Type

/// 设备事件类型
public enum EventLogType: String, Codable, Sendable {
    /// 进入任务详情页
    case enterTaskIn = "enter_task_in"
    /// 完成任务
    case completeTask = "complete_task"
    /// 跳过任务
    case skipTask = "skip_task"
    /// 切换选中的任务
    case selectedTaskChanged = "selected_task_changed"
    /// 滚轮选择确认 (发送选中项 ID)
    case wheelSelect = "wheel_select"
    /// 查看日程详情
    case viewEventDetail = "view_event_detail"
    /// 请求刷新数据
    case requestRefresh = "request_refresh"
    /// 设备唤醒
    case deviceWake = "device_wake"
    /// 设备休眠
    case deviceSleep = "device_sleep"
    /// 低电量通知
    case lowBattery = "low_battery"

    public var rawByte: UInt8 {
        switch self {
        case .enterTaskIn: return 0x10
        case .completeTask: return 0x11
        case .skipTask: return 0x12
        case .selectedTaskChanged: return 0x13
        case .wheelSelect: return 0x14
        case .viewEventDetail: return 0x15
        case .requestRefresh: return 0x20
        case .deviceWake: return 0x30
        case .deviceSleep: return 0x31
        case .lowBattery: return 0x40
        }
    }

    public init?(rawByte: UInt8) {
        switch rawByte {
        case 0x10: self = .enterTaskIn
        case 0x11: self = .completeTask
        case 0x12: self = .skipTask
        case 0x13: self = .selectedTaskChanged
        case 0x14: self = .wheelSelect
        case 0x15: self = .viewEventDetail
        case 0x20: self = .requestRefresh
        case 0x30: self = .deviceWake
        case 0x31: self = .deviceSleep
        case 0x40: self = .lowBattery
        default: return nil
        }
    }
}
