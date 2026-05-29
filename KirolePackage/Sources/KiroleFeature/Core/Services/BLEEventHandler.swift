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

        // DeviceWake (0x30) v2.3.0+: first payload byte is battery level
        if message.type == EventLogType.deviceWake.rawByte, !message.payload.isEmpty {
            service.deviceBatteryLevel = min(Int(message.payload[0]), 100)
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

        case .completeTask, .skipTask:
            // State mutation already applied via handleEventLogs (works for both live and replay)
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
                guard await BLERateLimiter.shared.allowSyncTrigger() else {
                    ErrorReporter.log(
                        .bleSecurity("Dropped refresh request due to sync throttle"),
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
                await AppState.shared.handleHardwareWake(now: eventLog.timestamp)
                // 整轮 sync 经退避节流，避免硬件频繁唤醒触发连接风暴。
                guard await BLERateLimiter.shared.allowSyncTrigger() else { return }
                await BLESyncCoordinator.shared.performSync(force: false)
            }

        case .deviceSleep:
            await AppState.shared.handleHardwareSleep(now: eventLog.timestamp)

        case .lowBattery:
            if let level = eventLog.batteryLevel {
                service.deviceBatteryLevel = level
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

        case .encoderRotateUp, .encoderRotateDown, .encoderShortPress, .encoderLongPress,
             .powerShortPress, .powerLongPress:
            // Hardware UI events — no App-side routing needed; already persisted via handleEventLogs.
            #if DEBUG
            print("[BLEEventHandler] Hardware UI event: \(eventLog.eventType.rawValue)")
            #endif
        }
    }

    // MARK: - Event-Specific Handlers

    /// EnterTaskIn: 生成 TaskInPage 并发送到设备
    private static func handleEnterTaskIn(_ eventLog: EventLog, service: BLEService) {
        guard let taskId = eventLog.taskId,
              let task = resolveTask(taskId: taskId) else {
            return
        }

        Task { @MainActor in
            let taskInPage = await DayPackGenerator.shared.generateTaskInPage(
                task: task,
                pet: AppState.shared.pet,
                userProfile: AppState.shared.userProfile
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
        await handleEventLogs(logs, service: service, isReplay: true)
    }

    /// 解析 Event Log 批次 payload:
    /// count(1B) + N 条记录，每条记录格式为 eventType(1B) + eventPayload(NB)
    static func parseEventLogBatchPayload(_ payload: Data) -> [EventLog] {
        guard !payload.isEmpty else { return [] }
        let count = Int(payload[0])
        var offset = 1
        var logs: [EventLog] = []

        for _ in 0..<count {
            guard offset < payload.count else { return [] }
            guard let recordLength = recordLength(in: payload, offset: offset) else { return [] }
            guard payload.count >= offset + recordLength else { return [] }

            let record = payload.subdata(in: offset..<(offset + recordLength))
            if let eventLog = parseEventLogRecord(from: record) {
                logs.append(eventLog)
            } else {
                return []
            }
            offset += recordLength
        }

        guard logs.count == count, offset == payload.count else { return [] }
        return logs
    }

    private static func recordLength(in payload: Data, offset: Int) -> Int? {
        guard offset < payload.count else { return nil }
        let type = payload[offset]

        switch type {
        case 0x01...0x06, 0x20, 0x31:
            return 1
        case 0x30:
            return 2  // type(1B) + BatteryLevel(1B), v2.3.0+
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
    ///
    /// State mutations here MUST work for both live single-event delivery and
    /// batch replay (offline events buffered by hardware while BLE was down).
    /// Live-only side effects (sending TaskInPage, triggering sync, etc.) live
    /// in `handleSingleEvent`'s switch — they are intentionally skipped during
    /// batch replay because those responses are stale by the time logs arrive.
    ///
    /// `isReplay: true` skips `enterTaskIn` focus session starts: App has no
    /// screen-activity data for the offline period, so focus time cannot be
    /// measured correctly. completeTask/skipTask still run to close any
    /// currently-active session.
    static func handleEventLogs(
        _ logs: [EventLog],
        service: BLEService,
        focusService: FocusSessionService = .shared,
        isReplay: Bool = false,
        lastTimestampOverride: UInt32? = nil
    ) async {
        Task {
            await persistEventLogs(logs)
        }

        let lastTimestamp: UInt32
        if let override = lastTimestampOverride {
            lastTimestamp = override
        } else {
            lastTimestamp = await localStorage.loadLastEventLogTimestamp() ?? 0
        }
        let processable = BLEEventHandler.filterAndSortForMutation(logs, since: lastTimestamp)

        for log in processable {
            await handleFocusSessionEvent(log, focusService: focusService, isReplay: isReplay)
            applyEventStateMutation(log)
        }
    }

    /// Filters to events newer than `lastTimestamp`, sorts ascending by timestamp,
    /// and removes duplicates by (eventType, taskId, second-precision timestamp).
    ///
    /// EventLog.id is regenerated on every BLE parse and cannot serve as a stable
    /// identifier, so deduplication uses the content triplet instead.
    nonisolated static func filterAndSortForMutation(
        _ logs: [EventLog],
        since lastTimestamp: UInt32
    ) -> [EventLog] {
        var seen = Set<String>()
        return logs
            .filter { UInt32($0.timestamp.timeIntervalSince1970) > lastTimestamp }
            .sorted { $0.timestamp < $1.timestamp }
            .filter { seen.insert(eventContentKey($0)).inserted }
    }

    /// A stable deduplication key derived from event content rather than EventLog.id.
    nonisolated static func eventContentKey(_ log: EventLog) -> String {
        "\(log.eventType.rawValue)|\(log.taskId ?? "")|\(UInt32(log.timestamp.timeIntervalSince1970))"
    }

    /// State changes that must apply for both live and replayed events.
    private static func applyEventStateMutation(_ log: EventLog) {
        guard log.eventType == .completeTask,
              let taskId = log.taskId,
              let task = resolveTask(taskId: taskId),
              !task.isCompleted else { return }
        AppState.shared.toggleTaskCompletion(task)
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
    private static func handleFocusSessionEvent(
        _ eventLog: EventLog,
        focusService: FocusSessionService,
        isReplay: Bool = false
    ) async {
        switch eventLog.eventType {
        case .enterTaskIn:
            // During replay we have no App-side screen data for the offline period,
            // so we cannot measure focus time. Skip to avoid a stale activeSession.
            guard !isReplay else { break }
            if let taskId = eventLog.taskId {
                let taskTitle = resolveTask(taskId: taskId)?.title ?? "Unknown Task"
                await focusService.startSession(
                    taskId: taskId,
                    taskTitle: taskTitle,
                    mode: FocusSessionService.shared.focusEnforcementMode,
                    startTime: eventLog.timestamp
                )
            }

        case .completeTask:
            if let taskId = eventLog.taskId {
                focusService.completeTask(taskId: taskId, endTime: eventLog.timestamp)
            }

        case .skipTask:
            if let taskId = eventLog.taskId {
                focusService.skipTask(taskId: taskId, endTime: eventLog.timestamp)
            }

        default:
            break
        }
    }

    nonisolated static func resolveTask(taskId: String, in tasks: [TaskItem]) -> TaskItem? {
        tasks
            .filter { $0.id == taskId }
            .max { lhs, rhs in
                let lhsRecency = lhs.remoteUpdatedAt ?? lhs.lastModified
                let rhsRecency = rhs.remoteUpdatedAt ?? rhs.lastModified
                if lhsRecency == rhsRecency {
                    return lhs.lastModified < rhs.lastModified
                }
                return lhsRecency < rhsRecency
            }
    }

    private static func resolveTask(taskId: String) -> TaskItem? {
        resolveTask(taskId: taskId, in: AppState.shared.tasks)
    }
}
