import Foundation

// MARK: - BLE Sync Coordinator

@MainActor
public final class BLESyncCoordinator {
    private struct DeferredFocusSessionEndDisplay {
        var newlyUnlocked: [String]
        var endedAt: Date
    }

    private enum OfflineSyncIntegrationError: LocalizedError {
        case missingDeviceIdentity
        case operationNotDurable(UInt32)

        var errorDescription: String? {
            switch self {
            case .missingDeviceIdentity:
                return "OfflineSync requires a connected device identity"
            case .operationNotDurable(let operationID):
                return "Offline operation \(operationID) was not durably applied"
            }
        }
    }

    public static let shared = BLESyncCoordinator()

    private let bleService = BLEService.shared
    private let dayPackGenerator = DayPackGenerator.shared
    private let localStorage = LocalStorage.shared
    private let policy = BLESyncPolicy()

    private var lastSyncSucceeded = true
    /// 上次成功发出的 Weather(0x04) 指纹（上 wire 的四个量化值）。内存态即可：重启后首轮
    /// 多发一次 ~10B 小帧，无害；不入 LocalStorage 以避开 resettable key 的测试隔离成本。
    private var lastSentWeatherFingerprint: String?
    /// In-flight 守卫：防止并发 performSync 重复发整轮（keep-alive 常驻连接后更易触发）。
    private var isSyncing = false
    /// 在途同步期间到达的请求；当前同步收尾后补跑一次。普通内容变化也不能被吞，否则旧
    /// DayPack 被判定过期后可能没有后续轮次发送最新清单。
    private var pendingSync = false
    private var pendingForceSync = false
    private var pendingHardwareWakeDate: Date?
    private var deferredFocusSessionEndDisplay: DeferredFocusSessionEndDisplay?
    /// Set only while the frozen payloads used by the current 0x25 transaction are being built.
    /// It becomes durable sync metadata only after the device returns RESULT=COMMITTED.
    private var stagedDayPackFingerprint: String?
    private var stagedTaskStateVersion: UInt64?
    private lazy var offlineSyncCoordinator = makeOfflineSyncCoordinator()
    /// Complete/Skip keeps the device on TaskIn until one final DayPack has been sent. Routine
    /// sync requests queue behind this window so no second DayPack can race the later 0x1B.
    private var taskActionPresentationCount = 0
    private let taskActionPresentationGate = BLEWriteGate()
    private var syncCompletionWaiters: [CheckedContinuation<Void, Never>] = []

    /// Connection timeout in seconds. Configurable for larger screen sizes
    /// that require longer refresh times (e.g., 7.3寸 full refresh ~12s).
    public var connectionTimeoutSeconds: TimeInterval = 30

    private init() {}

    public func nextSyncDate() async -> Date {
        let lastSync = await localStorage.loadLastBleSyncTime()
        return policy.nextSyncTime(now: Date(), lastSync: lastSync)
    }

    func handleOfflineSyncPayload(_ payload: Data) {
        offlineSyncCoordinator.handleInbound(payload: payload)
    }

    func handleOfflineSyncDisconnected() {
        offlineSyncCoordinator.handleDisconnected()
    }

    func deferFocusSessionEndHardwareDisplay(newlyUnlocked: [String], now: Date) {
        let existingUnlocks = deferredFocusSessionEndDisplay?.newlyUnlocked ?? []
        deferredFocusSessionEndDisplay = DeferredFocusSessionEndDisplay(
            newlyUnlocked: Array(Set(existingUnlocks + newlyUnlocked)).sorted(),
            endedAt: now
        )
    }

    private func flushDeferredFocusSessionEndHardwareDisplay(appState: AppState) async {
        guard let deferred = deferredFocusSessionEndDisplay else { return }
        deferredFocusSessionEndDisplay = nil
        await appState.syncFocusHardwareDisplay(session: nil, now: deferred.endedAt)
        if !deferred.newlyUnlocked.isEmpty {
            await appState.syncIdleHardwareDisplay()
        }
    }

