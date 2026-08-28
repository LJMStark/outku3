import Foundation

public enum BLEOfflineSyncCoordinatorError: Error, Sendable, Equatable {
    case busy
    case timedOut
    case disconnected
    case invalidInbound
    case mailboxOverflow
    case zeroSyncID
    case invalidDatasetMask(UInt8)
    case inconsistentOpenTransaction
    case transactionRecoveryFailed(UInt32)
    case operationOverflowRequiresRecovery
    case emptyOperationBatch
    case invalidOperationID
    case conflictingDuplicateOperation(UInt32)
    case nonIncreasingOperationID(previous: UInt32, current: UInt32)
    case operationIDGap(previous: UInt32, current: UInt32)
    case operationCountExceeded(expected: Int, actual: Int)
    case deviceRejected(OfflineSyncResultCode)
    /// The wait expired without a single `0x25` byte ever arriving on this connection.
    /// Firmware predating v2.12.0 logs `Unknown App→Device cmd: 0x25` and stays silent, so this
    /// is a capability verdict, not a transport fault — the caller must not fence the link.
    case offlineSyncUnsupported
}

/// Owns the ordering barrier for one wake-triggered OfflineSync transaction.
///
/// BLE framing, connection ownership, local operation idempotency and dataset encoding stay in
/// injected collaborators. This type only advances after the previous async write has completed,
/// and it matches device replies against the current BootSessionID or SyncID before resuming.
@MainActor
public final class BLEOfflineSyncCoordinator {
    public typealias SynchronizeTime = @MainActor @Sendable () async throws -> Void
    public typealias SendCommand = @MainActor @Sendable (
        OfflineSyncOutboundCommand
    ) async throws -> Void
    public typealias MakeSnapshot = @MainActor @Sendable () async throws -> OfflineDatasetSnapshot
    public typealias SendDataset = @MainActor @Sendable (Data) async throws -> Void
    public typealias ProcessOperation = @MainActor @Sendable (
        _ bootSessionID: UInt32,
        _ operation: OfflineSyncOperationRecord
    ) async throws -> Void
    public typealias MakeUInt32 = @MainActor @Sendable () -> UInt32
    public typealias PreviewFocus = @MainActor @Sendable (OfflineFocusState) async throws -> Void
    public typealias ResolveFocus = @MainActor @Sendable (OfflineFocusState) async throws -> OfflineFocusResolve
    public typealias RestoreOrdinaryFocusSync = @MainActor @Sendable (
        OfflineFocusState,
        OfflineFocusResolve
    ) async throws -> Void
    public typealias AbandonPendingFocusResolve = @MainActor @Sendable () -> Void
    public typealias InvalidatePendingFocusResolve = @MainActor @Sendable () -> Void

    public struct Dependencies: Sendable {
        public let synchronizeTime: SynchronizeTime
        public let sendCommand: SendCommand
        public let makeSnapshot: MakeSnapshot
        public let sendTaskList: SendDataset
        public let sendSchedule: SendDataset
        public let sendDayPack: SendDataset
        public let processOperation: ProcessOperation
        public let makeSyncID: MakeUInt32
        public let makeValidUntil: MakeUInt32
        public let makeResolveID: MakeUInt32
        public let freezeFocusStatus: @MainActor @Sendable () -> Void
        public let unfreezeFocusStatus: @MainActor @Sendable () -> Void
        public let previewFocusState: PreviewFocus
        public let resolveFocus: ResolveFocus
        public let restoreOrdinaryFocusSync: RestoreOrdinaryFocusSync
        public let abandonPendingFocusResolve: AbandonPendingFocusResolve
        public let invalidatePendingFocusResolve: InvalidatePendingFocusResolve

