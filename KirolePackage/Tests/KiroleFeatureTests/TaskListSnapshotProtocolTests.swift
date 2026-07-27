import Foundation
import Testing
@testable import KiroleFeature

@Suite("TaskListSnapshotProtocolTests", .serialized)
struct TaskListSnapshotProtocolTests {
    @MainActor private static let appState = AppState.makeForTesting()
    @Test("CompleteTask v1 carries an operation ID and exact task payload")
    func completeTaskV1Parsing() {
        let taskID = "task-123"
        var payload = Data([0x01])
        payload.appendBigEndian(UInt32(0x1020_3040))
        payload.append(UInt8(taskID.utf8.count))
        payload.append(contentsOf: taskID.utf8)
        payload.appendBigEndian(UInt32(1_700_000_000))

        let event = EventLog.fromBLEPayload(
            type: EventLogType.completeTask.rawByte,
            payload: payload
        )

        #expect(event?.eventType == .completeTask)
        #expect(event?.operationID == 0x1020_3040)
        #expect(event?.taskId == taskID)
        #expect(event?.timestamp == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(event?.hasDeviceTimestamp == true)
    }

    @Test("CompleteTask rejects the legacy payload without an operation ID")
    func completeTaskRejectsLegacyPayload() {
        let taskID = "task-123"
        var payload = Data([UInt8(taskID.utf8.count)])
        payload.append(contentsOf: taskID.utf8)
        payload.appendBigEndian(UInt32(1_700_000_000))

        #expect(EventLog.fromBLEPayload(type: EventLogType.completeTask.rawByte, payload: payload) == nil)
    }

    @Test("CompleteTask rejects trailing bytes so firmware and App cannot parse different records")
    func completeTaskRejectsTrailingBytes() {
        var payload = Data([0x01])
        payload.appendBigEndian(UInt32(7))
        payload.append(1)
        payload.append(contentsOf: Data("a".utf8))
        payload.appendBigEndian(UInt32(10))
        payload.append(0xFF)

        #expect(EventLog.fromBLEPayload(type: EventLogType.completeTask.rawByte, payload: payload) == nil)
    }

