import Foundation

// MARK: - BLE Event Handler

/// BLE 事件处理器，负责解析和处理从 E-ink 设备接收的事件
@MainActor
public enum BLEEventHandler {

    private static let localStorage = LocalStorage.shared
    struct EventProcessingResult {
        let logs: [EventLog]
        let taskOperationReceipts: [TaskOperationReceipt]
        let didStartFocusSession: Bool
        let didFailReplay: Bool
    }

    // MARK: - Payload Handling

    /// 处理接收到的 BLE 消息
    static func handleReceivedPayload(
        _ message: BLEReceivedMessage,
        service: BLEService,
        wifiDebugCoordinator: BLEWiFiDebugCoordinator = .shared,
        wifiAvatarSessionCoordinator: WiFiAvatarSessionCoordinator = .shared,
        deviceWakeCoordinator: BLEDeviceWakeCoordinator = .shared
    ) async {
        // 0x19 是当前连接内的实时控制应答，不属于可离线重放的 Event Log。
        // 必须在 EventLog 解析之前截获，否则可能被误丢弃或将来撞上同字节的新事件。
        if message.type == BLEDataType.wifiDebugMode.rawValue {
            wifiDebugCoordinator.handleResponse(payload: message.payload)
            return
        }

        // 0x25 是连接内的功耗握手应答，同样不进入可离线重放的 Event Log。
        // 入站 0x25 目前在 EventLogType 里无定义，落到下面会被静默丢弃——而握手正在等它。
        if message.type == BLEDataType.devicePowerControl.rawValue {
            deviceWakeCoordinator.handleResponse(payload: message.payload)
            return
        }

        // 0x1A WiFiAvatarSession 应答同为连接内实时握手结果，不进入离线 Event Log。
        if message.type == BLEDataType.wifiAvatarSession.rawValue {
            wifiAvatarSessionCoordinator.handleResponse(payload: message.payload)
            return
        }

        // 0x22 与 Wi-Fi 调试相同，是当前连接内的业务结果，不进入可离线重放的 Event Log。
        // 必须在 0x21 批次和 EventLogType 解析之前截获；AppState 负责按 operationID
        // 丢弃迟到的旧操作结果。
        if message.type == BLEDataType.avatarControl.rawValue {
            do {
                service.handleAvatarControlResult(try AvatarControlCodec.decodeResult(message.payload))
            } catch {
                ErrorReporter.log(error, context: "BLEEventHandler.avatarControl")
            }
            return
        }

        // 0x23 commit acknowledgement is a current-connection transaction result, not an offline
        // event. Bind it to the exact version and CRC before higher layers advance their state.
        if message.type == BLEDataType.taskLibraryTransaction.rawValue {
            do {
                service.handleTaskLibraryCommitAcknowledgement(
                    try TaskLibraryCodec.decodeAcknowledgement(message.payload)
                )
            } catch {
                ErrorReporter.log(error, context: "BLEEventHandler.taskLibraryTransaction")
            }
            return
        }

        // `0x24` is the current connection's atomic daily-content result, not an offline event.
        if message.type == BLEDataType.dailyContentTransaction.rawValue {
            do {
                service.handleDailyContentCommitAcknowledgement(
                    try DailyContentCodec.decodeAcknowledgement(message.payload)
                )
            } catch {
                ErrorReporter.log(error, context: "BLEEventHandler.dailyContentTransaction")
            }
            return
        }

        // Handle event log batch (0x21) separately -- keep existing batch logic
        if message.type == BLEDataType.eventLogBatch.rawValue {
            let succeeded = await handleEventLogBatch(message.payload, service: service)
            service.eventReplayBarrier.completeCurrentBatch(succeeded: succeeded)
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
        // BLE can deliver immediately after a cold launch. Do not answer taskNotFound from the
        // temporary empty state before local tasks have loaded.
        if requiresInitialLoadBeforeHandling(eventLog) {
            await AppState.shared.ensureInitialLoadComplete()
        }

        if eventLog.eventType == .enterTaskIn
            || eventLog.eventType == .completeTask
            || eventLog.eventType == .skipTask {
            await HardwarePagePresentationGate.shared.performPageTransaction {
                await handleFocusPageTransitionEvent(eventLog, service: service)
            }
            return
        }

        let processing = await processEventLogs([eventLog], service: service)
        await respondToLiveTaskOperations(
            processing.taskOperationReceipts,
            sender: service,
            presentationCoordinator: BLESyncCoordinator.shared
        )

        // Route to type-specific handlers
        switch eventLog.eventType {
        case .enterTaskIn, .completeTask, .skipTask:
            // Focus-page transitions return through the serialized branch above.
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
            guard eventLog.operationID != 0 else { break }
            Task { @MainActor in
                // 息屏后台链路：专注会话进行中，硬件周期性发 0x20（notify）唤醒被 iOS 挂起的 App。
                // 先在合并闸之前推一帧最新专注状态，让瓶子/段位按 30 分钟递增不被 60s 去抖饿死；
                // 整轮 sync 仍走下方 60s 合并闸。协议见 §5.7 / §8.5。
                // 专注推送自带短闸（20s，actor 原子）：0x20 触发的 0x14 回推放在下方 60s sync 合并窗
                // 之前（要按时更新瓶子/段位），故需独立限流——否则固件把 0x20 当 ~2s 心跳狂发时，每个
                // 0x20 各起 Task、可在首个 BLE 写完成前并发通过去重、无界排入写队列（codex 复审发现1）。
                if FocusSessionService.shared.activeSession != nil,
                   await BLERateLimiter.shared.allowFocusRefreshTrigger() {
                    await AppState.shared.handleFocusRefreshRequest()
                }
                // 0x20 用独立的 refresh 闸（非 deviceWake 的 10s 闸），不被频繁唤醒饿死。
                // 0x1B 业务确认已在本 Task 之外立即返回；这里的 60s 合并窗只约束附加的完整
                // DayPack 同步，不能延迟或吞掉任务清单确认。
                guard await BLERateLimiter.shared.allowRefreshTrigger() else {
                    ErrorReporter.log(
                        .sync(component: "BLE RequestRefresh", underlying: "coalesced (min 60s)"),
                        context: "BLEEventHandler.requestRefresh"
                    )
                    return
                }
                await BLESyncCoordinator.shared.performSync(force: true, trigger: .requestRefresh)
            }

        case .deviceWake:
            Task { @MainActor in
                // 记录实时上报的固件版本（v2.5.19+），并通知 OTA 协调器判定升级结果。
                if let firmware = eventLog.firmwareVersion {
                    service.deviceFirmwareVersion = firmware
                }
                BLEOTACoordinator.shared.handleDeviceWake(reportedVersion: eventLog.firmwareVersion)
                // v2.7: DeviceWake 库存不含 CustomActive，只能提示有待恢复操作；最终状态
                // 必须由本轮 sync 发 0x22 query 判定，不能在这里提交 App 身份。
                let avatarNeedsRecovery: Bool
                if let inventory = eventLog.avatarInventory {
                    avatarNeedsRecovery = await AppState.shared.reconcileCustomAvatarInventory(
                        hasImage: inventory.hasImage,
                        avatarID: inventory.avatarID,
                        byteLength: inventory.byteLength,
                        reportedCRC32: inventory.crc32
                    )
                } else {
                    avatarNeedsRecovery = false
                }
                let taskLibraryNeedsReseed: Bool
                let destinationID = service.taskListSnapshotDestinationID
                if let inventory = eventLog.taskLibraryInventory, !destinationID.isEmpty {
                    taskLibraryNeedsReseed = await BLESyncCoordinator.shared
                        .reconcileTaskLibraryInventory(
                            inventory,
                            destinationID: destinationID
                        )
                } else {
                    taskLibraryNeedsReseed = false
                }
                do {
                    try await service.syncTime()
                } catch {
                    ErrorReporter.log(
                        .sync(component: "BLE Sync Time", underlying: error.localizedDescription),
                        context: "BLEEventHandler.deviceWake"
                    )
                }
                await AppState.shared.handleHardwareWake(now: eventLog.timestamp)
                // 普通唤醒经退避节流；存在待办头像事务时强制本轮 query 恢复。
                let needsPrioritySync = avatarNeedsRecovery || taskLibraryNeedsReseed
                if !needsPrioritySync {
                    guard await BLERateLimiter.shared.allowSyncTrigger() else {
                        ErrorReporter.log(
                            .sync(component: "BLE DeviceWake", underlying: "throttled"),
                            context: "BLEEventHandler.deviceWake"
                        )
                        return
                    }
                }
                await BLESyncCoordinator.shared.performSync(
                    force: needsPrioritySync,
                    trigger: .deviceWake
                )
            }

        case .deviceSleep:
            // 设备在活链路上进入低功耗——记下来，下次要发业务数据前就知道需要先唤醒。
            BLEDeviceWakeCoordinator.shared.handleObservedSleep()
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

    private static func handleFocusPageTransitionEvent(
        _ eventLog: EventLog,
        service: BLEService
    ) async {
        if eventLog.eventType == .enterTaskIn {
            await handleEnterTaskIn(eventLog, service: service)
            return
        }

        let processing = await processEventLogs([eventLog], service: service)
        await respondToLiveTaskOperations(
            processing.taskOperationReceipts,
            sender: service,
            presentationCoordinator: BLESyncCoordinator.shared
        )
    }

    // MARK: - Event-Specific Handlers

    /// EnterTaskIn: 建立 App 专注会话。
    ///
    /// v2.16.0（Issue #29）起 **不再回发 `0x11 TaskInPage`**——设备从已提交任务库（`0x23`）本地读取
    /// 标题、详情和三阶段文案。入站 `0x10` 保留为 Device→App **唯一**的「专注已开始」信号，因此本
    /// 处理器仍必须建立会话；否则能量瓶、打断检测和 `0x14` 推送全部失效。
    private static func handleEnterTaskIn(_ eventLog: EventLog, service: BLEService) async {
        switch enterTaskInRoute(for: eventLog, tasks: AppState.shared.tasks) {
        case .recoverInteractive:
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
            do {
                try await service.sendDeviceMode(.interactive)
            } catch {
                ErrorReporter.log(
                    .sync(component: "BLE EnterTaskIn recovery", underlying: error.localizedDescription),
                    context: "BLEEventHandler.handleEnterTaskIn"
                )
            }
            // Persist the received event, but explicitly forbid a focus start because no matching
            // task/page exists.
            _ = await processEventLogs(
                [eventLog],
                service: service,
                allowEnterTaskInFocusStart: false
            )
            return

        case .startFocus:
            // 没有 0x11 首屏渲染要抢，初始 `0x14 FocusStatus` 立即下发——否则设备的第一次
            // 能量瓶/阶段更新要等到推送循环的下一拍。
            let processing = await processEventLogs([eventLog], service: service)
            guard processing.didStartFocusSession else {
                // 设备已经在本地进入了专注页，但 App 侧会话没能成为权威（持久化不可用 / 已有
                // 其他活跃会话）。明确把设备退回 Interactive，别留一个永远收不到有效 0x14 的专注页。
                do {
                    try await service.sendDeviceMode(.interactive)
                } catch {
                    ErrorReporter.log(
                        .sync(
                            component: "BLE EnterTaskIn focus recovery",
                            underlying: error.localizedDescription
                        ),
                        context: "BLEEventHandler.handleEnterTaskIn"
                    )
                }
                return
            }
        }
    }

    // MARK: - Event Log Parsing

    // MARK: - Event Log Batch Processing

    /// 处理 Event Log 批次数据
    private static func handleEventLogBatch(_ payload: Data, service: BLEService) async -> Bool {
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
            // A single zero count byte is the protocol's valid empty batch and still closes the
            // reconnect replay window. Missing or malformed bodies fail closed.
            return payload == Data([0])
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
        if logs.contains(where: { $0.eventType == .completeTask || $0.eventType == .skipTask }) {
            await AppState.shared.ensureInitialLoadComplete()
        }
        let hasFocusPageTransition = logs.contains {
            $0.eventType == .completeTask || $0.eventType == .skipTask
        }
        if hasFocusPageTransition {
            var succeeded = false
            await HardwarePagePresentationGate.shared.performPageTransaction {
                succeeded = await processAndRespondToReplayedEvents(logs, service: service)
            }
            return succeeded
        } else {
            return await processAndRespondToReplayedEvents(logs, service: service)
        }
    }

    private static func processAndRespondToReplayedEvents(
        _ logs: [EventLog],
        service: BLEService
    ) async -> Bool {
        let processing = await processEventLogs(logs, service: service, isReplay: true)
        // Replay deliberately skips stale live-only presentation work. There is no live TaskIn
        // page to commit after reconnect, so preserve record order and acknowledge each operation
        // directly as required by the offline recovery protocol.
        let outcome = await respondToReplayedTaskOperations(
            processing.taskOperationReceipts,
            sender: service,
            versionProvider: LocalStorage.shared
        )
        return !processing.didFailReplay && outcome == .sent
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
    @discardableResult
    static func handleEventLogs(
        _ logs: [EventLog],
        service: BLEService,
        focusService: FocusSessionService = .shared,
        isReplay: Bool = false,
        lastTimestampOverride: UInt32? = nil,
        tasksOverride: [TaskItem]? = nil,
        persistLogs: Bool = true,
        operationLedger: TaskOperationLedger = .shared,
        deviceIDOverride: String? = nil,
        appState: AppState = .shared,
        hardwareTaskPersistence: (any HardwareTaskStatePersisting)? = nil
    ) async -> [EventLog] {
        await processEventLogs(
            logs,
            service: service,
            focusService: focusService,
            isReplay: isReplay,
            lastTimestampOverride: lastTimestampOverride,
            tasksOverride: tasksOverride,
            persistLogs: persistLogs,
            operationLedger: operationLedger,
            deviceIDOverride: deviceIDOverride,
            appState: appState,
            hardwareTaskPersistence: hardwareTaskPersistence
        ).logs
    }

    static func processEventLogs(
        _ logs: [EventLog],
        service: BLEService?,
        focusService: FocusSessionService = .shared,
        isReplay: Bool = false,
        lastTimestampOverride: UInt32? = nil,
        tasksOverride: [TaskItem]? = nil,
        persistLogs: Bool = true,
        operationLedger: TaskOperationLedger = .shared,
        deviceIDOverride: String? = nil,
        appState: AppState = .shared,
        hardwareTaskPersistence: (any HardwareTaskStatePersisting)? = nil,
        nowProvider: @MainActor () -> Date = { Date() },
        allowEnterTaskInFocusStart: Bool = true
    ) async -> EventProcessingResult {
        let processable: [EventLog]
        if isReplay {
            // 0x21 重放批次：按高水位去重过滤，防离线积压事件被重复应用。
            let lastTimestamp: UInt32
            if let override = lastTimestampOverride {
                lastTimestamp = override
            } else {
                lastTimestamp = await localStorage.loadLastEventLogTimestamp() ?? 0
            }
            // Versioned task operations use the durable OperationID ledger, not the second-level
            // timestamp watermark. Otherwise a lost 0x1B followed by offline-ring replay at an
            // already-advanced timestamp would be filtered forever and could never be re-ACKed.
            processable = BLEEventHandler.deduplicatePreservingInputOrder(
                logs.filter {
                    Self.isVersionedTaskOperation($0)
                        || UInt32($0.timestamp.timeIntervalSince1970) > lastTimestamp
                }
            )
        } else {
            // 实时单事件路径不按高水位过滤：completeTask 自带 !isCompleted 幂等，
            // 同一秒内到达的后续事件（如旋钮选中后紧接短按完成）不能因秒级水位被误丢。
            processable = BLEEventHandler.sortAndDedup(logs)
        }

        let deviceID = deviceIDOverride
            ?? service?.connectedDeviceID?.uuidString
            ?? service?.lastKnownDeviceID?.uuidString
            ?? "unidentified-device"
        var receipts: [TaskOperationReceipt] = []
        var processedLogs: [EventLog] = []
        var didStartFocusSession = false
        var didFailReplay = false
        for log in processable {
            // Versioned Complete/Skip keep the raw wire task ID (often a bounded h-… hash) through
            // the OperationID ledger so a lost 0x1B ACK can still match after the task row is gone.
            // Canonical provider IDs are resolved only inside the domain mutation path.
            if let plannedReceipt = plannedTaskOperationReceipt(
                log,
                tasks: tasksOverride ?? appState.tasks
            ) {
                let receipt = await BLETaskOperationProcessor.process(
                    log,
                    plannedReceipt: plannedReceipt,
                    deviceID: deviceID,
                    focusService: focusService,
                    isReplay: isReplay,
                    operationLedger: operationLedger,
                    appState: appState,
                    hardwareTaskPersistence: hardwareTaskPersistence,
                    receivedAt: nowProvider()
                )
                processedLogs.append(log)
                receipts.append(receipt)
                if isReplay, receipt.result == .internalError {
                    // The device outbox is an ordered command stream. Continuing after a failed
                    // durable mutation could let a later operation overwrite its crash marker or
                    // receive an ACK before the failed prefix is safe to clear.
                    didFailReplay = true
                    break
                }
                continue
            }

            // Hardware echoes the bounded ASCII ID advertised by DayPack/TaskInPage/0x1B. Resolve
            // it once at the focus boundary so focus history retains the provider's original task
            // ID instead of the wire hash.
            let resolvedLog = resolvingTaskIdentifier(
                in: log,
                tasks: tasksOverride ?? appState.tasks
            )
            processedLogs.append(log)
            let focusTransitionApplied = await handleFocusSessionEvent(
                resolvedLog,
                focusService: focusService,
                isReplay: isReplay,
                tasksOverride: tasksOverride,
                allowEnterTaskInStart: allowEnterTaskInFocusStart
            )
            if resolvedLog.eventType == .enterTaskIn, focusTransitionApplied {
                didStartFocusSession = true
            }
            if let receipt = refreshReceipt(resolvedLog) {
                receipts.append(receipt)
            }
            applyReminderInteractionCooldown(resolvedLog)
        }

        // Persist only the prefix that actually ran. In particular, a replay failure must not
        // advance the watermark across later device outbox records that were neither executed nor
        // acknowledged. Persistence remains off the state-mutation critical path.
        if persistLogs {
            let logsToPersist = isReplay ? processedLogs : logs
            Task {
                await persistEventLogs(logsToPersist, advancesReplayWatermark: isReplay)
            }
        }

        return EventProcessingResult(
            logs: isReplay ? processedLogs : processable,
            taskOperationReceipts: receipts,
            didStartFocusSession: didStartFocusSession,
            didFailReplay: didFailReplay
        )
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

    /// A firmware EventLogBatch is an ordered command stream. RTC timestamps are data, not an
    /// ordering key: sorting them can acknowledge a later pending operation first and change focus
    /// completion semantics. Preserve wire order while still dropping exact duplicate records.
    nonisolated static func deduplicatePreservingInputOrder(_ logs: [EventLog]) -> [EventLog] {
        var seen = Set<String>()
        return logs.filter { seen.insert(eventContentKey($0)).inserted }
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
        if let operationID = log.operationID,
           TaskListSnapshotAction(eventType: log.eventType) != nil {
            return "\(log.eventType.rawValue)|operation=\(operationID)|task=\(log.taskId ?? "")|timestamp=\(UInt32(log.timestamp.timeIntervalSince1970))"
        }
        return "\(log.eventType.rawValue)|\(log.taskId ?? "")|\(UInt32(log.timestamp.timeIntervalSince1970))"
    }

    private nonisolated static func isVersionedTaskOperation(_ log: EventLog) -> Bool {
        log.operationID != nil && (log.eventType == .completeTask || log.eventType == .skipTask)
    }

    static func plannedTaskOperationReceipt(
        _ log: EventLog,
        tasks: [TaskItem] = AppState.shared.tasks
    ) -> TaskOperationReceipt? {
        guard let action = TaskListSnapshotAction(eventType: log.eventType),
              action == .completeTask || action == .skipTask,
              let operationID = log.operationID else {
            return nil
        }
        guard operationID != 0 else {
            return TaskOperationReceipt(action: action, operationID: 0, result: .invalidRequest)
        }

        guard let taskID = log.taskId, !taskID.isEmpty else {
            return TaskOperationReceipt(action: action, operationID: operationID, result: .invalidRequest)
        }
        guard let task = resolveTask(taskId: taskID, in: tasks), !task.pendingDeletion else {
            // Deletion wins over offline Complete/Skip: settle focus if needed, never resurrect.
            return TaskOperationReceipt(action: action, operationID: operationID, result: .taskNotFound)
        }
        let result: TaskListSnapshotResultCode = action == .completeTask && task.isCompleted
            ? .alreadyApplied
            : .applied
        return TaskOperationReceipt(action: action, operationID: operationID, result: result)
    }

    private static func refreshReceipt(_ log: EventLog) -> TaskOperationReceipt? {
        guard log.eventType == .requestRefresh, let operationID = log.operationID else { return nil }
        return TaskOperationReceipt(
            action: .requestRefresh,
            operationID: operationID,
            result: operationID == 0 ? .invalidRequest : .applied
        )
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

    /// 持久化事件日志；只有离线重放批次可以推进重放水位。
    private static func persistEventLogs(
        _ logs: [EventLog],
        advancesReplayWatermark: Bool
    ) async {
        do {
            let candidate = advancesReplayWatermark
                ? nextEventLogWatermark(current: 0, logs: logs, now: Date())
                : nil
            try await localStorage.appendEventLogs(
                logs,
                isReplay: advancesReplayWatermark,
                replayWatermarkCandidate: candidate
            )
        } catch {
            ErrorReporter.log(
                .persistence(
                    operation: "save",
                    target: "event_logs.json",
                    underlying: error.localizedDescription
                ),
                context: "BLEEventHandler.persistEventLogs"
            )
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

    @discardableResult
    private static func handleFocusSessionEvent(
        _ eventLog: EventLog,
        focusService: FocusSessionService,
        isReplay: Bool = false,
        tasksOverride: [TaskItem]? = nil,
        allowEnterTaskInStart: Bool = true,
    ) async -> Bool {
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
            guard !isReplay, allowEnterTaskInStart else { return false }
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
                let result = await focusService.startSession(
                    taskId: taskId,
                    taskTitle: task.title,
                    // 用注入实例的模式，别读 shared——测试/非 shared 调用会拿错
                    // （Codex review P2, 2026-07-04）。
                    mode: focusService.focusEnforcementMode,
                    startTime: startTime,
                    fallbackPolicy: .allowStandard,
                    sendInitialHardwareStatus: true
                )
                switch result {
                case .started, .alreadyActive:
                    return true
                case .blockedByActiveSession, .rejected, .persistenceUnavailable:
                    return false
                }
            } else {
                ErrorReporter.log(
                    .sync(
                        component: "BLE EnterTaskIn",
                        underlying: "focus start skipped — unresolvable taskId=\(eventLog.taskId ?? "nil")"
                    ),
                    context: "BLEEventHandler.handleFocusSessionEvent"
                )
            }
            return false

        case .completeTask:
            if let taskId = eventLog.taskId {
                return focusService.completeTask(taskId: taskId, endTime: sessionTimestamp)
            }
            return false

        case .skipTask:
            if let taskId = eventLog.taskId {
                return focusService.skipTask(taskId: taskId, endTime: sessionTimestamp)
            }
            return false

        default:
            return false
        }
    }

    nonisolated static func resolveTask(taskId: String, in tasks: [TaskItem]) -> TaskItem? {
        tasks
            .filter { $0.id == taskId || $0.hardwareIdentifier == taskId }
            .max { lhs, rhs in
                let lhsRecency = lhs.remoteUpdatedAt ?? lhs.lastModified
                let rhsRecency = rhs.remoteUpdatedAt ?? rhs.lastModified
                if lhsRecency == rhsRecency {
                    return lhs.lastModified < rhs.lastModified
                }
                return lhsRecency < rhsRecency
            }
    }

    static func requiresInitialLoadBeforeHandling(_ eventLog: EventLog) -> Bool {
        switch eventLog.eventType {
        case .enterTaskIn, .completeTask, .skipTask:
            return true
        case .requestRefresh:
            return eventLog.operationID != nil
        default:
            return false
        }
    }

    private nonisolated static func resolvingTaskIdentifier(
        in event: EventLog,
        tasks: [TaskItem]
    ) -> EventLog {
        guard event.eventType == .enterTaskIn
                || event.eventType == .completeTask
                || event.eventType == .skipTask,
              let taskID = event.taskId,
              let task = resolveTask(taskId: taskID, in: tasks),
              task.id != taskID else {
            return event
        }
        return EventLog(
            id: event.id,
            eventType: event.eventType,
            taskId: task.id,
            operationID: event.operationID,
            timestamp: event.timestamp,
            value: event.value,
            hasDeviceTimestamp: event.hasDeviceTimestamp,
            firmwareVersion: event.firmwareVersion,
            avatarInventory: event.avatarInventory
        )
    }

}