        public init(
            synchronizeTime: @escaping SynchronizeTime,
            sendCommand: @escaping SendCommand,
            makeSnapshot: @escaping MakeSnapshot,
            sendTaskList: @escaping SendDataset,
            sendSchedule: @escaping SendDataset,
            sendDayPack: @escaping SendDataset,
            processOperation: @escaping ProcessOperation,
            makeSyncID: @escaping MakeUInt32,
            makeValidUntil: @escaping MakeUInt32,
            makeResolveID: @escaping MakeUInt32 = { 1 },
            freezeFocusStatus: @escaping @MainActor @Sendable () -> Void = {},
            unfreezeFocusStatus: @escaping @MainActor @Sendable () -> Void = {},
            previewFocusState: @escaping PreviewFocus = { _ in },
            resolveFocus: @escaping ResolveFocus,
            restoreOrdinaryFocusSync: @escaping RestoreOrdinaryFocusSync = { _, _ in },
            abandonPendingFocusResolve: @escaping AbandonPendingFocusResolve = {},
            invalidatePendingFocusResolve: @escaping InvalidatePendingFocusResolve = {}
        ) {
            self.synchronizeTime = synchronizeTime
            self.sendCommand = sendCommand
            self.makeSnapshot = makeSnapshot
            self.sendTaskList = sendTaskList
            self.sendSchedule = sendSchedule
            self.sendDayPack = sendDayPack
            self.processOperation = processOperation
            self.makeSyncID = makeSyncID
            self.makeValidUntil = makeValidUntil
            self.makeResolveID = makeResolveID
            self.freezeFocusStatus = freezeFocusStatus
            self.unfreezeFocusStatus = unfreezeFocusStatus
            self.previewFocusState = previewFocusState
            self.resolveFocus = resolveFocus
            self.restoreOrdinaryFocusSync = restoreOrdinaryFocusSync
            self.abandonPendingFocusResolve = abandonPendingFocusResolve
            self.invalidatePendingFocusResolve = invalidatePendingFocusResolve
        }
    }

    public struct Completion: Sendable, Equatable {
        public let state: OfflineSyncState
        public let syncID: UInt32
        public let revision: UInt32
        public let processedOperationCount: Int
        public let didCommitDatasets: Bool
        public let didResolveFocus: Bool

        public init(
            state: OfflineSyncState,
            syncID: UInt32,
            revision: UInt32,
            processedOperationCount: Int,
            didCommitDatasets: Bool = true,
            didResolveFocus: Bool = false
        ) {
            self.state = state
            self.syncID = syncID
            self.revision = revision
            self.processedOperationCount = processedOperationCount
            self.didCommitDatasets = didCommitDatasets
            self.didResolveFocus = didResolveFocus
        }
    }

    public private(set) var isRunning = false
    public var requiresBLEConnection: Bool { isRunning }
    /// Tests replace this to prove focus blocks COMMIT without starting a real session.
    var hasActiveFocusSession: () -> Bool = {
        FocusSessionService.shared.activeSession != nil
    }

    enum Expectation: Equatable {
        case state
        case operationBatch(bootSessionID: UInt32)
        case committed(syncID: UInt32)
        case focusResolveOutcome(syncID: UInt32)
        case focusState(bootSessionID: UInt32)
    }

    private struct PendingWaiter {
        let id: UUID
        let expectation: Expectation
        var outboundWriteCompleted: Bool
        let continuation: CheckedContinuation<OfflineSyncInboundMessage, any Error>
    }

    private let responseTimeout: Duration
    let dependencies: Dependencies
    private let mailboxLimit = 128

    private var activeRunID: UUID?
    private var terminalError: BLEOfflineSyncCoordinatorError?
    var expectedBootSessionID: UInt32?
    var expectedSyncID: UInt32?
    var mailbox: [OfflineSyncInboundMessage] = []
    private var acceptsPreRunInbound = false
    private var preRunMailbox: [OfflineSyncInboundMessage] = []
    private var preRunTerminalError: BLEOfflineSyncCoordinatorError?
    /// True once any `0x25` frame — well-formed or not — has arrived on this connection.
    /// Distinguishes "the device speaks OfflineSync but this reply was late/lost" from
    /// "the firmware has no `0x25` handler at all". Reset per connection generation.
    private(set) var didObserveOfflineSyncInbound = false
    var didFreezeFocusStatus = false
    /// Firmware 1.3.1: keep `0x14` frozen until FOCUS_RESOLVE gets RESULT/COMMITTED.
    var awaitingFocusResolveResult = false
    private var waiter: PendingWaiter?
    private var timeoutTask: Task<Void, Never>?
    private var requestSendTask: Task<Void, Never>?

    public init(
        responseTimeout: Duration = .seconds(8),
        dependencies: Dependencies
    ) {
        self.responseTimeout = responseTimeout
        self.dependencies = dependencies
    }

