import Foundation
import Testing
@testable import KiroleFeature

@MainActor
@Suite("BLE OfflineSync Coordinator (0x25)", .serialized)
struct BLEOfflineSyncCoordinatorTests {
    private enum Event: Equatable {
        case time
        case snapshot
        case command(OfflineSyncOutboundCommand)
        case taskList(Data)
        case schedule(Data)
        case dayPack(Data)
        case operation(bootSessionID: UInt32, operationID: UInt32)
    }

    private struct OperationNotDurable: Error {}

    @MainActor
    private final class Recorder {
        var events: [Event] = []
        var coordinator: BLEOfflineSyncCoordinator?
        var taskListFailure: (any Error)?
        var suspendQueryWrite = false
        var queryWriteContinuation: CheckedContinuation<Void, Never>?
        var freezeCount = 0
        var unfreezeCount = 0
        var previewed: [OfflineFocusState] = []
        var restored: [(OfflineFocusState, OfflineFocusResolve)] = []

        let snapshot = OfflineDatasetSnapshot(
            taskListPayload: Data([0x02]),
            schedulePayload: Data([0x03]),
            dayPackPayload: Data([0x10])
        )

        func makeCoordinator(
            responseTimeout: Duration = .seconds(1),
            syncID: UInt32 = 0x0102_0304,
            processOperation: BLEOfflineSyncCoordinator.ProcessOperation? = nil
        ) -> BLEOfflineSyncCoordinator {
            let operationProcessor: BLEOfflineSyncCoordinator.ProcessOperation
            if let processOperation {
                operationProcessor = processOperation
            } else {
                operationProcessor = { bootSessionID, operation in
                    self.events.append(
                        .operation(
                            bootSessionID: bootSessionID,
                            operationID: operation.operationID
                        )
                    )
                }
            }
            let coordinator = BLEOfflineSyncCoordinator(
                responseTimeout: responseTimeout,
                dependencies: .init(
                    synchronizeTime: { self.events.append(.time) },
                    sendCommand: {
                        self.events.append(.command($0))
                        if $0 == .query, self.suspendQueryWrite {
                            await withCheckedContinuation {
                                self.queryWriteContinuation = $0
                            }
                        }
                    },
                    makeSnapshot: {
                        self.events.append(.snapshot)
                        return self.snapshot
                    },
                    sendTaskList: {
                        self.events.append(.taskList($0))
                        if let failure = self.taskListFailure { throw failure }
                    },
                    sendSchedule: { self.events.append(.schedule($0)) },
                    sendDayPack: { self.events.append(.dayPack($0)) },
                    processOperation: operationProcessor,
                    makeSyncID: { syncID },
                    makeValidUntil: { 0x0506_0708 },
                    freezeFocusStatus: { self.freezeCount += 1 },
                    unfreezeFocusStatus: { self.unfreezeCount += 1 },
                    previewFocusState: { self.previewed.append($0) },
                    restoreOrdinaryFocusSync: { snapshot, resolve in
                        self.restored.append((snapshot, resolve))
                    }
                )
            )
            self.coordinator = coordinator
            return coordinator
        }
    }

    @Test("STATE and OP_BATCH are buffered before the QUERY write callback completes")
    func buffersStateAndBatchDuringQueryWrite() async throws {
        let recorder = Recorder()
        recorder.suspendQueryWrite = true
        let coordinator = recorder.makeCoordinator()
        let task = Task { try await coordinator.synchronize() }

        try await waitUntil("suspended QUERY write") {
            recorder.queryWriteContinuation != nil
        }
        coordinator.handleInbound(.state(Self.state(pendingCount: 1, bootSessionID: 7)))
        coordinator.handleInbound(.operationBatch(.init(
            bootSessionID: 7,
            records: [Self.record(1)]
        )))

        recorder.suspendQueryWrite = false
        recorder.queryWriteContinuation?.resume()
        recorder.queryWriteContinuation = nil

        try await waitUntil("OP_ACK") {
            recorder.events.contains(.command(.opAck(.init(
                bootSessionID: 7,
                ackOperationID: 1
            ))))
        }
        try await waitUntil("COMMIT") {
            recorder.events.contains(.command(.commit(syncID: 0x0102_0304)))
        }
        coordinator.handleInbound(.result(Self.result()))

        let completion = try await task.value
        #expect(completion.processedOperationCount == 1)
        #expect(recorder.events.contains(.operation(bootSessionID: 7, operationID: 1)))
    }

