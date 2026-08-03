import Foundation
import Testing
@testable import KiroleFeature

/// Issue #25: merge offline device Complete/Skip with concurrent App task state.
@Suite("Offline task state merge", .serialized)
struct OfflineTaskStateMergeTests {
    private let deviceID = "merge-device"

    @Test("App status authority after device Complete timestamp supersedes offline replay")
    @MainActor
    func statusAuthorityAfterDeviceEventSupersedesOfflineComplete() async {
        let appState = AppState.makeForTesting()
        let t0 = Date(timeIntervalSince1970: 1_700_000_700)
        let task = TaskItem(
            id: "merge-status-authority",
            title: "Stay open",
            isCompleted: false,
            dueDate: Date(),
            lastModified: t0.addingTimeInterval(30),
            statusAuthorityAt: t0.addingTimeInterval(30)
        )
        appState.tasks = [task]
        let focus = makeFocusService()
        let ledger = TaskOperationLedger(persistenceEnabled: false)

        // Device completed at t0; App already owns status at t0+30; receive at t0+60.
        let event = completeEvent(
            taskID: task.id,
            operationID: 2_530,
            timestamp: t0
        )
        let receipt = await process(event, focus: focus, ledger: ledger, appState: appState)

        #expect(receipt.result == .supersededByApp)
        #expect(appState.tasks.first?.isCompleted == false)
        #expect(appState.tasks.first?.id == task.id)
        #expect(appState.tasks.first?.statusAuthorityAt == t0.addingTimeInterval(30))
    }

    @Test("Content edit then offline Complete keeps the task completed and absent from the queue")
    @MainActor
    func contentEditThenCompleteWins() async {
        let appState = AppState.makeForTesting()
        let task = TaskItem(
            id: "merge-complete",
            title: "Original",
            dueDate: Date(),
            lastModified: Date(timeIntervalSince1970: 1_700_000_000)
        )
        appState.tasks = [task]
        let focus = makeFocusService()
        let ledger = TaskOperationLedger(persistenceEnabled: false)
        let persistence = RecordingMergePersistence()

        var edited = task
        edited.title = "App edited title"
        edited.notes = "App notes"
        edited.lastModified = Date(timeIntervalSince1970: 1_700_000_100)
        appState.tasks = [edited]

        let event = completeEvent(
            taskID: task.id,
            operationID: 2_501,
            timestamp: Date(timeIntervalSince1970: 1_700_000_050)
        )
        let first = await process(event, focus: focus, ledger: ledger, appState: appState, persistence: persistence)
        let duplicate = await process(event, focus: focus, ledger: ledger, appState: appState, persistence: persistence)

        #expect(first.result == .applied)
        #expect(duplicate.result == .alreadyApplied || duplicate.result == .applied)
        #expect(appState.tasks.first?.isCompleted == true)
        #expect(appState.tasks.first?.title == "App edited title")
        #expect(appState.tasks.first?.notes == "App notes")
        #expect(appState.tasks.filter { !$0.isCompleted && !$0.pendingDeletion }.map(\.id).isEmpty)
        #expect(await ledger.decision(for: event, deviceID: deviceID) == .duplicate(first.result))
    }

    @Test("Content edit then offline Skip keeps latest content and moves the task to the tail")
    @MainActor
    func contentEditThenSkipKeepsContentAtTail() async {
        let appState = AppState.makeForTesting()
        let first = TaskItem(id: "merge-skip-a", title: "A", dueDate: Date())
        let second = TaskItem(id: "merge-skip-b", title: "B", dueDate: Date())
        let third = TaskItem(id: "merge-skip-c", title: "C", dueDate: Date())
        appState.tasks = [first, second, third]
        let focus = makeFocusService()
        let ledger = TaskOperationLedger(persistenceEnabled: false)

        var edited = first
        edited.title = "A revised"
        edited.notes = "latest notes"
        edited.lastModified = Date(timeIntervalSince1970: 1_700_000_200)
        appState.tasks = [edited, second, third]

        let event = skipEvent(
            taskID: first.id,
            operationID: 2_502,
            timestamp: Date(timeIntervalSince1970: 1_700_000_150)
        )
        let receipt = await process(event, focus: focus, ledger: ledger, appState: appState)

        #expect(receipt.result == .applied)
        #expect(appState.tasks.map(\.id) == [second.id, third.id, first.id])
        #expect(appState.tasks.last?.title == "A revised")
        #expect(appState.tasks.last?.notes == "latest notes")
        #expect(appState.tasks.last?.isCompleted == false)
        #expect(appState.tasks.last?.hardwareSkipOperationKey == "\(deviceID)|18|2502")
    }