    public func synchronize(
        shouldCommitDatasets: @escaping @MainActor (OfflineSyncState) async -> Bool = { _ in true }
    ) async throws -> Completion {
        try Task.checkCancellation()
        guard !isRunning else { throw BLEOfflineSyncCoordinatorError.busy }

        let runID = UUID()
        beginRun(runID)
        var begunSyncID: UInt32?

        do {
            try ensureRunIsActive(runID)
            // Firmware 1.3.1: lock ordinary 0x14 as soon as this wake transaction starts,
            // before Time/QUERY, so a cached idle/active snapshot cannot race FOCUS_STATE.
            dependencies.freezeFocusStatus()
            didFreezeFocusStatus = true

            try await dependencies.synchronizeTime()
            try ensureRunIsActive(runID)

            let stateMessage = try await request(
                .query,
                expecting: .state,
                runID: runID
            )
            guard case .state(let initialState) = stateMessage else {
                throw BLEOfflineSyncCoordinatorError.invalidInbound
            }

            let phase = try await runPostQueryPhase(
                initialState,
                allowInvalidStateRetry: true,
                runID: runID
            )
            let state = phase.state
            let processedCount = phase.processedCount
            let didResolveFocus = phase.didResolveFocus
            try ensureRunIsActive(runID)

            let allowCommit = await shouldCommitDatasets(state)
            let deviceRequiresCommit = state.stateFlags.contains(.needsFullSync)
                || !state.stateFlags.contains(.dataValid)
                || Self.datasetValidityExpired(state.validUntil)
            let overflow = state.stateFlags.contains(.operationOverflow)
            // Firmware 1.3.1: never send OfflineSync COMMIT while focus is still
            // active. Ordinary DayPack/Schedule may resume after RESULT/COMMITTED;
            // dataset COMMIT waits until the session ends.
            if hasActiveFocusSession() {
                let completion = Completion(
                    state: state,
                    syncID: 0,
                    revision: state.activeRevision,
                    processedOperationCount: processedCount,
                    didCommitDatasets: false,
                    didResolveFocus: didResolveFocus
                )
                finishRun(runID)
                return completion
            }
            let wantsCommit = DayPackRefreshArbiter.shouldCommitDatasets(
                structuralChanged: false,
                force: allowCommit,
                hasActiveFocusSession: false
            )
            if overflow && !deviceRequiresCommit {
                let completion = Completion(
                    state: state,
                    syncID: 0,
                    revision: state.activeRevision,
                    processedOperationCount: processedCount,
                    didCommitDatasets: false,
                    didResolveFocus: didResolveFocus
                )
                finishRun(runID)
                return completion
            }
            if !wantsCommit && !deviceRequiresCommit {
                let completion = Completion(
                    state: state,
                    syncID: 0,
                    revision: state.activeRevision,
                    processedOperationCount: processedCount,
                    didCommitDatasets: false,
                    didResolveFocus: didResolveFocus
                )
                finishRun(runID)
                return completion
            }

            let snapshot = try await dependencies.makeSnapshot()
            try ensureRunIsActive(runID)
            guard snapshot.datasetMask == .all else {
                throw BLEOfflineSyncCoordinatorError.invalidDatasetMask(
                    snapshot.datasetMask.rawValue
                )
            }

            let syncID = dependencies.makeSyncID()
            guard syncID != 0 else { throw BLEOfflineSyncCoordinatorError.zeroSyncID }
            expectedSyncID = syncID
            begunSyncID = syncID

            try await sendCommand(
                .begin(
                    OfflineSyncBegin(
                        syncID: syncID,
                        revision: snapshot.revision,
                        validUntil: dependencies.makeValidUntil(),
                        datasetMask: .all
                    )
                ),
                runID: runID
            )
            try await sendDataset(
                snapshot.taskListPayload,
                using: dependencies.sendTaskList,
                runID: runID
            )
            try await sendDataset(
                snapshot.dayPackPayload,
                using: dependencies.sendDayPack,
                runID: runID
            )
            try await sendDataset(
                snapshot.schedulePayload,
                using: dependencies.sendSchedule,
                runID: runID
            )

            let resultMessage = try await request(
                .commit(syncID: syncID),
                expecting: .committed(syncID: syncID),
                runID: runID
            )
            guard case .result(let result) = resultMessage else {
                throw BLEOfflineSyncCoordinatorError.invalidInbound
            }
            guard result.resultCode == .committed else {
                throw BLEOfflineSyncCoordinatorError.deviceRejected(result.resultCode)
            }
            try ensureRunIsActive(runID)

            let completion = Completion(
                state: state,
                syncID: syncID,
                revision: snapshot.revision,
                processedOperationCount: processedCount,
                didResolveFocus: didResolveFocus
            )
            finishRun(runID)
            return completion
        } catch {
            if let begunSyncID {
                await bestEffortAbort(syncID: begunSyncID)
            }
            finishRun(runID)
            throw error
        }
    }