    private func makeOfflineSyncCoordinator() -> BLEOfflineSyncCoordinator {
        BLEOfflineSyncCoordinator(
            dependencies: .init(
                synchronizeTime: { [weak self] in
                    guard let self else { throw BLEError.disconnected }
                    try await self.bleService.syncOfflineTime()
                },
                sendCommand: { [weak self] command in
                    guard let self else { throw BLEError.disconnected }
                    try await self.bleService.sendOfflineSyncCommand(command)
                },
                makeSnapshot: { [weak self] in
                    guard let self else { throw BLEError.disconnected }
                    let frozen = try await self.generateStableDayPack()
                    let snapshot = OfflineDatasetSnapshot(
                        tasks: frozen.tasks,
                        events: frozen.events,
                        dayPack: frozen.dayPack,
                        screenSize: self.bleService.hardwareScreenSize
                    )
                    self.stagedDayPackFingerprint = frozen.dayPack.stableFingerprint()
                    self.stagedTaskStateVersion = frozen.taskStateVersion
                    return snapshot
                },
                sendTaskList: { [weak self] payload in
                    guard let self else { throw BLEError.disconnected }
                    try await self.bleService.sendOfflineTaskListPayload(payload)
                },
                sendSchedule: { [weak self] payload in
                    guard let self else { throw BLEError.disconnected }
                    try await self.bleService.sendOfflineSchedulePayload(payload)
                },
                sendDayPack: { [weak self] payload in
                    guard let self else { throw BLEError.disconnected }
                    try await self.bleService.sendOfflineDayPackPayload(payload)
                },
                processOperation: { [weak self] bootSessionID, record in
                    guard let self,
                          let deviceID = self.bleService.connectedDeviceID?.uuidString else {
                        throw OfflineSyncIntegrationError.missingDeviceIdentity
                    }
                    let durable = await BLEOfflineOperationProcessor.process(
                        record,
                        deviceID: deviceID,
                        bootSessionID: bootSessionID
                    )
                    guard durable else {
                        throw OfflineSyncIntegrationError.operationNotDurable(record.operationID)
                    }
                },
                makeSyncID: {
                    UInt32.random(in: 1...UInt32.max)
                },
                makeValidUntil: {
                    let calendar = Calendar.current
                    let startOfToday = calendar.startOfDay(for: Date())
                    let startOfTomorrow = calendar.date(
                        byAdding: .day,
                        value: 1,
                        to: startOfToday
                    ) ?? Date().addingTimeInterval(24 * 60 * 60)
                    return UInt32(clamping: Int(startOfTomorrow.timeIntervalSince1970) - 1)
                }
            )
        )
    }

    private func generateStableDayPack() async throws -> (
        dayPack: DayPack,
        tasks: [TaskItem],
        events: [CalendarEvent],
        taskStateVersion: UInt64
    ) {
        let appState = AppState.shared
        for _ in 0..<3 {
            await appState.refreshSharedPetDialogueIfNeeded()
            let sourceTaskStateVersion = appState.taskStateVersion
            guard appState.currentPetDialogueTaskStateVersion == sourceTaskStateVersion else {
                continue
            }

            // Capture every input before the asynchronous generator runs. These values, not a
            // second AppState read, feed all three dataset encoders in this transaction.
            let pet = appState.pet
            let tasks = appState.tasks
            let events = appState.events
            let weather = appState.weather
            let deviceMode = appState.deviceMode
            let userProfile = appState.userProfile
            let customCompanions = appState.customCompanions
            let petDialogue = appState.currentPetDialogue
            let screenSize = bleService.hardwareScreenSize

            let dayPack = await dayPackGenerator.generateDayPack(
                pet: pet,
                tasks: tasks,
                events: events,
                weather: weather,
                deviceMode: deviceMode,
                userProfile: userProfile,
                customCompanions: customCompanions,
                screenSize: screenSize,
                petDialogue: petDialogue
            )
            guard appState.taskStateVersion == sourceTaskStateVersion else { continue }
            return (dayPack, tasks, events, sourceTaskStateVersion)
        }
        throw BLEError.staleTaskSnapshot
    }

