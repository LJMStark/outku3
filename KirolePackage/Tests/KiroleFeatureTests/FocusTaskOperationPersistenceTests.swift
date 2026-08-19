import Foundation
import Testing
@testable import KiroleFeature

@Suite("Hardware task focus persistence", .serialized)
struct FocusTaskOperationPersistenceTests {
    @Test("Mismatched FocusSessionId does not end the active session")
    @MainActor
    func mismatchedFocusSessionIdDoesNotEndActiveSession() async {
        let persistence = FocusPersistenceFailureStub()
        let service = makeService(persistence: persistence)
        let start = Date().addingTimeInterval(-60)
        let activeId = FocusSessionId(bootSessionID: 7, startOperationID: 3)
        await service.startSession(
            taskId: "focus-session-mismatch",
            taskTitle: "Mismatch",
            startTime: start,
            focusSessionId: activeId
        )
        let entry = operationEntry(
            taskID: "focus-session-mismatch",
            operationID: 800,
            action: .completeTask,
            start: start
        )

        let result = await service.settleHardwareTaskOperation(
            entry,
            focusSessionId: FocusSessionId(bootSessionID: 7, startOperationID: 4)
        )

        #expect(result == .durable)
        #expect(service.activeSession?.focusSessionId == activeId)
        #expect(await persistence.activeSession()?.focusSessionId == activeId)
        #expect(service.todaySessions.isEmpty)
    }

    @Test("History failure keeps the active marker and exact retry finishes once")
    @MainActor
    func historyFailureRetries() async {
        let persistence = FocusPersistenceFailureStub(failHistorySaves: 1)
        let service = makeService(persistence: persistence)
        let start = Date().addingTimeInterval(-60)
        await service.startSession(taskId: "focus-history", taskTitle: "History", startTime: start)
        let entry = operationEntry(
            taskID: "focus-history",
            operationID: 801,
            action: .completeTask,
            start: start
        )

        let first = await service.settleHardwareTaskOperation(entry)
        #expect(first == .persistenceFailed)
        #expect(await persistence.activeSession()?.id != nil)
        #expect(await persistence.sessions().isEmpty)

        let retry = await service.settleHardwareTaskOperation(entry)
        #expect(retry == .durable)
        #expect(await persistence.activeSession() == nil)
        #expect(await persistence.sessions().map(\.id) == [service.todaySessions[0].id])
    }

    @Test("Clear failure leaves one history row and retry never duplicates it")
    @MainActor
    func clearFailureRetriesIdempotently() async {
        let persistence = FocusPersistenceFailureStub(failClears: 1)
        let service = makeService(persistence: persistence)
        let start = Date().addingTimeInterval(-60)
        await service.startSession(taskId: "focus-clear", taskTitle: "Clear", startTime: start)
        let entry = operationEntry(
            taskID: "focus-clear",
            operationID: 802,
            action: .skipTask,
            start: start
        )

        let first = await service.settleHardwareTaskOperation(entry)
        #expect(first == .persistenceFailed)
        #expect(await persistence.sessions().count == 1)
        #expect(await persistence.activeSession()?.id != nil)

        let retry = await service.settleHardwareTaskOperation(entry)
        #expect(retry == .durable)
        #expect(await persistence.sessions().count == 1)
        #expect(await persistence.activeSession() == nil)
    }

    @Test("Launch recovery maps a pending Complete WAL to completed")
    @MainActor
    func pendingCompleteRestoresEndReason() async {
        await verifyLaunchRecovery(action: .completeTask, expected: .completed, operationID: 803)
    }

    @Test("Launch recovery maps a pending Skip WAL to skipped")
    @MainActor
    func pendingSkipRestoresEndReason() async {
        await verifyLaunchRecovery(action: .skipTask, expected: .skipped, operationID: 804)
    }

