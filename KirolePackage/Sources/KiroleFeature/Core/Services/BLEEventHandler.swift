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
    static func handleReceivedPayload(_ message: BLEReceivedMessage, service: BLEService) async {
        // Handle event log batch (0x21) separately -- keep existing batch logic
        if message.type == BLEDataType.eventLogBatch.rawValue {
            await handleEventLogBatch(message.payload, service: service)
            return
        }

        // Try to parse as an individual device event
        guard let eventLog = EventLog.fromBLEPayload(type: message.type, payload: message.payload) else {
            return
        }

        await handleSingleEvent(eventLog, service: service)
    }

    // MARK: - Single Event Routing

    /// 处理单个设备事件，路由到对应的处理逻辑
    private static func handleSingleEvent(_ eventLog: EventLog, service: BLEService) async {
        // Persist the event and handle focus session (existing logic)
        await handleEventLogs([eventLog], service: service)

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
                guard await BLERateLimiter.shared.allowRefreshRequest() else {
                    ErrorReporter.log(
                        .bleSecurity("Dropped refresh request due to rate limit"),
                        context: "BLEEventHandler.requestRefresh"
                    )
                    return
                }
                await BLESyncCoordinator.shared.performSync(force: true)
            }

        case .deviceWake:
            Task { @MainActor in
                do {
                    try await service.syncTime()
                } catch {
                    ErrorReporter.log(
                        .sync(component: "BLE Sync Time", underlying: error.localizedDescription),
                        context: "BLEEventHandler.deviceWake"
                    )
                }
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

        case .reminderAcknowledged:
            #if DEBUG
            print("[BLEEventHandler] Reminder acknowledged at \(eventLog.timestamp)")
            #endif

        case .reminderDismissed:
            #if DEBUG
            print("[BLEEventHandler] Reminder dismissed at \(eventLog.timestamp)")
            #endif

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
            do {
                try await service.sendTaskInPage(taskInPage)
            } catch {
                ErrorReporter.log(
                    .sync(component: "BLE TaskInPage", underlying: error.localizedDescription),
                    context: "BLEEventHandler.handleEnterTaskIn"
                )
            }
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
        content.title = "Kirole Device Low Battery"
        content.body = "Your Kirole device battery is at \(level)%. Please charge it soon."
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "kirole-low-battery",
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
    private static func handleEventLogBatch(_ payload: Data, service: BLEService) async {
        let logs = parseEventLogBatchPayload(payload)
        guard !logs.isEmpty else { return }
        await handleEventLogs(logs, service: service)
    }

    /// 解析 Event Log 批次 payload:
    /// count(1B) + N 条记录，每条记录格式为 eventType(1B) + eventPayload(NB)
    static func parseEventLogBatchPayload(_ payload: Data) -> [EventLog] {
        guard !payload.isEmpty else { return [] }
        let count = Int(payload[0])
        var offset = 1
        var logs: [EventLog] = []

        for _ in 0..<count {
            guard offset < payload.count else { break }
            guard let recordLength = recordLength(in: payload, offset: offset) else { break }
            guard payload.count >= offset + recordLength else { break }

            let record = payload.subdata(in: offset..<(offset + recordLength))
            if let eventLog = parseEventLogRecord(from: record) {
                logs.append(eventLog)
            }
            offset += recordLength
        }

        return logs
    }

    private static func recordLength(in payload: Data, offset: Int) -> Int? {
        guard offset < payload.count else { return nil }
        let type = payload[offset]

        switch type {
        case 0x01...0x06, 0x20, 0x30, 0x31:
            return 1
        case 0x40:
            return 2
        case 0x16, 0x17:
            return 5
        case 0x10...0x12:
            guard offset + 1 < payload.count else { return nil }
            let idLength = Int(payload[offset + 1])
            return 2 + idLength + 4
        case 0x13...0x15:
            guard offset + 1 < payload.count else { return nil }
            let idLength = Int(payload[offset + 1])
            return 2 + idLength
        default:
            return nil
        }
    }

    // MARK: - Event Log Handling

    /// 处理接收到的事件日志
    static func handleEventLogs(_ logs: [EventLog], service: BLEService) async {
        Task {
            await persistEventLogs(logs)
        }

        for log in logs {
            await handleFocusSessionEvent(log)
            service.onEventLogReceived?(log)
        }
    }

    /// 持久化事件日志
    private static func persistEventLogs(_ logs: [EventLog]) async {
        let lastTimestamp = await localStorage.loadLastEventLogTimestamp() ?? 0
        let filtered = logs.filter { UInt32($0.timestamp.timeIntervalSince1970) > lastTimestamp }
        guard !filtered.isEmpty else { return }

        do {
            let existing = try await localStorage.loadEventLogs() ?? []
            let merged = Array((existing + filtered).suffix(1000))
            try await localStorage.saveEventLogs(merged)
        } catch {
            ErrorReporter.log(
                .persistence(
                    operation: "save",
                    target: "event_logs.json",
                    underlying: error.localizedDescription
                ),
                context: "BLEEventHandler.persistEventLogs"
            )
            return
        }

        let maxTimestamp = filtered
            .map { UInt32($0.timestamp.timeIntervalSince1970) }
            .max() ?? lastTimestamp
        await localStorage.saveLastEventLogTimestamp(maxTimestamp)
    }

    // MARK: - Focus Session Events

    /// 处理专注会话相关事件
    private static func handleFocusSessionEvent(_ eventLog: EventLog) async {
        let focusService = FocusSessionService.shared

        switch eventLog.eventType {
        case .enterTaskIn:
            if let taskId = eventLog.taskId {
                let taskTitle = AppState.shared.tasks.first { $0.id == taskId }?.title ?? "Unknown Task"
                await focusService.startSession(
                    taskId: taskId,
                    taskTitle: taskTitle,
                    mode: AppState.shared.focusEnforcementMode
                )
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