    func performDeviceWakeSync(
        _ eventLog: EventLog,
        service: BLEService
    ) async {
        // DeviceWake must reserve the message boundary before generic event logging, inventory
        // reconciliation, or any other await can let a live 0x14/0x17/0x1B write run first.
        guard !isSyncing, taskActionPresentationCount == 0 else {
            pendingSync = true
            pendingForceSync = true
            pendingHardwareWakeDate = eventLog.timestamp
            return
        }
        isSyncing = true
        do {
            try await bleService.beginOfflineSyncWriteSession()
        } catch {
            isSyncing = false
            lastSyncSucceeded = false
            bleService.lastSyncFailed = true
            ErrorReporter.log(
                .sync(component: "BLESyncCoordinator", underlying: error.localizedDescription),
                context: "BLESyncCoordinator.acquireDeviceWakeWriteSession"
            )
            schedulePendingSyncIfPossible()
            return
        }

        if let firmware = eventLog.firmwareVersion {
            service.deviceFirmwareVersion = firmware
        }
        BLEOTACoordinator.shared.handleDeviceWake(reportedVersion: eventLog.firmwareVersion)
        if let inventory = eventLog.avatarInventory {
            _ = await AppState.shared.reconcileCustomAvatarInventory(
                hasImage: inventory.hasImage,
                avatarID: inventory.avatarID,
                byteLength: inventory.byteLength,
                reportedCRC32: inventory.crc32
            )
        }
        _ = await BLEEventHandler.processEventLogs([eventLog], service: service)
        await performSync(
            force: true,
            hardwareWakeDate: eventLog.timestamp,
            preacquiredOfflineWriteSession: true
        )
    }

    public func performSync(force: Bool = false, hardwareWakeDate: Date? = nil) async {
        await performSync(
            force: force,
            hardwareWakeDate: hardwareWakeDate,
            preacquiredOfflineWriteSession: false
        )
    }

