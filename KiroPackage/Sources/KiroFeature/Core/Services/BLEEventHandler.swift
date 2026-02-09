import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

// MARK: - BLE Event Handler

/// BLE 事件处理器，负责解析和处理从 E-ink 设备接收的事件
@MainActor
public enum BLEEventHandler {

    private static let localStorage = LocalStorage.shared

    // MARK: - Payload Handling

    /// 处理接收到的 BLE 消息
    static func handleReceivedPayload(_ message: BLEReceivedMessage, service: BLEService) {
        // Handle event log batch (0x21) separately -- keep existing batch logic
        if message.type == BLEDataType.eventLogBatch.rawValue {
            handleEventLogBatch(message.payload, service: service)
            return
        }

        // Try to parse as an individual device event
        guard let eventLog = EventLog.fromBLEPayload(type: message.type, payload: message.payload) else {
            return
        }

        handleSingleEvent(eventLog, service: service)
    }

    // MARK: - Single Event Routing

    /// 处理单个设备事件，路由到对应的处理逻辑
    private static func handleSingleEvent(_ eventLog: EventLog, service: BLEService) {
        // Persist the event and handle focus session (existing logic)
        handleEventLogs([eventLog], service: service)

        // Route to type-specific handlers
        switch eventLog.eventType {
        case .enterTaskIn:
            handleEnterTaskIn(eventLog, service: service)

        case .completeTask:
            handleCompleteTask(eventLog)

        case .skipTask:
            // Focus session already ended via handleFocusSessionEvent; no extra action needed
            break

        case .selectedTaskChanged:
            #if DEBUG
            print("[BLEEventHandler] Selected task changed: \(eventLog.taskId ?? "unknown")")
            #endif

        case .wheelSelect:
            #if DEBUG
            print("[BLEEventHandler] Wheel select: \(eventLog.taskId ?? "unknown")")
            #endif

        case .viewEventDetail:
            #if DEBUG
            print("[BLEEventHandler] View event detail: \(eventLog.taskId ?? "unknown")")
            #endif

        case .requestRefresh:
            Task { @MainActor in
                await BLESyncCoordinator.shared.performSync(force: true)
            }

        case .deviceWake:
            Task { @MainActor in
                try? await service.syncTime()
                await BLESyncCoordinator.shared.performSync(force: false)
            }

        case .deviceSleep:
            #if DEBUG
            print("[BLEEventHandler] Device entering sleep mode")
            #endif

        case .lowBattery:
            if let level = eventLog.batteryLevel {
                postLowBatteryNotification(level: level)
            }

        default:
            break
        }
    }

    // MARK: - Event-Specific Handlers

    /// EnterTaskIn: 生成 TaskInPage 并发送到设备
    private static func handleEnterTaskIn(_ eventLog: EventLog, service: BLEService) {
        guard let taskId = eventLog.taskId,
              let task = AppState.shared.tasks.first(where: { $0.id == taskId }) else {
            return
        }

        Task { @MainActor in
            let taskInPage = await DayPackGenerator.shared.generateTaskInPage(
                task: task, pet: AppState.shared.pet
            )
            try? await service.sendTaskInPage(taskInPage)
        }
    }

    /// CompleteTask: 标记任务为已完成
    private static func handleCompleteTask(_ eventLog: EventLog) {
        guard let taskId = eventLog.taskId,
              let task = AppState.shared.tasks.first(where: { $0.id == taskId }),
              !task.isCompleted else {
            return
        }

        AppState.shared.toggleTaskCompletion(task)
    }

    /// 低电量本地通知
    private static func postLowBatteryNotification(level: Int) {
        #if canImport(UserNotifications)
        let content = UNMutableNotificationContent()
        content.title = "Kiro Device Low Battery"
        content.body = "Your Kiro device battery is at \(level)%. Please charge it soon."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "kiro-low-battery",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
        #endif
    }

    // MARK: - Event Log Parsing

    /// 解析 Event Log 记录 (使用新的 BLE payload 格式)
    /// data 的第一个字节为 event type，其余为 payload
    public static func parseEventLogRecord(from data: Data) -> EventLog? {
        guard !data.isEmpty else { return nil }
        let typeByte = data[0]
        let payload = data.count > 1 ? data.subdata(in: 1..<data.count) : Data()
        return EventLog.fromBLEPayload(type: typeByte, payload: payload)
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
        Task {
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
