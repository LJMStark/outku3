import Foundation

// MARK: - Event Log

/// 从 E-ink 设备接收的事件日志
public struct EventLog: Codable, Sendable, Identifiable {
    public let id: UUID
    public let eventType: EventLogType
    public let taskId: String?
    public let timestamp: Date
    public let value: Int
    /// 仅当 `timestamp` 是从设备自身时钟（BLE payload 里的 4 字节时间戳）解析出来时为 true。
    /// deviceWake / lowBattery / encoder 等事件不携带设备时间戳，会用 App 端 `Date()` 兜底，此时为 false。
    /// 离线补传高水位（`lastEventLogTimestamp`）只允许由 `hasDeviceTimestamp == true` 的事件推进，
    /// 否则重连时先到的兜底事件会把补传 since 顶到“现在”，丢掉离线积压的真实事件——
    /// 见 `BLEEventHandler.nextEventLogWatermark`。
    public let hasDeviceTimestamp: Bool

    public init(
        id: UUID = UUID(),
        eventType: EventLogType,
        taskId: String? = nil,
        timestamp: Date = Date(),
        value: Int = 0,
        hasDeviceTimestamp: Bool = false
    ) {
        self.id = id
        self.eventType = eventType
        self.taskId = taskId
        self.timestamp = timestamp
        self.value = value
        self.hasDeviceTimestamp = hasDeviceTimestamp
    }

    // 向后兼容：旧 event_logs.json 没有 hasDeviceTimestamp 字段，缺失时默认 false，
    // 避免一次字段新增就让整份历史日志解码失败（与“读失败不应放大成数据丢失”一致）。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.eventType = try container.decode(EventLogType.self, forKey: .eventType)
        self.taskId = try container.decodeIfPresent(String.self, forKey: .taskId)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.value = try container.decodeIfPresent(Int.self, forKey: .value) ?? 0
        self.hasDeviceTimestamp = try container.decodeIfPresent(Bool.self, forKey: .hasDeviceTimestamp) ?? false
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
    /// 旋钮选择确认 (发送选中项 ID)
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
    /// 用户确认智能提醒（按键）
    case reminderAcknowledged = "reminder_acknowledged"
    /// 智能提醒超时自动关闭
    case reminderDismissed = "reminder_dismissed"
    /// 固件升级重启应答（0x00=成功 / 0x01=无文件 / 0x02=大小异常 / 0x03=SD卡 / 0x04=写入失败 / 0xFF=未知）
    case otaResult = "ota_result"

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
        case .reminderAcknowledged: return 0x16
        case .reminderDismissed: return 0x17
        case .otaResult: return 0x18
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
        case 0x30: self = .deviceWake
        case 0x31: self = .deviceSleep
        case 0x40: self = .lowBattery
        case 0x16: self = .reminderAcknowledged
        case 0x17: self = .reminderDismissed
        case 0x18: self = .otaResult
        default: return nil
        }
    }
}

// MARK: - Battery Level

public extension EventLog {
    /// Battery level for LowBattery / DeviceWake events (0-100).
    /// DeviceWake carries battery as its first payload byte since v2.3.0.
    var batteryLevel: Int? {
        switch eventType {
        case .lowBattery, .deviceWake:
            return value
        default:
            return nil
        }
    }
}

// MARK: - BLE Payload Parsing

public extension EventLog {
    /// Parse event payload from BLE message (after outer type+length header is stripped)
    static func fromBLEPayload(type: UInt8, payload: Data) -> EventLog? {
        guard let eventType = EventLogType(rawByte: type) else { return nil }

        switch eventType {
        case .enterTaskIn, .completeTask, .skipTask:
            return parseTaskEvent(eventType: eventType, payload: payload)

        case .selectedTaskChanged, .wheelSelect, .viewEventDetail:
            return parseIdOnlyEvent(eventType: eventType, payload: payload)

        case .lowBattery:
            let level = payload.isEmpty ? 0 : min(Int(payload[0]), 100)
            return EventLog(eventType: eventType, value: level)

        case .reminderAcknowledged, .reminderDismissed:
            return parseTimestampOnlyEvent(eventType: eventType, payload: payload)

        case .otaResult:
            let code = payload.isEmpty ? 0xFF : payload[0]
            return EventLog(eventType: eventType, value: Int(code))

        case .deviceWake:
            // v2.3.0+: first payload byte is battery level (0-100). Older/empty payloads → 0.
            let level = payload.isEmpty ? 0 : min(Int(payload[0]), 100)
            return EventLog(eventType: eventType, value: level)

        default:
            return EventLog(eventType: eventType)
        }
    }

    private static func parseTaskEvent(eventType: EventLogType, payload: Data) -> EventLog? {
        guard payload.count >= 1 else { return nil }
        let taskIdLength = Int(payload[0])
        guard payload.count >= 1 + taskIdLength else { return nil }

        let taskIdData = payload.subdata(in: 1..<(1 + taskIdLength))
        let taskId = String(data: taskIdData, encoding: .utf8)

        var timestamp = Date()
        var hasDeviceTimestamp = false
        let timestampOffset = 1 + taskIdLength
        if payload.count >= timestampOffset + 4 {
            let ts = UInt32(payload[timestampOffset]) << 24
                | UInt32(payload[timestampOffset + 1]) << 16
                | UInt32(payload[timestampOffset + 2]) << 8
                | UInt32(payload[timestampOffset + 3])
            timestamp = Date(timeIntervalSince1970: TimeInterval(ts))
            hasDeviceTimestamp = true
        }

        return EventLog(
            eventType: eventType,
            taskId: taskId,
            timestamp: timestamp,
            hasDeviceTimestamp: hasDeviceTimestamp
        )
    }

    private static func parseTimestampOnlyEvent(eventType: EventLogType, payload: Data) -> EventLog {
        guard payload.count == 4 else {
            return EventLog(eventType: eventType)
        }
        let ts = UInt32(payload[0]) << 24
            | UInt32(payload[1]) << 16
            | UInt32(payload[2]) << 8
            | UInt32(payload[3])
        return EventLog(
            eventType: eventType,
            timestamp: Date(timeIntervalSince1970: TimeInterval(ts)),
            hasDeviceTimestamp: true
        )
    }

    private static func parseIdOnlyEvent(eventType: EventLogType, payload: Data) -> EventLog? {
        guard payload.count >= 1 else {
            return EventLog(eventType: eventType)
        }
        let idLength = Int(payload[0])
        guard payload.count == 1 + idLength else {
            return EventLog(eventType: eventType)
        }

        let idData = payload.subdata(in: 1..<(1 + idLength))
        let id = String(data: idData, encoding: .utf8)

        return EventLog(eventType: eventType, taskId: id)
    }
}
