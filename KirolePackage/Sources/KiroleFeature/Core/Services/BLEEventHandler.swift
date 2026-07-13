import Foundation

// MARK: - BLE Event Handler

/// BLE 事件处理器，负责解析和处理从 E-ink 设备接收的事件
@MainActor
public enum BLEEventHandler {

    private static let localStorage = LocalStorage.shared

    // MARK: - Payload Handling

    /// 处理接收到的 BLE 消息
    static func handleReceivedPayload(
        _ message: BLEReceivedMessage,
        service: BLEService,
        wifiDebugCoordinator: BLEWiFiDebugCoordinator = .shared
    ) async {
        // 0x19 是当前连接内的实时控制应答，不属于可离线重放的 Event Log。
        // 必须在 EventLog 解析之前截获，否则可能被误丢弃或将来撞上同字节的新事件。
        if message.type == BLEDataType.wifiDebugMode.rawValue {
            wifiDebugCoordinator.handleResponse(payload: message.payload)
            return
        }

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
                // 息屏后台链路：专注会话进行中，硬件周期性发 0x20（notify）唤醒被 iOS 挂起的 App。
                // 先在合并闸之前推一帧最新专注状态，让瓶子/段位按 30 分钟递增不被 60s 去抖饿死；
                // 整轮 sync 仍走下方 60s 合并闸。协议见 §5.7 / §8.5。
                if FocusSessionService.shared.activeSession != nil {
                    await AppState.shared.handleFocusRefreshRequest()
                }
                // 0x20 用独立的 refresh 闸（非 deviceWake 的 10s 闸），不被频繁唤醒饿死。
                // 联调期固件把 0x20 当 ~2s 心跳狂发；refresh 闸用 60s 合并窗把整轮 sync 去抖为
                // 每分钟最多一次——既挡住心跳刷屏，又保留用户物理刷新（固件停止心跳后，一次按键
                // 即时触发）。根因在固件侧（0x20 不应心跳化），此为 App 侧临时兜底，见协议 §8.5。
                guard await BLERateLimiter.shared.allowRefreshTrigger() else {
                    ErrorReporter.log(
                        .sync(component: "BLE RequestRefresh", underlying: "coalesced (min 60s)"),
                        context: "BLEEventHandler.requestRefresh"
                    )
                    return
                }
                await BLESyncCoordinator.shared.performSync(force: true)
            }