    @Test("Launch recovery uses App receipt time for a live Complete with lagging device RTC")
    @MainActor
    func liveCompleteWithLaggingRTCRecoversAsCompleted() async {
        let start = Date().addingTimeInterval(-120)
        let active = FocusSession(
            taskId: "focus-live-lagging-rtc",
            taskTitle: "Live clock",
            startTime: start
        )
        let recordedAt = Date()
        let entry = TaskOperationLedgerEntry(
            deviceID: "test-device",
            action: .completeTask,
            operationID: 807,
            taskID: active.taskId,
            deviceTimestamp: UInt32(start.addingTimeInterval(-3_600).timeIntervalSince1970),
            result: .applied,
            state: .pending,
            recordedAt: recordedAt,
            timestampAuthority: .appReceipt
        )
        let persistence = FocusPersistenceFailureStub(initialActive: active)
        let service = makeService(
            persistence: persistence,
            ledger: TaskOperationLedger(persistenceEnabled: false, initialEntries: [entry]),
            launchRecoveryCompleted: false
        )

        await service.bootstrapForTesting()

        #expect(service.todaySessions.count == 1)
        #expect(service.todaySessions[0].endReason == .completed)
        #expect(service.todaySessions[0].endTime == recordedAt)
        #expect(await persistence.activeSession() == nil)
    }

    @Test("Launch recovery never applies an earlier live pending operation to a newer focus")
    @MainActor
    func earlierLivePendingCannotRecoverNewerFocus() async {
        let start = Date()
        let active = FocusSession(
            taskId: "focus-live-newer-session",
            taskTitle: "Newer focus",
            startTime: start
        )
        let entry = TaskOperationLedgerEntry(
            deviceID: "test-device",
            action: .skipTask,
            operationID: 809,
            taskID: active.taskId,
            deviceTimestamp: UInt32(start.timeIntervalSince1970),
            result: .applied,
            state: .pending,
            recordedAt: start.addingTimeInterval(-1),
            timestampAuthority: .appReceipt
        )
        let persistence = FocusPersistenceFailureStub(initialActive: active)
        let service = makeService(
            persistence: persistence,
            ledger: TaskOperationLedger(persistenceEnabled: false, initialEntries: [entry]),
            launchRecoveryCompleted: false
        )

        await service.bootstrapForTesting()

        #expect(service.todaySessions.count == 1)
        #expect(service.todaySessions[0].endReason == .recoveredOnLaunch)
    }

    @Test("A changed same-task focus generation is rejected at the settlement boundary")
    @MainActor
    func changedGenerationCannotEndNewFocus() async {
        let persistence = FocusPersistenceFailureStub()
        let service = makeService(persistence: persistence)
        let start = Date().addingTimeInterval(-60)
        await service.startSession(
            taskId: "focus-generation-boundary",
            taskTitle: "Original",
            startTime: start
        )
        let expectedGeneration = service.sessionStartGeneration(for: "focus-generation-boundary")
        let entry = operationEntry(
            taskID: "focus-generation-boundary",
            operationID: 808,
            action: .skipTask,
            start: start
        )

        service.endSession(reason: .manual)
        await service.waitForPendingPersistenceForTesting()
        await service.startSession(
            taskId: "focus-generation-boundary",
            taskTitle: "Replacement"
        )
        let replacementID = service.activeSession?.id

        let result = await service.settleHardwareTaskOperation(
            entry,
            expectedSessionStartGeneration: expectedGeneration
        )

        #expect(result == .supersededByApp)
        #expect(service.activeSession?.id == replacementID)
    }

