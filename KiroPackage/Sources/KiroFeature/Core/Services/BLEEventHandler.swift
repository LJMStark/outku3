import Foundation

// MARK: - BLE Event Handler

/// BLE 事件处理器，负责解析和处理从 E-ink 设备接收的事件
@MainActor
public enum BLEEventHandler {

    private static let localStorage = LocalStorage.shared

    // MARK: - Payload Handling

    /// 处理接收到的 BLE 消息
    static func handleReceivedPayload(_ message: BLEReceivedMessage, service: BLEService) {
        guard let dataType = BLEDataType(rawValue: message.type) else { return }

        switch dataType {
        case .eventLogBatch:
            handleEventLogBatch(message.payload, service: service)
        default:
            break
        }
    }

    // MARK: - Event Log Parsing

    /// 解析 Event Log 记录
    public static func parseEventLogRecord(from data: Data) -> EventLog? {
        EventLog.parseRecord(from: data) ?? parseLegacyEventLog(from: data)
    }

    /// 解析旧版 Event Log 格式
    private static func parseLegacyEventLog(from data: Data) -> EventLog? {
        guard data.count >= 2 else { return nil }

        let eventTypeByte = data[0]
        guard let eventType = EventLogType(rawByte: eventTypeByte) else { return nil }

        var taskId: String?
        var timestamp: Date = Date()

        let taskIdLength = Int(data[1])
        if data.count >= 2 + taskIdLength {
            let taskIdData = data.subdata(in: 2..<(2 + taskIdLength))
            taskId = String(data: taskIdData, encoding: .utf8)

            let timestampOffset = 2 + taskIdLength
            if data.count >= timestampOffset + 4 {
                let timestampData = data.subdata(in: timestampOffset..<(timestampOffset + 4))
                let timestampInt = timestampData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                timestamp = Date(timeIntervalSince1970: TimeInterval(timestampInt))
            }
        }

        return EventLog(
            eventType: eventType,
            taskId: taskId,
            timestamp: timestamp,
            value: 0
        )
    }

    // MARK: - Event Log Batch Processing

    /// 处理 Event Log 批次数据
    private static func handleEventLogBatch(_ payload: Data, service: BLEService) {
        guard payload.count >= 1 else { return }
        let count = Int(payload[0])
        var offset = 1
        var logs: [EventLog] = []

        for _ in 0..<count {
            guard payload.count >= offset + 7 else { break }
            let record = payload.subdata(in: offset..<(offset + 7))
            if let eventLog = parseEventLogRecord(from: record) {
                logs.append(eventLog)
            }
            offset += 7
        }

        guard !logs.isEmpty else { return }

        handleEventLogs(logs, service: service)
    }

    // MARK: - Event Log Handling

    /// 处理接收到的事件日志
    static func handleEventLogs(_ logs: [EventLog], service: BLEService) {
        Task { @MainActor in
            await persistEventLogs(logs)
        }

        for log in logs {
            handleFocusSessionEvent(log)
            service.onEventLogReceived?(log)
        }
    }

    /// 持久化事件日志
    private static func persistEventLogs(_ logs: [EventLog]) async {
        let lastTimestamp = await localStorage.loadLastEventLogTimestamp() ?? 0
        let filtered = logs.filter { UInt32($0.timestamp.timeIntervalSince1970) > lastTimestamp }
        guard !filtered.isEmpty else { return }

        let existing = (try? await localStorage.loadEventLogs()) ?? []
        let merged = Array((existing + filtered).suffix(1000))
        try? await localStorage.saveEventLogs(merged)

        let maxTimestamp = filtered
            .map { UInt32($0.timestamp.timeIntervalSince1970) }
            .max() ?? lastTimestamp
        await localStorage.saveLastEventLogTimestamp(maxTimestamp)
    }

    // MARK: - Focus Session Events

    /// 处理专注会话相关事件
    private static func handleFocusSessionEvent(_ eventLog: EventLog) {
        let focusService = FocusSessionService.shared

        switch eventLog.eventType {
        case .enterTaskIn:
            if let taskId = eventLog.taskId {
                let taskTitle = AppState.shared.tasks.first { $0.id == taskId }?.title ?? "Unknown Task"
                focusService.startSession(taskId: taskId, taskTitle: taskTitle)
            }

        case .completeTask:
            if let taskId = eventLog.taskId {
                focusService.completeTask(taskId: taskId)
            }

        case .skipTask:
            if let taskId = eventLog.taskId {
                focusService.skipTask(taskId: taskId)
            }

        default:
            break
        }
    }
}