    @Test("Operation overflow replays the retained batch but never overwrites device datasets")
    func operationOverflowStopsBeforeBegin() async throws {
        let recorder = Recorder()
        let coordinator = recorder.makeCoordinator()
        let task = Task { try await coordinator.synchronize() }

        try await waitUntil("QUERY") { recorder.events.contains(.command(.query)) }
        coordinator.handleInbound(.state(Self.state(
            pendingCount: 1,
            stateFlags: [.dataValid, .operationOverflow],
            validUntil: 2_000_000_000
        )))
        coordinator.handleInbound(.operationBatch(.init(
            bootSessionID: 7,
            records: [Self.record(1)]
        )))

        let completion = try await task.value
        #expect(completion.didCommitDatasets == false)
        #expect(recorder.events.contains(.operation(bootSessionID: 7, operationID: 1)))
        #expect(recorder.events.contains(.command(.opAck(.init(
            bootSessionID: 7,
            ackOperationID: 1
        )))))
        #expect(!recorder.events.contains { event in
            if case .command(.begin) = event { return true }
            if case .command(.commit) = event { return true }
            return false
        })
        #expect(!recorder.events.contains(.snapshot))
    }

    @Test("Overflow plus NeedsFullSync still performs the firmware full-state COMMIT")
    func operationOverflowWithNeedsFullSyncCommits() async throws {
        let recorder = Recorder()
        let coordinator = recorder.makeCoordinator()
        let task = Task { try await coordinator.synchronize() }

        try await waitUntil("QUERY") { recorder.events.contains(.command(.query)) }
        coordinator.handleInbound(.state(Self.state(
            pendingCount: 1,
            stateFlags: [.operationOverflow, .needsFullSync],
            validUntil: 2_000_000_000
        )))
        coordinator.handleInbound(.operationBatch(.init(
            bootSessionID: 7,
            records: [Self.record(1)]
        )))

        try await waitUntil("COMMIT") {
            recorder.events.contains(.command(.commit(syncID: 0x0102_0304)))
        }
        coordinator.handleInbound(.result(Self.result()))

        let completion = try await task.value
        #expect(completion.didCommitDatasets)
        #expect(recorder.events.contains(.snapshot))
    }

    private static func state(
        pendingCount: UInt8 = 0,
        bootSessionID: UInt32 = 7,
        stateFlags: OfflineSyncStateFlags = [.dataValid],
        currentSyncID: UInt32 = 0,
        validUntil: UInt32 = 12
    ) -> OfflineSyncState {
        OfflineSyncState(
            activeRevision: 11,
            validUntil: validUntil,
            datasetMask: .all,
            stateFlags: stateFlags,
            pendingCount: pendingCount,
            bootSessionID: bootSessionID,
            currentSyncID: currentSyncID
        )
    }

    private static func result(
        syncID: UInt32 = 0x0102_0304,
        code: OfflineSyncResultCode = .committed
    ) -> OfflineSyncResult {
        OfflineSyncResult(
            syncID: syncID,
            targetType: .offlineSync,
            resultCode: code
        )
    }

    private static func record(
        _ operationID: UInt32,
        payload: UInt8? = nil
    ) -> OfflineSyncOperationRecord {
        OfflineSyncOperationRecord(
            operationID: operationID,
            eventType: 0x01,
            originalPayload: Data([payload ?? UInt8(truncatingIfNeeded: operationID)])
        )
    }

    private static func completeRecord(_ operationID: UInt32) -> OfflineSyncOperationRecord {
        OfflineSyncOperationRecord(
            operationID: operationID,
            eventType: EventLogType.completeTask.rawByte,
            originalPayload: FocusWireFixtures.endPayload(
                operationID: operationID,
                taskID: "task-1",
                end: 1_786_396_800,
                elapsed: 0
            )
        )
    }

    private func waitUntil(
        _ description: String,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        // The full suite runs many MainActor-heavy BLE tests together. Give the newly-created
        // child task time to receive an actor turn before diagnosing a coordinator timeout.
        let deadline = clock.now.advanced(by: .seconds(10))
        while !condition() {
            guard clock.now < deadline else {
                Issue.record("Timed out waiting for \(description)")
                return
            }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    @Test("FocusSyncPending freezes 0x14, resolves, then restores ordinary sync without forcing COMMIT")
    func focusSyncPendingHandshake() async throws {
        let recorder = Recorder()
        let coordinator = recorder.makeCoordinator()
        coordinator.hasActiveFocusSession = { true }
        let snapshot = FocusWireFixtures.focusState(bootSessionID: 7)

        let task = Task {
            try await coordinator.synchronize(shouldCommitDatasets: { _ in false })
        }
        try await waitUntil("QUERY") { recorder.events.contains(.command(.query)) }
        #expect(recorder.freezeCount == 1)
        coordinator.handleInbound(.state(Self.state(
            stateFlags: [.dataValid, .focusSyncPending],
            validUntil: 2_000_000_000
        )))
        coordinator.handleInbound(.focusState(snapshot))

        try await waitUntil("FOCUS_RESOLVE") {
            recorder.events.contains { event in
                if case .command(.focusResolve(let resolve)) = event {
                    return resolve.resolveID == 1 && resolve.sessionId == snapshot.sessionId
                }
                return false
            }
        }
        #expect(recorder.previewed == [snapshot])

        let completion = try await task.value
        #expect(completion.didCommitDatasets == false)
        #expect(completion.didResolveFocus)
        #expect(recorder.restored.count == 1)
        #expect(recorder.unfreezeCount >= 1)
        #expect(!recorder.events.contains { event in
            if case .command(.begin) = event { return true }
            if case .command(.commit) = event { return true }
            return false
        })
    }

    @Test("NeedsFullSync after FOCUS_RESOLVE still COMMITs DayPack before Schedule")
    func focusResolveThenFullSyncCommitsDayPackBeforeSchedule() async throws {
        let recorder = Recorder()
        let coordinator = recorder.makeCoordinator()
        coordinator.hasActiveFocusSession = { true }
        let snapshot = FocusWireFixtures.focusState(bootSessionID: 7)

        let task = Task { try await coordinator.synchronize() }
        try await waitUntil("QUERY") { recorder.events.contains(.command(.query)) }
        coordinator.handleInbound(.state(Self.state(
            stateFlags: [.needsFullSync, .focusSyncPending],
            validUntil: 2_000_000_000
        )))
        coordinator.handleInbound(.focusState(snapshot))

        try await waitUntil("COMMIT") {
            recorder.events.contains(.command(.commit(syncID: 0x0102_0304)))
        }
        coordinator.handleInbound(.result(Self.result()))

        let completion = try await task.value
        #expect(completion.didCommitDatasets)
        #expect(completion.didResolveFocus)
        let dayPackIndex = recorder.events.firstIndex(of: .dayPack(Data([0x10])))
        let scheduleIndex = recorder.events.firstIndex(of: .schedule(Data([0x03])))
        #expect(dayPackIndex != nil && scheduleIndex != nil)
        if let dayPackIndex, let scheduleIndex {
            #expect(dayPackIndex < scheduleIndex)
        }
    }

    @Test("Focus session drains ops but skips BEGIN so TaskIn is not ejected")
    func focusSessionSkipsDatasetCommit() async throws {
        let recorder = Recorder()
        let coordinator = recorder.makeCoordinator()
        coordinator.hasActiveFocusSession = { true }

        let task = Task { try await coordinator.synchronize() }
        try await waitUntil("QUERY") { recorder.events.contains(.command(.query)) }
        coordinator.handleInbound(.state(Self.state(validUntil: 2_000_000_000)))

        let completion = try await task.value
        #expect(completion.didCommitDatasets == false)
        #expect(completion.processedOperationCount == 0)
        #expect(recorder.events.contains(.time))
        #expect(recorder.events.contains(.command(.query)))
        #expect(!recorder.events.contains(.snapshot))
        #expect(!recorder.events.contains { event in
            if case .command(.begin) = event { return true }
            if case .command(.commit) = event { return true }
            return false
        })
    }

    @Test("NeedsFullSync still commits during focus")
    func focusSessionStillCommitsWhenDeviceRequiresFullSync() async throws {
        let recorder = Recorder()
        let coordinator = recorder.makeCoordinator()
        coordinator.hasActiveFocusSession = { true }

        let task = Task { try await coordinator.synchronize() }
        try await waitUntil("QUERY") { recorder.events.contains(.command(.query)) }
        coordinator.handleInbound(.state(Self.state(
            stateFlags: [.needsFullSync],
            validUntil: 2_000_000_000
        )))

        try await waitUntil("COMMIT") {
            recorder.events.contains(.command(.commit(syncID: 0x0102_0304)))
        }
        coordinator.handleInbound(.result(Self.result()))

        let completion = try await task.value
        #expect(completion.didCommitDatasets)
        #expect(recorder.events.contains(.snapshot))
    }

    @Test("Caller can skip COMMIT when tasks and schedule did not change")
    func callerCanSkipDatasetCommit() async throws {
        let recorder = Recorder()
        let coordinator = recorder.makeCoordinator()

        let task = Task {
            try await coordinator.synchronize(shouldCommitDatasets: { _ in false })
        }
        try await waitUntil("QUERY") { recorder.events.contains(.command(.query)) }
        coordinator.handleInbound(.state(Self.state(validUntil: 2_000_000_000)))

        let completion = try await task.value
        #expect(completion.didCommitDatasets == false)
        #expect(!recorder.events.contains(.snapshot))
    }

    @Test("Runs Time, QUERY, BEGIN, all datasets, COMMIT and matching COMMITTED in order")
    func exactZeroPendingFlow() async throws {
        let recorder = Recorder()
        let coordinator = recorder.makeCoordinator()

        let task = Task { try await coordinator.synchronize() }
        try await waitUntil("QUERY") {
            recorder.events.contains(.command(.query))
        }
        coordinator.handleInbound(.state(Self.state()))

        try await waitUntil("COMMIT") {
            recorder.events.contains(.command(.commit(syncID: 0x0102_0304)))
        }
        coordinator.handleInbound(.result(Self.result()))

        let completion = try await task.value
        #expect(recorder.freezeCount == 1)
        #expect(recorder.unfreezeCount == 1)
        #expect(completion.syncID == 0x0102_0304)
        #expect(completion.processedOperationCount == 0)
        #expect(
            recorder.events == [
                .time,
                .command(.query),
                .snapshot,
                .command(
                    .begin(
                        OfflineSyncBegin(
                            syncID: 0x0102_0304,
                            revision: recorder.snapshot.revision,
                            validUntil: 0x0506_0708,
                            datasetMask: .all
                        )
                    )
                ),
                .taskList(Data([0x02])),
                .dayPack(Data([0x10])),
                .schedule(Data([0x03])),
                .command(.commit(syncID: 0x0102_0304)),
            ]
        )
    }

    @Test("STATE and OP_BATCH delayed from the previous run are dropped before QUERY")
    func staleMessagesBeforeQueryAreDropped() async throws {
        let recorder = Recorder()
        let coordinator = BLEOfflineSyncCoordinator(
            responseTimeout: .seconds(1),
            dependencies: .init(
                synchronizeTime: {
                    recorder.events.append(.time)
                    try await Task.sleep(for: .milliseconds(30))
                },
                sendCommand: { recorder.events.append(.command($0)) },
                makeSnapshot: {
                    recorder.events.append(.snapshot)
                    return recorder.snapshot
                },
                sendTaskList: { recorder.events.append(.taskList($0)) },
                sendSchedule: { recorder.events.append(.schedule($0)) },
                sendDayPack: { recorder.events.append(.dayPack($0)) },
                processOperation: { bootSessionID, operation in
                    recorder.events.append(.operation(
                        bootSessionID: bootSessionID,
                        operationID: operation.operationID
                    ))
                },
                makeSyncID: { 0x0102_0304 },
                makeValidUntil: { 0x0506_0708 }
            )
        )
        let task = Task { try await coordinator.synchronize() }

        try await waitUntil("Time") { recorder.events.contains(.time) }
        coordinator.handleInbound(.state(Self.state(bootSessionID: 99)))
        coordinator.handleInbound(
            .operationBatch(.init(bootSessionID: 7, records: [Self.record(1)]))
        )
        try await waitUntil("QUERY") { recorder.events.contains(.command(.query)) }
        coordinator.handleInbound(.state(Self.state(pendingCount: 1, bootSessionID: 7)))
        coordinator.handleInbound(
            .operationBatch(.init(bootSessionID: 7, records: [Self.record(2)]))
        )

        try await waitUntil("COMMIT") {
            recorder.events.contains(.command(.commit(syncID: 0x0102_0304)))
        }
        coordinator.handleInbound(.result(Self.result()))

        let completion = try await task.value
        #expect(completion.state.bootSessionID == 7)
        #expect(recorder.events.contains(.operation(bootSessionID: 7, operationID: 2)))
        #expect(!recorder.events.contains(.operation(bootSessionID: 7, operationID: 1)))
    }

    @Test("An open transaction is aborted and re-queried before a new BEGIN")
    func recoversOpenTransactionBeforeBegin() async throws {
        let recorder = Recorder()
        let coordinator = recorder.makeCoordinator()
        let task = Task { try await coordinator.synchronize() }

        try await waitUntil("initial QUERY") {
            recorder.events.contains(.command(.query))
        }
        coordinator.handleInbound(.state(Self.state(
            stateFlags: [.dataValid, .transactionOpen],
            currentSyncID: 0xAABB_CCDD
        )))

        try await waitUntil("recovery QUERY") {
            recorder.events.filter { $0 == .command(.query) }.count == 2
        }
        coordinator.handleInbound(.state(Self.state()))

        try await waitUntil("COMMIT") {
            recorder.events.contains(.command(.commit(syncID: 0x0102_0304)))
        }
        coordinator.handleInbound(.result(Self.result()))
        _ = try await task.value

        let abortIndex = try #require(recorder.events.firstIndex(
            of: .command(.abort(syncID: 0xAABB_CCDD))
        ))
        let secondQueryIndex = try #require(recorder.events.indices.last(where: {
            recorder.events[$0] == .command(.query)
        }))
        let beginIndex = try #require(recorder.events.firstIndex(where: {
            if case .command(.begin) = $0 { return true }
            return false
        }))
        #expect(abortIndex < secondQueryIndex)
        #expect(secondQueryIndex < beginIndex)
    }

    @Test("Buffers an early batch and cumulatively ACKs every processed batch")
    func earlyMultipleBatchesAreProcessedAndAcknowledged() async throws {
        let recorder = Recorder()
        let coordinator = recorder.makeCoordinator()
        let task = Task { try await coordinator.synchronize() }

        try await waitUntil("QUERY") { recorder.events.contains(.command(.query)) }
        coordinator.handleInbound(.state(Self.state(pendingCount: 3)))
        coordinator.handleInbound(
            .operationBatch(
                OfflineSyncOperationBatch(
                    bootSessionID: 7,
                    records: [Self.record(10), Self.record(11)]
                )
            )
        )

        try await waitUntil("first cumulative ACK") {
            recorder.events.contains(
                .command(.opAck(.init(bootSessionID: 7, ackOperationID: 11)))
            )
        }
        coordinator.handleInbound(
            .operationBatch(
                OfflineSyncOperationBatch(bootSessionID: 7, records: [Self.record(12)])
            )
        )

        try await waitUntil("COMMIT") {
            recorder.events.contains(.command(.commit(syncID: 0x0102_0304)))
        }
        coordinator.handleInbound(.result(Self.result()))

        let completion = try await task.value
        #expect(completion.processedOperationCount == 3)
        #expect(
            recorder.events.filter {
                if case .operation = $0 { return true }
                return false
            } == [
                .operation(bootSessionID: 7, operationID: 10),
                .operation(bootSessionID: 7, operationID: 11),
                .operation(bootSessionID: 7, operationID: 12),
            ]
        )
        #expect(
            recorder.events.filter {
                if case .command(.opAck) = $0 { return true }
                return false
            } == [
                .command(.opAck(.init(bootSessionID: 7, ackOperationID: 11))),
                .command(.opAck(.init(bootSessionID: 7, ackOperationID: 12))),
            ]
        )
    }

    @Test("Unsupported record in one batch does not block a later supported record or cumulative ACK")
    func unsupportedRecordDoesNotBlockBatch() async throws {
        let recorder = Recorder()
        let ledger = OfflineOperationLedger(persistenceEnabled: false)
        let coordinator = recorder.makeCoordinator { bootSessionID, record in
            let durable = await BLEOfflineOperationProcessor.process(
                record,
                deviceID: "device-a",
                bootSessionID: bootSessionID,
                ledger: ledger
            ) { event, _ in
                recorder.events.append(.operation(
                    bootSessionID: bootSessionID,
                    operationID: event.operationID ?? 0
                ))
                return true
            }
            guard durable else { throw OperationNotDurable() }
        }
        let task = Task { try await coordinator.synchronize() }

        try await waitUntil("QUERY") { recorder.events.contains(.command(.query)) }
        coordinator.handleInbound(.state(Self.state(pendingCount: 2)))
        coordinator.handleInbound(.operationBatch(.init(
            bootSessionID: 7,
            records: [
                OfflineSyncOperationRecord(
                    operationID: 10,
                    eventType: 0x99,
                    originalPayload: Data([0xDE, 0xAD])
                ),
                Self.completeRecord(11),
            ]
        )))

        try await waitUntil("cumulative ACK past unsupported record") {
            recorder.events.contains(.command(.opAck(.init(
                bootSessionID: 7,
                ackOperationID: 11
            ))))
        }
        try await waitUntil("COMMIT") {
            recorder.events.contains(.command(.commit(syncID: 0x0102_0304)))
        }
        coordinator.handleInbound(.result(Self.result()))

        let completion = try await task.value
        #expect(completion.processedOperationCount == 2)
        #expect(recorder.events.filter {
            if case .operation = $0 { return true }
            return false
        } == [.operation(bootSessionID: 7, operationID: 11)])
    }

    @Test("Ignores wrong boot batches and wrong sync results")
    func wrongBootAndSyncAreIgnored() async throws {
        let recorder = Recorder()
        let coordinator = recorder.makeCoordinator()
        let task = Task { try await coordinator.synchronize() }

        try await waitUntil("QUERY") { recorder.events.contains(.command(.query)) }
        coordinator.handleInbound(.state(Self.state(pendingCount: 1, bootSessionID: 7)))
        coordinator.handleInbound(
            .operationBatch(.init(bootSessionID: 8, records: [Self.record(1)]))
        )
        coordinator.handleInbound(
            .operationBatch(.init(bootSessionID: 7, records: [Self.record(2)]))
        )

        try await waitUntil("COMMIT") {
            recorder.events.contains(.command(.commit(syncID: 0x0102_0304)))
        }
        coordinator.handleInbound(.result(Self.result(syncID: 0x1111_1111)))
        coordinator.handleInbound(.result(Self.result(code: .accepted)))
        await Task.yield()
        #expect(coordinator.isRunning)
        coordinator.handleInbound(.result(Self.result()))

        _ = try await task.value
        #expect(
            recorder.events.contains(.operation(bootSessionID: 7, operationID: 2))
        )
        #expect(
            !recorder.events.contains(.operation(bootSessionID: 8, operationID: 1))
        )
    }

    @Test("Rejects a concurrent synchronization")
    func singleInFlight() async {
        let recorder = Recorder()
        let coordinator = recorder.makeCoordinator()
        let first = Task { try await coordinator.synchronize() }

        while !coordinator.isRunning { await Task.yield() }
        await #expect(throws: BLEOfflineSyncCoordinatorError.busy) {
            _ = try await coordinator.synchronize()
        }

        coordinator.handleDisconnected()
        _ = try? await first.value
    }

    @Test("Times out when STATE never arrives")
    func queryTimesOut() async {
        let recorder = Recorder()
        let coordinator = recorder.makeCoordinator(responseTimeout: .milliseconds(30))

        await #expect(throws: BLEOfflineSyncCoordinatorError.timedOut) {
            _ = try await coordinator.synchronize()
        }
        #expect(!coordinator.isRunning)
        #expect(!recorder.events.contains(.command(.abort(syncID: 0x0102_0304))))
    }

    @Test("Disconnect releases the current waiter")
    func disconnectFailsRun() async throws {
        let recorder = Recorder()
        let coordinator = recorder.makeCoordinator()
        let task = Task { try await coordinator.synchronize() }

        try await waitUntil("QUERY") { recorder.events.contains(.command(.query)) }
        coordinator.handleDisconnected()

        await #expect(throws: BLEOfflineSyncCoordinatorError.disconnected) {
            _ = try await task.value
        }
        #expect(!coordinator.isRunning)
    }

    @Test("A failure after BEGIN sends best-effort ABORT")
    func failureAfterBeginAborts() async throws {
        struct DatasetFailure: Error {}
        let recorder = Recorder()
        recorder.taskListFailure = DatasetFailure()
        let coordinator = recorder.makeCoordinator()
        let task = Task { try await coordinator.synchronize() }

        try await waitUntil("QUERY") { recorder.events.contains(.command(.query)) }
        coordinator.handleInbound(.state(Self.state()))

        await #expect(throws: DatasetFailure.self) {
            _ = try await task.value
        }
        #expect(recorder.events.contains(.command(.abort(syncID: 0x0102_0304))))
    }

    @Test("Cancellation after BEGIN sends best-effort ABORT and clears the run")
    func cancellationAfterBeginAborts() async throws {
        let recorder = Recorder()
        let coordinator = BLEOfflineSyncCoordinator(
            responseTimeout: .seconds(1),
            dependencies: .init(
                synchronizeTime: { recorder.events.append(.time) },
                sendCommand: { recorder.events.append(.command($0)) },
                makeSnapshot: {
                    recorder.events.append(.snapshot)
                    return recorder.snapshot
                },
                sendTaskList: {
                    recorder.events.append(.taskList($0))
                    try await Task.sleep(for: .seconds(10))
                },
                sendSchedule: { recorder.events.append(.schedule($0)) },
                sendDayPack: { recorder.events.append(.dayPack($0)) },
                processOperation: { _, _ in },
                makeSyncID: { 0x0102_0304 },
                makeValidUntil: { 0x0506_0708 }
            )
        )
        let task = Task { try await coordinator.synchronize() }

        try await waitUntil("QUERY") { recorder.events.contains(.command(.query)) }
        coordinator.handleInbound(.state(Self.state()))
        try await waitUntil("TaskList send") {
            recorder.events.contains(.taskList(Data([0x02])))
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(recorder.events.contains(.command(.abort(syncID: 0x0102_0304))))
        #expect(!coordinator.isRunning)
    }

    @Test("Malformed inbound payload fails the active run")
    func malformedInboundFailsRun() async throws {
        let recorder = Recorder()
        let coordinator = recorder.makeCoordinator()
        let task = Task { try await coordinator.synchronize() }

        try await waitUntil("QUERY") { recorder.events.contains(.command(.query)) }
        coordinator.handleInbound(payload: Data([0x80]))

        await #expect(throws: BLEOfflineSyncCoordinatorError.invalidInbound) {
            _ = try await task.value
        }
    }
}
