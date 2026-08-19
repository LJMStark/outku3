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
        var previewed: [OfflineFocusState] = []
        var restored: [(OfflineFocusState, OfflineFocusResolve)] = []
        let snapshot = OfflineDatasetSnapshot(
            taskListPayload: Data([0x02]),
            schedulePayload: Data([0x03]),
            dayPackPayload: Data([0x10])
        )

        func makeCoordinator(
            responseTimeout: Duration = .seconds(1)
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
                    processOperation: { _, _ in },
                    makeSyncID: { 0x0102_0304 },
                    makeValidUntil: { 0x0506_0708 },
                    freezeFocusStatus: { self.freezeCount += 1 },
                    unfreezeFocusStatus: { self.unfreezeCount += 1 },
                    previewFocusState: { self.previewed.append($0) },
                    restoreOrdinaryFocusSync: { snapshot, resolve in
                        self.restored.append((snapshot, resolve))
                    }
                )
            )
        }
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
        let recorder = Recorder()
        let coordinator = recorder.makeCoordinator(responseTimeout: .milliseconds(40))
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
        #expect(recorder.events.filter {
            if case .command(.focusResolve) = $0 { return true }
            return false
        }.count == 2)
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

    private static func state(
        stateFlags: OfflineSyncStateFlags
    ) -> OfflineSyncState {
        OfflineSyncState(
            activeRevision: 11,
            validUntil: 2_000_000_000,
            datasetMask: .all,
            stateFlags: stateFlags,
            pendingCount: 0,
            bootSessionID: 7,
            currentSyncID: 0
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
                return
            }
            try await Task.sleep(for: .milliseconds(1))
        }
    }
}