        case .deviceWake:
            Task { @MainActor in
                // 记录实时上报的固件版本（v2.5.19+），并通知 OTA 协调器判定升级结果。
                if let firmware = eventLog.firmwareVersion {
                    service.deviceFirmwareVersion = firmware
                }
                BLEOTACoordinator.shared.handleDeviceWake(reportedVersion: eventLog.firmwareVersion)
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
            // Cooldown reset now lives in handleEventLogs (applyReminderInteractionCooldown) so it
            // fires on BOTH the live and the 0x21-batch-replay paths; this live switch only logs.
            #if DEBUG
            print("[BLEEventHandler] Reminder \(eventLog.eventType.rawValue) at \(eventLog.timestamp)")
            #endif

        case .otaResult:
            let statusCode = UInt8(clamping: eventLog.value)
            BLEOTACoordinator.shared.handleOTAResult(statusCode: statusCode)

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
            // type(1B) + BatteryLevel(1B), v2.3.0+。协议 v2.5.19 的固件版本 3 字节
            // 只存在于实时 0x30 通知，批量记录恒为 2B（§5.15）——这里不读版本。
            return 2
        case 0x18, 0x40:
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
        lastTimestampOverride: UInt32? = nil,
        tasksOverride: [TaskItem]? = nil
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

        let processable: [EventLog]
        if isReplay {
            // 0x21 重放批次：按高水位去重过滤，防离线积压事件被重复应用。
            let lastTimestamp: UInt32
            if let override = lastTimestampOverride {
                lastTimestamp = override
            } else {
                lastTimestamp = await localStorage.loadLastEventLogTimestamp() ?? 0
            }
            processable = BLEEventHandler.filterAndSortForMutation(logs, since: lastTimestamp)
        } else {
            // 实时单事件路径不按高水位过滤：completeTask 自带 !isCompleted 幂等，
            // 同一秒内到达的后续事件（如旋钮选中后紧接短按完成）不能因秒级水位被误丢。
            processable = BLEEventHandler.sortAndDedup(logs)
        }

        for log in processable {
            await handleFocusSessionEvent(log, focusService: focusService, isReplay: isReplay, tasksOverride: tasksOverride)
            applyEventStateMutation(log, isReplay: isReplay)
            applyReminderInteractionCooldown(log)
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
        sortAndDedup(logs.filter { UInt32($0.timestamp.timeIntervalSince1970) > lastTimestamp })
    }

    /// Sorts ascending by timestamp and removes content-key duplicates WITHOUT applying any
    /// high-watermark filter. Used by the live single-event path, where every freshly delivered
    /// event must be processed (the watermark exists only to dedup 0x21 replay batches).
    nonisolated static func sortAndDedup(_ logs: [EventLog]) -> [EventLog] {
        var seen = Set<String>()
        return logs
            .sorted { $0.timestamp < $1.timestamp }
            .filter { seen.insert(eventContentKey($0)).inserted }
    }

    /// 允许的设备时间戳未来向偏移上限（秒）。超过 now + 此值的时间戳视为固件 RTC 错乱，
    /// 不允许推进高水位，避免一条异常未来时间戳（如 0xFFFFFFFE）把补传 since 永久顶死。
    nonisolated static let maxFutureTimestampSkew: UInt32 = 48 * 60 * 60

    /// 计算下一个事件高水位（= 0x20 补传请求的 since + 0x21 重放去重基线）。
    ///
    /// 只有同时满足三个条件的事件才能推进：携带真实设备时间戳（`hasDeviceTimestamp`）、
    /// 未超过 `now + maxFutureTimestampSkew`、严格大于 `current`。返回 nil 表示本批不推进
    /// （例如整批都是 deviceWake/lowBattery 等用 App 端 `Date()` 兜底的事件）。
    ///
    /// 这是补传链路的关键防线：若让无设备时间戳的兜底事件推进水位，重连时先到的 deviceWake
    /// 会把 since 顶到“现在”，离线积压的真实 completeTask 会被固件与本地双双过滤掉。
    nonisolated static func nextEventLogWatermark(
        current: UInt32,
        logs: [EventLog],
        now: Date
    ) -> UInt32? {
        let ceiling = UInt32(now.timeIntervalSince1970) &+ maxFutureTimestampSkew
        return logs
            .filter { $0.hasDeviceTimestamp }
            .map { UInt32($0.timestamp.timeIntervalSince1970) }
            .filter { $0 > current && $0 <= ceiling }
            .max()
    }

    /// A stable deduplication key derived from event content rather than EventLog.id.
    nonisolated static func eventContentKey(_ log: EventLog) -> String {
        "\(log.eventType.rawValue)|\(log.taskId ?? "")|\(UInt32(log.timestamp.timeIntervalSince1970))"
    }

    /// State changes that must apply for both live and replayed events.
    /// Replay applies the same state mutation but suppresses feedback side
    /// effects (sound/haptic, completion haiku) via `.hardwareReplay`.
    private static func applyEventStateMutation(_ log: EventLog, isReplay: Bool) {
        guard log.eventType == .completeTask,
              let taskId = log.taskId,
              let task = resolveTask(taskId: taskId),
              !task.isCompleted else { return }
        AppState.shared.toggleTaskCompletion(task, source: isReplay ? .hardwareReplay : .user)
    }

    /// Reminder ack/dismiss must reset the SmartReminder cooldown on BOTH live and replay
    /// (offline-then-reconnect `0x21` batch) paths. If it only ran on the live switch, an
    /// offline ack/dismiss delivered later via batch replay would never restart the 30-min
    /// cooldown, so the next sync could immediately re-push a reminder the user already handled
    /// on the hardware. `registerHardwareReminderInteraction` is max-merge, so a stale replayed
    /// timestamp can't pull the cooldown backwards, and re-running on the live path is idempotent.
    private static func applyReminderInteractionCooldown(_ log: EventLog) {
        guard log.eventType == .reminderAcknowledged || log.eventType == .reminderDismissed else { return }
        SmartReminderService.shared.registerHardwareReminderInteraction(at: log.timestamp)
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

        // 高水位只由带真实设备时间戳、且不超过 now+48h 的事件推进（A1/A4）；
        // 整批都是无设备时间戳的兜底事件时返回 nil，水位保持不变。
        if let maxTimestamp = nextEventLogWatermark(current: lastTimestamp, logs: filtered, now: Date()) {
            await localStorage.saveLastEventLogTimestamp(maxTimestamp)
        }
    }

    // MARK: - Focus Session Events

    /// 处理专注会话相关事件
    /// 专注事件时间戳防未来偏移：把进入专注路径的设备时间戳夹到不晚于 `now`。一次专注会话不可能在
    /// 未来结束——若固件 RTC 错乱跳到未来（或 dev 未签名模式伪造一帧），裸用 `eventLog.timestamp` 当会话
    /// 端点会把 `[start, 未来]` 整段算成专注时长，而 energy bottle 按 minutes/30 无上限发，能凭空解锁全部
    /// 场景并污染统计。与 `nextEventLogWatermark` 的 maxFutureTimestampSkew 同philosophy，此处更严（直接夹到 now）。
    nonisolated static func focusEventTimestamp(_ raw: Date, now: Date) -> Date {
        min(raw, now)
    }

    private static func handleFocusSessionEvent(
        _ eventLog: EventLog,
        focusService: FocusSessionService,
        isReplay: Bool = false,
        tasksOverride: [TaskItem]? = nil
    ) async {
        // 设备时间戳不可信：夹到不晚于 now，防未来偏移凭空铸造专注时长 / 能量瓶（见 focusEventTimestamp）。
        let sessionTimestamp = focusEventTimestamp(eventLog.timestamp, now: Date())
        switch eventLog.eventType {
        case .enterTaskIn:
            // INTENTIONAL — do not "fix" this into a back-fill. Product requirement:
            // focus must be judged live inside the App, never reconstructed from
            // hardware timestamps. During replay there is no App-side screen-activity
            // data for the offline period, so focus time cannot be measured and we do
            // NOT fabricate it. Skipping also avoids a stale activeSession. The Inku
            // competitive review's "back-fill offline focus" suggestion was rejected
            // for this reason. (See memory: project_focus_app_authoritative.)
            guard !isReplay else { break }
            // 与 handleEnterTaskIn 的 guard 对称：任务解析失败不得开会话。联调实测（2026-07-04）：
            // 固件 EnterTaskIn payload 未按 §5.3 带 UUID 时，首字节 0x00 解析成空 taskId + 错位读出
            // 1970 时间戳——旧逻辑仍以 "Unknown Task" 开会话，0x14 推出 elapsed=65535/bottles=255
            // 怪帧。解卡帧（DeviceMode.interactive）由 handleEnterTaskIn 分支负责，这里只跳过。
            if let taskId = eventLog.taskId,
               let task = resolveTask(taskId: taskId, in: tasksOverride ?? AppState.shared.tasks) {
                // 开新会话的起始时间过去向夹取（2 小时容忍）：固件 RTC 在 Time(0x05) 同步前是
                // 远古值（1970 级），合法 UUID + 远古时间戳同样会铸造溢出时长。只夹这里、不动
                // 全局 focusEventTimestamp——补传的历史事件时间戳合法地在过去。
                let startTime = max(sessionTimestamp, Date().addingTimeInterval(-7200))
                await focusService.startSession(
                    taskId: taskId,
                    taskTitle: task.title,
                    // 用注入实例的模式，别读 shared——测试/非 shared 调用会拿错
                    // （Codex review P2, 2026-07-04）。
                    mode: focusService.focusEnforcementMode,
                    startTime: startTime
                )
            } else {
                ErrorReporter.log(
                    .sync(
                        component: "BLE EnterTaskIn",
                        underlying: "focus start skipped — unresolvable taskId=\(eventLog.taskId ?? "nil")"
                    ),
                    context: "BLEEventHandler.handleFocusSessionEvent"
                )
            }

        case .completeTask:
            if let taskId = eventLog.taskId {
                focusService.completeTask(taskId: taskId, endTime: sessionTimestamp)
            }

        case .skipTask:
            if let taskId = eventLog.taskId {
                focusService.skipTask(taskId: taskId, endTime: sessionTimestamp)
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