    @Test("History plus active marker on launch is upserted by session ID")
    @MainActor
    func launchRecoveryDoesNotDuplicateHistory() async {
        let start = Date().addingTimeInterval(-120)
        let active = FocusSession(taskId: "focus-upsert", taskTitle: "Upsert", startTime: start)
        var priorHistory = active
        let originalEndTime = start.addingTimeInterval(30)
        priorHistory.endTime = originalEndTime
        priorHistory.endReason = .skipped
        priorHistory.calculatedFocusTime = 17
        priorHistory.earnedEnergyBottles = 0
        let persistence = FocusPersistenceFailureStub(
            initialSessions: [priorHistory],
            initialActive: active
        )
        let service = makeService(
            persistence: persistence,
            ledger: TaskOperationLedger(persistenceEnabled: false, initialEntries: []),
            launchRecoveryCompleted: false
        )

        await service.bootstrapForTesting()

        #expect(service.todaySessions.count == 1)
        #expect(await persistence.sessions().count == 1)
        #expect(await persistence.activeSession() == nil)
        #expect(service.todaySessions[0].endTime == originalEndTime)
        #expect(service.todaySessions[0].endReason == .skipped)
        #expect(service.todaySessions[0].calculatedFocusTime == 17)
        #expect(service.todaySessions[0].earnedEnergyBottles == 0)
    }

    @Test("A crash after active clear repairs the energy reward exactly once on launch")
    @MainActor
    func launchRepairsEnergyAfterClear() async {
        let persistence = FocusPersistenceFailureStub(failEnergyAwards: 1)
        let start = Date().addingTimeInterval(-31 * 60)
        let entry = operationEntry(
            taskID: "focus-energy-repair",
            operationID: 805,
            action: .completeTask,
            start: start
        )
        let firstService = makeService(persistence: persistence)
        await firstService.startSession(
            taskId: entry.taskID,
            taskTitle: "Energy repair",
            startTime: start
        )

        #expect(await firstService.settleHardwareTaskOperation(entry) == .persistenceFailed)
        #expect(await persistence.activeSession() == nil)
        #expect(await persistence.sessions().count == 1)
        #expect(await persistence.energyTotal() == 0)

        let restarted = makeService(
            persistence: persistence,
            ledger: TaskOperationLedger(persistenceEnabled: false, initialEntries: [entry]),
            launchRecoveryCompleted: false
        )
        await restarted.bootstrapForTesting()

        #expect(await persistence.energyTotal() == 1)
        #expect(await restarted.settleHardwareTaskOperation(entry) == .durable)
        #expect(await persistence.energyTotal() == 1)
    }

    @Test("Hardware settlement waits for the launch recovery barrier")
    @MainActor
    func settlementWaitsForLaunchRecovery() async {
        let persistence = FocusPersistenceFailureStub()
        let service = makeService(persistence: persistence)
        let start = Date().addingTimeInterval(-60)
        await service.startSession(taskId: "focus-barrier", taskTitle: "Barrier", startTime: start)
        let entry = operationEntry(
            taskID: "focus-barrier",
            operationID: 806,
            action: .skipTask,
            start: start
        )
        let barrier = FocusLaunchBarrier()
        service.installLaunchRecoveryBarrierForTesting(Task { await barrier.wait() })

        let settlement = Task { @MainActor in
            await service.settleHardwareTaskOperation(entry)
        }
        await Task.yield()
        #expect(service.activeSession?.taskId == "focus-barrier")

        await barrier.release()
        #expect(await settlement.value == .durable)
        #expect(service.activeSession == nil)
    }

    @MainActor
    private func verifyLaunchRecovery(
        action: TaskListSnapshotAction,
        expected: FocusEndReason,
        operationID: UInt32
    ) async {
        let start = Date().addingTimeInterval(-120)
        let active = FocusSession(taskId: "focus-launch-\(operationID)", taskTitle: "Launch", startTime: start)
        let entry = operationEntry(
            taskID: active.taskId,
            operationID: operationID,
            action: action,
            start: start
        )
        let persistence = FocusPersistenceFailureStub(initialActive: active)
        let ledger = TaskOperationLedger(persistenceEnabled: false, initialEntries: [entry])
        let service = makeService(
            persistence: persistence,
            ledger: ledger,
            launchRecoveryCompleted: false
        )

        await service.bootstrapForTesting()

        #expect(service.todaySessions.count == 1)
        #expect(service.todaySessions[0].endReason == expected)
        #expect(await persistence.sessions().map(\.endReason) == [expected])
        #expect(await persistence.activeSession() == nil)
    }

