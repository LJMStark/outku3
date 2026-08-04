import Foundation

// MARK: - BLE Sync Coordinator

private struct TaskActionDestinationBlocks {
    /// An empty destination is deliberately retained as an unbound fail-closed marker. It cannot
    /// be mistaken for any real device and therefore blocks every destination until process-local
    /// state is rebuilt from durable delivery records.
    private var destinationIDs: Set<String> = []

    var hasAny: Bool {
        !destinationIDs.isEmpty
    }

    mutating func insert(_ destinationID: String) {
        destinationIDs.insert(destinationID)
    }

    mutating func remove(_ destinationID: String, includingUnbound: Bool = false) {
        destinationIDs.remove(destinationID)
        if includingUnbound {
            destinationIDs.remove("")
        }
    }

    mutating func replace(_ destinationID: String, isBlocked: Bool) {
        if isBlocked {
            insert(destinationID)
        } else {
            remove(destinationID)
        }
    }

    /// A missing current destination means an explicit sync may still connect and identify B; a
    /// previously blocked A must not prevent that discovery. An unbound marker remains global.
    func blocks(_ destinationID: String?) -> Bool {
        if destinationIDs.contains("") { return true }
        guard let destinationID else { return false }
        guard !destinationID.isEmpty else { return true }
        return destinationIDs.contains(destinationID)
    }

    /// The internal pending runner cannot discover a destination without re-entering sync. Park it
    /// while disconnected if any destination is blocked, avoiding a self-scheduling retry loop.
    func blocksScheduledSync(_ destinationID: String?) -> Bool {
        guard destinationID != nil else { return hasAny }
        return blocks(destinationID)
    }
}

@MainActor
public final class BLESyncCoordinator {
    public static let shared = BLESyncCoordinator()

    private let bleService = BLEService.shared
    private let dayPackGenerator = DayPackGenerator.shared
    private let taskLibraryPhaseTextService = TaskLibraryPhaseTextService.shared
    private let taskLibraryDeliveryRetrier = TaskLibraryDeliveryRetrier()
    private let taskLibraryAcknowledgementGate = TaskLibraryAcknowledgementGate()
    private let dailyContentPackageGenerator = DailyContentPackageGenerator.shared
    private let dailyContentDeliveryRetrier = DailyContentDeliveryRetrier()
    private let dailyContentAcknowledgementGate = DailyContentAcknowledgementGate()
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
    private var pendingSyncTrigger: BLESyncTrigger?
    /// Current-connection lookup for late 0x23 results. The frozen transaction itself is durable
    /// in LocalStorage, so disconnect cleanup can discard this map without losing retry state.
    private var pendingTaskLibraries: [String: TaskLibraryCommittedState] = [:]
    /// Current-connection lookup for a late 0x24 commit result. The frozen package remains durable
    /// so reconnect can resend the exact bytes from sequence zero.
    private var pendingDailyContents: [String: DailyContentCommittedState] = [:]
    /// A phase-text preparation may use the full three-minute product window. Keep the connection
    /// alive through preparation and the following 0x23 write so the 30-second idle recycler cannot
    /// discard the exact transaction this window is preparing.
    private var isTaskLibraryTransactionInFlight = false
    private var isDailyContentTransactionInFlight = false
    /// Real-time DeviceWake inventory wins over the persisted marker for the current connection.
    private var taskLibraryDeviceInventories: [String: TaskLibraryDeviceInventory] = [:]
    /// Complete/Skip keeps the device on TaskIn until one final DayPack has been sent. Routine
    /// sync requests queue behind this window so no second DayPack can race the later 0x1B.
    private var taskActionPresentationCount = 0
    /// An uncertain 0x1B write keeps its original DayPack/Overview pair authoritative across
    /// firmware retries. Pending routine sync stays parked until that exact response is delivered
    /// and its delivery-state cleanup has returned.
    private var pendingTaskActionAcknowledgementBlocks = TaskActionDestinationBlocks()
    /// A durable attempted response can outlive the process. This destination-bound state stops the
    /// internal pending scheduler from spinning while still allowing a later explicit performSync
    /// call to re-query storage and clear a transient lookup failure.
    private var persistedAttemptedDeliveryBlocks = TaskActionDestinationBlocks()
    private let taskActionPresentationGate = BLEWriteGate()
    private let hardwarePagePresentationGate: HardwarePagePresentationGate
    private let taskActionAppState: AppState
    private let taskActionDayPackSender: (@MainActor () async -> UInt64?)?
    private let pendingSyncRunner: (@MainActor (_ force: Bool, _ trigger: BLESyncTrigger) -> Void)?
    private let attemptedDeliveryChecker: @Sendable (_ destinationID: String) async throws -> Bool
    private let connectedDestinationProvider: @MainActor () -> String?

    /// Connection timeout in seconds. Configurable for larger screen sizes
    /// that require longer refresh times (e.g., 7.3寸 full refresh ~12s).
    public var connectionTimeoutSeconds: TimeInterval = 30

    private init() {
        hardwarePagePresentationGate = .shared
        taskActionAppState = .shared
        taskActionDayPackSender = nil
        pendingSyncRunner = nil
        attemptedDeliveryChecker = { destinationID in
            try await LocalStorage.shared.hasAttemptedTaskListSnapshotDelivery(
                for: destinationID
            )
        }
        connectedDestinationProvider = {
            let service = BLEService.shared
            guard service.connectionState.isConnected else { return nil }
            return service.taskListSnapshotDestinationID
        }
    }

#if DEBUG
    static func makeForTestingTaskActionPresentation(
        appState: AppState,
        sendFinalDayPack: @escaping @MainActor () async -> UInt64?,
        runScheduledSync: (@MainActor (_ force: Bool, _ trigger: BLESyncTrigger) -> Void)? = nil,
        hardwarePagePresentationGate: HardwarePagePresentationGate = .shared,
        attemptedDeliveryChecker: @escaping @Sendable (
            _ destinationID: String
        ) async throws -> Bool = { _ in false },
        connectedDestinationProvider: @escaping @MainActor () -> String? = { nil }
    ) -> BLESyncCoordinator {
        BLESyncCoordinator(
            hardwarePagePresentationGate: hardwarePagePresentationGate,
            taskActionAppState: appState,
            taskActionDayPackSender: sendFinalDayPack,
            pendingSyncRunner: runScheduledSync,
            attemptedDeliveryChecker: attemptedDeliveryChecker,
            connectedDestinationProvider: connectedDestinationProvider
        )
    }

    private init(
        hardwarePagePresentationGate: HardwarePagePresentationGate,
        taskActionAppState: AppState,
        taskActionDayPackSender: @escaping @MainActor () async -> UInt64?,
        pendingSyncRunner: (@MainActor (_ force: Bool, _ trigger: BLESyncTrigger) -> Void)?,
        attemptedDeliveryChecker: @escaping @Sendable (
            _ destinationID: String
        ) async throws -> Bool,
        connectedDestinationProvider: @escaping @MainActor () -> String?
    ) {
        self.hardwarePagePresentationGate = hardwarePagePresentationGate
        self.taskActionAppState = taskActionAppState
        self.taskActionDayPackSender = taskActionDayPackSender
        self.pendingSyncRunner = pendingSyncRunner
        self.attemptedDeliveryChecker = attemptedDeliveryChecker
        self.connectedDestinationProvider = connectedDestinationProvider
    }

    func setSyncingForTesting(_ isSyncing: Bool) {
        self.isSyncing = isSyncing
        if !isSyncing {
            schedulePendingSyncIfPossible()
        }
    }

    func shouldDeferForPersistedAttemptedDeliveryForTesting(
        force: Bool,
        trigger: BLESyncTrigger
    ) async -> Bool {
        await shouldDeferForPersistedAttemptedDelivery(
            force: force,
            trigger: trigger,
            missingDestinationBlocks: false
        )
    }

    func shouldDeferRoutineDayPackWriteForTesting(
        force: Bool,
        trigger: BLESyncTrigger
    ) async -> Bool {
        await shouldDeferRoutineDayPackWrite(force: force, trigger: trigger)
    }
#endif

    private func shouldSendFullTaskLibraryForConnectedDevice() async -> Bool {
        guard let destinationID = connectedDestinationProvider(), !destinationID.isEmpty else {
            return false
        }
        let committedSnapshot: TaskLibraryCommittedSnapshot?
        let pendingDelivery: TaskLibraryPendingDelivery?
        do {
            committedSnapshot = try await localStorage.loadTaskLibraryCommittedSnapshot(
                for: destinationID
            )
            pendingDelivery = try await localStorage.loadTaskLibraryPendingDelivery(
                for: destinationID
            )
        } catch {
            ErrorReporter.log(error, context: "BLESyncCoordinator.loadTaskLibraryDeliveryState")
            return true
        }
        let pendingMatchesCurrent = pendingDelivery?.validation.matchesCurrentSource() == true
            && Self.pendingTaskLibraryBaseMatches(
                pendingDelivery,
                committedState: committedSnapshot?.state
            )
        let currentPersona = TaskLibraryPhaseSourceFingerprint.persona(
            userProfile: AppState.shared.userProfile,
            customCompanions: AppState.shared.customCompanions
        )
        let personaChanged = committedSnapshot?.hasCompleteRecords == true
            && committedSnapshot?.personaFingerprint != currentPersona
        return TaskLibraryFullSyncPolicy.shouldSendFullLibrary(
            locallyCommitted: committedSnapshot?.state,
            deviceInventory: taskLibraryDeviceInventories[destinationID],
            hasPendingTransaction: pendingMatchesCurrent
        ) || committedSnapshot?.hasCompleteRecords == false
            || personaChanged
            || AppState.shared.taskLibraryReadyUpdate() != nil
    }

