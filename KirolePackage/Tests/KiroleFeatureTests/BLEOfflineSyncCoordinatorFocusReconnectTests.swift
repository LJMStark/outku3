import Foundation
import Testing
@testable import KiroleFeature

@MainActor
@Suite("BLE OfflineSync FOCUS_RESOLVE 1.3.1", .serialized)
struct BLEOfflineSyncCoordinatorFocusReconnectTests {
    private enum Event: Equatable {
        case command(OfflineSyncOutboundCommand)
        case snapshot
        case taskList(Data)
        case schedule(Data)
        case dayPack(Data)
    }

    @MainActor
    private final class Recorder {
        var events: [Event] = []
        var freezeCount = 0
        var unfreezeCount = 0
        var focusLifecycle: [String] = []
        var previewed: [OfflineFocusState] = []
        var restored: [(OfflineFocusState, OfflineFocusResolve)] = []
        var processedOperations: [(bootSessionID: UInt32, operationID: UInt32)] = []
        let snapshot = OfflineDatasetSnapshot(
            taskListPayload: Data([0x02]),
            schedulePayload: Data([0x03]),
            dayPackPayload: Data([0x10])
        )

        func makeCoordinator(
            responseTimeout: Duration = .seconds(1),
            resolveFocus: BLEOfflineSyncCoordinator.ResolveFocus? = nil,
            restoreOrdinaryFocusSync: BLEOfflineSyncCoordinator.RestoreOrdinaryFocusSync? = nil,
            abandonPendingFocusResolve: @escaping BLEOfflineSyncCoordinator.AbandonPendingFocusResolve = {},
            invalidatePendingFocusResolve: @escaping BLEOfflineSyncCoordinator.InvalidatePendingFocusResolve = {}
        ) -> BLEOfflineSyncCoordinator {
            BLEOfflineSyncCoordinator(
                responseTimeout: responseTimeout,
                dependencies: .init(
                    synchronizeTime: {},
                    sendCommand: { self.events.append(.command($0)) },
                    makeSnapshot: {
                        self.events.append(.snapshot)
                        return self.snapshot
                    },
                    sendTaskList: { self.events.append(.taskList($0)) },
                    sendSchedule: { self.events.append(.schedule($0)) },
                    sendDayPack: { self.events.append(.dayPack($0)) },
                    processOperation: { bootSessionID, operation in
                        self.processedOperations.append(
                            (bootSessionID: bootSessionID, operationID: operation.operationID)
                        )
                    },
                    makeSyncID: { 0x0102_0304 },
                    makeValidUntil: { 0x0506_0708 },
                    freezeFocusStatus: {
                        self.freezeCount += 1
                        self.focusLifecycle.append("freeze")
                    },
                    unfreezeFocusStatus: {
                        self.unfreezeCount += 1
                        self.focusLifecycle.append("unfreeze")
                    },
                    previewFocusState: { self.previewed.append($0) },
                    resolveFocus: resolveFocus ?? { state in
                        guard state.focusRevision < UInt32.max else {
                            fatalError("Focus revision exhausted in test fixture")
                        }
                        return OfflineFocusResolve(
                            resolveID: 1,
                            sessionId: state.sessionId,
                            focusState: state.focusState == .active ? .active : .idle,
                            result: state.focusState == .active ? .accepted : .closed,
                            startTimestamp: state.startTimestamp,
                            endTimestamp: state.endTimestamp,
                            elapsedSeconds: state.elapsedSeconds,
                            focusRevision: state.focusRevision + 1,
                            phase: .idle,
                            bottles: 0
                        )
                    },
                    restoreOrdinaryFocusSync: restoreOrdinaryFocusSync ?? { snapshot, resolve in
                        self.restored.append((snapshot, resolve))
                    },
                    abandonPendingFocusResolve: abandonPendingFocusResolve,
                    invalidatePendingFocusResolve: invalidatePendingFocusResolve
                )
            )
        }

        var focusResolves: [OfflineFocusResolve] {
            events.compactMap { event in
                if case .command(.focusResolve(let resolve)) = event {
                    return resolve
                }
                return nil
            }
        }
    }

    private enum RestoreFailure: Error, Equatable {
        case persistenceUnavailable
    }