    @MainActor
    private func makeService(
        persistence: FocusPersistenceFailureStub,
        ledger: TaskOperationLedger = TaskOperationLedger(
            persistenceEnabled: false,
            initialEntries: []
        ),
        launchRecoveryCompleted: Bool = true
    ) -> FocusSessionService {
        FocusSessionService.makeForTesting(
            focusGuardService: FocusPersistenceGuardStub(),
            persistenceEnabled: true,
            launchRecoveryCompleted: launchRecoveryCompleted,
            focusPersistence: persistence,
            taskOperationLedger: ledger
        )
    }

    private func operationEntry(
        taskID: String,
        operationID: UInt32,
        action: TaskListSnapshotAction,
        start: Date
    ) -> TaskOperationLedgerEntry {
        let now = Date()
        return TaskOperationLedgerEntry(
            deviceID: "test-device",
            action: action,
            operationID: operationID,
            taskID: taskID,
            deviceTimestamp: UInt32(max(start, now.addingTimeInterval(-1)).timeIntervalSince1970),
            result: .applied,
            state: .pending,
            recordedAt: now
        )
    }
}

private actor FocusPersistenceFailureStub: FocusSessionPersisting {
    private var storedSessions: [FocusSession]
    private var storedActive: FocusSession?
    private var remainingHistoryFailures: Int
    private var remainingClearFailures: Int
    private var remainingEnergyAwardFailures: Int
    private var energyAwards: [UUID: Int] = [:]
    private var storedEnergyTotal = 0

    init(
        initialSessions: [FocusSession] = [],
        initialActive: FocusSession? = nil,
        failHistorySaves: Int = 0,
        failClears: Int = 0,
        failEnergyAwards: Int = 0
    ) {
        storedSessions = initialSessions
        storedActive = initialActive
        remainingHistoryFailures = failHistorySaves
        remainingClearFailures = failClears
        remainingEnergyAwardFailures = failEnergyAwards
    }

    func loadSessions() async throws -> [FocusSession]? {
        storedSessions
    }

    func saveSessions(_ sessions: [FocusSession], date: Date) async throws {
        if remainingHistoryFailures > 0 {
            remainingHistoryFailures -= 1
            throw FocusPersistenceTestError.injectedHistoryFailure
        }
        storedSessions = sessions
    }

    func loadActiveSession() async throws -> FocusSession? {
        storedActive
    }

    func saveActiveSession(_ session: FocusSession) async throws {
        storedActive = session
    }

    func clearActiveSession() async throws {
        if remainingClearFailures > 0 {
            remainingClearFailures -= 1
            throw FocusPersistenceTestError.injectedClearFailure
        }
        storedActive = nil
    }

    func applyEnergyReward(receiptID: UUID, bottles: Int) async throws -> Int {
        if remainingEnergyAwardFailures > 0 {
            remainingEnergyAwardFailures -= 1
            throw FocusPersistenceTestError.injectedEnergyAwardFailure
        }
        if let target = energyAwards[receiptID] {
            storedEnergyTotal = max(storedEnergyTotal, target)
            return storedEnergyTotal
        }
        let target = storedEnergyTotal + max(0, bottles)
        energyAwards[receiptID] = target
        storedEnergyTotal = target
        return target
    }

    func sessions() -> [FocusSession] {
        storedSessions
    }

    func activeSession() -> FocusSession? {
        storedActive
    }

    func energyTotal() -> Int {
        storedEnergyTotal
    }
}

private enum FocusPersistenceTestError: Error {
    case injectedHistoryFailure
    case injectedClearFailure
    case injectedEnergyAwardFailure
}

private actor FocusLaunchBarrier {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isReleased = false

    func wait() async {
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func release() {
        isReleased = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class FocusPersistenceGuardStub: FocusGuardService {
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