    @Test("Deletion then offline Complete settles focus without resurrecting the task")
    @MainActor
    func deletionThenCompleteSettlesFocusWithoutResurrection() async {
        let appState = AppState.makeForTesting()
        let task = TaskItem(id: "merge-deleted-complete", title: "Focus me", dueDate: Date())
        appState.tasks = [task]
        let focus = makeFocusService()
        let ledger = TaskOperationLedger(persistenceEnabled: false)
        let start = Date(timeIntervalSince1970: 1_700_000_300)
        await focus.startSession(taskId: task.id, taskTitle: task.title, startTime: start)
        #expect(focus.activeSession?.taskId == task.id)

        appState.tasks = []

        let event = completeEvent(
            taskID: task.id,
            operationID: 2_503,
            timestamp: start.addingTimeInterval(31 * 60)
        )
        let first = await process(event, focus: focus, ledger: ledger, appState: appState)
        let duplicate = await process(event, focus: focus, ledger: ledger, appState: appState)

        #expect(first.result == .taskNotFound)
        #expect(duplicate.result == .taskNotFound)
        #expect(focus.activeSession == nil)
        #expect(focus.todaySessions.count == 1)
        #expect(focus.todaySessions[0].endReason == .completed)
        #expect(focus.todaySessions[0].earnedEnergyBottles >= 1)
        #expect(appState.tasks.isEmpty)
    }

    @Test("Deletion then offline Skip does not enqueue or resurrect the task")
    @MainActor
    func deletionThenSkipDoesNotEnqueue() async {
        let appState = AppState.makeForTesting()
        let kept = TaskItem(id: "merge-kept", title: "Kept", dueDate: Date())
        let deleted = TaskItem(id: "merge-deleted-skip", title: "Gone", dueDate: Date())
        appState.tasks = [kept, deleted]
        let focus = makeFocusService()
        let ledger = TaskOperationLedger(persistenceEnabled: false)
        let start = Date(timeIntervalSince1970: 1_700_000_400)
        await focus.startSession(taskId: deleted.id, taskTitle: deleted.title, startTime: start)

        appState.tasks = [kept]

        let event = skipEvent(
            taskID: deleted.id,
            operationID: 2_504,
            timestamp: start.addingTimeInterval(90)
        )
        let receipt = await process(event, focus: focus, ledger: ledger, appState: appState)

        #expect(receipt.result == .taskNotFound)
        #expect(focus.activeSession == nil)
        #expect(focus.todaySessions.last?.endReason == .skipped)
        #expect(appState.tasks.map(\.id) == [kept.id])
        #expect(appState.tasks.contains(where: { $0.id == deleted.id }) == false)
    }

    @Test("Pending deletion still blocks Complete/Skip resurrection while Complete settles focus")
    @MainActor
    func pendingDeletionBlocksResurrection() async {
        let appState = AppState.makeForTesting()
        let task = TaskItem(
            id: "merge-pending-delete",
            title: "Soft deleted",
            dueDate: Date(),
            pendingDeletion: true
        )
        appState.tasks = [task]
        let focus = makeFocusService()
        let ledger = TaskOperationLedger(persistenceEnabled: false)
        let start = Date(timeIntervalSince1970: 1_700_000_450)
        await focus.startSession(taskId: task.id, taskTitle: task.title, startTime: start)

        let complete = await process(
            completeEvent(taskID: task.id, operationID: 2_505, timestamp: start.addingTimeInterval(60)),
            focus: focus,
            ledger: ledger,
            appState: appState
        )
        #expect(complete.result == .taskNotFound)
        #expect(focus.activeSession == nil)
        #expect(appState.tasks.first?.pendingDeletion == true)
        #expect(appState.tasks.first?.isCompleted == false)

        appState.tasks = [
            TaskItem(id: task.id, title: task.title, dueDate: Date(), pendingDeletion: true)
        ]
        await focus.startSession(taskId: task.id, taskTitle: task.title, startTime: start)
        let skip = await process(
            skipEvent(taskID: task.id, operationID: 2_506, timestamp: start.addingTimeInterval(70)),
            focus: focus,
            ledger: ledger,
            appState: appState
        )
        #expect(skip.result == .taskNotFound)
        #expect(appState.tasks.map(\.id) == [task.id])
        #expect(appState.tasks.first?.pendingDeletion == true)
        #expect(appState.tasks.first?.hardwareSkipOperationKey == nil)
    }

    @Test("App reorder then offline skips append in wire order on top of the App base order")
    @MainActor
    func appReorderThenSkipsAppendInWireOrder() async {
        let appState = AppState.makeForTesting()
        // Device originally saw A,B,C. App reordered to C,A,B while offline.
        let a = TaskItem(id: "merge-order-a", title: "A", dueDate: Date())
        let b = TaskItem(id: "merge-order-b", title: "B", dueDate: Date())
        let c = TaskItem(id: "merge-order-c", title: "C", dueDate: Date())
        appState.tasks = [c, a, b]
        let focus = makeFocusService()
        let ledger = TaskOperationLedger(persistenceEnabled: false)

        // Device offline skip order (wire/insertion): A then B.
        let skipA = skipEvent(
            taskID: a.id,
            operationID: 2_510,
            timestamp: Date(timeIntervalSince1970: 1_700_000_510)
        )
        let skipB = skipEvent(
            taskID: b.id,
            operationID: 2_511,
            timestamp: Date(timeIntervalSince1970: 1_700_000_511)
        )

        let result = await BLEEventHandler.processEventLogs(
            [skipA, skipB],
            service: nil,
            focusService: focus,
            isReplay: true,
            persistLogs: false,
            operationLedger: ledger,
            deviceIDOverride: deviceID,
            appState: appState,
            hardwareTaskPersistence: RecordingMergePersistence()
        )

        #expect(result.taskOperationReceipts.map(\.result) == [.applied, .applied])
        // Base App order C,A,B → skip A → C,B,A → skip B → C,A,B
        #expect(appState.tasks.map(\.id) == [c.id, a.id, b.id])
        #expect(appState.tasks.map(\.title) == ["C", "A", "B"])
        #expect(appState.tasks[1].hardwareSkipOperationKey == "\(deviceID)|18|2510")
        #expect(appState.tasks[2].hardwareSkipOperationKey == "\(deviceID)|18|2511")
    }