    /// Accepts a decoded 0x25 inbound message. Messages for another boot or sync remain inert in
    /// the bounded mailbox and can never satisfy the current phase.
    public func handleInbound(_ inbound: OfflineSyncInboundMessage) {
        didObserveOfflineSyncInbound = true
        guard activeRunID != nil else {
            guard acceptsPreRunInbound, preRunTerminalError == nil else { return }
            guard preRunMailbox.count < mailboxLimit else {
                preRunTerminalError = .mailboxOverflow
                return
            }
            preRunMailbox.append(inbound)
            return
        }
        guard terminalError == nil else { return }

        if case .result(let result) = inbound,
           result.syncID == expectedSyncID {
            switch result.resultCode {
            case .accepted, .staged:
                // BEGIN / FOCUS_RESOLVE may ACK with ACCEPTED. That is not COMMITTED
                // and must not unlock focus or finish a dataset COMMIT.
                return
            case .committed:
                guard result.targetType == .offlineSync else { return }
            case .invalidState:
                // FOCUS_RESOLVE 0x10 is a deterministic refusal, not a late STATE.
                // Deliver it to the waiter for one re-query; do not treat it as COMMITTED.
                if awaitingFocusResolveResult, result.targetType == .offlineSync {
                    break
                }
                failRun(with: .deviceRejected(result.resultCode))
                return
            case .missingDataset, .expired, .invalidPayload, .busy, .internalError:
                failRun(with: .deviceRejected(result.resultCode))
                return
            }
        }
        guard isRelevantToCurrentRun(inbound) else { return }

        if let waiter, waiter.outboundWriteCompleted,
           message(inbound, matches: waiter.expectation) {
            accept(inbound)
            finishWaiter(waiter.id, returning: inbound)
            return
        }

        guard mailbox.count < mailboxLimit else {
            failRun(with: .mailboxOverflow)
            return
        }
        mailbox.append(inbound)
    }

    /// Decodes only the inner 0x25 payload. The BLE simple-frame Type/Length bytes are removed by
    /// the caller before delivery.
    public func handleInbound(payload: Data) {
        // A malformed 0x25 still proves the firmware has an OfflineSync handler, so mark the
        // capability before decoding rather than only on the success path.
        didObserveOfflineSyncInbound = true
        do {
            handleInbound(try OfflineSyncCodec.decodeInbound(payload))
        } catch {
            if activeRunID != nil {
                failRun(with: .invalidInbound)
            } else if acceptsPreRunInbound {
                preRunTerminalError = .invalidInbound
            }
        }
    }

    /// Notify may deliver STATE immediately after DeviceWake, before the DeviceWake task has
    /// entered `synchronize`. Capture that bounded prefix for this connection generation.
    func preparePreRunInboundCapture() {
        guard !isRunning else { return }
        acceptsPreRunInbound = true
        preRunMailbox.removeAll(keepingCapacity: true)
        preRunTerminalError = nil
        didObserveOfflineSyncInbound = false
    }

    public func handleDisconnected() {
        acceptsPreRunInbound = false
        preRunMailbox.removeAll(keepingCapacity: true)
        preRunTerminalError = nil
        didObserveOfflineSyncInbound = false
        guard activeRunID != nil else { return }
        failRun(with: .disconnected)
    }

    private func beginRun(_ runID: UUID) {
        isRunning = true
        activeRunID = runID
        terminalError = preRunTerminalError
        expectedBootSessionID = nil
        expectedSyncID = nil
        didFreezeFocusStatus = false
        awaitingFocusResolveResult = false
        mailbox = preRunMailbox
        acceptsPreRunInbound = false
        preRunMailbox.removeAll(keepingCapacity: true)
        preRunTerminalError = nil
    }

    private func finishRun(_ runID: UUID) {
        guard activeRunID == runID else { return }
        timeoutTask?.cancel()
        requestSendTask?.cancel()
        timeoutTask = nil
        requestSendTask = nil
        waiter = nil
        mailbox.removeAll(keepingCapacity: true)
        expectedBootSessionID = nil
        expectedSyncID = nil
        if didFreezeFocusStatus && !awaitingFocusResolveResult {
            dependencies.unfreezeFocusStatus()
            didFreezeFocusStatus = false
        }
        awaitingFocusResolveResult = false
        terminalError = nil
        activeRunID = nil
        isRunning = false
    }

