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

    static func shouldRestoreOrdinaryFocusAfterReconnect(
        didResolveFocus: Bool,
        hasActiveFocusSession: Bool
    ) -> Bool {
        didResolveFocus || hasActiveFocusSession
    }

    let bleService = BLEService.shared
    let dayPackGenerator = DayPackGenerator.shared
    let localStorage = LocalStorage.shared
    let policy = BLESyncPolicy()

    var lastSyncSucceeded = true
    /// 上次成功发出的 Weather(0x04) 指纹（上 wire 的四个量化值）。内存态即可：重启后首轮
    /// 多发一次 ~10B 小帧，无害；不入 LocalStorage 以避开 resettable key 的测试隔离成本。
    private var lastSentWeatherFingerprint: String?
    /// Owns both the active slot and any coalesced follow-up request. Reserving the next slot before
    /// scheduling its Task prevents another DeviceWake from starting a competing transaction.
    var syncState = BLEDeviceWakeSyncState()
    /// DeviceWake bookkeeping contains awaits. The snapshot closes the merge window, then waits for
    /// every wake admitted before that close so focus/interruption state cannot miss the transaction.
    private var deviceWakeProcessingCount = 0
    private var deviceWakeProcessingWaiters: [CheckedContinuation<Void, Never>] = []
    private var deviceWakeTasks: [UUID: Task<Void, Never>] = [:]
    private var activePerformSyncOwnerID: UUID?
    private let deviceWakeBarrier = BLEDeviceWakeBarrier()
    private var deviceWakeFocusFreezeLease: FocusStatusFreezeLease?
    private var offlineFocusFreezeLease: FocusStatusFreezeLease?
    private(set) var focusReconciledConnectionGeneration: UInt64?
    private var deferredFocusSessionEndDisplay: DeferredFocusSessionEndDisplay?
    /// Set only while the frozen payloads used by the current 0x25 transaction are being built.
    /// It becomes durable sync metadata only after the device returns RESULT=COMMITTED.
    private var stagedDayPackFingerprint: String?
    private var stagedTaskStateVersion: UInt64?
    /// Last TaskList/Schedule/agenda identity that was actually COMMITted. Dialogue-only
    /// refreshes must not write this, or a focus skip would hide a later real change.
    /// Persisted (LocalStorage) so an app relaunch does not force a no-change full refresh.
    private var lastCommittedStructuralHash: String?
    private var hasLoadedPersistedStructuralHash = false
    /// Structural hash of the frozen snapshot the current 0x25 transaction is sending. Only
    /// this value may become `lastCommittedStructuralHash`: recomputing from live AppState
    /// after COMMIT would record a mid-transaction task change as already committed and the
    /// follow-up round could never see the difference.
    private var stagedStructuralHash: String?
    private lazy var offlineSyncCoordinator = makeOfflineSyncCoordinator()
    /// Complete/Skip keeps the device on TaskIn until one final DayPack has been sent. Routine
    /// sync requests queue behind this window so no second DayPack can race the later 0x1B.
    var taskActionPresentationCount = 0
    let taskActionPresentationGate = BLEWriteGate()
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
        cancelDeviceWakeTasks()
        if activePerformSyncOwnerID == nil {
            syncState.resetForDisconnectedConnection()
        }
        offlineSyncCoordinator.handleDisconnected()
        focusReconciledConnectionGeneration = nil
        releaseFocusFreezeLeases()
    }

    func prepareForConnectionGeneration(_ generation: UInt64) {
        cancelDeviceWakeTasks()
        if activePerformSyncOwnerID == nil {
            syncState.resetForDisconnectedConnection()
        }
        deviceWakeBarrier.prepare(generation: generation)
        offlineSyncCoordinator.preparePreRunInboundCapture()
        focusReconciledConnectionGeneration = nil
    }

    func noteInboundMessage(type: UInt8, generation: UInt64) {
        guard type == EventLogType.deviceWake.rawByte else { return }
        deviceWakeBarrier.observe(generation: generation)
    }

    func isFocusReconciled(generation: UInt64) -> Bool {
        focusReconciledConnectionGeneration == generation
    }

    private func acquireDeviceWakeFocusFreezeIfNeeded() {
        guard deviceWakeFocusFreezeLease == nil else { return }
        deviceWakeFocusFreezeLease = FocusSessionService.shared.acquireFocusStatusFreeze()
    }

    private func acquireOfflineFocusFreezeIfNeeded() {
        guard offlineFocusFreezeLease == nil else { return }
        offlineFocusFreezeLease = FocusSessionService.shared.acquireFocusStatusFreeze()
    }

    private func releaseOfflineFocusFreezeLease() {
        guard let lease = offlineFocusFreezeLease else { return }
        FocusSessionService.shared.releaseFocusStatusFreeze(lease)
        offlineFocusFreezeLease = nil
    }

    private func releaseFocusFreezeLeases() {
        releaseOfflineFocusFreezeLease()
        if let lease = deviceWakeFocusFreezeLease {
            FocusSessionService.shared.releaseFocusStatusFreeze(lease)
            deviceWakeFocusFreezeLease = nil
        }
    }

    private func currentReadyGenerationForCancellation(
        transactionGeneration: UInt64?
    ) -> UInt64? {
        let candidate = transactionGeneration ?? bleService.currentConnectionGeneration
        guard bleService.isReadyConnectionGeneration(candidate) else { return nil }
        return candidate
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
        let makeResolveID: @MainActor @Sendable () -> UInt32 = {
            UInt32.random(in: 1...UInt32.max)
        }
        return BLEOfflineSyncCoordinator(
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
                    self.syncState.closeDeviceWakeMergeWindow()
                    await self.waitForDeviceWakeProcessingToFinish()
                    let frozen = try await self.generateStableDayPack()
                    let snapshot = OfflineDatasetSnapshot(
                        tasks: frozen.tasks,
                        events: frozen.events,
                        dayPack: frozen.dayPack,
                        screenSize: self.bleService.hardwareScreenSize
                    )
                    self.stagedDayPackFingerprint = frozen.dayPack.stableFingerprint()
                    self.stagedTaskStateVersion = frozen.taskStateVersion
                    self.stagedStructuralHash = frozen.structuralHash
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
                },
                makeResolveID: makeResolveID,
                freezeFocusStatus: { [weak self] in
                    self?.acquireOfflineFocusFreezeIfNeeded()
                },
                unfreezeFocusStatus: {
                    // BLESyncCoordinator owns the lease through write-gate release and the
                    // authoritative post-COMMITTED restore. The protocol helper may finish its
                    // waiter here, but it must not unfreeze ordinary 0x14 yet.
                },
                previewFocusState: { state in
                    try await FocusSessionService.shared.applyReconnectPreview(state)
                },
                resolveFocus: { state in
                    try await FocusSessionService.shared.resolveReconnect(
                        state,
                        resolveID: makeResolveID()
                    )
                },
                restoreOrdinaryFocusSync: { snapshot, resolve in
                    try await FocusSessionService.shared.restoreOrdinaryFocusSyncAfterResolve(
                        snapshot,
                        resolve: resolve
                    )
                },
                abandonPendingFocusResolve: {
                    FocusSessionService.shared.abandonPendingReconnect()
                },
                invalidatePendingFocusResolve: {
                    FocusSessionService.shared.invalidatePendingReconnectAfterInvalidState()
                }
            )
        )
    }

    /// Firmware 1.3.1: after RESULT/COMMITTED, restore ordinary DayPack/Schedule.
    /// Ordinary 0x10 does not leave TaskIn. Dataset COMMIT is never a reconnect step.
    private func sendOrdinaryDatasetsAfterFocusResolve() async {
        do {
            let frozen = try await generateStableDayPack()
            try await bleService.sendOfflineDayPackPayload(
                BLEDataEncoder.encodeDayPack(frozen.dayPack, screenSize: bleService.hardwareScreenSize)
            )
            try await bleService.sendOfflineSchedulePayload(
                BLEDataEncoder.encodeSchedule(frozen.events)
            )
        } catch {
            ErrorReporter.log(
                .sync(
                    component: "FocusReconnect ordinary datasets",
                    underlying: error.localizedDescription
                ),
                context: "BLESyncCoordinator.sendOrdinaryDatasetsAfterFocusResolve"
            )
        }
    }

    private func generateStableDayPack() async throws -> (
        dayPack: DayPack,
        tasks: [TaskItem],
        events: [CalendarEvent],
        taskStateVersion: UInt64,
        structuralHash: String
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
            // Hash the same captured inputs the datasets are built from, never a fresh
            // AppState read: this is what "committed" will mean if the transaction lands.
            let structuralHash = HardwareContentFingerprint.structural(
                tasks: tasks,
                events: events,
                now: Date(),
                screenSize: screenSize,
                deviceMode: deviceMode,
                companionKey: HardwareContentFingerprint.companionKey(from: userProfile)
            )
            return (dayPack, tasks, events, sourceTaskStateVersion, structuralHash)
        }
        throw BLEError.staleTaskSnapshot
    }

    private func performDeviceWakeSync(
        _ eventLog: EventLog,
        service: BLEService,
        generation: UInt64
    ) async {
        guard !Task.isCancelled,
              service.isReadyConnectionGeneration(generation) else { return }
        noteInboundMessage(
            type: EventLogType.deviceWake.rawByte,
            generation: generation
        )
        // Freeze ordinary 0x14 before any DeviceWake side effect or write can suspend.
        acquireDeviceWakeFocusFreezeIfNeeded()
        let decision = syncState.handleDeviceWake(
            at: eventLog.timestamp,
            taskActionBlocked: taskActionPresentationCount > 0
        )

        switch decision {
        case .mergeIntoActiveSync:
            beginDeviceWakeProcessing()
            _ = await processDeviceWake(
                eventLog,
                service: service,
                generation: generation
            )
            finishDeviceWakeProcessing()
            return

        case .enqueueForcedSync:
            beginDeviceWakeProcessing()
            let isCurrent = await processDeviceWake(
                eventLog,
                service: service,
                generation: generation
            )
            finishDeviceWakeProcessing()
            guard isCurrent else { return }
            schedulePendingSyncIfPossible()
            return

        case .startDedicatedSync:
            break
        }

        // DeviceWake must reserve the message boundary before generic event logging, inventory
        // reconciliation, or any other await can let a live 0x14/0x17/0x1B write run first.
        do {
            guard !Task.isCancelled,
                  service.isReadyConnectionGeneration(generation) else {
                finishActiveSyncReservation(transactionCommitted: false, retryMergedWake: false)
                return
            }
            try await bleService.beginOfflineSyncWriteSession()
        } catch {
            beginDeviceWakeProcessing()
            _ = await processDeviceWake(
                eventLog,
                service: service,
                generation: generation
            )
            finishDeviceWakeProcessing()
            lastSyncSucceeded = false
            bleService.lastSyncFailed = true
            syncState.enqueue(force: true, hardwareWakeDate: eventLog.timestamp)
            ErrorReporter.log(
                .sync(component: "BLESyncCoordinator", underlying: error.localizedDescription),
                context: "BLESyncCoordinator.acquireDeviceWakeWriteSession"
            )
            finishActiveSyncReservation(transactionCommitted: false)
            return
        }

        guard !Task.isCancelled,
              service.isReadyConnectionGeneration(generation) else {
            await bleService.endOfflineSyncWriteSession()
            finishActiveSyncReservation(transactionCommitted: false, retryMergedWake: false)
            return
        }

        beginDeviceWakeProcessing()
        let isCurrent = await processDeviceWake(
            eventLog,
            service: service,
            generation: generation
        )
        finishDeviceWakeProcessing()
        guard isCurrent else {
            await bleService.endOfflineSyncWriteSession()
            finishActiveSyncReservation(transactionCommitted: false, retryMergedWake: false)
            return
        }
        await performSync(
            force: true,
            hardwareWakeDate: eventLog.timestamp,
            preacquiredOfflineWriteSession: true,
            activeSyncReservationAlreadyHeld: true
        )
    }

    /// DeviceWake starts an OfflineSync transaction that waits for later 0x25 notifications.
    /// Detaching that transaction from the serial inbound delivery pump lets buffered STATE /
    /// FOCUS_STATE / OP_BATCH messages continue feeding the waiter without reordering them.
    func enqueueDeviceWakeSync(
        _ eventLog: EventLog,
        service: BLEService,
        generation: UInt64
    ) {
        let taskID = UUID()
        deviceWakeTasks[taskID] = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performDeviceWakeSync(
                eventLog,
                service: service,
                generation: generation
            )
            self.deviceWakeTasks[taskID] = nil
        }
    }

    private func cancelDeviceWakeTasks() {
        deviceWakeTasks.values.forEach { $0.cancel() }
        deviceWakeTasks.removeAll()
    }

    public func performSync(force: Bool = false, hardwareWakeDate: Date? = nil) async {
        await performSync(
            force: force,
            hardwareWakeDate: hardwareWakeDate,
            preacquiredOfflineWriteSession: false,
            activeSyncReservationAlreadyHeld: false
        )
    }

    private func performSync(
        force: Bool,
        hardwareWakeDate: Date?,
        preacquiredOfflineWriteSession: Bool,
        activeSyncReservationAlreadyHeld: Bool
    ) async {
        // 并发守卫：keep-alive 默认开后连接常驻，多触发源（后台刷新 / 硬件 0x20·0x30 / 指纹变化）可能并发进入。
        // 以前靠"已连接→.connectionInProgress"意外串行；连接跳过后需显式守卫，否则会重复发整轮 + 帧交错。
        // @MainActor 下在首个 await 前同步置位，保证原子。被丢弃的 force:true 记下、收尾后补跑一次——
        // 否则在途的 force:false 若随后被 shouldSync 拦下，硬件的强制刷新就丢了。
        if !activeSyncReservationAlreadyHeld {
            guard syncState.beginSync(
                force: force,
                hardwareWakeDate: hardwareWakeDate,
                taskActionBlocked: taskActionPresentationCount > 0
            ) else { return }
        }
        let syncOwnerID = UUID()
        precondition(activePerformSyncOwnerID == nil)
        activePerformSyncOwnerID = syncOwnerID
        acquireOfflineFocusFreezeIfNeeded()
        var transactionCommitted = false
        var retryMergedWakeOnFailure = true
        defer {
            finishActiveSyncReservation(
                transactionCommitted: transactionCommitted,
                retryMergedWake: retryMergedWakeOnFailure
            )
            if activePerformSyncOwnerID == syncOwnerID {
                activePerformSyncOwnerID = nil
            }
        }

        // Own the complete-message boundary before the first await after accepting this sync.
        // DeviceWake can otherwise yield to focus/UI/debug writes before Time(0x05).
        var ownsOfflineWriteSession = preacquiredOfflineWriteSession
        if !ownsOfflineWriteSession {
            do {
                try await bleService.beginOfflineSyncWriteSession()
                ownsOfflineWriteSession = true
            } catch {
                releaseFocusFreezeLeases()
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
        if !hasLoadedPersistedStructuralHash {
            hasLoadedPersistedStructuralHash = true
            lastCommittedStructuralHash = await localStorage.loadLastCommittedStructuralHash()
        }
        // Dialogue is not a refresh condition. Task-bar / schedule / agenda / companion
        // identity decide whether the screen should receive a new 0x25 COMMIT.
        let structuralHash = HardwareContentFingerprint.structural(
            from: appState,
            now: now,
            screenSize: bleService.hardwareScreenSize
        )
        let contentChanged = lastCommittedStructuralHash != structuralHash
        let commitForce = DayPackRefreshArbiter.shouldForceCommit(
            force: force,
            isHardwareWake: hardwareWakeDate != nil
        )
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
        let effectiveForce = force || syncState.activeSyncHadMergedWake
        guard policy.shouldSync(
            now: now,
            lastSync: lastSync,
            contentChanged: contentChanged || weatherChanged,
            force: effectiveForce,
            hasPriorityCustomAvatarOperation: hasPriorityCustomAvatarOperation
        ) else {
            await bleService.endOfflineSyncWriteSession()
            ownsOfflineWriteSession = false
            releaseFocusFreezeLeases()
            return
        }

        var timeoutTask: Task<Void, Never>?
        defer { timeoutTask?.cancel() }
        var transactionGeneration: UInt64?

        stagedDayPackFingerprint = nil
        stagedTaskStateVersion = nil
        stagedStructuralHash = nil
        defer {
            stagedDayPackFingerprint = nil
            stagedTaskStateVersion = nil
            stagedStructuralHash = nil
        }

        do {
            // keep-alive 模式下连接可能仍保持。已连接就跳过连接步骤——否则 connectKnownPeripheral 会因
            // canBeginConnect=false 抛 .connectionInProgress，导致首次同步后每轮同步/补传全部失败。
            if !bleService.connectionState.isConnected {
                try await bleService.connectToPreferredDevice(timeout: 10)
            }

            let generation = bleService.currentConnectionGeneration
            transactionGeneration = generation
            let didObserveDeviceWake: Bool
            do {
                didObserveDeviceWake = try await deviceWakeBarrier.wait(
                    generation: generation,
                    timeout: .seconds(5)
                )
            } catch is CancellationError {
                // Caller cancellation while this run is only waiting for DeviceWake must release
                // its reservation immediately. It is not a protocol timeout and must not start a
                // recovery round.
                syncState.closeDeviceWakeMergeWindow()
                let retainsReadyConnection = currentReadyGenerationForCancellation(
                    transactionGeneration: transactionGeneration
                ) != nil
                retryMergedWakeOnFailure = retainsReadyConnection
                    && syncState.activeSyncHadMergedWake
                if ownsOfflineWriteSession {
                    await bleService.endOfflineSyncWriteSession()
                    ownsOfflineWriteSession = false
                }
                if retainsReadyConnection {
                    // This task owns only the OfflineSync lease. A DeviceWake delivered during
                    // gate cleanup owns its separate lease until the forced run finishes.
                    releaseOfflineFocusFreezeLease()
                } else {
                    releaseFocusFreezeLeases()
                }
                return
            }
            guard didObserveDeviceWake else {
                // Notify 已建立，BLE 连接本身是健康的。DeviceWake 是固件发起业务同步的
                // 第一条消息，不是连接健康证明。暂时没收到时只结束本次同步等待；保持连接，
                // 由同 generation 的迟到 DeviceWake 重新发起一轮，绝不主动断开硬件。
                retryMergedWakeOnFailure = false
                await BLEDeviceWakeDeferredSyncExit.finish(
                    closeDeviceWakeMergeWindow: {
                        self.syncState.closeDeviceWakeMergeWindow()
                    },
                    ownsOfflineWriteSession: ownsOfflineWriteSession,
                    endOfflineWriteSession: {
                        await self.bleService.endOfflineSyncWriteSession()
                    },
                    releaseOfflineFocusFreezeLease: {
                        // 若 DeviceWake 恰在上面的 await 期间到达，它持有独立 lease，并会在
                        // 随后专用同步完成时释放。这里不能释放那份 lease。
                        self.releaseOfflineFocusFreezeLease()
                    }
                )
                ownsOfflineWriteSession = false
                return
            }

            // The 30-second sync watchdog starts only after link, GATT, Notify and DeviceWake are
            // ready. It can no longer consume the first connection's readiness budget.
            timeoutTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(self.connectionTimeoutSeconds))
                guard !Task.isCancelled else { return }
                while !Task.isCancelled,
                      self.policy.shouldHoldConnectionForCustomAvatar(
                        chunkedTransferInFlight: self.bleService.isChunkedTransferInFlight,
                        operationState: appState.customAvatarOperationState
                      ) {
                    try? await Task.sleep(for: .seconds(5))
                }
                guard !Task.isCancelled else { return }
                if self.bleService.connectionState.isConnected,
                   !self.bleService.shouldKeepConnectionOpenForDebug,
                   !self.offlineSyncCoordinator.requiresBLEConnection,
                   self.taskActionPresentationCount == 0 {
                    self.bleService.disconnectIfCurrentGeneration(generation)
                }
            }

            // Firmware 1.3.1: Time -> QUERY/STATE -> FOCUS_STATE -> OP_BATCH ->
            // OP_ACK -> FOCUS_RESOLVE -> RESULT/COMMITTED -> unlock. Dataset
            // COMMIT is deferred while a focus session is still active.
            let completion = try await offlineSyncCoordinator.synchronize { [weak self] _ in
                guard let self else { return false }
                let afterOpsHash = HardwareContentFingerprint.structural(
                    from: AppState.shared,
                    now: Date(),
                    screenSize: self.bleService.hardwareScreenSize
                )
                return DayPackRefreshArbiter.shouldCommitDatasets(
                    structuralChanged: self.lastCommittedStructuralHash != afterOpsHash,
                    force: commitForce,
                    hasActiveFocusSession: FocusSessionService.shared.activeSession != nil
                )
            }
            if completion.didResolveFocus && !completion.didCommitDatasets {
                await sendOrdinaryDatasetsAfterFocusResolve()
            }
            transactionCommitted = true
            await bleService.endOfflineSyncWriteSession()
            ownsOfflineWriteSession = false
            focusReconciledConnectionGeneration = generation
            // An empty idle device snapshot needs no FOCUS_RESOLVE, even when the App still owns
            // an active session. In that case restore the ordinary active 0x14 after releasing the
            // reconnect barrier instead of leaving the device idle until a later periodic refresh.
            if Self.shouldRestoreOrdinaryFocusAfterReconnect(
                didResolveFocus: completion.didResolveFocus,
                hasActiveFocusSession: FocusSessionService.shared.activeSession != nil
            ) {
                await FocusSessionService.shared.restoreOrdinaryFocusBLEAfterReconnect {
                    self.releaseFocusFreezeLeases()
                }
            } else {
                releaseFocusFreezeLeases()
            }

            if completion.didCommitDatasets {
                guard let committedFingerprint = stagedDayPackFingerprint,
                      let committedStructuralHash = stagedStructuralHash else {
                    throw BLEError.staleTaskSnapshot
                }
                // Record the frozen snapshot's hash, not live state: a task completed while
                // the datasets were on the air must remain an uncommitted difference so the
                // version-mismatch follow-up below can actually fire a re-commit.
                lastCommittedStructuralHash = committedStructuralHash
                await localStorage.saveLastCommittedStructuralHash(committedStructuralHash)
                await localStorage.saveLastDayPackHash(committedFingerprint)
                if let sourceVersion = stagedTaskStateVersion,
                   appState.taskStateVersion != sourceVersion {
                    syncState.enqueue(force: false, hardwareWakeDate: nil)
                }
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
            if let wakeDate = syncState.activeHardwareWakeDate {
                await appState.syncHardwareWakeDisplay(now: wakeDate)
            }
            await appState.flushPriorityCustomAvatarOperationIfNeeded()
            await appState.flushPendingCustomCompanionPushIfNeeded()
        } catch is CancellationError {
            // Caller cancellation is not a transport failure. In particular, a cancelled task
            // from an older generation must never tear down a newer ready connection.
            // Close the merge window before the first await. A DeviceWake delivered during gate
            // cleanup will then enqueue its own forced run instead of disappearing into this one.
            syncState.closeDeviceWakeMergeWindow()
            let retainsReadyConnection = currentReadyGenerationForCancellation(
                transactionGeneration: transactionGeneration
            ) != nil
            retryMergedWakeOnFailure = retainsReadyConnection
                && syncState.activeSyncHadMergedWake
            if ownsOfflineWriteSession {
                await bleService.endOfflineSyncWriteSession()
                ownsOfflineWriteSession = false
            }
            if retainsReadyConnection {
                // Keep a DeviceWake-owned lease, if any, but never leak this cancelled run's
                // OfflineSync lease when no wake arrives.
                releaseOfflineFocusFreezeLease()
            } else {
                releaseFocusFreezeLeases()
            }
            return
        } catch {
            lastSyncSucceeded = false
            bleService.lastSyncFailed = true
            if case BLEOfflineSyncCoordinatorError.deviceRejected(.invalidState) = error {
                retryMergedWakeOnFailure = false
            }
            // STATE has no request ID. After a failed QUERY/transaction, a delayed response on
            // this connection could satisfy the next run. Reset the BLE generation before any
            // retry so old notifications cannot cross the boundary, even during Focus/debug.
            if !transactionCommitted, bleService.connectionState.isConnected {
                if let transactionGeneration {
                    bleService.disconnectIfCurrentGeneration(transactionGeneration)
                }
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
            if !bleService.connectionState.isConnected {
                releaseFocusFreezeLeases()
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
            if let transactionGeneration {
                bleService.disconnectIfCurrentGeneration(transactionGeneration)
            }
        }
    }

    func schedulePendingSyncIfPossible() {
        guard let request = syncState.reservePendingSyncIfPossible(
            taskActionBlocked: taskActionPresentationCount > 0
        ) else { return }
        Task { @MainActor in
            await self.performSync(
                force: request.force,
                hardwareWakeDate: request.hardwareWakeDate,
                preacquiredOfflineWriteSession: false,
                activeSyncReservationAlreadyHeld: true
            )
        }
    }

    private func finishActiveSyncReservation(
        transactionCommitted: Bool,
        retryMergedWake: Bool = true
    ) {
        syncState.finishActiveSync(
            transactionCommitted: transactionCommitted,
            retryMergedWake: retryMergedWake
        )
        let waiters = syncCompletionWaiters
        syncCompletionWaiters.removeAll()
        waiters.forEach { $0.resume() }
        schedulePendingSyncIfPossible()
    }

    private func beginDeviceWakeProcessing() {
        deviceWakeProcessingCount += 1
    }

    private func finishDeviceWakeProcessing() {
        precondition(deviceWakeProcessingCount > 0)
        deviceWakeProcessingCount -= 1
        guard deviceWakeProcessingCount == 0 else { return }
        let waiters = deviceWakeProcessingWaiters
        deviceWakeProcessingWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func waitForDeviceWakeProcessingToFinish() async {
        guard deviceWakeProcessingCount > 0 else { return }
        await withCheckedContinuation { continuation in
            deviceWakeProcessingWaiters.append(continuation)
        }
    }

    private func processDeviceWake(
        _ eventLog: EventLog,
        service: BLEService,
        generation: UInt64
    ) async -> Bool {
        guard !Task.isCancelled,
              service.isReadyConnectionGeneration(generation) else { return false }
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
            guard !Task.isCancelled,
                  service.isReadyConnectionGeneration(generation) else { return false }
        }
        _ = await BLEEventHandler.processEventLogs([eventLog], service: service)
        guard !Task.isCancelled,
              service.isReadyConnectionGeneration(generation) else { return false }
        let appState = AppState.shared
        await appState.ensureInitialLoadComplete()
        guard !Task.isCancelled,
              service.isReadyConnectionGeneration(generation) else { return false }
        await appState.recordHardwareWakeActivity(now: eventLog.timestamp)
        return !Task.isCancelled && service.isReadyConnectionGeneration(generation)
    }

    func waitForActiveSyncToFinish() async {
        guard syncState.isSyncing else { return }
        await withCheckedContinuation { continuation in
            syncCompletionWaiters.append(continuation)
        }
    }
}