    @Test("STATE received immediately after DeviceWake is retained until the run begins")
    func preRunStateIsRetainedForTheQuery() async throws {
        let recorder = Recorder()
        let coordinator = recorder.makeCoordinator()
        coordinator.hasActiveFocusSession = { false }
        coordinator.preparePreRunInboundCapture()
        coordinator.handleInbound(.state(Self.state(stateFlags: [.dataValid])))

        let completion = try await coordinator.synchronize(shouldCommitDatasets: { _ in false })

        #expect(recorder.events.contains(.command(.query)))
        #expect(completion.didResolveFocus == false)
        #expect(completion.didCommitDatasets == false)
        #expect(completion.state.stateFlags == [.dataValid])
    }

    @Test("FOCUS_RESOLVE waits for RESULT/COMMITTED before unlocking")
    func waitsForCommittedResult() async throws {
        let recorder = Recorder()
        let coordinator = recorder.makeCoordinator()
        coordinator.hasActiveFocusSession = { true }
        let snapshot = FocusWireFixtures.focusState(bootSessionID: 7)

        let task = Task {
            try await coordinator.synchronize(shouldCommitDatasets: { _ in false })
        }
        try await waitUntil("QUERY") {
            recorder.events.contains(.command(.query))
        }
        #expect(recorder.freezeCount == 1)
        coordinator.handleInbound(.state(Self.state(
            stateFlags: [.dataValid, .focusSyncPending]
        )))
        coordinator.handleInbound(.focusState(snapshot))

        try await waitUntil("FOCUS_RESOLVE") {
            recorder.events.contains { event in
                if case .command(.focusResolve(let resolve)) = event {
                    return resolve.resolveID == 1
                }
                return false
            }
        }
        #expect(recorder.previewed == [snapshot])
        #expect(recorder.restored.isEmpty)
        #expect(recorder.unfreezeCount == 0)

        coordinator.handleInbound(.result(Self.focusResult(code: .accepted)))
        await Task.yield()
        #expect(coordinator.isRunning)
        #expect(recorder.restored.isEmpty)

        coordinator.handleInbound(.result(Self.focusResult(syncID: 0x1111_1111)))
        await Task.yield()
        #expect(recorder.restored.isEmpty)

        coordinator.handleInbound(.result(Self.focusResult()))
        let completion = try await task.value
        #expect(completion.didResolveFocus)
        #expect(completion.didCommitDatasets == false)
        #expect(recorder.restored.count == 1)
        #expect(recorder.unfreezeCount == 1)
    }

    @Test("COMMITTED keeps 0x14 frozen until durable Focus restore finishes")
    func committedWaitsForDurableRestoreBeforeUnlocking() async throws {
        let recorder = Recorder()
        var resumeRestore: CheckedContinuation<Void, Never>?
        let coordinator = recorder.makeCoordinator(
            restoreOrdinaryFocusSync: { snapshot, resolve in
                recorder.focusLifecycle.append("restore-start")
                await withCheckedContinuation { continuation in
                    resumeRestore = continuation
                }
                recorder.restored.append((snapshot, resolve))
                recorder.focusLifecycle.append("restore-end")
            }
        )
        coordinator.hasActiveFocusSession = { true }

        let task = Task {
            try await coordinator.synchronize(shouldCommitDatasets: { _ in false })
        }
        try await waitUntil("QUERY") {
            recorder.events.contains(.command(.query))
        }
        coordinator.handleInbound(.state(Self.state(
            stateFlags: [.dataValid, .focusSyncPending]
        )))
        coordinator.handleInbound(.focusState(FocusWireFixtures.focusState(bootSessionID: 7)))
        try await waitUntil("FOCUS_RESOLVE") {
            recorder.focusResolves.count == 1
        }
        coordinator.handleInbound(.result(Self.focusResult()))

        try await waitUntil("durable restore start") {
            recorder.focusLifecycle.contains("restore-start")
        }
        #expect(recorder.unfreezeCount == 0)
        #expect(recorder.focusLifecycle == ["freeze", "restore-start"])

        resumeRestore?.resume()
        _ = try await task.value

        #expect(recorder.focusLifecycle == ["freeze", "restore-start", "restore-end", "unfreeze"])
        #expect(recorder.unfreezeCount == 1)
    }

