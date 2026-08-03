import Foundation
import Testing
@testable import KiroleFeature

@MainActor
struct BLEEventReplayBarrierTests {
    @Test("Replay wait stays closed until the matching batch completes")
    func waitsForMatchingBatch() async {
        let barrier = BLEEventReplayBarrier(timeout: .seconds(30))
        let ticket = barrier.beginRequest(connectionGeneration: 7)
        let result = Task { @MainActor in await barrier.wait(for: ticket) }
        let connectedPathResult = Task { @MainActor in
            await barrier.waitForExistingRequest(connectionGeneration: 7)
        }

        await Task.yield()
        #expect(!result.isCancelled)
        barrier.completeCurrentBatch(succeeded: true)

        #expect(await result.value)
        #expect(await connectedPathResult.value == true)
        #expect(barrier.isSatisfied(connectionGeneration: 7))
        #expect(!barrier.isSatisfied(connectionGeneration: 8))
    }

    @Test("A superseded request cannot release the current connection")
    func rejectsStaleCompletion() async {
        let barrier = BLEEventReplayBarrier(timeout: .seconds(30))
        let old = barrier.beginRequest(connectionGeneration: 10)
        let oldResult = Task { @MainActor in await barrier.wait(for: old) }
        let current = barrier.beginRequest(connectionGeneration: 11)
        let currentResult = Task { @MainActor in await barrier.wait(for: current) }

        await Task.yield()
        barrier.failRequest(old)
        #expect(await oldResult.value == false)
        #expect(!barrier.isSatisfied(connectionGeneration: 11))

        barrier.completeCurrentBatch(succeeded: true)
        #expect(await currentResult.value)
    }

    @Test("Controlled timeout fails closed")
    func timeoutFailsClosed() async {
        let clock = ControlledReplaySleeper()
        let barrier = BLEEventReplayBarrier(
            timeout: .seconds(5),
            sleeper: { duration in try await clock.sleep(for: duration) }
        )
        let ticket = barrier.beginRequest(connectionGeneration: 20)
        let result = Task { @MainActor in await barrier.wait(for: ticket) }

        await clock.waitUntilSleeping()
        await clock.advance()

        #expect(await result.value == false)
        #expect(!barrier.isSatisfied(connectionGeneration: 20))
    }

    @Test("Disconnect resolves a pending replay as failure")
    func disconnectFailsClosed() async {
        let barrier = BLEEventReplayBarrier(timeout: .seconds(30))
        let ticket = barrier.beginRequest(connectionGeneration: 30)
        let result = Task { @MainActor in await barrier.wait(for: ticket) }

        await Task.yield()
        barrier.handleDisconnect()

        #expect(await result.value == false)
        #expect(!barrier.isSatisfied(connectionGeneration: 30))
    }

    @Test("A failed replay operation stops the ordered batch before the next action")
    func replayFailureStopsLaterActions() async {
        let appState = AppState.makeForTesting()
        let barrier = BLEEventReplayBarrier(timeout: .seconds(30))
        let ticket = barrier.beginRequest(connectionGeneration: 40)
        let first = TaskItem(id: "replay-first", title: "First")
        let second = TaskItem(id: "replay-second", title: "Second")
        let third = TaskItem(id: "replay-third", title: "Third")
        appState.tasks = [first, second, third]
        let persistence = FailFirstReplayPersistence()
        let ledger = TaskOperationLedger(persistenceEnabled: false)
        let focus = FocusSessionService.makeForTesting(
            focusGuardService: ControlledFocusGuardStub(),
            taskOperationLedger: ledger
        )
        let firstEvent = EventLog(
            eventType: .skipTask,
            taskId: first.id,
            operationID: 101,
            timestamp: Date(timeIntervalSince1970: 1_700_000_101),
            hasDeviceTimestamp: true
        )
        let secondEvent = EventLog(
            eventType: .skipTask,
            taskId: second.id,
            operationID: 102,
            timestamp: Date(timeIntervalSince1970: 1_700_000_102),
            hasDeviceTimestamp: true
        )

        let result = await BLEEventHandler.processEventLogs(
            [firstEvent, secondEvent],
            service: nil,
            focusService: focus,
            isReplay: true,
            lastTimestampOverride: 0,
            persistLogs: false,
            operationLedger: ledger,
            deviceIDOverride: "replay-device",
            appState: appState,
            hardwareTaskPersistence: persistence
        )

        #expect(result.didFailReplay)
        #expect(result.logs.map(\.operationID) == [101])
        #expect(result.taskOperationReceipts.map(\.operationID) == [101])
        #expect(result.taskOperationReceipts.map(\.result) == [.internalError])
        #expect(appState.tasks.map(\.id) == [second.id, third.id, first.id])
        #expect(appState.tasks.first(where: { $0.id == second.id })?.hardwareSkipOperationKey == nil)
        #expect(await ledger.decision(for: secondEvent, deviceID: "replay-device") == .new)

        barrier.completeCurrentBatch(succeeded: !result.didFailReplay)
        let replaySucceeded = await barrier.wait(for: ticket)
        var taskLibrarySendCount = 0
        if replaySucceeded {
            taskLibrarySendCount += 1
        }
        #expect(!replaySucceeded)
        #expect(taskLibrarySendCount == 0)
    }
}

private actor ControlledReplaySleeper {
    private var continuation: CheckedContinuation<Void, Error>?
    private var waitingContinuations: [CheckedContinuation<Void, Never>] = []

    func sleep(for _: Duration) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            waitingContinuations.forEach { $0.resume() }
            waitingContinuations = []
        }
    }

    func waitUntilSleeping() async {
        if continuation != nil { return }
        await withCheckedContinuation { continuation in
            waitingContinuations.append(continuation)
        }
    }

    func advance() {
        continuation?.resume()
        continuation = nil
    }
}

private actor FailFirstReplayPersistence: HardwareTaskStatePersisting {
    private var hasFailed = false

    func saveTasks(_: [TaskItem]) async throws {
        guard hasFailed else {
            hasFailed = true
            throw ReplayPersistenceFailure.injected
        }
    }

    func savePet(_: Pet) async throws {}
}

private enum ReplayPersistenceFailure: Error {
    case injected
}