    @Test("CompleteTask rejects zero operation IDs and invalid task ID lengths")
    func completeTaskRejectsInvalidIdentityFields() {
        func payload(operationID: UInt32, taskID: String) -> Data {
            var data = Data([0x01])
            data.appendBigEndian(operationID)
            data.append(UInt8(taskID.utf8.count))
            data.append(contentsOf: taskID.utf8)
            data.appendBigEndian(UInt32(10))
            return data
        }

        #expect(EventLog.fromBLEPayload(
            type: EventLogType.completeTask.rawByte,
            payload: payload(operationID: 0, taskID: "a")
        ) == nil)
        #expect(EventLog.fromBLEPayload(
            type: EventLogType.completeTask.rawByte,
            payload: payload(operationID: 1, taskID: "")
        ) == nil)
        #expect(EventLog.fromBLEPayload(
            type: EventLogType.completeTask.rawByte,
            payload: payload(operationID: 1, taskID: String(repeating: "a", count: 37))
        ) == nil)
    }

    @Test("RequestRefresh accepts only the v1 request ID payload")
    func requestRefreshParsing() {
        var payload = Data([0x01])
        payload.appendBigEndian(UInt32(0xAABB_CCDD))

        let versioned = EventLog.fromBLEPayload(
            type: EventLogType.requestRefresh.rawByte,
            payload: payload
        )
        #expect(versioned?.operationID == 0xAABB_CCDD)
        #expect(EventLog.fromBLEPayload(type: EventLogType.requestRefresh.rawByte, payload: Data()) == nil)
        #expect(EventLog.fromBLEPayload(type: EventLogType.requestRefresh.rawByte, payload: Data([0x01])) == nil)
        #expect(EventLog.fromBLEPayload(
            type: EventLogType.requestRefresh.rawByte,
            payload: Data([0x01, 0x00, 0x00, 0x00, 0x00])
        ) == nil)
    }

    @Test("RequestRefresh is live-only and cannot be replayed from EventLogBatch")
    @MainActor
    func requestRefreshIsRejectedFromBatch() {
        let batch = Data([0x01, EventLogType.requestRefresh.rawByte])

        #expect(BLEEventHandler.parseEventLogBatchPayload(batch).isEmpty)
    }

    @Test("TaskListSnapshotAck has a stable strict byte layout")
    func snapshotAckEncoding() {
        let ack = TaskListSnapshotAck(
            action: .completeTask,
            operationID: 0x1020_3040,
            result: .applied,
            version: TaskListSnapshotVersion(epoch: 0x5060_7080, revision: 9),
            tasks: [
                TaskSummary(id: "id-1", title: "Plan BLE", isCompleted: false, priority: 3),
            ]
        )

        let payload = BLEDataEncoder.encodeTaskListSnapshotAck(ack)

        #expect(payload == Data([
            0x01, 0x11,
            0x10, 0x20, 0x30, 0x40,
            0x00,
            0x50, 0x60, 0x70, 0x80,
            0x00, 0x00, 0x00, 0x09,
            0x01,
            0x04, 0x69, 0x64, 0x2D, 0x31,
            0x08, 0x50, 0x6C, 0x61, 0x6E, 0x20, 0x42, 0x4C, 0x45,
            0x00, 0x03,
        ]))
    }

    @Test("Task snapshot content comparison covers every field visible on Overview")
    func snapshotContentComparison() {
        let baseline = [
            TaskSummary(id: "id-1", title: "Plan BLE", isCompleted: false, priority: 3),
        ]

        #expect(TaskListSnapshotContent.isEquivalent(baseline, baseline))
        #expect(!TaskListSnapshotContent.isEquivalent(
            baseline,
            [TaskSummary(id: "id-1", title: "Plan BLE", isCompleted: true, priority: 3)]
        ))
        #expect(!TaskListSnapshotContent.isEquivalent(
            baseline,
            [TaskSummary(id: "id-1", title: "Plan BLE", isCompleted: false, priority: 2)]
        ))
        #expect(!TaskListSnapshotContent.isEquivalent(
            baseline,
            [TaskSummary(id: "id-2", title: "Plan BLE", isCompleted: false, priority: 3)]
        ))
        #expect(!TaskListSnapshotContent.isEquivalent(
            baseline,
            [TaskSummary(id: "id-1", title: "Ship BLE", isCompleted: false, priority: 3)]
        ))
    }

    @Test("Opaque provider task IDs use a stable collision-resistant hardware ID")
    func opaqueTaskIDMapping() {
        let first = TaskItem(
            id: "提醒-\(String(repeating: "provider-segment-", count: 4))-a",
            title: "First"
        )
        let second = TaskItem(
            id: "提醒-\(String(repeating: "provider-segment-", count: 4))-b",
            title: "Second"
        )

        #expect(first.hardwareIdentifier == TaskSummary(from: first).id)
        #expect(first.hardwareIdentifier.utf8.count == 34)
        #expect(first.hardwareIdentifier.utf8.allSatisfy { $0 < 0x80 })
        #expect(first.hardwareIdentifier != second.hardwareIdentifier)
        #expect(TaskItem(id: "plain-id", title: "Plain").hardwareIdentifier == "plain-id")
    }

    @Test("A hardware ID from the snapshot resolves back to its opaque App task")
    @MainActor
    func hardwareIDResolvesOpaqueTask() async {
        let appState = AppState.makeForTesting()
        let task = TaskItem(
            id: "外部任务-\(String(repeating: "x", count: 60))",
            title: "Opaque",
            lastModified: Date().addingTimeInterval(-30)
        )
        appState.tasks = [task]
        let event = EventLog(
            eventType: .completeTask,
            taskId: task.hardwareIdentifier,
            operationID: 76,
            timestamp: Date(),
            hasDeviceTimestamp: true
        )
        let focusService = makeFocusService()
        await focusService.startSession(
            taskId: task.id,
            taskTitle: task.title,
            startTime: Date().addingTimeInterval(-60)
        )

        let result = await BLEEventHandler.processEventLogs(
            [event],
            service: .shared,
            focusService: focusService,
            persistLogs: false,
            operationLedger: TaskOperationLedger(persistenceEnabled: false),
            deviceIDOverride: "test-device",
            appState: appState
        )

        #expect(result.taskOperationReceipts.map(\.result) == [.applied])
        #expect(appState.tasks.first?.isCompleted == true)
        #expect(focusService.activeSession == nil)
        #expect(focusService.todaySessions.last?.taskId == task.id)
        #expect(focusService.todaySessions.last?.endReason == .completed)
    }

    @Test("Conflicting payloads with one operation ID both reach the ledger")
    func operationIDConflictIsNotSilentlyDeduplicated() {
        let logs = [
            EventLog(
                eventType: .completeTask,
                taskId: "task-a",
                operationID: 42,
                timestamp: Date(timeIntervalSince1970: 100),
                hasDeviceTimestamp: true
            ),
            EventLog(
                eventType: .completeTask,
                taskId: "task-b",
                operationID: 42,
                timestamp: Date(timeIntervalSince1970: 100),
                hasDeviceTimestamp: true
            ),
        ]

        #expect(BLEEventHandler.sortAndDedup(logs).count == 2)
    }

    @Test("One operation ID with a different payload returns invalidRequest without a second mutation")
    @MainActor
    func operationIDConflictReturnsInvalidRequest() async {
        await SharedPersistenceTestLock.shared.withLock {
        let firstID = "snapshot-conflict-a-\(UUID().uuidString)"
        let secondID = "snapshot-conflict-b-\(UUID().uuidString)"
        Self.appState.tasks.append(TaskItem(id: firstID, title: "First", dueDate: Date()))
        Self.appState.tasks.append(TaskItem(id: secondID, title: "Second", dueDate: Date()))
        defer {
            Self.appState.tasks.removeAll { [firstID, secondID].contains($0.id) }
        }

        let ledger = TaskOperationLedger(persistenceEnabled: false)
        let eventTime = Date()
        let first = EventLog(
            eventType: .completeTask,
            taskId: firstID,
            operationID: 77,
            timestamp: eventTime,
            hasDeviceTimestamp: true
        )
        let conflict = EventLog(
            eventType: .completeTask,
            taskId: secondID,
            operationID: 77,
            timestamp: eventTime.addingTimeInterval(1),
            hasDeviceTimestamp: true
        )

        let firstResult = await BLEEventHandler.processEventLogs(
            [first], service: BLEService.shared, focusService: makeFocusService(),
            persistLogs: false,
            operationLedger: ledger, deviceIDOverride: "test-device", appState: Self.appState
        )
        let conflictResult = await BLEEventHandler.processEventLogs(
            [conflict], service: BLEService.shared, focusService: makeFocusService(),
            persistLogs: false,
            operationLedger: ledger, deviceIDOverride: "test-device", appState: Self.appState
        )

        #expect(firstResult.taskOperationReceipts.map(\.result) == [.applied])
        #expect(conflictResult.taskOperationReceipts.map(\.result) == [.invalidRequest])
        #expect(Self.appState.tasks.first(where: { $0.id == firstID })?.isCompleted == true)
        #expect(Self.appState.tasks.first(where: { $0.id == secondID })?.isCompleted == false)
        }
    }

    @Test("Versioned CompleteTask in an offline batch preserves its operation ID")
    @MainActor
    func versionedBatchParsing() {
        let taskID = "offline-task"
        var operation = Data([0x01])
        operation.appendBigEndian(UInt32(91))
        operation.append(UInt8(taskID.utf8.count))
        operation.append(contentsOf: taskID.utf8)
        operation.appendBigEndian(UInt32(1_700_000_100))

        var batch = Data([0x01, EventLogType.completeTask.rawByte])
        batch.append(operation)
        let logs = BLEEventHandler.parseEventLogBatchPayload(batch)

        #expect(logs.count == 1)
        #expect(logs[0].operationID == 91)
        #expect(logs[0].taskId == taskID)
    }

    @Test("CompleteTask is idempotent and a retry receives the cached business result")
    @MainActor
    func completeTaskIdempotency() async {
        await SharedPersistenceTestLock.shared.withLock {
        let taskID = "snapshot-complete-\(UUID().uuidString)"
        let task = TaskItem(id: taskID, title: "Complete once", dueDate: Date())
        Self.appState.tasks.append(task)
        defer {
            Self.appState.tasks.removeAll { $0.id == taskID }
        }
        let focus = makeFocusService()
        let ledger = TaskOperationLedger(persistenceEnabled: false)
        let operation = EventLog(
            eventType: .completeTask,
            taskId: taskID,
            operationID: 100,
            timestamp: Date(),
            hasDeviceTimestamp: true
        )

        let first = await BLEEventHandler.processEventLogs(
            [operation], service: BLEService.shared, focusService: focus,
            persistLogs: false,
            operationLedger: ledger, deviceIDOverride: "test-device", appState: Self.appState
        )
        let retry = await BLEEventHandler.processEventLogs(
            [operation], service: BLEService.shared, focusService: focus,
            persistLogs: false,
            operationLedger: ledger, deviceIDOverride: "test-device", appState: Self.appState
        )

        #expect(first.taskOperationReceipts.map(\.result) == [.applied])
        #expect(retry.taskOperationReceipts.map(\.result) == [.applied])
        #expect(Self.appState.tasks.first(where: { $0.id == taskID })?.isCompleted == true)
        }
    }

    @Test("Retrying the same completion after an App-side undo does not complete it again")
    @MainActor
    func completionRetryAfterUndo() async {
        await SharedPersistenceTestLock.shared.withLock {
        let taskID = "snapshot-undo-\(UUID().uuidString)"
        let task = TaskItem(id: taskID, title: "Undo remains authoritative", dueDate: Date())
        Self.appState.tasks.append(task)
        defer {
            Self.appState.tasks.removeAll { $0.id == taskID }
        }
        let event = EventLog(
            eventType: .completeTask,
            taskId: taskID,
            operationID: 200,
            timestamp: Date(),
            hasDeviceTimestamp: true
        )
        let ledger = TaskOperationLedger(persistenceEnabled: false)
        let focus = makeFocusService()

        _ = await BLEEventHandler.processEventLogs(
            [event], service: BLEService.shared, focusService: focus,
            persistLogs: false,
            operationLedger: ledger, deviceIDOverride: "test-device", appState: Self.appState
        )
        if let index = Self.appState.tasks.firstIndex(where: { $0.id == taskID }) {
            Self.appState.tasks[index].isCompleted = false
            Self.appState.tasks[index].hardwareCompletionOperationKey = nil
            Self.appState.tasks[index].lastModified = Date()
        }
        let retry = await BLEEventHandler.processEventLogs(
            [event], service: BLEService.shared, focusService: focus,
            persistLogs: false,
            operationLedger: ledger, deviceIDOverride: "test-device", appState: Self.appState
        )

        #expect(retry.taskOperationReceipts.map(\.result) == [.applied])
        #expect(Self.appState.tasks.first(where: { $0.id == taskID })?.isCompleted == false)
        }
    }

    @Test("Versioned offline operations bypass the timestamp watermark and are re-acknowledged")
    @MainActor
    func operationIDReplayBypassesWatermark() async {
        await SharedPersistenceTestLock.shared.withLock {
        let taskID = "snapshot-replay-\(UUID().uuidString)"
        let task = TaskItem(id: taskID, title: "Replay by operation ID", dueDate: Date())
        Self.appState.tasks.append(task)
        defer {
            Self.appState.tasks.removeAll { $0.id == taskID }
        }

        let eventTime = Date()
        let result = await BLEEventHandler.processEventLogs(
            [
                EventLog(
                    eventType: .completeTask,
                    taskId: taskID,
                    operationID: 201,
                    timestamp: eventTime,
                    hasDeviceTimestamp: true
                ),
            ],
            service: BLEService.shared,
            focusService: makeFocusService(),
            isReplay: true,
            lastTimestampOverride: UInt32(eventTime.timeIntervalSince1970) + 100,
            persistLogs: false,
            operationLedger: TaskOperationLedger(persistenceEnabled: false),
            deviceIDOverride: "test-device",
            appState: Self.appState
        )

        #expect(result.logs.count == 1)
        #expect(result.taskOperationReceipts.map(\.result) == [.applied])
        #expect(Self.appState.tasks.first(where: { $0.id == taskID })?.isCompleted == true)
        }
    }

    @Test("Offline task operations preserve firmware batch order even when RTC timestamps are reversed")
    @MainActor
    func offlineTaskOperationsPreserveBatchOrder() async {
        await SharedPersistenceTestLock.shared.withLock {
        let firstID = "snapshot-order-first-\(UUID().uuidString)"
        let secondID = "snapshot-order-second-\(UUID().uuidString)"
        Self.appState.tasks.append(TaskItem(id: firstID, title: "First on wire", dueDate: Date()))
        Self.appState.tasks.append(TaskItem(id: secondID, title: "Second on wire", dueDate: Date()))
        defer {
            Self.appState.tasks.removeAll { [firstID, secondID].contains($0.id) }
        }

        let result = await BLEEventHandler.processEventLogs(
            [
                EventLog(
                    eventType: .skipTask,
                    taskId: firstID,
                    operationID: 401,
                    timestamp: Date(timeIntervalSince1970: 200),
                    hasDeviceTimestamp: true
                ),
                EventLog(
                    eventType: .completeTask,
                    taskId: secondID,
                    operationID: 402,
                    timestamp: Date(timeIntervalSince1970: 100),
                    hasDeviceTimestamp: true
                ),
            ],
            service: BLEService.shared,
            focusService: makeFocusService(),
            isReplay: true,
            lastTimestampOverride: 1_000,
            persistLogs: false,
            operationLedger: TaskOperationLedger(persistenceEnabled: false),
            deviceIDOverride: "test-device",
            appState: Self.appState
        )

        #expect(result.taskOperationReceipts.map(\.operationID) == [401, 402])
        #expect(result.taskOperationReceipts.map(\.action) == [.skipTask, .completeTask])
        }
    }

    @Test("Complete then Skip in one reversed-RTC batch settles focus as completed")
    @MainActor
    func batchOrderControlsFocusEndReason() async {
        await SharedPersistenceTestLock.shared.withLock {
        let taskID = "snapshot-focus-order-\(UUID().uuidString)"
        let task = TaskItem(id: taskID, title: "Wire order wins", dueDate: Date())
        Self.appState.tasks.append(task)
        defer {
            Self.appState.tasks.removeAll { $0.id == taskID }
        }
        let focus = makeFocusService()
        await focus.startSession(
            taskId: taskID,
            taskTitle: task.title,
            mode: .standard,
            startTime: Date(timeIntervalSince1970: 50)
        )

        let result = await BLEEventHandler.processEventLogs(
            [
                EventLog(
                    eventType: .completeTask,
                    taskId: taskID,
                    operationID: 411,
                    timestamp: Date(timeIntervalSince1970: 200),
                    hasDeviceTimestamp: true
                ),
                EventLog(
                    eventType: .skipTask,
                    taskId: taskID,
                    operationID: 412,
                    timestamp: Date(timeIntervalSince1970: 100),
                    hasDeviceTimestamp: true
                ),
            ],
            service: BLEService.shared,
            focusService: focus,
            isReplay: true,
            lastTimestampOverride: 1_000,
            persistLogs: false,
            operationLedger: TaskOperationLedger(persistenceEnabled: false),
            deviceIDOverride: "test-device",
            appState: Self.appState
        )

        #expect(result.taskOperationReceipts.map(\.action) == [.completeTask, .skipTask])
        #expect(focus.todaySessions.last(where: { $0.taskId == taskID })?.endReason == .completed)
        }
    }

    @Test("SkipTask ends focus semantics but never removes or completes the task")
    @MainActor
    func skipDoesNotMutateTaskList() async {
        await SharedPersistenceTestLock.shared.withLock {
        let taskID = "snapshot-skip-\(UUID().uuidString)"
        let task = TaskItem(id: taskID, title: "Keep after skip", dueDate: Date())
        Self.appState.tasks.append(task)
        defer {
            Self.appState.tasks.removeAll { $0.id == taskID }
        }

        let result = await BLEEventHandler.processEventLogs(
            [
                EventLog(
                    eventType: .skipTask,
                    taskId: taskID,
                    operationID: 101,
                    timestamp: Date(),
                    hasDeviceTimestamp: true
                ),
            ],
            service: BLEService.shared,
            focusService: makeFocusService(),
            persistLogs: false,
            operationLedger: TaskOperationLedger(persistenceEnabled: false),
            deviceIDOverride: "test-device",
            appState: Self.appState
        )

        #expect(result.taskOperationReceipts.map(\.result) == [.applied])
        #expect(Self.appState.tasks.first(where: { $0.id == taskID })?.isCompleted == false)
        }
    }

    @Test("Retrying an old SkipTask does not end a newer session for the same task")
    @MainActor
    func skipRetryDoesNotEndNewSession() async {
        await SharedPersistenceTestLock.shared.withLock {
        let taskID = "snapshot-skip-retry-\(UUID().uuidString)"
        let task = TaskItem(id: taskID, title: "New session survives", dueDate: Date())
        Self.appState.tasks.append(task)
        defer {
            Self.appState.tasks.removeAll { $0.id == taskID }
        }
        let focus = makeFocusService()
        let ledger = TaskOperationLedger(persistenceEnabled: false)
        let event = EventLog(
            eventType: .skipTask,
            taskId: taskID,
            operationID: 202,
            timestamp: Date(),
            hasDeviceTimestamp: true
        )
        await focus.startSession(taskId: taskID, taskTitle: task.title, mode: .standard)
        _ = await BLEEventHandler.processEventLogs(
            [event], service: BLEService.shared, focusService: focus,
            persistLogs: false,
            operationLedger: ledger, deviceIDOverride: "test-device", appState: Self.appState
        )
        await focus.startSession(taskId: taskID, taskTitle: task.title, mode: .standard)

        let retry = await BLEEventHandler.processEventLogs(
            [event], service: BLEService.shared, focusService: focus,
            persistLogs: false,
            operationLedger: ledger, deviceIDOverride: "test-device", appState: Self.appState
        )

        #expect(retry.taskOperationReceipts.map(\.result) == [.applied])
        #expect(focus.activeSession?.taskId == taskID)
        }
    }

    @Test("Resuming a crash-pending Skip does not end a newer session")
    @MainActor
    func pendingSkipResumeDoesNotEndNewSession() async {
        await SharedPersistenceTestLock.shared.withLock {
        let taskID = "snapshot-pending-skip-\(UUID().uuidString)"
        let task = TaskItem(id: taskID, title: "Newer session survives pending retry", dueDate: Date())
        Self.appState.tasks.append(task)
        defer {
            Self.appState.tasks.removeAll { $0.id == taskID }
        }
        let eventTime = Date(timeIntervalSince1970: 1_700_000_220)
        let event = EventLog(
            eventType: .skipTask,
            taskId: taskID,
            operationID: 220,
            timestamp: eventTime,
            hasDeviceTimestamp: true
        )
        let pending = TaskOperationLedgerEntry(
            deviceID: "test-device",
            action: .skipTask,
            operationID: 220,
            taskID: taskID,
            deviceTimestamp: UInt32(eventTime.timeIntervalSince1970),
            result: .applied,
            state: .pending,
            recordedAt: eventTime
        )
        let focus = makeFocusService()
        await focus.startSession(
            taskId: taskID,
            taskTitle: task.title,
            mode: .standard,
            startTime: eventTime.addingTimeInterval(60)
        )

        let result = await BLEEventHandler.processEventLogs(
            [event],
            service: BLEService.shared,
            focusService: focus,
            persistLogs: false,
            operationLedger: TaskOperationLedger(persistenceEnabled: false, initialEntries: [pending]),
            deviceIDOverride: "test-device",
            appState: Self.appState
        )

        #expect(result.taskOperationReceipts.map(\.result) == [.supersededByApp])
        #expect(focus.activeSession?.taskId == taskID)
        }
    }

    @Test("The idempotency ledger reloads a receipt after a simulated App restart")
    func ledgerPersistsAcrossInstances() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let storage = LocalStorage.shared
            let original = try await storage.loadTaskOperationLedger()
            try await storage.saveTaskOperationLedger([])

            let event = EventLog(
                eventType: .completeTask,
                taskId: "persisted-task",
                operationID: 203,
                timestamp: Date(timeIntervalSince1970: 1_700_000_203),
                hasDeviceTimestamp: true
            )
            let beforeRestart = TaskOperationLedger()
            #expect(await beforeRestart.decision(for: event, deviceID: "device-a") == .new)
            #expect(await beforeRestart.record(event: event, deviceID: "device-a", result: .applied))

            let afterRestart = TaskOperationLedger()
            #expect(
                await afterRestart.decision(for: event, deviceID: "device-a")
                    == .duplicate(.applied)
            )

            if let original {
                try await storage.saveTaskOperationLedger(original)
            } else {
                try await storage.deleteFile(named: "task_operation_ledger.json")
            }
        }
    }

    @Test("A pending receipt resumes the domain mutation after a simulated crash")
    @MainActor
    func pendingReceiptResumesAfterCrash() async {
        await SharedPersistenceTestLock.shared.withLock {
        let taskID = "snapshot-crash-resume-\(UUID().uuidString)"
        Self.appState.tasks.append(TaskItem(id: taskID, title: "Resume after crash", dueDate: Date()))
        defer {
            Self.appState.tasks.removeAll { $0.id == taskID }
        }

        let timestamp = Date()
        let operation = EventLog(
            eventType: .completeTask,
            taskId: taskID,
            operationID: 211,
            timestamp: timestamp,
            hasDeviceTimestamp: true
        )
        let pending = TaskOperationLedgerEntry(
            deviceID: "test-device",
            action: .completeTask,
            operationID: 211,
            taskID: taskID,
            deviceTimestamp: UInt32(timestamp.timeIntervalSince1970),
            result: .applied,
            state: .pending,
            recordedAt: Date()
        )
        let ledger = TaskOperationLedger(
            persistenceEnabled: false,
            initialEntries: [pending]
        )

        let result = await BLEEventHandler.processEventLogs(
            [operation],
            service: BLEService.shared,
            focusService: makeFocusService(),
            persistLogs: false,
            operationLedger: ledger,
            deviceIDOverride: "test-device",
            appState: Self.appState
        )

        #expect(result.taskOperationReceipts.map(\.result) == [.applied])
        #expect(Self.appState.tasks.first(where: { $0.id == taskID })?.isCompleted == true)
        #expect(await ledger.decision(for: operation, deviceID: "test-device") == .duplicate(.applied))
        }
    }

    @Test("Unknown task returns taskNotFound together with the current snapshot")
    @MainActor
    func unknownTaskResult() async {
        let result = await BLEEventHandler.processEventLogs(
            [
                EventLog(
                    eventType: .completeTask,
                    taskId: "missing-\(UUID().uuidString)",
                    operationID: 102,
                    timestamp: Date(),
                    hasDeviceTimestamp: true
                ),
            ],
            service: BLEService.shared,
            focusService: makeFocusService(),
            persistLogs: false,
            operationLedger: TaskOperationLedger(persistenceEnabled: false),
            deviceIDOverride: "test-device"
        )

        #expect(result.taskOperationReceipts.map(\.result) == [.taskNotFound])
    }

    @Test("Empty task ID returns invalidRequest and never mutates state")
    @MainActor
    func emptyTaskIDResult() async {
        let result = await BLEEventHandler.processEventLogs(
            [
                EventLog(
                    eventType: .completeTask,
                    taskId: "",
                    operationID: 204,
                    timestamp: Date(timeIntervalSince1970: 1_700_000_204),
                    hasDeviceTimestamp: true
                ),
            ],
            service: BLEService.shared,
            focusService: makeFocusService(),
            persistLogs: false,
            operationLedger: TaskOperationLedger(persistenceEnabled: false),
            deviceIDOverride: "test-device"
        )

        #expect(result.taskOperationReceipts.map(\.result) == [.invalidRequest])
    }

    @MainActor
    private func makeFocusService() -> FocusSessionService {
        FocusSessionService.makeForTesting(
            focusGuardService: TaskListSnapshotFocusGuardStub(),
            persistenceEnabled: false
        )
    }
}

@MainActor
private final class TaskListSnapshotFocusGuardStub: FocusGuardService {
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