    func ensureRunIsActive(_ runID: UUID) throws {
        try Task.checkCancellation()
        if let terminalError { throw terminalError }
        guard activeRunID == runID else {
            throw BLEOfflineSyncCoordinatorError.disconnected
        }
    }

    func sendCommand(
        _ command: OfflineSyncOutboundCommand,
        runID: UUID
    ) async throws {
        try ensureRunIsActive(runID)
        try await dependencies.sendCommand(command)
        try ensureRunIsActive(runID)
    }

    private func sendDataset(
        _ payload: Data,
        using sender: SendDataset,
        runID: UUID
    ) async throws {
        try ensureRunIsActive(runID)
        try await sender(payload)
        try ensureRunIsActive(runID)
    }

    func request(
        _ command: OfflineSyncOutboundCommand,
        expecting expectation: Expectation,
        runID: UUID
    ) async throws -> OfflineSyncInboundMessage {
        try await waitForMessage(
            expecting: expectation,
            runID: runID,
            command: command
        )
    }

    func waitForMessage(
        expecting expectation: Expectation,
        runID: UUID,
        command: OfflineSyncOutboundCommand? = nil
    ) async throws -> OfflineSyncInboundMessage {
        try ensureRunIsActive(runID)
        let waiterID = UUID()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                guard self.waiter == nil else {
                    continuation.resume(throwing: BLEOfflineSyncCoordinatorError.busy)
                    return
                }

                self.waiter = PendingWaiter(
                    id: waiterID,
                    expectation: expectation,
                    outboundWriteCompleted: command == nil,
                    continuation: continuation
                )

                if let command {
                    self.startRequestWrite(command, waiterID: waiterID, runID: runID)
                } else {
                    self.consumeBufferedMessage(for: waiterID)
                    if self.waiter?.id == waiterID {
                        self.startTimeout(for: waiterID)
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finishWaiter(waiterID, throwing: CancellationError())
            }
        }
    }