    private func sendFullTaskLibraryIfNeeded(
        tasks: [TaskItem],
        userProfile: UserProfile,
        customCompanions: [CustomCompanion],
        allowedReadyUpdate: TaskLibraryReadyUpdate?,
        preservesPendingStableChanges: Bool,
        expectedTaskStateVersion: UInt64,
        expectedCompanionIdentityFingerprint: String
    ) async throws {
        guard let destinationID = connectedDestinationProvider(), !destinationID.isEmpty else {
            return
        }
        // 0x23 的「今天」与 0x24 共用同一对时间源：任务库自 v2.16.0（2026-08-04 客户拍板）
        // 只纳入当天任务，跨日边界必须与当天内容包一致。
        let now = AppState.shared.taskLibraryNowProvider()
        let calendar = AppState.shared.dailyContentCalendarProvider()

        var committedSnapshot: TaskLibraryCommittedSnapshot?
        var persistedPending: TaskLibraryPendingDelivery?
        do {
            committedSnapshot = try await localStorage.loadTaskLibraryCommittedSnapshot(
                for: destinationID
            )
            persistedPending = try await localStorage.loadTaskLibraryPendingDelivery(
                for: destinationID
            )
        } catch {
            ErrorReporter.log(error, context: "BLESyncCoordinator.loadTaskLibraryDeliveryState")
            committedSnapshot = nil
            persistedPending = nil
        }
        let requiresFullLibrary = TaskLibraryFullSyncPolicy.shouldSendFullLibrary(
            locallyCommitted: committedSnapshot?.state,
            deviceInventory: taskLibraryDeviceInventories[destinationID],
            hasPendingTransaction: false
        ) || committedSnapshot?.hasCompleteRecords == false
        let currentPersona = TaskLibraryPhaseSourceFingerprint.persona(
            userProfile: userProfile,
            customCompanions: customCompanions
        )
        let personaChanged = committedSnapshot?.hasCompleteRecords == true
            && committedSnapshot?.personaFingerprint != currentPersona
        let pendingIsSupersededByComplete = allowedReadyUpdate?.scope == .complete
            && persistedPending?.updateScope != .complete
        let pendingMatchesCurrent = !pendingIsSupersededByComplete
            && persistedPending?.validation.matchesCurrentSource() == true
            && persistedPending?.personaFingerprint == currentPersona
            && Self.pendingTaskLibraryBaseMatches(
                persistedPending,
                committedState: committedSnapshot?.state
            )
        guard requiresFullLibrary || personaChanged || pendingMatchesCurrent
                || allowedReadyUpdate != nil else {
            return
        }

        isTaskLibraryTransactionInFlight = true
        defer { isTaskLibraryTransactionInFlight = false }
        let delivery: TaskLibraryPendingDelivery
        if let persistedPending, pendingMatchesCurrent {
            delivery = persistedPending
        } else {
            let scope: TaskLibraryUpdateScope
            let capturedGeneration: UInt64
            if requiresFullLibrary || personaChanged {
                scope = preservesPendingStableChanges
                    ? allowedReadyUpdate?.scope ?? .taskRemovals([])
                    : .complete
                capturedGeneration = AppState.shared.taskLibraryStabilityState.generation
            } else if let readyUpdate = allowedReadyUpdate {
                scope = readyUpdate.scope
                capturedGeneration = readyUpdate.generation
            } else {
                return
            }

            var phaseTexts = AppState.shared.currentPreparedTaskLibraryPhaseTexts(for: tasks)
            if committedSnapshot == nil || personaChanged {
                // A first binding has no prior lines to reuse and is not delayed by the edit
                // stability window. Give its initial AI preparation the normal bounded chance.
                let initial = await taskLibraryPhaseTextService.prepare(
                    tasks: tasks,
                    userProfile: userProfile,
                    customCompanions: customCompanions,
                    now: now,
                    calendar: calendar
                )
                phaseTexts.merge(initial) { _, newest in newest }
            }
            let plannedUpdate = try TaskLibraryUpdatePlanner.makeUpdate(
                tasks: tasks,
                baseline: committedSnapshot,
                version: Self.nextTaskLibraryVersion(
                    after: persistedPending?.transaction.version ?? committedSnapshot?.state.version
                ),
                scope: scope,
                preparedPhaseTexts: phaseTexts,
                userProfile: userProfile,
                customCompanions: customCompanions,
                now: now,
                calendar: calendar,
                forceFullTransaction: requiresFullLibrary || personaChanged
            )
            let preparedUpdate: TaskLibraryPreparedUpdate
            if preservesPendingStableChanges, requiresFullLibrary || personaChanged {
                preparedUpdate = TaskLibraryPreparedUpdate(
                    transaction: plannedUpdate.transaction,
                    targetRecords: plannedUpdate.targetRecords,
                    phaseSourceFingerprints: plannedUpdate.phaseSourceFingerprints,
                    validation: Self.pendingValidationForFrozenUpdate(
                        scope: scope,
                        plannedValidation: plannedUpdate.validation
                    ),
                    personaFingerprint: plannedUpdate.personaFingerprint
                )
            } else {
                preparedUpdate = plannedUpdate
            }
            if preparedUpdate.transaction.kind == .incremental,
               preparedUpdate.transaction.records.isEmpty,
               preparedUpdate.transaction.deletedTaskIDs.isEmpty {
                try await localStorage.removeTaskLibraryPendingDelivery(for: destinationID)
                AppState.shared.markTaskLibraryUpdateCommitted(
                    scope: scope,
                    generation: capturedGeneration
                )
                return
            }
            delivery = TaskLibraryPendingDelivery(
                preparedUpdate: preparedUpdate,
                updateScope: scope,
                capturedStabilityGeneration: capturedGeneration
            )
            // Validate the exact wire shape before making it the durable retry candidate. A local
            // duplicate/oversized identifier must not poison every future connection with an
            // unencodable pending transaction.
            _ = try TaskLibraryCodec.committedState(for: delivery.transaction)
            try await localStorage.saveTaskLibraryPendingDelivery(
                delivery,
                for: destinationID
            )
        }

        let pendingState = try TaskLibraryCodec.committedState(for: delivery.transaction)
        pendingTaskLibraries[destinationID] = pendingState
        _ = try await taskLibraryDeliveryRetrier.deliver(delivery.transaction) { transaction in
            try await self.sendTaskLibraryAttempt(
                transaction,
                expectedState: pendingState,
                expectedDestinationID: destinationID,
                expectedTaskStateVersion: expectedTaskStateVersion,
                expectedCompanionIdentityFingerprint: expectedCompanionIdentityFingerprint
            )
        }
        let didClearPending = try await recordTaskLibraryCommit(
            pendingState,
            destinationID: destinationID,
            pendingDelivery: delivery,
            clearPendingRequested: true
        )
        guard didClearPending else {
            throw BLEError.staleTaskSnapshot
        }
        if let scope = delivery.updateScope,
           let generation = delivery.capturedStabilityGeneration {
            AppState.shared.markTaskLibraryUpdateCommitted(
                scope: scope,
                generation: generation
            )
        }
    }

