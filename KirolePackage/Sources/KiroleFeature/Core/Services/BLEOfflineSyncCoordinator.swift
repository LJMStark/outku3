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
    case operationCountExceeded(expected: Int, actual: Int)
    case deviceRejected(OfflineSyncResultCode)
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

        public init(
            synchronizeTime: @escaping SynchronizeTime,
            sendCommand: @escaping SendCommand,
            makeSnapshot: @escaping MakeSnapshot,
            sendTaskList: @escaping SendDataset,
            sendSchedule: @escaping SendDataset,
            sendDayPack: @escaping SendDataset,
            processOperation: @escaping ProcessOperation,
            makeSyncID: @escaping MakeUInt32,
            makeValidUntil: @escaping MakeUInt32
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
        }
    }

    public struct Completion: Sendable, Equatable {
        public let state: OfflineSyncState
        public let syncID: UInt32
        public let revision: UInt32
        public let processedOperationCount: Int
        public let didCommitDatasets: Bool

        public init(
            state: OfflineSyncState,
            syncID: UInt32,
            revision: UInt32,
            processedOperationCount: Int,
            didCommitDatasets: Bool = true
        ) {
            self.state = state
            self.syncID = syncID
            self.revision = revision
            self.processedOperationCount = processedOperationCount
            self.didCommitDatasets = didCommitDatasets
        }
    }

    public private(set) var isRunning = false
    public var requiresBLEConnection: Bool { isRunning }
    /// Tests replace this to prove focus blocks COMMIT without starting a real session.
    var hasActiveFocusSession: () -> Bool = {
        FocusSessionService.shared.activeSession != nil
    }

    private enum Expectation: Equatable {
        case state
        case operationBatch(bootSessionID: UInt32)
        case committed(syncID: UInt32)
    }

    private struct PendingWaiter {
        let id: UUID
        let expectation: Expectation
        var outboundWriteCompleted: Bool
        let continuation: CheckedContinuation<OfflineSyncInboundMessage, any Error>
    }

    private let responseTimeout: Duration
    private let dependencies: Dependencies
    private let mailboxLimit = 128

    private var activeRunID: UUID?
    private var terminalError: BLEOfflineSyncCoordinatorError?
    private var expectedBootSessionID: UInt32?
    private var expectedSyncID: UInt32?
    private var mailbox: [OfflineSyncInboundMessage] = []
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

            let state = try await recoverOpenTransactionIfNeeded(
                initialState,
                runID: runID
            )

            let processedCount = try await drainOperations(
                state: state,
                runID: runID
            )
            try ensureRunIsActive(runID)
            // Overflow means firmware has already discarded at least one offline operation. The
            // remaining batch can still be durably replayed and ACKed, but pushing the App's stale
            // snapshot would overwrite device state that can no longer be reconstructed. The v1.1
            // contract asks for business compensation without defining that algorithm, so fail
            // safely before BEGIN and preserve the device's current committed datasets.
            guard !state.stateFlags.contains(.operationOverflow) else {
                throw BLEOfflineSyncCoordinatorError.operationOverflowRequiresRecovery
            }

            let allowCommit = await shouldCommitDatasets(state)
            let deviceRequiresCommit = state.stateFlags.contains(.needsFullSync)
                || !state.stateFlags.contains(.dataValid)
                || Self.datasetValidityExpired(state.validUntil)
            // Focus must not COMMIT TaskList/Schedule/DayPack: firmware treats COMMIT as an
            // atomic dataset switch and leaves TaskIn. Device wipe / expired ValidUntil still
            // force a full snapshot. The caller decides idle commits (task/schedule/agenda
            // change or a physical 0x20); dialogue-only refresh is never a reason.
            let wantsCommit = DayPackRefreshArbiter.shouldCommitDatasets(
                structuralChanged: false,
                force: allowCommit,
                hasActiveFocusSession: hasActiveFocusSession()
            )
            if !wantsCommit && !deviceRequiresCommit {
                let completion = Completion(
                    state: state,
                    syncID: 0,
                    revision: state.activeRevision,
                    processedOperationCount: processedCount,
                    didCommitDatasets: false
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
                snapshot.schedulePayload,
                using: dependencies.sendSchedule,
                runID: runID
            )
            try await sendDataset(
                snapshot.dayPackPayload,
                using: dependencies.sendDayPack,
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
                processedOperationCount: processedCount
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
        guard activeRunID != nil, terminalError == nil else { return }

        if case .result(let result) = inbound,
           result.syncID == expectedSyncID {
            switch result.resultCode {
            case .accepted, .staged:
                // BEGIN and individual datasets may acknowledge their staging progress with the
                // same SyncID. They are not the terminal COMMIT response.
                return
            case .committed:
                guard result.targetType == .offlineSync else { return }
            case .invalidState, .missingDataset, .expired, .invalidPayload, .busy, .internalError:
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
        do {
            handleInbound(try OfflineSyncCodec.decodeInbound(payload))
        } catch {
            guard activeRunID != nil else { return }
            failRun(with: .invalidInbound)
        }
    }

    public func handleDisconnected() {
        guard activeRunID != nil else { return }
        failRun(with: .disconnected)
    }

    private func beginRun(_ runID: UUID) {
        isRunning = true
        activeRunID = runID
        terminalError = nil
        expectedBootSessionID = nil
        expectedSyncID = nil
        mailbox.removeAll(keepingCapacity: true)
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
        terminalError = nil
        activeRunID = nil
        isRunning = false
    }

    private func ensureRunIsActive(_ runID: UUID) throws {
        try Task.checkCancellation()
        if let terminalError { throw terminalError }
        guard activeRunID == runID else {
            throw BLEOfflineSyncCoordinatorError.disconnected
        }
    }

    private func drainOperations(
        state: OfflineSyncState,
        runID: UUID
    ) async throws -> Int {
        let expectedCount = Int(state.pendingCount)
        guard expectedCount > 0 else { return 0 }

        var acceptedRecords: [UInt32: OfflineSyncOperationRecord] = [:]
        var lastProcessedID: UInt32?

        while acceptedRecords.count < expectedCount {
            let inbound = try await waitForMessage(
                expecting: .operationBatch(bootSessionID: state.bootSessionID),
                runID: runID
            )
            guard case .operationBatch(let batch) = inbound else {
                throw BLEOfflineSyncCoordinatorError.invalidInbound
            }
            guard !batch.records.isEmpty else {
                throw BLEOfflineSyncCoordinatorError.emptyOperationBatch
            }

            let newRecords = try validate(
                batch.records,
                acceptedRecords: acceptedRecords,
                lastProcessedID: lastProcessedID,
                expectedCount: expectedCount
            )

            do {
                for record in newRecords {
                    try ensureRunIsActive(runID)
                    try await dependencies.processOperation(state.bootSessionID, record)
                    try ensureRunIsActive(runID)
                    acceptedRecords[record.operationID] = record
                    lastProcessedID = record.operationID
                }
            } catch {
                if let lastProcessedID {
                    try? await dependencies.sendCommand(
                        .opAck(
                            OfflineSyncOperationAck(
                                bootSessionID: state.bootSessionID,
                                ackOperationID: lastProcessedID
                            )
                        )
                    )
                }
                throw error
            }

            guard let cumulativeAckID = lastProcessedID else {
                throw BLEOfflineSyncCoordinatorError.emptyOperationBatch
            }
            try await sendCommand(
                .opAck(
                    OfflineSyncOperationAck(
                        bootSessionID: state.bootSessionID,
                        ackOperationID: cumulativeAckID
                    )
                ),
                runID: runID
            )
        }

        return acceptedRecords.count
    }

    private func recoverOpenTransactionIfNeeded(
        _ state: OfflineSyncState,
        runID: UUID
    ) async throws -> OfflineSyncState {
        guard state.stateFlags.contains(.transactionOpen) else { return state }
        guard state.currentSyncID != 0 else {
            throw BLEOfflineSyncCoordinatorError.inconsistentOpenTransaction
        }

        try await sendCommand(.abort(syncID: state.currentSyncID), runID: runID)
        // The second QUERY defines a fresh STATE/OP_BATCH boundary. Do not let batches or results
        // emitted for the abandoned transaction satisfy the refreshed state.
        expectedBootSessionID = nil
        mailbox.removeAll(keepingCapacity: true)
        let refreshedMessage = try await request(
            .query,
            expecting: .state,
            runID: runID
        )
        guard case .state(let refreshed) = refreshedMessage else {
            throw BLEOfflineSyncCoordinatorError.invalidInbound
        }
        guard !refreshed.stateFlags.contains(.transactionOpen),
              refreshed.currentSyncID == 0 else {
            throw BLEOfflineSyncCoordinatorError.transactionRecoveryFailed(
                refreshed.currentSyncID
            )
        }
        return refreshed
    }

    private func validate(
        _ records: [OfflineSyncOperationRecord],
        acceptedRecords: [UInt32: OfflineSyncOperationRecord],
        lastProcessedID: UInt32?,
        expectedCount: Int
    ) throws -> [OfflineSyncOperationRecord] {
        var newRecords: [OfflineSyncOperationRecord] = []
        var candidateLastID = lastProcessedID

        for record in records {
            guard record.operationID != 0 else {
                throw BLEOfflineSyncCoordinatorError.invalidOperationID
            }
            if let previous = acceptedRecords[record.operationID] {
                guard previous == record else {
                    throw BLEOfflineSyncCoordinatorError.conflictingDuplicateOperation(
                        record.operationID
                    )
                }
                continue
            }
            if let duplicateInBatch = newRecords.first(where: {
                $0.operationID == record.operationID
            }) {
                guard duplicateInBatch == record else {
                    throw BLEOfflineSyncCoordinatorError.conflictingDuplicateOperation(
                        record.operationID
                    )
                }
                continue
            }
            if let candidateLastID, record.operationID <= candidateLastID {
                throw BLEOfflineSyncCoordinatorError.nonIncreasingOperationID(
                    previous: candidateLastID,
                    current: record.operationID
                )
            }
            newRecords.append(record)
            candidateLastID = record.operationID
        }

        let resultingCount = acceptedRecords.count + newRecords.count
        guard resultingCount <= expectedCount else {
            throw BLEOfflineSyncCoordinatorError.operationCountExceeded(
                expected: expectedCount,
                actual: resultingCount
            )
        }
        return newRecords
    }

    private func sendCommand(
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

    private func request(
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

    private func waitForMessage(
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
            self?.finishWaiter(
                waiterID,
                throwing: BLEOfflineSyncCoordinatorError.timedOut
            )
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
        case .operationBatch:
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
        case .result(let result):
            guard let expectedSyncID else { return false }
            guard let waiter,
                  waiter.expectation == .committed(syncID: expectedSyncID) else {
                return false
            }
            return result.syncID == expectedSyncID
                && result.targetType == .offlineSync
                && result.resultCode == .committed
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