    private func startRequestWrite(
        _ command: OfflineSyncOutboundCommand,
        waiterID: UUID,
        runID: UUID
    ) {
        requestSendTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try self.ensureRunIsActive(runID)
                try await self.dependencies.sendCommand(command)
                try self.ensureRunIsActive(runID)
                guard var pending = self.waiter, pending.id == waiterID else { return }
                pending.outboundWriteCompleted = true
                self.waiter = pending
                self.requestSendTask = nil
                self.consumeBufferedMessage(for: waiterID)
                if self.waiter?.id == waiterID {
                    self.startTimeout(for: waiterID)
                }
            } catch {
                self.requestSendTask = nil
                self.finishWaiter(waiterID, throwing: error)
            }
        }
    }

    private func startTimeout(for waiterID: UUID) {
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor [weak self, responseTimeout] in
            do {
                try await Task.sleep(for: responseTimeout)
            } catch {
                return
            }
            guard let self else { return }
            // Silence across the whole connection means no `0x25` handler exists (firmware older
            // than v2.12.0). Report that as a capability verdict so the caller keeps the link
            // instead of fencing a generation that has no late reply to fence.
            let verdict: BLEOfflineSyncCoordinatorError = self.didObserveOfflineSyncInbound
                ? .timedOut
                : .offlineSyncUnsupported
            self.finishWaiter(waiterID, throwing: verdict)
        }
    }

    private func consumeBufferedMessage(for waiterID: UUID) {
        guard let waiter, waiter.id == waiterID, waiter.outboundWriteCompleted,
              let index = mailbox.firstIndex(where: {
                  message($0, matches: waiter.expectation)
              }) else {
            return
        }
        let inbound = mailbox.remove(at: index)
        accept(inbound)
        finishWaiter(waiterID, returning: inbound)
    }

    private func message(
        _ inbound: OfflineSyncInboundMessage,
        matches expectation: Expectation
    ) -> Bool {
        switch (expectation, inbound) {
        case (.state, .state):
            return true
        case (.operationBatch(let expectedBoot), .operationBatch(let batch)):
            return batch.bootSessionID == expectedBoot
        case (.committed(let expectedSync), .result(let result)):
            return result.syncID == expectedSync
                && result.targetType == .offlineSync
                && result.resultCode == .committed
        case (.focusResolveOutcome(let expectedSync), .result(let result)):
            return result.syncID == expectedSync
                && result.targetType == .offlineSync
                && (result.resultCode == .committed || result.resultCode == .invalidState)
        case (.focusState(let expectedBoot), .focusState(let state)):
            return state.bootSessionID == expectedBoot
        default:
            return false
        }
    }

    private func accept(_ inbound: OfflineSyncInboundMessage) {
        switch inbound {
        case .state(let state):
            expectedBootSessionID = state.bootSessionID
            mailbox.removeAll { buffered in
                if case .operationBatch(let batch) = buffered {
                    return batch.bootSessionID != state.bootSessionID
                }
                return false
            }
        case .result(let result):
            expectedSyncID = result.syncID
        case .operationBatch, .focusState:
            break
        }
    }

    private func isRelevantToCurrentRun(_ inbound: OfflineSyncInboundMessage) -> Bool {
        switch inbound {
        case .state:
            // STATE has no request identifier. Accept it only after this run has installed its
            // QUERY waiter; a reply delayed from the previous connection/run must not satisfy the
            // next transaction while it is still sending Time.
            guard let waiter else { return false }
            return waiter.expectation == .state && expectedBootSessionID == nil
        case .operationBatch(let batch):
            // OP_BATCH may follow this run's STATE before its waiter is installed, so buffer it
            // after either accepting STATE or observing the matching STATE already buffered while
            // QUERY's GATT write callback is still pending. A batch that arrives before STATE is
            // stale and must still be dropped.
            if let expectedBootSessionID {
                return batch.bootSessionID == expectedBootSessionID
            }
            guard let waiter, waiter.expectation == .state else { return false }
            return mailbox.contains { buffered in
                guard case .state(let state) = buffered else { return false }
                return state.bootSessionID == batch.bootSessionID
            }
        case .focusState(let snapshot):
            if let expectedBootSessionID {
                return snapshot.bootSessionID == expectedBootSessionID
            }
            // FOCUS_STATE may race ahead of STATE during QUERY. Buffer it so a missing
            // FocusSyncPending bit cannot drop the snapshot and unlock a stale 0x14.
            guard let waiter, waiter.expectation == .state else { return false }
            if let bufferedState = mailbox.compactMap({ message -> OfflineSyncState? in
                guard case .state(let state) = message else { return nil }
                return state
            }).first {
                return snapshot.bootSessionID == bufferedState.bootSessionID
            }
            return true
        case .result(let result):
            guard expectedSyncID != nil else { return false }
            guard let waiter else { return false }
            switch waiter.expectation {
            case .committed(let syncID):
                return result.syncID == syncID
                    && result.targetType == .offlineSync
                    && result.resultCode == .committed
            case .focusResolveOutcome(let syncID):
                return result.syncID == syncID
                    && result.targetType == .offlineSync
                    && (result.resultCode == .committed || result.resultCode == .invalidState)
            default:
                return false
            }
        }
    }

    private func finishWaiter(
        _ waiterID: UUID,
        returning message: OfflineSyncInboundMessage
    ) {
        guard let pending = waiter, pending.id == waiterID else { return }
        clearWaiter(cancelRequestWrite: false)
        pending.continuation.resume(returning: message)
    }

    private func finishWaiter(_ waiterID: UUID, throwing error: any Error) {
        guard let pending = waiter, pending.id == waiterID else { return }
        clearWaiter(cancelRequestWrite: true)
        pending.continuation.resume(throwing: error)
    }

    private func clearWaiter(cancelRequestWrite: Bool) {
        timeoutTask?.cancel()
        timeoutTask = nil
        if cancelRequestWrite { requestSendTask?.cancel() }
        requestSendTask = nil
        waiter = nil
    }

    private func failRun(with error: BLEOfflineSyncCoordinatorError) {
        terminalError = error
        if let waiter {
            finishWaiter(waiter.id, throwing: error)
        }
    }

    private func bestEffortAbort(syncID: UInt32) async {
        let sendCommand = dependencies.sendCommand
        await Task { @MainActor in
            try? await sendCommand(.abort(syncID: syncID))
        }.value
    }

    /// `ValidUntil` is a Unix timestamp. Zero or a time that has already passed means the
    /// device can no longer run from the last committed datasets and needs a new COMMIT.
    static func datasetValidityExpired(_ validUntil: UInt32, now: Date = Date()) -> Bool {
        validUntil == 0 || TimeInterval(validUntil) <= now.timeIntervalSince1970
    }
}
