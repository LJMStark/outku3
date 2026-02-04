import Foundation

// MARK: - Event Log

/// 从 E-ink 设备接收的事件日志
public struct EventLog: Codable, Sendable, Identifiable {
    public let id: UUID
    public let eventType: EventLogType
    public let taskId: String?
    public let timestamp: Date
    public let value: Int

    public init(
        id: UUID = UUID(),
        eventType: EventLogType,
        taskId: String? = nil,
        timestamp: Date = Date(),
        value: Int = 0
    ) {
        self.id = id
        self.eventType = eventType
        self.taskId = taskId
        self.timestamp = timestamp
        self.value = value
    }
}

// MARK: - Event Log Type

/// 设备事件类型
public enum EventLogType: String, Codable, Sendable {
    /// 旋钮上旋
    case encoderRotateUp = "encoder_rotate_up"
    /// 旋钮下旋
    case encoderRotateDown = "encoder_rotate_down"
    /// 旋钮短按
    case encoderShortPress = "encoder_short_press"
    /// 旋钮长按
    case encoderLongPress = "encoder_long_press"
    /// 电源键短按
    case powerShortPress = "power_short_press"
    /// 电源键长按
    case powerLongPress = "power_long_press"
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
        case .encoderRotateUp: return 0x01
        case .encoderRotateDown: return 0x02
        case .encoderShortPress: return 0x03
        case .encoderLongPress: return 0x04
        case .powerShortPress: return 0x05
        case .powerLongPress: return 0x06
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
        case 0x01: self = .encoderRotateUp
        case 0x02: self = .encoderRotateDown
        case 0x03: self = .encoderShortPress
        case 0x04: self = .encoderLongPress
        case 0x05: self = .powerShortPress
        case 0x06: self = .powerLongPress
        case 0x10: self = .enterTaskIn
        case 0x11: self = .completeTask
        case 0x12: self = .skipTask
        case 0x13: self = .selectedTaskChanged
        case 0x14: self = .wheelSelect
        case 0x15: self = .viewEventDetail
        case 0x20: self = .requestRefresh
        case 0x07, 0x30: self = .deviceWake
        case 0x08, 0x31: self = .deviceSleep
        case 0x09, 0x40: self = .lowBattery
        default: return nil
        }
    }
}

// MARK: - Event Log Parsing

public extension EventLog {
    /// 解析硬件 Event Log 记录（eventType + timestamp + value）
    static func parseRecord(from data: Data) -> EventLog? {
        guard data.count >= 7 else { return nil }
        let typeByte = data[0]
        guard let type = EventLogType(rawByte: typeByte) else { return nil }

        let timestamp = UInt32(data[1]) << 24 | UInt32(data[2]) << 16 | UInt32(data[3]) << 8 | UInt32(data[4])
        let valueRaw = Int16(bitPattern: UInt16(data[5]) << 8 | UInt16(data[6]))

        return EventLog(
            eventType: type,
            taskId: nil,
            timestamp: Date(timeIntervalSince1970: TimeInterval(timestamp)),
            value: Int(valueRaw)
        )
    }
}
