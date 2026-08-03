import Foundation
import Testing
@testable import KiroleFeature

@Suite("Simulator bridge integration", .serialized)
struct SimulatorBridgeIntegrationTests {
    @Test("Hardware presentation exports the complete queue with wire IDs and prepared phase text")
    @MainActor
    func completeHardwareTaskLibraryProjection() {
        let appState = AppState.makeForTesting()
        let longID = "provider-task-" + String(repeating: "x", count: 48)
        let preparedTask = TaskItem(
            id: longID,
            title: "Prepared task",
            notes: "Prepared detail"
        )
        let fallbackTask = TaskItem(
            id: "fallback-task",
            title: "Fallback task",
            notes: "Fallback detail"
        )
        let completedTask = TaskItem(
            id: "completed-task",
            title: "Already done",
            isCompleted: true
        )
        let preparedTexts = TaskLibraryPhaseTexts(
            starting: "Prepared start.",
            building: "Prepared middle.",
            deep: "Prepared deep."
        )
        appState.suppressesTaskLibraryChangeTracking = true
        appState.tasks = [preparedTask, fallbackTask, completedTask]
        appState.suppressesTaskLibraryChangeTracking = false
        appState.preparedTaskLibraryPhaseTexts[preparedTask.hardwareIdentifier] =
            PreparedTaskLibraryPhaseText(
                fingerprint: TaskLibraryPhaseSourceFingerprint.make(
                    task: preparedTask,
                    userProfile: appState.userProfile,
                    customCompanions: appState.customCompanions
                ),
                texts: preparedTexts
            )

        let records = appState.simulatorTaskLibraryRecords()

        #expect(records.map(\.taskID) == [
            preparedTask.hardwareIdentifier,
            fallbackTask.hardwareIdentifier
        ])
        #expect(records.map(\.order) == [0, 1])
        #expect(records[0].title == preparedTask.title)
        #expect(records[0].detail == preparedTask.notes)
        #expect(records[0].phaseTexts == preparedTexts)
        #expect(records[1].phaseTexts == .localFallback)
        #expect(appState.simulatorFocusTaskID(for: FocusSession(
            taskId: preparedTask.id,
            taskTitle: preparedTask.title
        )) == preparedTask.hardwareIdentifier)
    }

    @Test("Start, complete, and skip commands remain ordered across an awaited start")
    @MainActor
    func taskCommandQueueIsStrictlySerial() async {
        let recorder = SimulatorCommandRecorder()
        let queue = SimulatorBridgeTaskCommandQueue { command in
            await recorder.process(command)
        }

        queue.enqueue(.start(taskID: "task-1"))
        await recorder.waitUntilStartIsSuspended()
        queue.enqueue(.complete(taskID: "task-1"))
        queue.enqueue(.skip(taskID: "task-2"))

        #expect(recorder.events == ["start-begin"])

        recorder.resumeStart()
        await queue.waitUntilIdle()

        #expect(recorder.events == [
            "start-begin", "start-end",
            "complete-begin", "complete-end",
            "skip-begin", "skip-end"
        ])
    }

    @Test("Wire task commands canonicalize identity and complete through AppState persistence")
    @MainActor
    func taskCommandsUseProductionEventTransaction() async {
        let appState = AppState.makeForTesting()
        let task = TaskItem(
            id: "provider-task-" + String(repeating: "y", count: 48),
            title: "Canonical task"
        )
        appState.tasks = [task]
        let appPersistence = ScenarioAppPersistence()
        let focusPersistence = ScenarioFocusPersistence()
        let focusService = FocusSessionService.makeForTesting(
            focusGuardService: FocusPersistenceGuardStub(),
            persistenceEnabled: true,
            launchRecoveryCompleted: true,
            focusPersistence: focusPersistence,
            taskOperationLedger: TaskOperationLedger(persistenceEnabled: false),
            hardwareDisplaySyncExecutor: { _ in },
            sessionEndPresentationExecutor: { _, _, _, _ in }
        )
        let ledger = TaskOperationLedger(persistenceEnabled: false)

        await SimulatorBridge.processTaskCommand(
            .start(taskID: task.hardwareIdentifier),
            operationID: 900,
            appState: appState,
            focusService: focusService,
            operationLedger: ledger,
            hardwareTaskPersistence: appPersistence,
            now: Date().addingTimeInterval(-60)
        )
        #expect(focusService.activeSession?.taskId == task.id)

        await SimulatorBridge.processTaskCommand(
            .complete(taskID: task.hardwareIdentifier),
            operationID: 901,
            appState: appState,
            focusService: focusService,
            operationLedger: ledger,
            hardwareTaskPersistence: appPersistence,
            now: Date()
        )
        await focusService.waitForPendingPersistenceForTesting()

        #expect(appState.tasks.first?.isCompleted == true)
        #expect(focusService.todaySessions.last?.taskId == task.id)
        #expect(focusService.todaySessions.last?.endReason == .completed)
        #expect(await appPersistence.load().tasks.first?.isCompleted == true)
    }
}

@MainActor
private final class SimulatorCommandRecorder {
    private(set) var events: [String] = []
    private var startContinuation: CheckedContinuation<Void, Never>?

    func process(_ command: SimulatorBridgeTaskCommand) async {
        switch command {
        case .start:
            events.append("start-begin")
            await withCheckedContinuation { continuation in
                startContinuation = continuation
            }
            events.append("start-end")
        case .complete:
            events.append("complete-begin")
            events.append("complete-end")
        case .skip:
            events.append("skip-begin")
            events.append("skip-end")
        }
    }

    func waitUntilStartIsSuspended() async {
        for _ in 0..<100 where startContinuation == nil {
            await Task.yield()
        }
        #expect(startContinuation != nil)
    }

    func resumeStart() {
        startContinuation?.resume()
        startContinuation = nil
    }
}