    @Test("Ledger reload preserves merge results across App restart")
    @MainActor
    func ledgerReloadKeepsMergeResults() async {
        let appState = AppState.makeForTesting()
        let task = TaskItem(
            id: "merge-restart",
            title: "Before",
            dueDate: Date(),
            lastModified: Date(timeIntervalSince1970: 1_700_000_600)
        )
        appState.tasks = [task]
        var edited = task
        edited.title = "After edit"
        edited.lastModified = Date(timeIntervalSince1970: 1_700_000_620)
        appState.tasks = [edited]

        let persistence = InMemoryMergeLedgerPersistence()
        let ledger = TaskOperationLedger(
            persistenceEnabled: true,
            initialEntries: [],
            persistence: persistence
        )
        let focus = makeFocusService(ledger: ledger)
        let event = completeEvent(
            taskID: task.id,
            operationID: 2_520,
            timestamp: Date(timeIntervalSince1970: 1_700_000_610)
        )

        let first = await process(event, focus: focus, ledger: ledger, appState: appState)
        #expect(first.result == .applied)
        #expect(appState.tasks.first?.isCompleted == true)

        let reloaded = TaskOperationLedger(
            persistenceEnabled: true,
            initialEntries: nil,
            persistence: persistence
        )
        let focusAfter = makeFocusService(ledger: reloaded)
        let duplicate = await process(event, focus: focusAfter, ledger: reloaded, appState: appState)

        #expect(duplicate.result == .applied || duplicate.result == .alreadyApplied)
        #expect(await reloaded.decision(for: event, deviceID: deviceID) == .duplicate(first.result))
        #expect(appState.tasks.first?.isCompleted == true)
        #expect(appState.tasks.first?.title == "After edit")
    }

    // MARK: - Helpers

    @MainActor
    private func process(
        _ event: EventLog,
        focus: FocusSessionService,
        ledger: TaskOperationLedger,
        appState: AppState,
        persistence: (any HardwareTaskStatePersisting)? = nil
    ) async -> TaskOperationReceipt {
        let planned = BLEEventHandler.plannedTaskOperationReceipt(event, tasks: appState.tasks)
            ?? TaskOperationReceipt(
                action: TaskListSnapshotAction(eventType: event.eventType) ?? .completeTask,
                operationID: event.operationID ?? 0,
                result: .invalidRequest
            )
        return await BLETaskOperationProcessor.process(
            event,
            plannedReceipt: planned,
            deviceID: deviceID,
            focusService: focus,
            isReplay: true,
            operationLedger: ledger,
            appState: appState,
            hardwareTaskPersistence: persistence ?? RecordingMergePersistence()
        )
    }

    private func completeEvent(taskID: String, operationID: UInt32, timestamp: Date) -> EventLog {
        EventLog(
            eventType: .completeTask,
            taskId: taskID,
            operationID: operationID,
            timestamp: timestamp,
            hasDeviceTimestamp: true
        )
    }

    private func skipEvent(taskID: String, operationID: UInt32, timestamp: Date) -> EventLog {
        EventLog(
            eventType: .skipTask,
            taskId: taskID,
            operationID: operationID,
            timestamp: timestamp,
            hasDeviceTimestamp: true
        )
    }

    @MainActor
    private func makeFocusService(
        ledger: TaskOperationLedger = TaskOperationLedger(persistenceEnabled: false)
    ) -> FocusSessionService {
        FocusSessionService.makeForTesting(
            focusGuardService: MergeFocusGuardStub(),
            persistenceEnabled: false,
            taskOperationLedger: ledger
        )
    }
}

private actor RecordingMergePersistence: HardwareTaskStatePersisting {
    func saveTasks(_: [TaskItem]) async throws {}
    func savePet(_: Pet) async throws {}
}

private actor InMemoryMergeLedgerPersistence: TaskOperationLedgerPersisting {
    private var entries: [TaskOperationLedgerEntry] = []

    func loadTaskOperationLedger() async throws -> [TaskOperationLedgerEntry]? {
        entries
    }

    func saveTaskOperationLedger(_ entries: [TaskOperationLedgerEntry]) async throws {
        self.entries = entries
    }
}

@MainActor
private final class MergeFocusGuardStub: FocusGuardService {
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
