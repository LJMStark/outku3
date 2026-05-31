import Foundation

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
                // 0x20 用独立的 refresh 闸（非 deviceWake 的 10s 闸），不被频繁唤醒饿死；
                // 2s 下限防固件把 0x20 当心跳狂发导致背靠背整轮 sync。
                guard await BLERateLimiter.shared.allowRefreshTrigger() else {
                    ErrorReporter.log(
                        .sync(component: "BLE RequestRefresh", underlying: "throttled (min 2s)"),
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
                guard await BLERateLimiter.shared.allowSyncTrigger() else {
                    ErrorReporter.log(
                        .sync(component: "BLE DeviceWake", underlying: "throttled"),
                        context: "BLEEventHandler.deviceWake"
                    )
                    return
                }
                await BLESyncCoordinator.shared.performSync(force: false)
            }

        case .deviceSleep:
            await AppState.shared.handleHardwareSleep(now: eventLog.timestamp)

        case .lowBattery:
            if let level = eventLog.batteryLevel {
                service.deviceBatteryLevel = level
                await NotificationService.shared.scheduleLowBatteryNotification(level: level)
            }

        case .reminderAcknowledged, .reminderDismissed:
            // 用户在硬件上已查看/忽略提醒：联动 App 端限流冷却，避免紧接着又推一条。
            SmartReminderService.shared.registerHardwareReminderInteraction(at: eventLog.timestamp)
            #if DEBUG
            print("[BLEEventHandler] Reminder \(eventLog.eventType.rawValue) at \(eventLog.timestamp)")
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
            // 设备已进入任务详情页、正等 TaskInPage。App 找不到该 task（clean install / 任务被删 /
            // 本地数据被 reset，而硬件仍持旧 DayPack 缓存）时不能静默——设备会永久卡在详情页“像死机”。
            // 记日志 + 发 DeviceMode(.interactive) 把设备退回交互概览解卡。
            ErrorReporter.log(
                .sync(
                    component: "BLE EnterTaskIn",
                    underlying: "task not found (taskId=\(eventLog.taskId ?? "nil"), \(AppState.shared.tasks.count) local tasks) — recovering device to interactive mode"
                ),
                context: "BLEEventHandler.handleEnterTaskIn"
            )
            Task { @MainActor in
                do {
                    try await service.sendDeviceMode(.interactive)
                } catch {
                    ErrorReporter.log(
                        .sync(component: "BLE EnterTaskIn recovery", underlying: error.localizedDescription),
                        context: "BLEEventHandler.handleEnterTaskIn"
                    )
                }
            }
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
        guard !logs.isEmpty else {
            // count>0 却一条都没解析出来 = 真正的解析失败。补传是核心功能：若静默丢弃，硬件下次还发
            // 同一批，时间戳不前进 → 死循环重发、任务状态永不更新，且硬件团队完全无法排查。
            let declaredCount = payload.first.map(Int.init) ?? 0
            if declaredCount > 0 {
                let hexPrefix = payload.prefix(24).map { String(format: "%02x", $0) }.joined(separator: " ")
                ErrorReporter.log(
                    .sync(component: "BLE EventLogBatch", underlying: "parse failed: declaredCount=\(declaredCount) payloadBytes=\(payload.count) hex=[\(hexPrefix)]"),
                    context: "BLEEventHandler.handleEventLogBatch"
                )
            }
            return
        }
        // 补传路径补回电量：实时路径在 handleReceivedPayload 已处理电量，但批量重放的
        // deviceWake/lowBattery 原先会丢掉电量字节，这里取本批最新一条带电量的应用。
        //
        // best-effort：deviceWake/lowBattery 的 BLE payload 不含设备时间戳（EventLog 用 Date() 兜底），
        // 故无法用 lastEventLogTimestamp 高水位可靠区分"过期电量"。正常增量批次取到的即最新；极端下
        // 设备重发旧批次可能短暂回退，会被下一条实时 deviceWake 纠正。电量仅展示用途，可接受。
        if let latestBattery = logs
            .filter({ $0.eventType == .deviceWake || $0.eventType == .lowBattery })
            .max(by: { $0.timestamp < $1.timestamp })?
            .batteryLevel {
            service.deviceBatteryLevel = latestBattery
        }
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
        // 持久化在后台进行，不阻塞状态变更。
        //
        // 已知 advisory 竞态（codex review P2）：两个真正并发到达的批次可能都先读到同一旧高水位再过滤，
        // 重复处理重叠事件。当前 applyEventStateMutation 仅处理 completeTask 且带 !isCompleted 幂等保护，
        // 故无可见危害。完整消除需把 persistEventLogs 的“存日志”与“推进高水位”解耦后做原子 claim——
        // 留作单独带测试的改动（全局串行化会破坏共享 AppState.shared 的并行测试隔离）。
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