    @Test("A failed durable Focus restore does not unlock ordinary 0x14")
    func failedDurableRestoreKeepsFreeze() async throws {
        let recorder = Recorder()
        let coordinator = recorder.makeCoordinator(
            restoreOrdinaryFocusSync: { _, _ in
                throw RestoreFailure.persistenceUnavailable
            }
        )
        coordinator.hasActiveFocusSession = { true }

        let task = Task {
            try await coordinator.synchronize(shouldCommitDatasets: { _ in false })
        }
        try await waitUntil("QUERY") {
            recorder.events.contains(.command(.query))
        }
        coordinator.handleInbound(.state(Self.state(
            stateFlags: [.dataValid, .focusSyncPending]
        )))
        coordinator.handleInbound(.focusState(FocusWireFixtures.focusState(bootSessionID: 7)))
        try await waitUntil("FOCUS_RESOLVE") {
            recorder.focusResolves.count == 1
        }
        coordinator.handleInbound(.result(Self.focusResult()))

        await #expect(throws: RestoreFailure.persistenceUnavailable) {
            _ = try await task.value
        }
        #expect(recorder.unfreezeCount == 0)
        #expect(recorder.focusLifecycle == ["freeze"])
    }

    @Test("Active focus defers COMMIT even when NeedsFullSync is set")
    func activeFocusDefersCommitAfterResolve() async throws {
        let recorder = Recorder()
        let coordinator = recorder.makeCoordinator()
        coordinator.hasActiveFocusSession = { true }

        let task = Task { try await coordinator.synchronize() }
        try await waitUntil("QUERY") {
            recorder.events.contains(.command(.query))
        }
        coordinator.handleInbound(.state(Self.state(
            stateFlags: [.needsFullSync, .focusSyncPending]
        )))
        coordinator.handleInbound(.focusState(FocusWireFixtures.focusState(bootSessionID: 7)))

        try await waitUntil("FOCUS_RESOLVE") {
            recorder.events.contains { event in
                if case .command(.focusResolve) = event { return true }
                return false
            }
        }
        coordinator.handleInbound(.result(Self.focusResult()))

        let completion = try await task.value
        #expect(completion.didResolveFocus)
        #expect(completion.didCommitDatasets == false)
        #expect(!recorder.events.contains(.snapshot))
    }

    @Test("NeedsFullSync after idle FOCUS_RESOLVE COMMITs DayPack before Schedule")
    func idleResolveThenFullSyncCommits() async throws {
        let recorder = Recorder()
        let coordinator = recorder.makeCoordinator()
        coordinator.hasActiveFocusSession = { false }

        let task = Task { try await coordinator.synchronize() }
        try await waitUntil("QUERY") {
            recorder.events.contains(.command(.query))
        }
        coordinator.handleInbound(.state(Self.state(
            stateFlags: [.needsFullSync, .focusSyncPending]
        )))
        coordinator.handleInbound(.focusState(FocusWireFixtures.focusState(bootSessionID: 7)))

        try await waitUntil("FOCUS_RESOLVE") {
            recorder.events.contains { event in
                if case .command(.focusResolve) = event { return true }
                return false
            }
        }
        coordinator.handleInbound(.result(Self.focusResult()))

        try await waitUntil("COMMIT") {
            recorder.events.contains(.command(.commit(syncID: 0x0102_0304)))
        }
        coordinator.handleInbound(.result(Self.datasetResult()))

        let completion = try await task.value
        #expect(completion.didCommitDatasets)
        #expect(completion.didResolveFocus)
        let dayPack = try #require(recorder.events.firstIndex(of: .dayPack(Data([0x10]))))
        let schedule = try #require(recorder.events.firstIndex(of: .schedule(Data([0x03]))))
        #expect(dayPack < schedule)
    }

    @Test("FOCUS_RESOLVE timeout retries the same payload and keeps 0x14 frozen")
    func timeoutRetriesAndKeepsFreeze() async throws {
        var nextResolveID: UInt32 = 7
        let recorder = Recorder()
        let coordinator = recorder.makeCoordinator(
            responseTimeout: .milliseconds(40),
            resolveFocus: { state in
                guard state.focusRevision < UInt32.max else {
                    fatalError("Focus revision exhausted in test fixture")
                }
                let resolveID = nextResolveID
                nextResolveID += 1
                return OfflineFocusResolve(
                    resolveID: resolveID,
                    sessionId: state.sessionId,
                    focusState: .active,
                    result: .accepted,
                    startTimestamp: state.startTimestamp,
                    endTimestamp: state.endTimestamp,
                    elapsedSeconds: state.elapsedSeconds,
                    focusRevision: state.focusRevision + 1,
                    phase: .idle,
                    bottles: 0
                )
            }
        )
        coordinator.hasActiveFocusSession = { true }

        let task = Task { try await coordinator.synchronize() }
        try await waitUntil("QUERY") {
            recorder.events.contains(.command(.query))
        }
        coordinator.handleInbound(.state(Self.state(
            stateFlags: [.dataValid, .focusSyncPending]
        )))
        coordinator.handleInbound(.focusState(FocusWireFixtures.focusState(bootSessionID: 7)))

        await #expect(throws: BLEOfflineSyncCoordinatorError.timedOut) {
            _ = try await task.value
        }
        #expect(recorder.restored.isEmpty)
        #expect(recorder.unfreezeCount == 0)
        #expect(recorder.focusResolves.count == 2)
        #expect(recorder.focusResolves[0] == recorder.focusResolves[1])
    }

    @Test("NeedsFullSync without FocusSyncPending still waits for FOCUS_STATE and defers COMMIT")
    func liveSessionDefersFullSyncCommit() async throws {
        let recorder = Recorder()
        let coordinator = recorder.makeCoordinator()
        coordinator.hasActiveFocusSession = { true }

        let task = Task { try await coordinator.synchronize() }
        try await waitUntil("QUERY") {
            recorder.events.contains(.command(.query))
        }
        coordinator.handleInbound(.state(Self.state(stateFlags: [.needsFullSync])))
        coordinator.handleInbound(.focusState(FocusWireFixtures.focusState(bootSessionID: 7)))

        try await waitUntil("FOCUS_RESOLVE") {
            recorder.events.contains { event in
                if case .command(.focusResolve) = event { return true }
                return false
            }
        }
        coordinator.handleInbound(.result(Self.focusResult()))

        let completion = try await task.value
        #expect(completion.didResolveFocus)
        #expect(completion.didCommitDatasets == false)
        #expect(!recorder.events.contains(.snapshot))
    }

    @Test("All-zero idle FOCUS_STATE without pending or an App session skips FOCUS_RESOLVE")
    func idleZeroSnapshotWithoutPendingSkipsResolveAndCommits() async throws {
        let recorder = Recorder()
        let coordinator = recorder.makeCoordinator()
        coordinator.hasActiveFocusSession = { false }

        let task = Task { try await coordinator.synchronize() }
        try await waitUntil("QUERY") {
            recorder.events.contains(.command(.query))
        }
        coordinator.handleInbound(.focusState(FocusWireFixtures.idleZeroFocusState()))
        coordinator.handleInbound(.state(Self.state(stateFlags: [.needsFullSync])))

        try await waitUntil("COMMIT") {
            recorder.events.contains(.command(.commit(syncID: 0x0102_0304)))
        }
        coordinator.handleInbound(.result(Self.datasetResult()))

        let completion = try await task.value
        #expect(completion.didResolveFocus == false)
        #expect(completion.didCommitDatasets)
        #expect(recorder.unfreezeCount == 1)
        #expect(!recorder.events.contains { event in
            if case .command(.focusResolve) = event { return true }
            return false
        })
    }

    @Test("All-zero idle FOCUS_STATE still resolves when FocusSyncPending is set")
    func idleZeroSnapshotStillResolvesWhenPending() async throws {
        let recorder = Recorder()
        let coordinator = recorder.makeCoordinator()
        coordinator.hasActiveFocusSession = { false }

        let task = Task {
            try await coordinator.synchronize(shouldCommitDatasets: { _ in false })
        }
        try await waitUntil("QUERY") {
            recorder.events.contains(.command(.query))
        }
        coordinator.handleInbound(.state(Self.state(stateFlags: [.dataValid, .focusSyncPending])))
        coordinator.handleInbound(.focusState(FocusWireFixtures.idleZeroFocusState()))

        try await waitUntil("FOCUS_RESOLVE") {
            recorder.events.contains { event in
                if case .command(.focusResolve) = event { return true }
                return false
            }
        }
        coordinator.handleInbound(.result(Self.focusResult()))

        let completion = try await task.value
        #expect(completion.didResolveFocus)
        #expect(recorder.unfreezeCount == 1)
    }

    @Test("FOCUS_RESOLVE INVALID_STATE requeries once then skips a now-idle snapshot")
    func invalidStateRequeriesOnceThenSkipsIdle() async throws {
        let recorder = Recorder()
        let coordinator = recorder.makeCoordinator()
        coordinator.hasActiveFocusSession = { false }

        let task = Task { try await coordinator.synchronize() }
        try await waitUntil("QUERY") {
            recorder.events.contains(.command(.query))
        }
        coordinator.handleInbound(.state(Self.state(
            stateFlags: [.needsFullSync, .focusSyncPending]
        )))
        coordinator.handleInbound(.focusState(FocusWireFixtures.focusState(bootSessionID: 7)))

        try await waitUntil("FOCUS_RESOLVE") {
            recorder.events.contains { event in
                if case .command(.focusResolve) = event { return true }
                return false
            }
        }
        coordinator.handleInbound(.result(Self.focusResult(code: .invalidState)))

        try await waitUntil("second QUERY") {
            recorder.events.filter { $0 == .command(.query) }.count == 2
        }
        coordinator.handleInbound(.focusState(FocusWireFixtures.idleZeroFocusState()))
        coordinator.handleInbound(.state(Self.state(stateFlags: [.needsFullSync])))

        try await waitUntil("COMMIT") {
            recorder.events.contains(.command(.commit(syncID: 0x0102_0304)))
        }
        coordinator.handleInbound(.result(Self.datasetResult()))

        let completion = try await task.value
        #expect(completion.didResolveFocus == false)
        #expect(completion.didCommitDatasets)
        #expect(recorder.events.filter {
            if case .command(.focusResolve) = $0 { return true }
            return false
        }.count == 1)
        #expect(recorder.unfreezeCount == 1)
    }

    @Test("A second FOCUS_RESOLVE INVALID_STATE still rejects and does not unlock")
    func secondInvalidStateStillRejects() async throws {
        let recorder = Recorder()
        let coordinator = recorder.makeCoordinator()
        coordinator.hasActiveFocusSession = { false }

        let task = Task { try await coordinator.synchronize() }
        try await waitUntil("QUERY") {
            recorder.events.contains(.command(.query))
        }
        coordinator.handleInbound(.state(Self.state(
            stateFlags: [.needsFullSync, .focusSyncPending]
        )))
        coordinator.handleInbound(.focusState(FocusWireFixtures.focusState(bootSessionID: 7)))

        try await waitUntil("FOCUS_RESOLVE") {
            recorder.events.contains { event in
                if case .command(.focusResolve) = event { return true }
                return false
            }
        }
        coordinator.handleInbound(.result(Self.focusResult(code: .invalidState)))

        try await waitUntil("second QUERY") {
            recorder.events.filter { $0 == .command(.query) }.count == 2
        }
        coordinator.handleInbound(.state(Self.state(
            stateFlags: [.needsFullSync, .focusSyncPending]
        )))
        coordinator.handleInbound(.focusState(FocusWireFixtures.focusState(bootSessionID: 7)))

        try await waitUntil("second FOCUS_RESOLVE") {
            recorder.events.filter {
                if case .command(.focusResolve) = $0 { return true }
                return false
            }.count == 2
        }
        coordinator.handleInbound(.result(Self.focusResult(code: .invalidState)))

        await #expect(throws: BLEOfflineSyncCoordinatorError.deviceRejected(.invalidState)) {
            _ = try await task.value
        }
        #expect(recorder.restored.isEmpty)
        #expect(recorder.unfreezeCount == 0)
        #expect(!recorder.events.contains(.command(.commit(syncID: 0x0102_0304))))
    }

    @Test("FOCUS_STATE without FocusSyncPending still resolves before ordinary 0x14 unlocks")
    func snapshotWithoutPendingFlagStillResolves() async throws {
        let recorder = Recorder()
        let coordinator = recorder.makeCoordinator()
        coordinator.hasActiveFocusSession = { false }

        let task = Task {
            try await coordinator.synchronize(shouldCommitDatasets: { _ in false })
        }
        try await waitUntil("QUERY") {
            recorder.events.contains(.command(.query))
        }
        coordinator.handleInbound(.focusState(FocusWireFixtures.focusState(bootSessionID: 7)))
        coordinator.handleInbound(.state(Self.state(stateFlags: [.dataValid])))

        try await waitUntil("FOCUS_RESOLVE") {
            recorder.events.contains { event in
                if case .command(.focusResolve) = event { return true }
                return false
            }
        }
        coordinator.handleInbound(.result(Self.focusResult()))

        let completion = try await task.value
        #expect(completion.didResolveFocus)
        #expect(recorder.unfreezeCount == 1)
        #expect(recorder.restored.count == 1)
    }

    @Test("Active session without FOCUS_STATE keeps 0x14 frozen")
    func activeSessionWithoutSnapshotKeepsFreeze() async throws {
        let recorder = Recorder()
        let coordinator = recorder.makeCoordinator(responseTimeout: .milliseconds(40))
        coordinator.hasActiveFocusSession = { true }

        let task = Task { try await coordinator.synchronize() }
        try await waitUntil("QUERY") {
            recorder.events.contains(.command(.query))
        }
        coordinator.handleInbound(.state(Self.state(stateFlags: [.dataValid])))

        await #expect(throws: BLEOfflineSyncCoordinatorError.timedOut) {
            _ = try await task.value
        }
        #expect(recorder.unfreezeCount == 0)
        #expect(recorder.restored.isEmpty)
        #expect(!recorder.events.contains { event in
            if case .command(.focusResolve) = event { return true }
            return false
        })
    }

    @Test("INVALID_STATE requery drains new ops and does not COMMIT from the old STATE")
    func invalidStateRequeryUsesNewStateAndPendingOps() async throws {
        let recorder = Recorder()
        let coordinator = recorder.makeCoordinator()
        coordinator.hasActiveFocusSession = { false }

        let task = Task {
            try await coordinator.synchronize(shouldCommitDatasets: { _ in false })
        }
        try await waitUntil("QUERY") {
            recorder.events.contains(.command(.query))
        }
        coordinator.handleInbound(.state(Self.state(
            stateFlags: [.needsFullSync, .focusSyncPending]
        )))
        coordinator.handleInbound(.focusState(FocusWireFixtures.focusState(bootSessionID: 7)))

        try await waitUntil("FOCUS_RESOLVE") {
            !recorder.focusResolves.isEmpty
        }
        coordinator.handleInbound(.result(Self.focusResult(code: .invalidState)))

        try await waitUntil("second QUERY") {
            recorder.events.filter { $0 == .command(.query) }.count == 2
        }
        coordinator.handleInbound(.state(Self.state(
            stateFlags: [.dataValid],
            pendingCount: 1,
            bootSessionID: 8
        )))
        coordinator.handleInbound(.operationBatch(.init(
            bootSessionID: 8,
            records: [Self.record(3)]
        )))

        try await waitUntil("OP_ACK") {
            recorder.events.contains(.command(.opAck(.init(
                bootSessionID: 8,
                ackOperationID: 3
            ))))
        }

        let completion = try await task.value
        #expect(completion.didResolveFocus == false)
        #expect(completion.didCommitDatasets == false)
        #expect(completion.processedOperationCount == 1)
        #expect(completion.state.bootSessionID == 8)
        #expect(completion.state.stateFlags.contains(.needsFullSync) == false)
        #expect(recorder.processedOperations.count == 1)
        #expect(recorder.processedOperations.first?.bootSessionID == 8)
        #expect(recorder.processedOperations.first?.operationID == 3)
        #expect(!recorder.events.contains(.snapshot))
        #expect(!recorder.events.contains(.command(.commit(syncID: 0x0102_0304))))
        #expect(recorder.focusResolves.count == 1)
        #expect(recorder.unfreezeCount == 1)
    }

    @Test("INVALID_STATE requery sends a new ResolveID when the snapshot payload changes")
    func invalidStateRequeryUsesNewResolveWhenSnapshotChanges() async throws {
        let service = FocusSessionService.makeForTesting(
            focusGuardService: FocusReconnectTestGuard(),
            persistenceEnabled: false
        )
        var nextID: UInt32 = 10
        let recorder = Recorder()
        let coordinator = recorder.makeCoordinator(
            resolveFocus: { state in
                let id = nextID
                nextID += 10
                return try await service.resolveReconnect(state, resolveID: id)
            },
            restoreOrdinaryFocusSync: { snapshot, resolve in
                try await service.commitReconnectAfterResolve(from: snapshot, resolve: resolve)
                recorder.restored.append((snapshot, resolve))
            },
            abandonPendingFocusResolve: {
                service.abandonPendingReconnect()
            },
            invalidatePendingFocusResolve: {
                service.invalidatePendingReconnectAfterInvalidState()
            }
        )
        coordinator.hasActiveFocusSession = { false }

        let task = Task {
            try await coordinator.synchronize(shouldCommitDatasets: { _ in false })
        }
        try await waitUntil("QUERY") {
            recorder.events.contains(.command(.query))
        }
        let firstSnapshot = FocusWireFixtures.focusState(bootSessionID: 7, elapsed: 120)
        coordinator.handleInbound(.state(Self.state(
            stateFlags: [.dataValid, .focusSyncPending]
        )))
        coordinator.handleInbound(.focusState(firstSnapshot))

        try await waitUntil("FOCUS_RESOLVE") {
            recorder.focusResolves.count == 1
        }
        #expect(service.activeSession == nil)
        coordinator.handleInbound(.result(Self.focusResult(
            syncID: recorder.focusResolves[0].resolveID,
            code: .invalidState
        )))

        try await waitUntil("second QUERY") {
            recorder.events.filter { $0 == .command(.query) }.count == 2
        }
        let secondSnapshot = FocusWireFixtures.focusState(bootSessionID: 7, elapsed: 400)
        coordinator.handleInbound(.state(Self.state(
            stateFlags: [.dataValid, .focusSyncPending]
        )))
        coordinator.handleInbound(.focusState(secondSnapshot))

        try await waitUntil("second FOCUS_RESOLVE") {
            recorder.focusResolves.count == 2
        }
        #expect(service.activeSession == nil)
        let firstResolve = recorder.focusResolves[0]
        let secondResolve = recorder.focusResolves[1]
        #expect(firstResolve.resolveID == 10)
        #expect(secondResolve.resolveID == 20)
        #expect(firstResolve.elapsedSeconds == 120)
        #expect(secondResolve.elapsedSeconds == 400)
        #expect(firstResolve.matchesPayload(of: secondResolve) == false)

        coordinator.handleInbound(.result(Self.focusResult(syncID: secondResolve.resolveID)))

        let completion = try await task.value
        #expect(completion.didResolveFocus)
        #expect(service.activeSession?.focusSessionId == secondSnapshot.sessionId)
        #expect(recorder.restored.count == 1)
    }

    private static func state(
        stateFlags: OfflineSyncStateFlags,
        pendingCount: UInt8 = 0,
        bootSessionID: UInt32 = 7
    ) -> OfflineSyncState {
        OfflineSyncState(
            activeRevision: 11,
            validUntil: 2_000_000_000,
            datasetMask: .all,
            stateFlags: stateFlags,
            pendingCount: pendingCount,
            bootSessionID: bootSessionID,
            currentSyncID: 0
        )
    }

    private static func record(_ operationID: UInt32) -> OfflineSyncOperationRecord {
        OfflineSyncOperationRecord(
            operationID: operationID,
            eventType: 0x01,
            originalPayload: Data([UInt8(truncatingIfNeeded: operationID)])
        )
    }

    private static func focusResult(
        syncID: UInt32 = 1,
        code: OfflineSyncResultCode = .committed
    ) -> OfflineSyncResult {
        OfflineSyncResult(
            syncID: syncID,
            targetType: .offlineSync,
            resultCode: code
        )
    }

    private static func datasetResult() -> OfflineSyncResult {
        OfflineSyncResult(
            syncID: 0x0102_0304,
            targetType: .offlineSync,
            resultCode: .committed
        )
    }

    private func waitUntil(
        _ description: String,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        while !condition() {
            guard clock.now < deadline else {
                Issue.record("Timed out waiting for \(description)")
                throw BLEOfflineSyncCoordinatorError.timedOut
            }
            try await Task.sleep(for: .milliseconds(1))
        }
    }
}

@MainActor
private final class FocusReconnectTestGuard: FocusGuardService {
    var authorizationStatus: FocusAuthorizationStatus = .notDetermined
    var isDeepFocusFeatureEnabled = false
    var isDeepFocusCapable = false
    var canShowDeepFocusEntry: Bool { false }
    var selectedApplicationCount = 0
    var isPickerPresented = false
    func refreshAuthorizationStatus() async {}
    func requestAuthorization() async -> FocusAuthorizationStatus { .notDetermined }
    func presentAppPicker() {}
    func applyShield(selection: FocusAppSelection) throws {}
    func clearShield() {}
    func currentSelection() -> FocusAppSelection? { nil }
}