    private func sendTaskLibraryAttempt(
        _ transaction: TaskLibraryTransaction,
        expectedState: TaskLibraryCommittedState,
        expectedDestinationID: String,
        expectedTaskStateVersion: UInt64,
        expectedCompanionIdentityFingerprint: String
    ) async throws -> TaskLibraryCommitAcknowledgement {
        let registration = taskLibraryAcknowledgementGate.register(
            expected: expectedState,
            expectedDestinationID: expectedDestinationID,
            timeout: .seconds(5)
        )
        do {
            try await bleService.sendTaskLibraryTransaction(
                transaction,
                expectedTaskStateVersion: expectedTaskStateVersion,
                expectedDestinationID: expectedDestinationID,
                validateAdditionalSnapshot: {
                    guard Self.companionIdentityFingerprint(AppState.shared)
                            == expectedCompanionIdentityFingerprint else {
                        throw BLEError.staleTaskSnapshot
                    }
                }
            )
        } catch {
            taskLibraryAcknowledgementGate.fail(error)
            throw error
        }

        return try await withTaskCancellationHandler {
            try await taskLibraryAcknowledgementGate.value(for: registration)
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.taskLibraryAcknowledgementGate.fail(CancellationError())
            }
        }
    }

    private func recordTaskLibraryCommit(
        _ state: TaskLibraryCommittedState,
        destinationID: String,
        pendingDelivery: TaskLibraryPendingDelivery?,
        clearPendingRequested: Bool
    ) async throws -> Bool {
        let deliveryState = try pendingDelivery.map {
            try TaskLibraryCodec.committedState(for: $0.transaction)
        }
        if deliveryState == state, let pendingDelivery {
            try await localStorage.saveTaskLibraryCommittedSnapshot(
                TaskLibraryCommittedSnapshot(
                    state: state,
                    records: pendingDelivery.targetRecords,
                    phaseSourceFingerprints: pendingDelivery.phaseSourceFingerprints,
                    personaFingerprint: pendingDelivery.personaFingerprint
                ),
                for: destinationID
            )
        } else {
            try await localStorage.saveTaskLibraryCommittedState(state, for: destinationID)
        }
        var didClearPending = clearPendingRequested
        if clearPendingRequested, let pendingDelivery {
            didClearPending = deliveryState == state
                && pendingDelivery.validation.matchesCurrentSource()
        }
        if didClearPending {
            try await localStorage.removeTaskLibraryPendingDelivery(for: destinationID)
            if let pendingDelivery,
               !pendingDelivery.validation.matchesCurrentSource() {
                // The source changed while the storage actor was removing the old marker. Restore
                // the frozen delivery so the queued sync can replace it with the new source.
                try await localStorage.saveTaskLibraryPendingDelivery(
                    pendingDelivery,
                    for: destinationID
                )
                didClearPending = false
            }
        }
        if didClearPending {
            if pendingTaskLibraries[destinationID] == state {
                pendingTaskLibraries.removeValue(forKey: destinationID)
            }
        } else if pendingTaskLibraries[destinationID] == state {
            // The device committed this exact version, but the App source changed before the ACK.
            // Keep only the durable marker that forces a newer rebuild; a duplicate old ACK must
            // not enter the late-result path and clear that marker.
            pendingTaskLibraries.removeValue(forKey: destinationID)
        }
        taskLibraryDeviceInventories[destinationID] = .committed(state)
        return didClearPending
    }

    /// Restarts at epoch 1 after a reinstall. That is safe only because `0x30` reports the device's
    /// committed task-library state: with no local binding record the App must send a Full
    /// transaction (Base = 0, unconditional replace, §4.22 rule 3), so the device never orders
    /// `0x23` versions against its own. Daily content seeds differently and for a different reason
    /// — read `nextDailyContentVersion` before making the two match.
    private static func nextTaskLibraryVersion(
        after version: TaskLibraryVersion?
    ) -> TaskLibraryVersion {
        guard let version else {
            return TaskLibraryVersion(epoch: 1, revision: 1)
        }
        if version.revision < .max {
            return TaskLibraryVersion(epoch: version.epoch, revision: version.revision + 1)
        }
        let nextEpoch = version.epoch == .max ? UInt32(1) : version.epoch + 1
        return TaskLibraryVersion(epoch: nextEpoch, revision: 1)
    }

    private static func pendingTaskLibraryBaseMatches(
        _ delivery: TaskLibraryPendingDelivery?,
        committedState: TaskLibraryCommittedState?
    ) -> Bool {
        guard let delivery else { return false }
        switch delivery.transaction.kind {
        case .full:
            return true
        case .incremental:
            return delivery.transaction.baseState == committedState
        }
    }

    public func nextSyncDate() async -> Date {
        let lastSync = await localStorage.loadLastBleSyncTime()
        return policy.nextSyncTime(now: Date(), lastSync: lastSync)
    }

    func reconcileTaskLibraryInventory(
        _ inventory: TaskLibraryDeviceInventory,
        destinationID: String
    ) async -> Bool {
        guard !destinationID.isEmpty else { return false }
        taskLibraryDeviceInventories[destinationID] = inventory
        pendingTaskLibraries.removeValue(forKey: destinationID)
        do {
            switch inventory {
            case .missing:
                try await localStorage.removeTaskLibraryCommittedState(for: destinationID)
                return true
            case let .committed(state):
                if let pending = try await localStorage.loadTaskLibraryPendingDelivery(
                    for: destinationID
                ), try TaskLibraryCodec.committedState(for: pending.transaction) == state {
                    // The device may have committed the transaction while its 0x23 ACK was lost.
                    // Its reconnect inventory is authoritative: promote the exact frozen target
                    // instead of degrading the local baseline to a state-only marker and rebuilding
                    // the same library with fallback copy.
                    try await localStorage.saveTaskLibraryCommittedSnapshot(
                        TaskLibraryCommittedSnapshot(
                            state: state,
                            records: pending.targetRecords,
                            phaseSourceFingerprints: pending.phaseSourceFingerprints,
                            personaFingerprint: pending.personaFingerprint
                        ),
                        for: destinationID
                    )
                    try await localStorage.removeTaskLibraryPendingDelivery(for: destinationID)
                    if pending.validation.matchesCurrentSource(),
                       let scope = pending.updateScope,
                       let generation = pending.capturedStabilityGeneration {
                        AppState.shared.markTaskLibraryUpdateCommitted(
                            scope: scope,
                            generation: generation
                        )
                    }
                    return false
                }
                guard try await localStorage.loadTaskLibraryCommittedState(
                    for: destinationID
                ) != nil else {
                    return true
                }
                try await localStorage.saveTaskLibraryCommittedState(state, for: destinationID)
                return false
            }
        } catch {
            ErrorReporter.log(error, context: "BLESyncCoordinator.reconcileTaskLibraryInventory")
            return inventory == .missing
        }
    }

    func handleTaskLibraryCommitAcknowledgement(
        _ acknowledgement: TaskLibraryCommitAcknowledgement,
        destinationID: String
    ) async {
        if taskLibraryAcknowledgementGate.receive(
            acknowledgement,
            destinationID: destinationID
        ) {
            let acknowledgedState = TaskLibraryCommittedState(
                version: acknowledgement.version,
                contentCRC32: acknowledgement.contentCRC32
            )
            if pendingTaskLibraries[destinationID] == acknowledgedState {
                // The sending coroutine owns durable cleanup after it rechecks the source snapshot.
                // Removing this connection-only marker now prevents a duplicate ACK from racing
                // through the late-result path and deleting a newer pending source.
                pendingTaskLibraries.removeValue(forKey: destinationID)
            }
            return
        }
        guard !destinationID.isEmpty,
              let pending = pendingTaskLibraries[destinationID],
              pending.version == acknowledgement.version,
              pending.contentCRC32 == acknowledgement.contentCRC32 else {
            return
        }
        guard acknowledgement.result == .committed else { return }
        let persistedPending: TaskLibraryPendingDelivery?
        do {
            persistedPending = try await localStorage.loadTaskLibraryPendingDelivery(
                for: destinationID
            )
        } catch {
            ErrorReporter.log(
                error,
                context: "BLESyncCoordinator.handleTaskLibraryCommitAcknowledgement.pending"
            )
            do {
                _ = try await recordTaskLibraryCommit(
                    pending,
                    destinationID: destinationID,
                    pendingDelivery: nil,
                    clearPendingRequested: false
                )
            } catch {
                ErrorReporter.log(
                    error,
                    context: "BLESyncCoordinator.handleTaskLibraryCommitAcknowledgement.commit"
                )
            }
            return
        }
        do {
            let didClearPending = try await recordTaskLibraryCommit(
                pending,
                destinationID: destinationID,
                pendingDelivery: persistedPending,
                clearPendingRequested: true
            )
            if didClearPending,
               let scope = persistedPending?.updateScope,
               let generation = persistedPending?.capturedStabilityGeneration {
                AppState.shared.markTaskLibraryUpdateCommitted(
                    scope: scope,
                    generation: generation
                )
            }
        } catch {
            ErrorReporter.log(error, context: "BLESyncCoordinator.handleTaskLibraryCommitAcknowledgement")
        }
    }

    func handleTaskLibraryDisconnected(destinationID: String) {
        taskLibraryAcknowledgementGate.fail(BLEError.disconnected)
        guard !destinationID.isEmpty else { return }
        pendingTaskLibraries.removeValue(forKey: destinationID)
        taskLibraryDeviceInventories.removeValue(forKey: destinationID)
    }

    func handleAllTaskLibrariesUnbound() async {
        taskLibraryAcknowledgementGate.fail(BLEError.disconnected)
        dailyContentAcknowledgementGate.fail(BLEError.disconnected)
        pendingTaskLibraries.removeAll()
        taskLibraryDeviceInventories.removeAll()
        pendingDailyContents.removeAll()
        do {
            try await localStorage.clearTaskLibraryCommittedStates()
        } catch {
            ErrorReporter.log(error, context: "BLESyncCoordinator.handleAllTaskLibrariesUnbound")
        }
        do {
            try await localStorage.clearTaskLibraryPendingDeliveries()
        } catch {
            ErrorReporter.log(error, context: "BLESyncCoordinator.handleAllTaskLibrariesUnbound.pending")
        }
        do {
            try await localStorage.clearDailyContentCommittedSnapshots()
        } catch {
            ErrorReporter.log(error, context: "BLESyncCoordinator.handleAllTaskLibrariesUnbound.daily")
        }
        do {
            try await localStorage.clearDailyContentPendingDeliveries()
        } catch {
            ErrorReporter.log(error, context: "BLESyncCoordinator.handleAllTaskLibrariesUnbound.dailyPending")
        }
    }

    private func shouldSendDailyContentForConnectedDevice(
        presentationSourceFingerprint: String,
        readyGeneration: UInt64?
    ) async -> Bool {
        guard let destinationID = connectedDestinationProvider(), !destinationID.isEmpty else {
            return false
        }
        do {
            let committed = try await localStorage.loadDailyContentCommittedSnapshot(
                for: destinationID
            )
            let pending = try await localStorage.loadDailyContentPendingDelivery(
                for: destinationID
            )
            return readyGeneration != nil
                || committed?.sourceFingerprint != presentationSourceFingerprint
                || pending != nil
        } catch {
            ErrorReporter.log(error, context: "BLESyncCoordinator.loadDailyContentDeliveryState")
            return true
        }
    }

    private func sendDailyContentIfNeeded(
        input: DailyContentGenerationInput,
        presentationSourceFingerprint: String,
        currentSourceFingerprint: String,
        capturedStabilityGeneration: UInt64?
    ) async throws {
        guard let destinationID = connectedDestinationProvider(), !destinationID.isEmpty else {
            return
        }

        let committed = try await localStorage.loadDailyContentCommittedSnapshot(
            for: destinationID
        )
        var pending = try await localStorage.loadDailyContentPendingDelivery(
            for: destinationID
        )
        var latestKnownVersion = committed?.state.version

        if let stalePending = pending,
           stalePending.sourceFingerprint != presentationSourceFingerprint {
            latestKnownVersion = Self.newerDailyContentVersion(
                latestKnownVersion,
                stalePending.transaction.version
            )
            try await localStorage.removeDailyContentPendingDelivery(for: destinationID)
            // The source changed, so only the latest replacement remains retryable. The old ACK
            // may have been lost after firmware committed it; advance beyond its version to avoid
            // reusing the same version with different bytes.
            pendingDailyContents.removeValue(forKey: destinationID)
            pending = nil
        }

        if committed?.sourceFingerprint == presentationSourceFingerprint, pending == nil {
            AppState.shared.markDailyContentCommitted(
                capturedGeneration: capturedStabilityGeneration
            )
            return
        }

        let delivery: DailyContentPendingDelivery
        if let pending {
            delivery = pending
        } else {
            let preparedInput = DailyContentGenerationInput(
                now: input.now,
                calendar: input.calendar,
                events: input.events,
                tasks: input.tasks,
                pet: input.pet,
                weather: input.weather,
                deviceMode: input.deviceMode,
                userProfile: input.userProfile,
                customCompanions: input.customCompanions,
                usageDays: input.usageDays,
                sceneID: input.sceneID,
                focusMinutes: input.focusMinutes,
                previousPackage: committed?.package,
                previousEventFingerprints: committed?.eventFingerprints ?? [:],
                previousPersonaFingerprint: committed?.personaFingerprint ?? "",
                previousEventDialogueFingerprint: committed?.eventDialogueFingerprint ?? "",
                previousStaticCopyFingerprint: committed?.staticCopyFingerprint ?? ""
            )
            let package = await dailyContentPackageGenerator.generate(input: preparedInput)
            guard connectedDestinationProvider() == destinationID else {
                throw BLEPresentationDestinationError.changed
            }
            if capturedStabilityGeneration != nil {
                let latestSource = DailyContentSource.packageSourceFingerprint(
                    events: AppState.shared.events,
                    tasks: AppState.shared.tasks,
                    pet: AppState.shared.pet,
                    usageDays: input.usageDays,
                    sceneID: input.sceneID,
                    focusMinutes: input.focusMinutes,
                    at: input.now,
                    calendar: input.calendar,
                    userProfile: AppState.shared.userProfile,
                    customCompanions: AppState.shared.customCompanions
                )
                guard latestSource == currentSourceFingerprint else {
                    throw DailyContentDeliveryError.sourceChanged
                }
            }
            let transaction = DailyContentTransaction(
                version: Self.nextDailyContentVersion(after: latestKnownVersion),
                package: package
            )
            delivery = DailyContentPendingDelivery(
                transaction: transaction,
                sourceFingerprint: presentationSourceFingerprint,
                eventSourceFingerprint: DailyContentSource.sourceFingerprint(
                    events: input.events,
                    at: input.now,
                    calendar: input.calendar,
                    userProfile: input.userProfile,
                    customCompanions: input.customCompanions
                ),
                eventFingerprints: DailyContentSource.eventFingerprints(
                    input.events,
                    at: input.now,
                    calendar: input.calendar
                ),
                personaFingerprint: DailyContentSource.personaFingerprint(
                    userProfile: input.userProfile,
                    customCompanions: input.customCompanions
                ),
                eventDialogueFingerprint: DailyContentSource.eventDialogueFingerprint(
                    pet: input.pet,
                    userProfile: input.userProfile,
                    customCompanions: input.customCompanions
                ),
                staticCopyFingerprint: DailyContentSource.staticCopyFingerprint(
                    eventTitles: DailyContentSource.todayEvents(
                        from: input.events,
                        at: input.now,
                        calendar: input.calendar
                    ).map(\.title),
                    tasks: input.tasks,
                    pet: input.pet,
                    usageDays: input.usageDays,
                    sceneID: input.sceneID,
                    userProfile: input.userProfile,
                    customCompanions: input.customCompanions
                ),
                capturedStabilityGeneration: capturedStabilityGeneration
            )
            try await localStorage.saveDailyContentPendingDelivery(
                delivery,
                for: destinationID
            )
        }

        let expected = try DailyContentCodec.committedState(for: delivery.transaction)
        pendingDailyContents[destinationID] = expected
        isDailyContentTransactionInFlight = true
        defer { isDailyContentTransactionInFlight = false }
        _ = try await dailyContentDeliveryRetrier.deliver(delivery.transaction) { transaction in
            try await self.sendDailyContentAttempt(
                transaction,
                expected: expected,
                destinationID: destinationID
            )
        }

        guard connectedDestinationProvider() == destinationID else {
            throw BLEPresentationDestinationError.changed
        }
        try await recordDailyContentCommit(
            expected,
            destinationID: destinationID,
            pendingDelivery: delivery
        )
        pendingDailyContents.removeValue(forKey: destinationID)
        AppState.shared.markDailyContentCommitted(
            capturedGeneration: delivery.capturedStabilityGeneration
        )
    }

    private func sendDailyContentAttempt(
        _ transaction: DailyContentTransaction,
        expected: DailyContentCommittedState,
        destinationID: String
    ) async throws -> DailyContentCommitAcknowledgement {
        let registration = dailyContentAcknowledgementGate.register(
            expected: expected,
            expectedDestinationID: destinationID,
            timeout: .seconds(120)
        )
        do {
            try await bleService.sendDailyContentTransaction(
                transaction,
                expectedDestinationID: destinationID
            )
        } catch {
            dailyContentAcknowledgementGate.fail(error)
            throw error
        }
        return try await withTaskCancellationHandler {
            try await dailyContentAcknowledgementGate.value(for: registration)
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.dailyContentAcknowledgementGate.fail(CancellationError())
            }
        }
    }

    private func recordDailyContentCommit(
        _ state: DailyContentCommittedState,
        destinationID: String,
        pendingDelivery: DailyContentPendingDelivery
    ) async throws {
        guard try DailyContentCodec.committedState(for: pendingDelivery.transaction) == state else {
            return
        }
        try await localStorage.saveDailyContentCommittedSnapshot(
            DailyContentCommittedSnapshot(
                state: state,
                package: pendingDelivery.transaction.package,
                eventFingerprints: pendingDelivery.eventFingerprints,
                personaFingerprint: pendingDelivery.personaFingerprint,
                eventDialogueFingerprint: pendingDelivery.eventDialogueFingerprint,
                staticCopyFingerprint: pendingDelivery.staticCopyFingerprint,
                sourceFingerprint: pendingDelivery.sourceFingerprint
            ),
            for: destinationID
        )
        let persisted = try await localStorage.loadDailyContentPendingDelivery(for: destinationID)
        if persisted?.transaction == pendingDelivery.transaction {
            try await localStorage.removeDailyContentPendingDelivery(for: destinationID)
        }
    }

    func handleDailyContentCommitAcknowledgement(
        _ acknowledgement: DailyContentCommitAcknowledgement,
        destinationID: String
    ) async {
        if dailyContentAcknowledgementGate.receive(
            acknowledgement,
            destinationID: destinationID
        ) {
            return
        }
        guard !destinationID.isEmpty,
              acknowledgement.result == .committed,
              pendingDailyContents[destinationID] == DailyContentCommittedState(
                version: acknowledgement.version,
                contentCRC32: acknowledgement.contentCRC32
              ) else {
            return
        }
        do {
            guard let pending = try await localStorage.loadDailyContentPendingDelivery(
                for: destinationID
            ) else { return }
            let state = try DailyContentCodec.committedState(for: pending.transaction)
            guard state.version == acknowledgement.version,
                  state.contentCRC32 == acknowledgement.contentCRC32 else { return }
            try await recordDailyContentCommit(
                state,
                destinationID: destinationID,
                pendingDelivery: pending
            )
            pendingDailyContents.removeValue(forKey: destinationID)
            if pending.matchesCurrentSource() {
                AppState.shared.markDailyContentCommitted(
                    capturedGeneration: pending.capturedStabilityGeneration
                )
            }
        } catch {
            ErrorReporter.log(error, context: "BLESyncCoordinator.handleDailyContentCommitAcknowledgement")
        }
    }

    func handleDailyContentDisconnected(destinationID: String) {
        dailyContentAcknowledgementGate.fail(BLEError.disconnected)
        guard !destinationID.isEmpty else { return }
        pendingDailyContents.removeValue(forKey: destinationID)
    }

    /// Seeds a fresh epoch from wall-clock seconds instead of restarting at 1. `0x30` carries a
    /// `TaskLibraryState` field but no daily-content counterpart, so unlike the task library the App
    /// cannot learn what a device still holds from a previous install; a clock-derived epoch keeps
    /// a reinstall's first version off a value that device may already have committed. Do not
    /// unify this with `nextTaskLibraryVersion` — each is safe for its own reason.
    private static func nextDailyContentVersion(
        after previous: DailyContentVersion?
    ) -> DailyContentVersion {
        guard let previous else {
            let seconds = UInt64(max(1, Int(Date().timeIntervalSince1970)))
            return DailyContentVersion(
                epoch: UInt32(truncatingIfNeeded: seconds),
                revision: 1
            )
        }
        if previous.revision < .max {
            return DailyContentVersion(
                epoch: previous.epoch,
                revision: previous.revision + 1
            )
        }
        return DailyContentVersion(
            epoch: previous.epoch == .max ? 1 : previous.epoch + 1,
            revision: 1
        )
    }

    private static func newerDailyContentVersion(
        _ lhs: DailyContentVersion?,
        _ rhs: DailyContentVersion
    ) -> DailyContentVersion {
        guard let lhs else { return rhs }
        if lhs.epoch != rhs.epoch { return lhs.epoch > rhs.epoch ? lhs : rhs }
        return lhs.revision >= rhs.revision ? lhs : rhs
    }

