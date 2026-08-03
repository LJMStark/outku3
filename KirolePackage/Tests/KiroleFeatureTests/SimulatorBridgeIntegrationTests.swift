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
        let queue = SimulatorBridgeTaskCommandQueue { command, _ in
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

        _ = await SimulatorBridge.processTaskCommand(
            .start(taskID: task.hardwareIdentifier),
            operationID: 900,
            appState: appState,
            focusService: focusService,
            operationLedger: ledger,
            hardwareTaskPersistence: appPersistence,
            now: Date().addingTimeInterval(-60)
        )
        #expect(focusService.activeSession?.taskId == task.id)

        let receipt = await SimulatorBridge.processTaskCommand(
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
        #expect(receipt == TaskOperationReceipt(
            action: .completeTask,
            operationID: 901,
            result: .applied
        ))
        #expect(focusService.todaySessions.last?.taskId == task.id)
        #expect(focusService.todaySessions.last?.endReason == .completed)
        #expect(await appPersistence.load().tasks.first?.isCompleted == true)
    }

    @Test("Task action parser preserves device operation identity and timestamp")
    func taskActionParserPreservesMetadata() throws {
        let timestamp = 1_700_123_456.25
        let command = try #require(SimulatorBridge.taskCommand(from: """
        {"type":"hw_complete_task","taskId":"task-1","operationId":4294967294,"timestamp":\(timestamp)}
        """))

        #expect(command == .complete(
            taskID: "task-1",
            operationID: 4_294_967_294,
            timestamp: Date(timeIntervalSince1970: timestamp)
        ))
        #expect(SimulatorBridge.taskCommand(from: """
        {"type":"hw_skip_task","taskId":"task-2"}
        """) == .skip(taskID: "task-2"))
        #expect(SimulatorBridge.taskCommand(from: """
        {"type":"hw_skip_task","taskId":"task-2","operationId":0,"timestamp":1700123456}
        """) == nil)
        #expect(SimulatorBridge.taskCommand(from: """
        {"type":"hw_skip_task","taskId":"task-2","operationId":7,"timestamp":"1700123456"}
        """) == nil)
        #expect(SimulatorBridge.taskCommand(from: """
        {"type":"hw_task_action_replay_end"}
        """) == .replayEnd)
    }

    @Test("Device operation metadata reaches the existing ledger unchanged")
    @MainActor
    func deviceMetadataReachesLedger() async throws {
        let appState = AppState.makeForTesting()
        let task = TaskItem(id: "ledger-task", title: "Ledger task")
        appState.tasks = [task]
        let ledgerPersistence = RecordingSimulatorLedgerPersistence()
        let ledger = TaskOperationLedger(
            persistenceEnabled: true,
            persistence: ledgerPersistence
        )
        let timestamp = Date(timeIntervalSince1970: 1_700_222_333)

        let receipt = await SimulatorBridge.processTaskCommand(
            .skip(taskID: task.hardwareIdentifier, operationID: 8_888, timestamp: timestamp),
            operationID: 999,
            appState: appState,
            focusService: makeSimulatorFocusService(ledger: ledger),
            operationLedger: ledger,
            hardwareTaskPersistence: ScenarioAppPersistence(),
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        let entry = try #require(await ledgerPersistence.latestEntry())
        #expect(receipt?.operationID == 8_888)
        #expect(entry.operationID == 8_888)
        #expect(entry.deviceTimestamp == 1_700_222_333)
        #expect(entry.timestampAuthority == .deviceClock)
    }

    @Test("Repeated and conflicting simulator actions use the production idempotency ledger")
    @MainActor
    func taskActionReplayAndConflict() async {
        let appState = AppState.makeForTesting()
        let timestamp = Date(timeIntervalSince1970: 1_700_333_444)
        let first = TaskItem(
            id: "replay-a",
            title: "First",
            lastModified: timestamp.addingTimeInterval(-10)
        )
        let second = TaskItem(
            id: "replay-b",
            title: "Second",
            lastModified: timestamp.addingTimeInterval(-10)
        )
        appState.tasks = [first, second]
        let ledger = TaskOperationLedger(persistenceEnabled: false)
        let persistence = ScenarioAppPersistence()
        let focus = makeSimulatorFocusService(ledger: ledger)
        let command = SimulatorBridgeTaskCommand.complete(
            taskID: first.hardwareIdentifier,
            operationID: 7_777,
            timestamp: timestamp
        )

        let firstReceipt = await SimulatorBridge.processTaskCommand(
            command,
            operationID: 1,
            appState: appState,
            focusService: focus,
            operationLedger: ledger,
            hardwareTaskPersistence: persistence,
            now: Date()
        )
        let duplicateReceipt = await SimulatorBridge.processTaskCommand(
            command,
            operationID: 2,
            appState: appState,
            focusService: focus,
            operationLedger: ledger,
            hardwareTaskPersistence: persistence,
            now: Date()
        )
        let conflictReceipt = await SimulatorBridge.processTaskCommand(
            .complete(
                taskID: second.hardwareIdentifier,
                operationID: 7_777,
                timestamp: timestamp
            ),
            operationID: 3,
            appState: appState,
            focusService: focus,
            operationLedger: ledger,
            hardwareTaskPersistence: persistence,
            now: Date()
        )

        #expect(firstReceipt?.result == .applied)
        #expect(duplicateReceipt == firstReceipt)
        #expect(conflictReceipt?.result == .invalidRequest)
        #expect(appState.tasks.first(where: { $0.id == first.id })?.isCompleted == true)
        #expect(appState.tasks.first(where: { $0.id == second.id })?.isCompleted == false)
    }

    @Test("Business ACK JSON is delivered before the task library and errors retain the outbox")
    @MainActor
    func taskActionAcknowledgementOrdering() async throws {
        let delivery = SimulatorBridgeTaskDeliveryCoordinator()
        delivery.beginConnection(generation: 0)
        var deliveredTypes: [String] = []
        let applied = TaskOperationReceipt(
            action: .skipTask,
            operationID: 6_666,
            result: .alreadyApplied
        )
        let appliedPayload = try #require(
            SimulatorBridge.taskActionAcknowledgementPayload(applied)
        )
        await delivery.deliver(
            receipt: applied,
            isOfflineReplay: false,
            acknowledgementPayload: appliedPayload,
            taskLibraryPayload: { SimulatorBridge.taskLibraryPayload(records: []) },
            send: { payload in
                let type = payload["type"] as? String ?? "missing"
                deliveredTypes.append(type)
                if type == "app_task_action_ack" {
                    #expect(payload["action"] as? String == "skip")
                    #expect(payload["operationId"] as? Int == 6_666)
                    #expect(payload["result"] as? String == "alreadyApplied")
                }
                return true
            }
        )
        #expect(deliveredTypes == ["app_task_action_ack", "app_task_library"])

        deliveredTypes = []
        let firstOffline = TaskOperationReceipt(
            action: .completeTask,
            operationID: 6_667,
            result: .applied
        )
        let secondOffline = TaskOperationReceipt(
            action: .skipTask,
            operationID: 6_668,
            result: .applied
        )
        for receipt in [firstOffline, secondOffline] {
            await delivery.deliver(
                receipt: receipt,
                isOfflineReplay: true,
                acknowledgementPayload: try #require(
                    SimulatorBridge.taskActionAcknowledgementPayload(receipt)
                ),
                taskLibraryPayload: { SimulatorBridge.taskLibraryPayload(records: []) },
                send: { payload in
                    deliveredTypes.append(payload["type"] as? String ?? "missing")
                    return true
                }
            )
        }
        #expect(deliveredTypes == ["app_task_action_ack", "app_task_action_ack"])
        await delivery.finishOfflineReplay(
            taskLibraryPayload: { SimulatorBridge.taskLibraryPayload(records: []) },
            send: { payload in
                deliveredTypes.append(payload["type"] as? String ?? "missing")
                return true
            }
        )
        #expect(deliveredTypes == [
            "app_task_action_ack", "app_task_action_ack", "app_task_library"
        ])

        deliveredTypes = []
        let failedOffline = TaskOperationReceipt(
            action: .completeTask,
            operationID: 6_669,
            result: .internalError
        )
        await delivery.deliver(
            receipt: failedOffline,
            isOfflineReplay: true,
            acknowledgementPayload: try #require(
                SimulatorBridge.taskActionAcknowledgementPayload(failedOffline)
            ),
            taskLibraryPayload: { SimulatorBridge.taskLibraryPayload(records: []) },
            send: { payload in
                deliveredTypes.append(payload["type"] as? String ?? "missing")
                #expect(payload["result"] as? String == "internalError")
                return true
            }
        )
        await delivery.finishOfflineReplay(
            taskLibraryPayload: { SimulatorBridge.taskLibraryPayload(records: []) },
            send: { payload in
                deliveredTypes.append(payload["type"] as? String ?? "missing")
                return true
            }
        )
        #expect(deliveredTypes == ["app_task_action_ack"])
    }

    @Test("A stale connection failure cannot block the current replay library")
    @MainActor
    func staleReplayFailureDoesNotCrossConnections() async throws {
        let delivery = SimulatorBridgeTaskDeliveryCoordinator()
        let receipt = TaskOperationReceipt(
            action: .completeTask,
            operationID: 7_001,
            result: .applied
        )
        let acknowledgement = try #require(
            SimulatorBridge.taskActionAcknowledgementPayload(receipt)
        )

        delivery.beginConnection(generation: 1)
        delivery.beginConnection(generation: 2)
        await delivery.deliver(
            receipt: receipt,
            isOfflineReplay: true,
            connectionGeneration: 1,
            acknowledgementPayload: acknowledgement,
            taskLibraryPayload: { SimulatorBridge.taskLibraryPayload(records: []) },
            send: { _ in false }
        )

        var deliveredTypes: [String] = []
        await delivery.deliver(
            receipt: receipt,
            isOfflineReplay: true,
            connectionGeneration: 2,
            acknowledgementPayload: acknowledgement,
            taskLibraryPayload: { SimulatorBridge.taskLibraryPayload(records: []) },
            send: { payload in
                deliveredTypes.append(payload["type"] as? String ?? "missing")
                return true
            }
        )
        await delivery.finishOfflineReplay(
            connectionGeneration: 2,
            taskLibraryPayload: { SimulatorBridge.taskLibraryPayload(records: []) },
            send: { payload in
                deliveredTypes.append(payload["type"] as? String ?? "missing")
                return true
            }
        )

        #expect(deliveredTypes == ["app_task_action_ack", "app_task_library"])
    }

    @MainActor
    private func makeSimulatorFocusService(
        ledger: TaskOperationLedger
    ) -> FocusSessionService {
        FocusSessionService.makeForTesting(
            focusGuardService: FocusPersistenceGuardStub(),
            taskOperationLedger: ledger,
            hardwareDisplaySyncExecutor: { _ in },
            sessionEndPresentationExecutor: { _, _, _, _ in }
        )
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
        case .replayEnd:
            events.append("replay-end")
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

private actor RecordingSimulatorLedgerPersistence: TaskOperationLedgerPersisting {
    private var entries: [TaskOperationLedgerEntry] = []

    func loadTaskOperationLedger() async throws -> [TaskOperationLedgerEntry]? {
        entries
    }

    func saveTaskOperationLedger(_ entries: [TaskOperationLedgerEntry]) async throws {
        self.entries = entries
    }

    func latestEntry() -> TaskOperationLedgerEntry? {
        entries.last
    }
}