    private func performSync(
        force: Bool,
        hardwareWakeDate: Date?,
        preacquiredOfflineWriteSession: Bool
    ) async {
        // 并发守卫：keep-alive 默认开后连接常驻，多触发源（后台刷新 / 硬件 0x20·0x30 / 指纹变化）可能并发进入。
        // 以前靠"已连接→.connectionInProgress"意外串行；连接跳过后需显式守卫，否则会重复发整轮 + 帧交错。
        // @MainActor 下在首个 await 前同步置位，保证原子。被丢弃的 force:true 记下、收尾后补跑一次——
        // 否则在途的 force:false 若随后被 shouldSync 拦下，硬件的强制刷新就丢了。
        guard preacquiredOfflineWriteSession
            || (!isSyncing && taskActionPresentationCount == 0) else {
            pendingSync = true
            if force { pendingForceSync = true }
            if let hardwareWakeDate { pendingHardwareWakeDate = hardwareWakeDate }
            return
        }
        isSyncing = true
        defer {
            isSyncing = false
            let waiters = syncCompletionWaiters
            syncCompletionWaiters.removeAll()
            waiters.forEach { $0.resume() }
            schedulePendingSyncIfPossible()
        }

        // Own the complete-message boundary before the first await after accepting this sync.
        // DeviceWake can otherwise yield to focus/UI/debug writes before Time(0x05).
        var ownsOfflineWriteSession = preacquiredOfflineWriteSession
        if !ownsOfflineWriteSession {
            do {
                try await bleService.beginOfflineSyncWriteSession()
                ownsOfflineWriteSession = true
            } catch {
                lastSyncSucceeded = false
                bleService.lastSyncFailed = true
                ErrorReporter.log(
                    .sync(component: "BLESyncCoordinator", underlying: error.localizedDescription),
                    context: "BLESyncCoordinator.acquireOfflineWriteSession"
                )
                return
            }
        }

        let now = Date()
        let lastSync = await localStorage.loadLastBleSyncTime()

        let appState = AppState.shared
        // 冷启动防御：0x20/0x30 可在 loadLocalData 完成前直呼本方法，用空 tasks/events 组出
        // 空 DayPack 推上硬件（闪一屏空首页）。其余入口（syncConnectedExternalData 等）都已等待，
        // 这里补齐（幂等，加载完成后零开销）。2026-07-04 审计 F3。
        await appState.ensureInitialLoadComplete()
        if let hardwareWakeDate {
            // Local usage/interruption bookkeeping happens after the transaction boundary is
            // owned. Its interruption drain suppresses the usual immediate 0x14 side effect.
            await appState.recordHardwareWakeActivity(now: hardwareWakeDate)
        }
        let contentChanged: Bool
        if force {
            // DeviceWake must reach Time/QUERY immediately. The actual frozen datasets are built
            // only after pending device operations have been durably applied.
            contentChanged = true
        } else {
            do {
                let preliminaryDayPack = try await generateStableDayPack().dayPack
                contentChanged = await localStorage.loadLastDayPackHash()
                    != preliminaryDayPack.stableFingerprint()
            } catch {
                pendingSync = true
                await bleService.endOfflineSyncWriteSession()
                ownsOfflineWriteSession = false
                return
            }
        }
        // 天气单独参与轮次放行（不影响 DayPack 发送判定）：天气已移出 DayPack 指纹，若不在
        // 这里放行，"只有天气变化"时 0x04 要等到点轮（白天 1h/夜间 4h）才能上硬件顶栏。
        // 天气变化放行的轮只发 Time/PetStatus/Weather 小帧——DayPack 指纹未变不会全刷。
        let w = appState.weather
        // hasData=false 是无定位权限 / WeatherKit 失败时的占位默认（22/26/18 sunny）——App 头部
        // 用 hasData 把它藏掉（AppHeaderView），BLE 侧同样不得把假天气发上硬件顶栏：无真实数据
        // 时不发 0x04、也不以天气名义放行轮次，硬件保持上次显示（peer review 2026-07-04）。
        let weatherFingerprint: String? = w.hasData
            ? "\(w.temperature)|\(w.highTemp)|\(w.lowTemp)|\(w.condition)"
            : nil
        let weatherChanged = weatherFingerprint != nil && weatherFingerprint != lastSentWeatherFingerprint

        let hasPriorityCustomAvatarOperation = appState.pendingCustomAvatarOperation?
            .requiresPriorityBLEFlush == true
        guard policy.shouldSync(
            now: now,
            lastSync: lastSync,
            contentChanged: contentChanged || weatherChanged,
            force: force,
            hasPriorityCustomAvatarOperation: hasPriorityCustomAvatarOperation
        ) else {
            await bleService.endOfflineSyncWriteSession()
            ownsOfflineWriteSession = false
            return
        }

        let timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(self.connectionTimeoutSeconds))
            guard !Task.isCancelled else { return }
            // 最坏 0x15 KRI 约 2.24MB / 4472 片，限流下需 4–5 分钟。
            // 30s 超时到点先等它结束，否则同步收尾会主动提前掐断每次头像传输。
            while !Task.isCancelled,
                  self.policy.shouldHoldConnectionForCustomAvatar(
                    chunkedTransferInFlight: self.bleService.isChunkedTransferInFlight,
                    operationState: appState.customAvatarOperationState
                  ) {
                try? await Task.sleep(for: .seconds(5))
            }
            guard !Task.isCancelled else { return }
            // 硬件调试需要长连接时不因超时主动断连。
            if self.bleService.connectionState.isConnected,
               !self.bleService.shouldKeepConnectionOpenForDebug,
               !self.offlineSyncCoordinator.requiresBLEConnection,
               self.taskActionPresentationCount == 0 {
                self.bleService.disconnect()
            }
        }
        defer { timeoutTask.cancel() }

        var transactionCommitted = false
        stagedDayPackFingerprint = nil
        stagedTaskStateVersion = nil
        defer {
            stagedDayPackFingerprint = nil
            stagedTaskStateVersion = nil
        }

        do {
            // keep-alive 模式下连接可能仍保持。已连接就跳过连接步骤——否则 connectKnownPeripheral 会因
            // canBeginConnect=false 抛 .connectionInProgress，导致首次同步后每轮同步/补传全部失败。
            if !bleService.connectionState.isConnected {
                // Connect with retry: 3 attempts, 1s/2s/4s backoff
                var connected = false
                var lastConnectError: Error?
                for attempt in 0..<3 {
                    do {
                        try await bleService.connectToPreferredDevice(timeout: 10)
                        connected = true
                        break
                    } catch {
                        lastConnectError = error
                        #if DEBUG
                        print("[BLESyncCoordinator] Connect attempt \(attempt + 1)/3 failed: \(error.localizedDescription)")
                        #endif
                        if attempt < 2 {
                            try? await Task.sleep(for: .seconds(Double(1 << attempt)))
                        }
                    }
                }
                // 保留底层原因：connectionFailed(error) 的描述会带上 underlying，外层 catch 即可在 Release 看到。
                guard connected else { throw BLEError.connectionFailed(lastConnectError) }
            }

            // The session acquired before local preparation owns the complete hardware contract:
            // 0x05 -> QUERY/STATE -> OP_BATCH/OP_ACK -> BEGIN -> 0x02 -> 0x03 -> 0x10
            // -> COMMIT -> RESULT=COMMITTED. No other business frame is emitted before it returns.
            _ = try await offlineSyncCoordinator.synchronize()
            transactionCommitted = true
            await bleService.endOfflineSyncWriteSession()
            ownsOfflineWriteSession = false

            guard let committedFingerprint = stagedDayPackFingerprint else {
                throw BLEError.staleTaskSnapshot
            }
            await localStorage.saveLastDayPackHash(committedFingerprint)
            if let sourceVersion = stagedTaskStateVersion,
               appState.taskStateVersion != sourceVersion {
                pendingSync = true
            }

            let completedAt = Date()
            await localStorage.saveLastBleSyncTime(completedAt)
            bleService.updateLastSyncTime(completedAt)
            bleService.lastSyncFailed = false
            lastSyncSucceeded = true

            // The required transaction has finished. Existing live-only display, weather and
            // avatar messages may now run without splitting the staged datasets.
            await flushDeferredFocusSessionEndHardwareDisplay(appState: appState)
            do {
                try await bleService.sendPetStatus(
                    appState.pet,
                    companionCharacter: appState.userProfile.companionCharacter,
                    customActive: appState.userProfile.customCompanionId != nil
                )
            } catch {
                ErrorReporter.log(
                    .sync(
                        component: "BLE PetStatus",
                        underlying: error.localizedDescription
                    ),
                    context: "BLESyncCoordinator.performSync"
                )
            }
            if let weatherFingerprint {
                do {
                    try await bleService.sendWeather(w)
                    lastSentWeatherFingerprint = weatherFingerprint
                } catch {
                    ErrorReporter.log(
                        .sync(component: "BLE Weather", underlying: error.localizedDescription),
                        context: "BLESyncCoordinator.performSync"
                    )
                }
            }
            if let hardwareWakeDate {
                await appState.syncHardwareWakeDisplay(now: hardwareWakeDate)
            }
            await appState.flushPriorityCustomAvatarOperationIfNeeded()
            await appState.flushPendingCustomCompanionPushIfNeeded()
        } catch {
            lastSyncSucceeded = false
            bleService.lastSyncFailed = true
            // STATE has no request ID. After a failed QUERY/transaction, a delayed response on
            // this connection could satisfy the next run. Reset the BLE generation before any
            // retry so old notifications cannot cross the boundary, even during Focus/debug.
            if !transactionCommitted, bleService.connectionState.isConnected {
                bleService.disconnect()
            }
            if !transactionCommitted {
                // A deferred idle/scene frame belongs only to this transaction's OP_BATCH. The
                // failed run disconnects, so retaining it could later overwrite a newly-started
                // focus session after an unrelated successful sync.
                deferredFocusSessionEndDisplay = nil
            }
            if ownsOfflineWriteSession {
                await bleService.endOfflineSyncWriteSession()
                ownsOfflineWriteSession = false
            }
            // 整轮同步失败的最终兜底——必须无条件上报。否则 Release/TestFlight 包（硬件团队拿的就是它）
            // 下 #if DEBUG 被裁剪，sync 失败彻底静默，硬件团队无法区分“没触发同步”和“同步失败了”。
            ErrorReporter.log(
                .sync(component: "BLESyncCoordinator", underlying: error.localizedDescription),
                context: "BLESyncCoordinator.performSync"
            )
        }

        // 智能提醒在断连前统一投递：硬件可达 → 只推 E-ink（手机保持安静）；硬件离线 → 落 iOS 本地通知，
        // 否则离线用户这条温和提醒就彻底丢了（NotificationService 此前完全没有调用方）。
        if transactionCommitted {
            await deliverSmartReminder(appState: appState)
        }

        // 同步收尾默认主动断连（省电脉冲式同步）；硬件调试仍需控制通道时保持连接不断。
        // 专注会话进行中也保持连接：硬件靠这条常驻连接的 notify(0x20) 唤醒被 iOS 挂起的 App
        // 推送实时专注状态（息屏后台链路）；脉冲式断连只服务空闲期。
        // 取舍（codex 复审 2026-07-13 发现3）：专注期不主动断连 → 写失败的"僵尸连接"不在此回收；
        // 但反向为写失败断连会经 handleDeviceDisconnected 杀掉专注会话（更糟），真正断链由
        // CoreBluetooth didDisconnect 兜底（→endSession→重连）。故刻意不为写失败断连。
        if bleService.connectionState.isConnected,
           !bleService.shouldKeepConnectionOpenForDebug,
           taskActionPresentationCount == 0,
           FocusSessionService.shared.activeSession == nil,
           // 头像大帧还在发就不断——由超时任务等它收尾（发完后连接闲置到下一轮 sync 收口，
           // 只是电池成本、无正确性问题）。
           !policy.shouldHoldConnectionForCustomAvatar(
            chunkedTransferInFlight: bleService.isChunkedTransferInFlight,
            operationState: appState.customAvatarOperationState
           ) {
            bleService.disconnect()
        }
    }

    private func schedulePendingSyncIfPossible() {
        guard pendingSync, !isSyncing, taskActionPresentationCount == 0 else { return }
        let shouldForce = pendingForceSync
        pendingSync = false
        pendingForceSync = false
        let hardwareWakeDate = pendingHardwareWakeDate
        pendingHardwareWakeDate = nil
        Task { @MainActor in
            await self.performSync(force: shouldForce, hardwareWakeDate: hardwareWakeDate)
        }
    }

    private func waitForActiveSyncToFinish() async {
        guard isSyncing else { return }
        await withCheckedContinuation { continuation in
            syncCompletionWaiters.append(continuation)
        }
    }

    private func sendFinalTaskActionDayPack() async -> UInt64? {
        let appState = AppState.shared
        await appState.ensureInitialLoadComplete()

        for _ in 0..<3 {
            await appState.refreshSharedPetDialogueIfNeeded()
            let sourceTaskStateVersion = appState.taskStateVersion
            guard appState.currentPetDialogueTaskStateVersion == sourceTaskStateVersion else {
                continue
            }

            let dayPack = await dayPackGenerator.generateDayPack(
                pet: appState.pet,
                tasks: appState.tasks,
                events: appState.events,
                weather: appState.weather,
                deviceMode: appState.deviceMode,
                userProfile: appState.userProfile,
                customCompanions: appState.customCompanions,
                screenSize: bleService.hardwareScreenSize,
                petDialogue: appState.currentPetDialogue
            )
            guard appState.taskStateVersion == sourceTaskStateVersion else { continue }

            let fingerprint = dayPack.stableFingerprint()
            if await localStorage.loadLastDayPackHash() == fingerprint {
                // A routine sync that was already in flight successfully sent this exact final
                // state. Reuse it instead of emitting a duplicate 0x10 before the same 0x1B.
                return sourceTaskStateVersion
            }

            if !bleService.connectionState.isConnected {
                do {
                    try await bleService.connectToPreferredDevice(timeout: 10)
                } catch {
                    pendingSync = true
                    ErrorReporter.log(
                        .sync(
                            component: "BLE Task Action DayPack",
                            underlying: error.localizedDescription
                        ),
                        context: "BLESyncCoordinator.sendFinalTaskActionDayPack"
                    )
                    return nil
                }
            }

            var taskStateChanged = false
            var lastWriteError: Error?
            for attempt in 0..<2 {
                do {
                    try await bleService.sendDayPack(
                        dayPack,
                        expectedTaskStateVersion: sourceTaskStateVersion
                    )
                    await localStorage.saveLastDayPackHash(fingerprint)
                    return sourceTaskStateVersion
                } catch let error as BLEError {
                    if case .staleTaskSnapshot = error {
                        taskStateChanged = true
                        break
                    }
                    lastWriteError = error
                } catch {
                    lastWriteError = error
                }

                if attempt == 0 {
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
            if taskStateChanged { continue }

            ErrorReporter.log(
                .sync(
                    component: "BLE Task Action DayPack",
                    underlying: lastWriteError?.localizedDescription ?? "write failed after 2 attempts"
                ),
                context: "BLESyncCoordinator.sendFinalTaskActionDayPack"
            )
            pendingSync = true
            return nil
        }

        pendingSync = true
        ErrorReporter.log(
            .sync(
                component: "BLE Task Action DayPack",
                underlying: "task state changed during 3 consecutive generation attempts"
            ),
            context: "BLESyncCoordinator.sendFinalTaskActionDayPack"
        )
        return nil
    }

    static func completeTaskActionPresentation(
        maximumAttempts: Int = 3,
        sendFinalDayPack: @MainActor () async -> UInt64?,
        acknowledge: @MainActor (UInt64) async -> TaskListSnapshotResponder.Outcome
    ) async -> Bool {
        for _ in 0..<maximumAttempts {
            guard let taskStateVersion = await sendFinalDayPack() else { return false }
            switch await acknowledge(taskStateVersion) {
            case .sent:
                return true
            case .staleTaskState:
                continue
            case .failed:
                return false
            }
        }
        return false
    }

    /// 路由一条到期的智能提醒：硬件可达就推设备，否则落本地通知，让离线用户也收得到。
    /// 每轮同步只评估一次（限流逻辑在 SmartReminderService 内）。
    private func deliverSmartReminder(appState: AppState) async {
        guard let reminder = await SmartReminderService.shared.evaluateAndPushReminder(
            tasks: appState.tasks,
            pet: appState.pet
        ) else { return }

        if bleService.connectionState.isConnected {
            do {
                try await bleService.sendSmartReminder(
                    text: reminder.text,
                    urgency: reminder.urgency,
                    petMood: appState.pet.mood
                )
                SmartReminderService.shared.markReminderSent()
                return
            } catch {
                ErrorReporter.log(
                    .sync(component: "BLE SmartReminder", underlying: error.localizedDescription),
                    context: "BLESyncCoordinator.deliverSmartReminder"
                )
                // 已连接却写失败：落本地通知兜底，别让提醒丢了。
            }
        }

        // 硬件离线（或 BLE 写失败）：E-ink 显示不了，回退到 iOS 本地通知。
        await NotificationService.shared.refreshAuthorizationStatus()
        let delivered = await NotificationService.shared.scheduleLocalNotification(from: reminder)
        // 只有确实投递了才消耗 30 分钟冷却；BLE 与通知都失败时留待下轮重试。
        if delivered {
            SmartReminderService.shared.markReminderSent()
        }
    }
}

extension BLESyncCoordinator: TaskActionPresentationCoordinating {
    func sendFinalDayPackBeforeAcknowledgement(
        _ acknowledgement: @MainActor @Sendable (
            _ expectedTaskStateVersion: UInt64
        ) async -> TaskListSnapshotResponder.Outcome
    ) async {
        taskActionPresentationCount += 1
        AppState.shared.cancelPendingBLESyncForTaskActionPresentation()

        do {
            try await taskActionPresentationGate.acquire()
        } catch {
            // Firmware keeps the operation pending and retries the same OperationID. Sending
            // 0x1B here would exit TaskIn without the final DayPack and recreate the double refresh.
            taskActionPresentationCount -= 1
            schedulePendingSyncIfPossible()
            return
        }

        await waitForActiveSyncToFinish()
        AppState.shared.cancelPendingBLESyncForTaskActionPresentation()
        let completed = await Self.completeTaskActionPresentation(
            sendFinalDayPack: { await self.sendFinalTaskActionDayPack() },
            acknowledge: acknowledgement
        )
        if !completed {
            pendingSync = true
            ErrorReporter.log(
                .sync(
                    component: "BLE Task Action Presentation",
                    underlying: "final DayPack and acknowledgement did not complete as one task version"
                ),
                context: "BLESyncCoordinator.sendFinalDayPackBeforeAcknowledgement"
            )
        }

        await taskActionPresentationGate.release()
        taskActionPresentationCount -= 1
        schedulePendingSyncIfPossible()
    }
}

#if os(iOS)
// @preconcurrency: BGAppRefreshTask 未标注 Sendable，但 setTaskCompleted 可跨线程调用（Apple 的
// OperationQueue 范式即在 completionBlock off-main 调用），到期 handler 需同步结案故必须捕获 task。
@preconcurrency import BackgroundTasks
import os

@MainActor
public extension BLESyncCoordinator {
    func performBackgroundSync(task: BGAppRefreshTask) async {
        // 本次任务局部的线程安全幂等结案器：到期(可能在非主线程)与正常路径都调 complete，
        // unfair lock 保证 setTaskCompleted 只发生一次（重复调用会 crash，漏调会被 watchdog 强杀）。
        let completed = OSAllocatedUnfairLock(initialState: false)
        @Sendable func complete(success: Bool) {
            let firstTime = completed.withLock { done -> Bool in
                guard !done else { return false }
                done = true
                return true
            }
            if firstTime {
                task.setTaskCompleted(success: success)
            }
        }

        task.expirationHandler = { [weak self] in
            // 到期必须【同步】结案，不能排队等 MainActor（系统可能马上挂起进程，晚一步即被 watchdog
            // 强杀并削减后台预算）。断连优先级更低，丢到 MainActor 即可。专注会话或
            // Wi-Fi 联调进行中保持连接，供硬件 notify 和热点关闭/查询继续使用。
            complete(success: false)
            Task { @MainActor in
                guard let self,
                      FocusSessionService.shared.activeSession == nil,
                      !self.bleService.shouldKeepConnectionOpenForDebug,
                      !self.policy.shouldHoldConnectionForCustomAvatar(
                        chunkedTransferInFlight: self.bleService.isChunkedTransferInFlight,
                        operationState: AppState.shared.customAvatarOperationState
                      ) else { return }
                self.bleService.disconnect()
            }
        }

        await AuthManager.shared.initialize()
        await AppState.shared.syncConnectedExternalData()
        await performSync()
        BLEBackgroundSyncScheduler.shared.schedule()
        complete(success: lastSyncSucceeded)
    }
}
#endif