#if DEBUG
    func setPendingTaskLibraryForTesting(
        _ state: TaskLibraryCommittedState,
        destinationID: String
    ) {
        pendingTaskLibraries[destinationID] = state
    }

    func clearPendingTaskLibraryForTesting(destinationID: String) {
        pendingTaskLibraries.removeValue(forKey: destinationID)
        taskLibraryDeviceInventories.removeValue(forKey: destinationID)
    }

    func registerTaskLibraryAcknowledgementForTesting(
        _ state: TaskLibraryCommittedState,
        destinationID: String
    ) {
        _ = taskLibraryAcknowledgementGate.register(
            expected: state,
            expectedDestinationID: destinationID,
            timeout: .seconds(86_400)
        )
    }
#endif

    public func performSync(
        force: Bool = false,
        trigger: BLESyncTrigger = .automatic
    ) async {
        // Debounced AppState sync tasks are cancellable. A manual refresh cancels the old task
        // before collecting all external sources, so a timer that has just fired must not continue
        // through DayPack generation and start an obsolete write.
        guard !Task.isCancelled else { return }
        // 并发守卫：keep-alive 默认开后连接常驻，多触发源（后台刷新 / 硬件 0x20·0x30 / 指纹变化）可能并发进入。
        // 以前靠"已连接→.connectionInProgress"意外串行；连接跳过后需显式守卫，否则会重复发整轮 + 帧交错。
        // @MainActor 下在首个 await 前同步置位，保证原子。被丢弃的 force:true 记下、收尾后补跑一次——
        // 否则在途的 force:false 若随后被 shouldSync 拦下，硬件的强制刷新就丢了。
        guard !isSyncing, taskActionPresentationCount == 0 else {
            queuePendingSync(force: force, trigger: trigger)
            return
        }
        isSyncing = true
        var shouldSchedulePendingSyncOnExit = true
        defer {
            isSyncing = false
            if shouldSchedulePendingSyncOnExit {
                schedulePendingSyncIfPossible()
            }
        }

        // Re-query before the in-memory ACK guard. A prior storage read may have failed, and an
        // explicit refresh must be able to prove that the durable attempted response is now gone.
        if await shouldDeferForPersistedAttemptedDelivery(
            force: force,
            trigger: trigger,
            missingDestinationBlocks: true
        ) {
            shouldSchedulePendingSyncOnExit = false
            return
        }
        guard taskActionPresentationCount == 0,
              !pendingTaskActionAcknowledgementBlocks.blocks(
                connectedDestinationProvider()
              ) else {
            queuePendingSync(force: force, trigger: trigger)
            return
        }

        let now = Date()
        let lastSync = await localStorage.loadLastBleSyncTime()

        let appState = AppState.shared
        // 冷启动防御：0x20/0x30 可在 loadLocalData 完成前直呼本方法，用空 tasks/events 组出
        // 空 DayPack 推上硬件（闪一屏空首页）。其余入口（syncConnectedExternalData 等）都已等待，
        // 这里补齐（幂等，加载完成后零开销）。2026-07-04 审计 F3。
        await appState.ensureInitialLoadComplete()
        guard !Task.isCancelled else { return }
        // v2.5.0: the hardware bubble shows the SAME line as the App home. Refresh it, then
        // feed currentPetDialogue into the DayPack so both surfaces stay in sync.
        await appState.refreshSharedPetDialogueIfNeeded()
        guard !Task.isCancelled else { return }
        let sourceTaskStateVersion = appState.taskStateVersion
        let sourceIdentityFingerprint = Self.companionIdentityFingerprint(appState)
        let taskLibraryPresentation = appState.taskLibraryPresentationSnapshot()
        let presentationTasks = taskLibraryPresentation.tasks
        let presentationPetDialogue = taskLibraryPresentation.petDialogue
        let dailyContentPresentation = appState.dailyContentPresentationSnapshot()
        let presentationEvents = dailyContentPresentation.events
        let usageDays = await localStorage.loadConsecutiveDays()
        let dailyContentSceneID = appState.currentDisplaySceneId()
        let dailyContentFocusMinutes = Int(
            FocusSessionService.shared.todayFocusTimeIncludingActive(now: now) / 60
        )
        let dailyContentPresentationSourceFingerprint = DailyContentSource.packageSourceFingerprint(
            events: presentationEvents,
            tasks: presentationTasks,
            pet: appState.pet,
            usageDays: usageDays,
            sceneID: dailyContentSceneID,
            focusMinutes: dailyContentFocusMinutes,
            at: now,
            userProfile: appState.userProfile,
            customCompanions: appState.customCompanions
        )
        let currentDailyContentSourceFingerprint = DailyContentSource.packageSourceFingerprint(
            events: appState.events,
            tasks: appState.tasks,
            pet: appState.pet,
            usageDays: usageDays,
            sceneID: dailyContentSceneID,
            focusMinutes: dailyContentFocusMinutes,
            at: now,
            userProfile: appState.userProfile,
            customCompanions: appState.customCompanions
        )
        guard appState.currentPetDialogueTaskStateVersion == sourceTaskStateVersion else {
            queuePendingSync(force: force, trigger: trigger)
            return
        }
        let dayPack = await dayPackGenerator.generateDayPack(
            pet: appState.pet,
            tasks: presentationTasks,
            events: presentationEvents,
            weather: appState.weather,
            deviceMode: appState.deviceMode,
            userProfile: appState.userProfile,
            customCompanions: appState.customCompanions,
            screenSize: bleService.hardwareScreenSize,
            petDialogue: presentationPetDialogue,
            now: now
        )
        // DayPack generation also awaits event/support/settlement text. If tasks changed during
        // that work, do not let the old task/dialogue transaction reach the hardware.
        guard appState.taskStateVersion == sourceTaskStateVersion,
              Self.companionIdentityFingerprint(appState) == sourceIdentityFingerprint else {
            queuePendingSync(force: force, trigger: trigger)
            return
        }
        guard !Task.isCancelled else { return }

        let fingerprint = dayPack.stableFingerprint()
        let semanticFingerprint = dayPack.refreshSemanticFingerprint(
            allTasks: presentationTasks,
            at: now
        )
        let lastHash = await localStorage.loadLastDayPackHash()
        let lastSemanticHash = await localStorage.loadLastDayPackSemanticHash()
        let contentChanged = lastHash != fingerprint
        // Builds before this arbitration only stored the full wire hash. If the full hash is still
        // equal, the semantic baseline is exact and can be backfilled without sending a new packet.
        if !contentChanged, lastSemanticHash == nil {
            await localStorage.saveLastDayPackSemanticHash(semanticFingerprint)
        }
        let semanticContentChanged = lastSemanticHash.map { $0 != semanticFingerprint } ?? false
        let shouldSendDayPack = DayPackRefreshArbiter.shouldSend(
            trigger: trigger,
            wireContentChanged: contentChanged,
            hasActiveTimedEvent: DayPackRefreshArbiter.hasActiveTimedEvent(
                in: presentationEvents,
                at: now
            ),
            hasPreviousSemanticFingerprint: lastSemanticHash != nil,
            semanticContentChanged: semanticContentChanged
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
        // A stability deadline is process-local and can expire while BLE is disconnected. It must
        // open a connection even though no destination inventory can be queried until afterward.
        let hasReadyTaskLibraryUpdate = taskLibraryPresentation.readyUpdate != nil
        let commitsTaskLibraryBeforeDayPack = Self.commitsTaskLibraryBeforeDayPack(
            readyUpdate: taskLibraryPresentation.readyUpdate
        )
        let connectedDeviceNeedsTaskLibrarySync = await shouldSendFullTaskLibraryForConnectedDevice()
        let connectedDeviceNeedsDailyContentSync = await shouldSendDailyContentForConnectedDevice(
            presentationSourceFingerprint: dailyContentPresentationSourceFingerprint,
            readyGeneration: dailyContentPresentation.readyGeneration
        )
        let hasPriorityTaskLibrarySync = hasReadyTaskLibraryUpdate
            || connectedDeviceNeedsTaskLibrarySync
        let hasPriorityDailyContentSync = dailyContentPresentation.readyGeneration != nil
            || connectedDeviceNeedsDailyContentSync
        guard policy.shouldSync(
            now: now,
            lastSync: lastSync,
            contentChanged: shouldSendDayPack || weatherChanged,
            // Identity lives in the small 0x01 frame, not necessarily in DayPack's fingerprint.
            // It therefore owns one immediate sync round even when AI text falls back to the same
            // bytes and the routine interval has not elapsed.
            force: force || trigger.bypassesRoutineSyncInterval
                || hasPriorityTaskLibrarySync || hasPriorityDailyContentSync,
            hasPriorityCustomAvatarOperation: hasPriorityCustomAvatarOperation
        ) else {
            return
        }
        guard !Task.isCancelled else { return }

        let timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(self.connectionTimeoutSeconds))
            guard !Task.isCancelled else { return }
            // 最坏 0x15 KRI 约 2.24MB / 4472 片，限流下需 4–5 分钟。
            // 30s 超时到点先等它结束，否则同步收尾会主动提前掐断每次头像传输。
            while !Task.isCancelled,
                  self.isTaskLibraryTransactionInFlight
                    || self.isDailyContentTransactionInFlight
                    || self.policy.shouldHoldConnectionForCustomAvatar(
                        chunkedTransferInFlight: self.bleService.isChunkedTransferInFlight,
                        operationState: appState.customAvatarOperationState
                    ) {
                try? await Task.sleep(for: .seconds(5))
            }
            guard !Task.isCancelled else { return }
            // 超时只回收空闲连接。专注靠常驻 BLE + 0x20 心跳维持；这里主动断开会把
            // 正常会话错误结算为 `.disconnected`。
            if self.policy.shouldDisconnectAfterTimeout(
                isConnected: self.bleService.connectionState.isConnected,
                keepsDebugConnectionOpen: self.bleService.shouldKeepConnectionOpenForDebug,
                hasTaskActionPresentation: self.taskActionPresentationCount > 0,
                hasActiveFocusSession: FocusSessionService.shared.activeSession != nil,
                holdsCustomAvatarConnection: self.policy.shouldHoldConnectionForCustomAvatar(
                    chunkedTransferInFlight: self.bleService.isChunkedTransferInFlight,
                    operationState: appState.customAvatarOperationState
                )
            ) {
                self.bleService.disconnect()
            }
        }
        defer { timeoutTask.cancel() }

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
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        lastConnectError = error
                        #if DEBUG
                        print("[BLESyncCoordinator] Connect attempt \(attempt + 1)/3 failed: \(error.localizedDescription)")
                        #endif
                        if attempt < 2 {
                            do {
                                try await Task.sleep(for: .seconds(Double(1 << attempt)))
                            } catch is CancellationError {
                                throw CancellationError()
                            } catch {
                                // The backoff clock itself has no other recoverable failure.
                            }
                        }
                    }
                }
                // 保留底层原因：connectionFailed(error) 的描述会带上 underlying，外层 catch 即可在 Release 看到。
                guard connected else { throw BLEError.connectionFailed(lastConnectError) }
            }

            // Entry cannot know the target while disconnected. Once connection identifies the
            // device, durable attempted state is authoritative and every lookup error fails closed.
            if await shouldDeferForPersistedAttemptedDelivery(
                force: force,
                trigger: trigger,
                missingDestinationBlocks: true
            ) {
                shouldSchedulePendingSyncOnExit = false
                return
            }
            guard !pendingTaskActionAcknowledgementBlocks.blocks(
                connectedDestinationProvider()
            ) else {
                queuePendingSync(force: force, trigger: trigger)
                return
            }

            // `completeSecureConnection` opens this window before reporting success. Re-check it
            // here because keep-alive/parallel triggers can observe `.connected` while the 0x21
            // batch is still being processed and otherwise bypass connection waiting entirely.
            guard await bleService.requestEventLogsIfNeeded() else {
                throw BLEError.connectionFailed(nil)
            }
            guard appState.taskStateVersion == sourceTaskStateVersion else {
                // Offline Complete/Skip changed the source after this round generated its
                // DayPack. Keep every old byte off the wire and rebuild from the replayed state.
                queuePendingSync(force: true, trigger: trigger)
                return
            }

            if Task.isCancelled {
                if bleService.connectionState.isConnected,
                   !bleService.shouldKeepConnectionOpenForDebug,
                   taskActionPresentationCount == 0,
                   FocusSessionService.shared.activeSession == nil,
                   !policy.shouldHoldConnectionForCustomAvatar(
                    chunkedTransferInFlight: bleService.isChunkedTransferInFlight,
                    operationState: appState.customAvatarOperationState
                   ) {
                    bleService.disconnect()
                }
                return
            }

            await appState.flushPriorityCustomAvatarOperationIfNeeded()
            let dailyContentInput = DailyContentGenerationInput(
                now: now,
                events: presentationEvents,
                tasks: presentationTasks,
                pet: appState.pet,
                weather: appState.weather,
                deviceMode: appState.deviceMode,
                userProfile: appState.userProfile,
                customCompanions: appState.customCompanions,
                usageDays: usageDays,
                sceneID: dailyContentSceneID,
                focusMinutes: dailyContentFocusMinutes
            )
            var dayPackSendFailed = false
            var presentationSnapshotIsCurrent = false
            var taskLibraryCommittedBeforeDayPack = false
            _ = try await hardwarePagePresentationGate.performPresentationWrite(
                droppingIfPageTransactionIntervened: false
            ) {
                guard appState.taskStateVersion == sourceTaskStateVersion,
                      Self.companionIdentityFingerprint(appState) == sourceIdentityFingerprint,
                      appState.currentPetDialogueTaskStateVersion == sourceTaskStateVersion else {
                    return
                }
                let lastHashAtWire = await self.localStorage.loadLastDayPackHash()
                guard appState.taskStateVersion == sourceTaskStateVersion,
                      Self.companionIdentityFingerprint(appState) == sourceIdentityFingerprint else {
                    return
                }
                presentationSnapshotIsCurrent = true
                try await bleService.syncTime()
                try await bleService.sendPetStatus(
                    appState.pet,
                    companionCharacter: appState.userProfile.companionCharacter,
                    // v2.5.32: 例行 sync 恒重申自定义激活态——0x01 不再把用户图刷回内置。
                    customActive: appState.userProfile.customCompanionId != nil
                )
                // 顶栏天气走独立 Weather(0x04) 帧（协议 §4.5），每轮发送。此前 sendWeather 只挂在
                // 零调用的 syncAllData 上——硬件顶栏天气从未被更新过（2026-07-04 审计 F1）。
                // 辅助帧单独容错：写失败只记日志、不算轮失败——顶栏装饰不能阻断后面的 DayPack
                // 重试与离线事件补传（与 DayPack/eventLog 的既有"失败不阻断"哲学一致）。
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

                guard appState.taskStateVersion == sourceTaskStateVersion,
                      Self.companionIdentityFingerprint(appState) == sourceIdentityFingerprint else {
                    presentationSnapshotIsCurrent = false
                    return
                }
                if commitsTaskLibraryBeforeDayPack {
                    // At the stability deadline, the new Overview must not appear until the
                    // matching offline task details are durably committed by firmware. A lost or
                    // rejected 0x23 therefore leaves the old DayPack visible and retries later.
                    try await sendFullTaskLibraryIfNeeded(
                        tasks: taskLibraryPresentation.tasks,
                        userProfile: appState.userProfile,
                        customCompanions: appState.customCompanions,
                        allowedReadyUpdate: taskLibraryPresentation.readyUpdate,
                        preservesPendingStableChanges: taskLibraryPresentation.usesFrozenBaseline,
                        expectedTaskStateVersion: sourceTaskStateVersion,
                        expectedCompanionIdentityFingerprint: sourceIdentityFingerprint
                    )
                    taskLibraryCommittedBeforeDayPack = true
                    guard appState.taskStateVersion == sourceTaskStateVersion,
                          Self.companionIdentityFingerprint(appState)
                            == sourceIdentityFingerprint else {
                        presentationSnapshotIsCurrent = false
                        return
                    }
                }
                do {
                    try await sendDailyContentIfNeeded(
                        input: dailyContentInput,
                        presentationSourceFingerprint: dailyContentPresentationSourceFingerprint,
                        currentSourceFingerprint: currentDailyContentSourceFingerprint,
                        capturedStabilityGeneration: dailyContentPresentation.readyGeneration
                    )
                } catch DailyContentDeliveryError.sourceChanged {
                    presentationSnapshotIsCurrent = false
                    return
                }
                guard appState.taskStateVersion == sourceTaskStateVersion,
                      Self.companionIdentityFingerprint(appState)
                        == sourceIdentityFingerprint else {
                    presentationSnapshotIsCurrent = false
                    return
                }
                if Self.shouldSendPreparedDayPack(
                    requested: shouldSendDayPack,
                    lastSentFingerprint: lastHashAtWire,
                    preparedFingerprint: fingerprint,
                    hasActiveFocusSession: FocusSessionService.shared.activeSession != nil
                ) {
                    // Send DayPack with retry: 2 attempts, 500ms/1s backoff
                    var sent = false
                    var superseded = false
                    var lastWriteError: Error?
                    for attempt in 0..<2 {
                        guard !(await shouldDeferRoutineDayPackWrite(
                            force: force,
                            trigger: trigger
                        )) else {
                            presentationSnapshotIsCurrent = false
                            shouldSchedulePendingSyncOnExit = false
                            superseded = true
                            break
                        }
                        do {
                            try await bleService.sendDayPack(
                                dayPack,
                                expectedTaskStateVersion: sourceTaskStateVersion
                            )
                            sent = true
                            break
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            if let bleError = error as? BLEError,
                               case .staleTaskSnapshot = bleError {
                                superseded = true
                                queuePendingSync(force: force, trigger: trigger)
                                break
                            }
                            lastWriteError = error
                            #if DEBUG
                            print("[BLESyncCoordinator] Write attempt \(attempt + 1)/2 failed: \(error.localizedDescription)")
                            #endif
                            if attempt < 1 {
                                try? await Task.sleep(for: .milliseconds(500 * (attempt + 1)))
                            }
                        }
                    }
                    if sent {
                        await localStorage.saveLastDayPackHash(fingerprint)
                        await localStorage.saveLastDayPackSemanticHash(semanticFingerprint)
                    } else if !superseded {
                        // DayPack 是 App→硬件最核心的帧；两次写失败必须留痕，否则硬件一直显示旧数据、
                        // App 端在 Release 下毫无信号（下轮会重试，但失败本身不可见）。
                        // 不在此处 throw：后面的事件补传（requestEventLogsIfNeeded）是核心功能，
                        // 不能因显示帧写失败而放弃；整轮成败在末尾按本标志判定。
                        dayPackSendFailed = true
                        ErrorReporter.log(
                            .sync(component: "BLE DayPack", underlying: lastWriteError?.localizedDescription ?? "write failed after 2 attempts"),
                            context: "BLESyncCoordinator.performSync"
                        )
                    }
                }
            }
            guard presentationSnapshotIsCurrent else {
                queuePendingSync(force: force, trigger: trigger)
                return
            }

            if dailyContentPresentation.readyGeneration == nil,
               appState.dailyContentPresentationSnapshot().readyGeneration != nil {
                // The schedule deadline crossed while this round was preparing its frozen
                // package. Keep the prior daily package/overview pair and switch in one next round.
                queuePendingSync(force: force, trigger: trigger)
                return
            }

            if !taskLibraryCommittedBeforeDayPack {
                if Self.commitsTaskLibraryBeforeDayPack(
                    readyUpdate: appState.taskLibraryReadyUpdate()
                ) {
                    // The deadline crossed while this round was preparing or connecting. This
                    // round used the frozen DayPack, so keep the old library with it and let the
                    // next round perform the ordered library-first switch.
                    queuePendingSync(force: force, trigger: trigger)
                    return
                }
                do {
                    try await sendFullTaskLibraryIfNeeded(
                        tasks: taskLibraryPresentation.tasks,
                        userProfile: appState.userProfile,
                        customCompanions: appState.customCompanions,
                        allowedReadyUpdate: taskLibraryPresentation.readyUpdate,
                        preservesPendingStableChanges: taskLibraryPresentation.usesFrozenBaseline,
                        expectedTaskStateVersion: sourceTaskStateVersion,
                        expectedCompanionIdentityFingerprint: sourceIdentityFingerprint
                    )
                } catch {
                    if let bleError = error as? BLEError,
                       case .staleTaskSnapshot = bleError {
                        queuePendingSync(force: force, trigger: trigger)
                        return
                    }
                    if error is BLEPresentationDestinationError {
                        queuePendingSync(force: force, trigger: trigger)
                        return
                    }
                    // Older firmware may not support 0x23 yet. The retained DayPack/TaskIn/0x1B
                    // path continues while firmware work is tracked separately in issue #26.
                    ErrorReporter.log(
                        .sync(
                            component: "BLE Task Library",
                            underlying: error.localizedDescription
                        ),
                        context: "BLESyncCoordinator.performSync"
                    )
                }
            }

            await appState.flushPendingCustomCompanionPushIfNeeded()

            if dayPackSendFailed {
                // 硬件仍在显示旧内容：这轮不算成功。不更新 lastBleSyncTime（避免 Settings 显示
                // 绿色"刚同步过"），点亮 lastSyncFailed 供用户重试。
                bleService.lastSyncFailed = true
                lastSyncSucceeded = false
            } else {
                let completedAt = Date()
                await localStorage.saveLastBleSyncTime(completedAt)
                bleService.updateLastSyncTime(completedAt)
                bleService.lastSyncFailed = false
                lastSyncSucceeded = true
            }
        } catch is CancellationError {
            // A newer explicit refresh superseded this debounced automatic round. Cancellation is
            // not a transport failure and must not turn Settings red or trigger another retry.
            if bleService.connectionState.isConnected,
               !bleService.shouldKeepConnectionOpenForDebug,
               taskActionPresentationCount == 0,
               FocusSessionService.shared.activeSession == nil,
               !policy.shouldHoldConnectionForCustomAvatar(
                chunkedTransferInFlight: bleService.isChunkedTransferInFlight,
                operationState: appState.customAvatarOperationState
               ) {
                bleService.disconnect()
            }
            return
        } catch {
            lastSyncSucceeded = false
            bleService.lastSyncFailed = true
            // 整轮同步失败的最终兜底——必须无条件上报。否则 Release/TestFlight 包（硬件团队拿的就是它）
            // 下 #if DEBUG 被裁剪，sync 失败彻底静默，硬件团队无法区分“没触发同步”和“同步失败了”。
            ErrorReporter.log(
                .sync(component: "BLESyncCoordinator", underlying: error.localizedDescription),
                context: "BLESyncCoordinator.performSync"
            )
        }

        // 智能提醒在断连前统一投递：硬件可达 → 只推 E-ink（手机保持安静）；硬件离线 → 落 iOS 本地通知，
        // 否则离线用户这条温和提醒就彻底丢了（NotificationService 此前完全没有调用方）。
        await deliverSmartReminder(appState: appState)

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

    private static func companionIdentityFingerprint(_ appState: AppState) -> String {
        let profile = appState.userProfile
        guard let customID = profile.customCompanionId else {
            return "built-in|\(profile.companionCharacter.rawValue)|\(profile.intimacyStage.rawValue)"
        }
        let revision = appState.customCompanions
            .first(where: { $0.id == customID })?
            .avatarRevisionKey ?? "missing"
        return "custom|\(customID.uuidString)|\(revision)"
    }

    static func shouldSendPreparedDayPack(
        requested: Bool,
        lastSentFingerprint: String?,
        preparedFingerprint: String,
        hasActiveFocusSession: Bool
    ) -> Bool {
        requested && !hasActiveFocusSession && lastSentFingerprint != preparedFingerprint
    }

    private func schedulePendingSyncIfPossible() {
        let destinationID = connectedDestinationProvider()
        guard pendingSync,
              !isSyncing,
              taskActionPresentationCount == 0,
              !pendingTaskActionAcknowledgementBlocks.blocksScheduledSync(destinationID),
              !persistedAttemptedDeliveryBlocks.blocksScheduledSync(destinationID) else { return }
        let shouldForce = pendingForceSync
        let trigger = pendingSyncTrigger ?? .automatic
        pendingSync = false
        pendingForceSync = false
        pendingSyncTrigger = nil
        if let pendingSyncRunner {
            pendingSyncRunner(shouldForce, trigger)
            return
        }
        Task { @MainActor in await self.performSync(force: shouldForce, trigger: trigger) }
    }

    private func queuePendingSync(force: Bool, trigger: BLESyncTrigger) {
        pendingSync = true
        if force { pendingForceSync = true }
        if let pendingSyncTrigger {
            self.pendingSyncTrigger = pendingSyncTrigger.merged(with: trigger)
        } else {
            pendingSyncTrigger = trigger
        }
    }

    /// Reads the durable attempted marker for the currently connected target. The caller decides
    /// whether an empty destination is an expected pre-connect state or a fail-closed error.
    private func shouldDeferForPersistedAttemptedDelivery(
        force: Bool,
        trigger: BLESyncTrigger,
        missingDestinationBlocks: Bool
    ) async -> Bool {
        guard let destinationID = connectedDestinationProvider() else {
            // A disconnected entry is allowed to establish a connection, but it must not clear a
            // block learned for the last connected target. The post-connect checkpoint rechecks.
            if persistedAttemptedDeliveryBlocks.hasAny {
                queuePendingSync(force: force, trigger: trigger)
            }
            return false
        }
        guard !destinationID.isEmpty else {
            guard missingDestinationBlocks else { return false }
            persistedAttemptedDeliveryBlocks.insert(destinationID)
            queuePendingSync(force: force, trigger: trigger)
            ErrorReporter.log(
                .sync(
                    component: "BLE Task Action Delivery Check",
                    underlying: "connected device has no snapshot destination ID"
                ),
                context: "BLESyncCoordinator.performSync"
            )
            return true
        }

        do {
            let hasAttemptedDelivery = try await attemptedDeliveryChecker(destinationID)
            let currentDestinationID = connectedDestinationProvider()
            guard currentDestinationID == destinationID else {
                persistedAttemptedDeliveryBlocks.replace(
                    destinationID,
                    isBlocked: hasAttemptedDelivery
                )
                if let currentDestinationID {
                    persistedAttemptedDeliveryBlocks.insert(currentDestinationID)
                }
                queuePendingSync(force: force, trigger: trigger)
                ErrorReporter.log(
                    .sync(
                        component: "BLE Task Action Delivery Check",
                        underlying: "connected snapshot destination changed during lookup"
                    ),
                    context: "BLESyncCoordinator.performSync"
                )
                return true
            }
            // A successful lookup for an identified current device supersedes a prior transient
            // empty-ID lookup. Per-device blocks for every other destination remain untouched.
            persistedAttemptedDeliveryBlocks.remove(
                destinationID,
                includingUnbound: true
            )
            if hasAttemptedDelivery {
                persistedAttemptedDeliveryBlocks.insert(destinationID)
            }
            guard hasAttemptedDelivery else { return false }
        } catch {
            persistedAttemptedDeliveryBlocks.insert(destinationID)
            if let currentDestinationID = connectedDestinationProvider(),
               currentDestinationID != destinationID {
                persistedAttemptedDeliveryBlocks.insert(currentDestinationID)
            }
            queuePendingSync(force: force, trigger: trigger)
            ErrorReporter.log(
                .sync(
                    component: "BLE Task Action Delivery Check",
                    underlying: error.localizedDescription
                ),
                context: "BLESyncCoordinator.performSync"
            )
            return true
        }

        queuePendingSync(force: force, trigger: trigger)
        return true
    }

    private func shouldDeferRoutineDayPackWrite(
        force: Bool,
        trigger: BLESyncTrigger
    ) async -> Bool {
        if taskActionPresentationCount > 0
            || pendingTaskActionAcknowledgementBlocks.blocks(
                connectedDestinationProvider()
            )
            || hardwarePagePresentationGate.hasPageTransactionDemand {
            queuePendingSync(force: force, trigger: trigger)
            return true
        }
        if await shouldDeferForPersistedAttemptedDelivery(
            force: force,
            trigger: trigger,
            missingDestinationBlocks: true
        ) {
            return true
        }
        // The storage query yielded MainActor. A task-action page transaction may have queued
        // during that suspension, so close the final race immediately before sendDayPack.
        if taskActionPresentationCount > 0
            || pendingTaskActionAcknowledgementBlocks.blocks(
                connectedDestinationProvider()
            )
            || hardwarePagePresentationGate.hasPageTransactionDemand {
            queuePendingSync(force: force, trigger: trigger)
            return true
        }
        return false
    }

    private func sendFinalTaskActionDayPack(
        destinationID: String,
        destinationDidChange: @MainActor () -> Void
    ) async -> UInt64? {
        var reportedDestinationChange = false
        func recordDestinationChange() {
            destinationDidChange()
            pendingSync = true
            if !reportedDestinationChange {
                reportedDestinationChange = true
                ErrorReporter.log(
                    .sync(
                        component: "BLE Task Action DayPack",
                        underlying: "snapshot destination changed during presentation"
                    ),
                    context: "BLESyncCoordinator.sendFinalTaskActionDayPack"
                )
            }
        }
        func validateDestination() -> Bool {
            guard connectedDestinationProvider() == destinationID else {
                recordDestinationChange()
                return false
            }
            return true
        }

        guard validateDestination() else { return nil }
        let appState = AppState.shared
        await appState.ensureInitialLoadComplete()
        guard validateDestination() else { return nil }

        for _ in 0..<3 {
            await appState.refreshSharedPetDialogueIfNeeded()
            guard validateDestination() else { return nil }
            let sourceTaskStateVersion = appState.taskStateVersion
            let presentationTasks = appState.tasksForHardwarePresentation()
            let presentationPetDialogue = appState.petDialogueForHardwarePresentation()
            guard appState.currentPetDialogueTaskStateVersion == sourceTaskStateVersion else {
                continue
            }

            let dayPack = await dayPackGenerator.generateDayPack(
                pet: appState.pet,
                tasks: presentationTasks,
                events: appState.events,
                weather: appState.weather,
                deviceMode: appState.deviceMode,
                userProfile: appState.userProfile,
                customCompanions: appState.customCompanions,
                screenSize: bleService.hardwareScreenSize,
                petDialogue: presentationPetDialogue
            )
            guard validateDestination() else { return nil }
            guard appState.taskStateVersion == sourceTaskStateVersion else { continue }

            let fingerprint = dayPack.stableFingerprint()
            let semanticFingerprint = dayPack.refreshSemanticFingerprint(
                allTasks: presentationTasks,
                at: Date()
            )
            let lastDayPackHash = await localStorage.loadLastDayPackHash()
            guard validateDestination() else { return nil }
            if lastDayPackHash == fingerprint {
                // A routine sync that was already in flight successfully sent this exact final
                // state. Reuse it instead of emitting a duplicate 0x10 before the same 0x1B.
                await localStorage.saveLastDayPackSemanticHash(semanticFingerprint)
                guard validateDestination() else { return nil }
                return sourceTaskStateVersion
            }

            var taskStateChanged = false
            var lastWriteError: Error?
            for attempt in 0..<2 {
                guard validateDestination() else { return nil }
                do {
                    try await bleService.sendDayPack(
                        dayPack,
                        expectedTaskStateVersion: sourceTaskStateVersion,
                        expectedDestinationID: destinationID
                    )
                    guard validateDestination() else { return nil }
                    await localStorage.saveLastDayPackHash(fingerprint)
                    guard validateDestination() else { return nil }
                    await localStorage.saveLastDayPackSemanticHash(semanticFingerprint)
                    guard validateDestination() else { return nil }
                    return sourceTaskStateVersion
                } catch is BLEPresentationDestinationError {
                    recordDestinationChange()
                    return nil
                } catch let error as BLEError {
                    guard validateDestination() else { return nil }
                    if case .staleTaskSnapshot = error {
                        taskStateChanged = true
                        break
                    }
                    lastWriteError = error
                } catch {
                    guard validateDestination() else { return nil }
                    lastWriteError = error
                }

                if attempt == 0 {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard validateDestination() else { return nil }
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

    nonisolated static func commitsTaskLibraryBeforeDayPack(
        readyUpdate: TaskLibraryReadyUpdate?
    ) -> Bool {
        readyUpdate?.scope == .complete || readyUpdate?.scope == .hardwareQueue
    }

    nonisolated static func pendingValidationForFrozenUpdate(
        scope: TaskLibraryUpdateScope,
        plannedValidation: TaskLibraryPendingValidation
    ) -> TaskLibraryPendingValidation {
        guard case .taskRemovals(let taskIDs) = scope else {
            return plannedValidation
        }
        return .taskRemovals(Array(taskIDs).sorted())
    }

    /// 路由一条到期的智能提醒：硬件可达就推设备，否则落本地通知，让离线用户也收得到。
    /// 每轮同步只评估一次（限流逻辑在 SmartReminderService 内）。
    private func deliverSmartReminder(appState: AppState) async {
        guard let reminder = await Self.evaluateSmartReminder(
            tasks: appState.tasks,
            pet: appState.pet,
            userProfile: appState.userProfile,
            evaluator: SmartReminderService.shared
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

    static func evaluateSmartReminder(
        tasks: [TaskItem],
        pet: Pet,
        userProfile: UserProfile,
        evaluator: any SmartReminderEvaluating
    ) async -> SmartReminderResult? {
        await evaluator.evaluateAndPushReminder(
            tasks: tasks,
            pet: pet,
            userProfile: userProfile
        )
    }
}

extension BLESyncCoordinator: TaskActionPresentationCoordinating {
    func sendFinalDayPackBeforeAcknowledgement(
        _ acknowledgement: @MainActor @Sendable (
            _ expectedTaskStateVersion: UInt64
        ) async -> TaskListSnapshotResponder.Outcome
    ) async {
        await sendFinalDayPackBeforeAcknowledgement(
            // Compatibility entry point for isolated coordinators that predate destination
            // binding. Production event handling always calls the explicit overload.
            destinationID: connectedDestinationProvider() ?? "single-active-device",
            acknowledgement
        )
    }

    func sendFinalDayPackBeforeAcknowledgement(
        destinationID: String,
        _ acknowledgement: @MainActor @Sendable (
            _ expectedTaskStateVersion: UInt64
        ) async -> TaskListSnapshotResponder.Outcome
    ) async {
        guard !destinationID.isEmpty else {
            failClosedForUnboundTaskAction(
                context: "BLESyncCoordinator.sendFinalDayPackBeforeAcknowledgement"
            )
            return
        }

        await performTaskActionPresentation {
            var acknowledgementFailed = false
            var destinationChanged = false
            let completed = await Self.completeTaskActionPresentation(
                sendFinalDayPack: {
                    if let taskActionDayPackSender = self.taskActionDayPackSender {
                        if let currentDestinationID = self.connectedDestinationProvider(),
                           currentDestinationID != destinationID {
                            destinationChanged = true
                            return nil
                        }
                        let taskStateVersion = await taskActionDayPackSender()
                        if let currentDestinationID = self.connectedDestinationProvider(),
                           currentDestinationID != destinationID {
                            destinationChanged = true
                            return nil
                        }
                        return taskStateVersion
                    }
                    return await self.sendFinalTaskActionDayPack(
                        destinationID: destinationID,
                        destinationDidChange: { destinationChanged = true }
                    )
                },
                acknowledge: { taskStateVersion in
                    let outcome = await acknowledgement(taskStateVersion)
                    if outcome == .failed {
                        acknowledgementFailed = true
                    }
                    return outcome
                }
            )
            if completed {
                pendingTaskActionAcknowledgementBlocks.remove(destinationID)
                persistedAttemptedDeliveryBlocks.remove(destinationID)
            } else if acknowledgementFailed || destinationChanged {
                pendingTaskActionAcknowledgementBlocks.insert(destinationID)
                persistedAttemptedDeliveryBlocks.insert(destinationID)
            }
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
            return !pendingTaskActionAcknowledgementBlocks.blocks(
                connectedDestinationProvider()
            )
        }
    }

    func replayAttemptedAcknowledgement(
        _ acknowledgement: @MainActor @Sendable () async -> TaskListSnapshotResponder.Outcome
    ) async {
        await replayAttemptedAcknowledgement(
            destinationID: connectedDestinationProvider() ?? "single-active-device",
            acknowledgement
        )
    }

    func replayAttemptedAcknowledgement(
        destinationID: String,
        _ acknowledgement: @MainActor @Sendable () async -> TaskListSnapshotResponder.Outcome
    ) async {
        guard !destinationID.isEmpty else {
            failClosedForUnboundTaskAction(
                context: "BLESyncCoordinator.replayAttemptedAcknowledgement"
            )
            return
        }

        pendingTaskActionAcknowledgementBlocks.insert(destinationID)
        persistedAttemptedDeliveryBlocks.insert(destinationID)
        await performTaskActionPresentation {
            let outcome = await acknowledgement()
            if outcome == .sent {
                pendingTaskActionAcknowledgementBlocks.remove(destinationID)
                persistedAttemptedDeliveryBlocks.remove(destinationID)
            }
            // A failed replay for A still must release routine work after the connection has
            // switched to clear B. A remains blocked in its own destination entry.
            return !pendingTaskActionAcknowledgementBlocks.blocks(
                connectedDestinationProvider()
            )
        }
    }

    private func failClosedForUnboundTaskAction(context: String) {
        pendingTaskActionAcknowledgementBlocks.insert("")
        persistedAttemptedDeliveryBlocks.insert("")
        pendingSync = true
        ErrorReporter.log(
            .sync(
                component: "BLE Task Action Presentation",
                underlying: "task action has no snapshot destination ID"
            ),
            context: context
        )
    }

    private func performTaskActionPresentation(
        _ operation: @MainActor () async -> Bool
    ) async {
        taskActionPresentationCount += 1
        taskActionAppState.cancelPendingBLESyncForTaskActionPresentation()

        do {
            try await taskActionPresentationGate.acquire()
        } catch {
            // Firmware keeps the operation pending and retries the same OperationID. Sending
            // 0x1B here would exit TaskIn without the final DayPack and recreate the double refresh.
            taskActionPresentationCount -= 1
            guard !pendingTaskActionAcknowledgementBlocks.blocks(
                connectedDestinationProvider()
            ) else { return }
            taskActionAppState.resumeDeferredBLESyncAfterTaskActionPresentation()
            schedulePendingSyncIfPossible()
            return
        }

        taskActionAppState.cancelPendingBLESyncForTaskActionPresentation()
        let shouldResumeRoutineSync = await operation()

        await taskActionPresentationGate.release()
        taskActionPresentationCount -= 1
        guard shouldResumeRoutineSync else { return }
        // PetStatus(0x01) is not part of the final DayPack→0x1B transaction. Re-fire any
        // identity/manual round that was parked so hardware does not keep a stale companion.
        taskActionAppState.resumeDeferredBLESyncAfterTaskActionPresentation()
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
        await performSync(trigger: .background)
        BLEBackgroundSyncScheduler.shared.schedule()
        complete(success: lastSyncSucceeded)
    }
}
#endif
