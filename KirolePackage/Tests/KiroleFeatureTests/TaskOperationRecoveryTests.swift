import Foundation
import Testing
@testable import KiroleFeature

@Suite("Task operation recovery", .serialized)
struct TaskOperationRecoveryTests {
    @Test("A live completion uses App receipt time when the hardware RTC lags")
    @MainActor
    func liveCompletionIgnoresLaggingHardwareClock() async throws {
        let fixture = try Self.loadLaggingClockFixture()
        let appState = AppState.makeForTesting()
        let receivedAt = Date()
        let sessionStart = receivedAt.addingTimeInterval(-fixture.sessionElapsedSeconds)
        let task = TaskItem(
            id: "live-lagging-rtc-\(UUID().uuidString)",
            title: "Complete from hardware",
            dueDate: receivedAt,
            lastModified: receivedAt.addingTimeInterval(-fixture.taskModifiedSecondsAgo)
        )
        appState.tasks = [task]

        let focus = makeFocusService()
        await focus.startSession(
            taskId: task.id,
            taskTitle: task.title,
            startTime: sessionStart
        )
        let operation = EventLog(
            eventType: .completeTask,
            taskId: task.id,
            operationID: 711,
            timestamp: receivedAt.addingTimeInterval(-fixture.hardwareClockLagSeconds),
            hasDeviceTimestamp: true
        )

        let processing = await BLEEventHandler.processEventLogs(
            [operation],
            service: .shared,
            focusService: focus,
            isReplay: false,
            persistLogs: false,
            operationLedger: TaskOperationLedger(persistenceEnabled: false),
            deviceIDOverride: "test-device",
            appState: appState
        )

        #expect(processing.taskOperationReceipts.map(\.result) == [.applied])
        #expect(appState.tasks.first?.isCompleted == true)
        #expect(focus.activeSession == nil)
        #expect(
            focus.todaySessions.last?.endTime?.timeIntervalSince(sessionStart) ?? 0
                >= fixture.minimumSettledSeconds
        )
    }

    @Test("A live completion ignores an implausible future hardware clock")
    @MainActor
    func liveCompletionIgnoresFutureHardwareClock() async {
        let appState = AppState.makeForTesting()
        let task = TaskItem(
            id: "live-future-rtc-\(UUID().uuidString)",
            title: "Complete despite RTC skew",
            dueDate: Date()
        )
        appState.tasks = [task]
        let operation = EventLog(
            eventType: .completeTask,
            taskId: task.id,
            operationID: 712,
            timestamp: Date().addingTimeInterval(8 * 60 * 60),
            hasDeviceTimestamp: true
        )

        let processing = await BLEEventHandler.processEventLogs(
            [operation],
            service: .shared,
            focusService: makeFocusService(),
            isReplay: false,
            persistLogs: false,
            operationLedger: TaskOperationLedger(persistenceEnabled: false),
            deviceIDOverride: "test-device",
            appState: appState
        )

        #expect(processing.taskOperationReceipts.map(\.result) == [.applied])
        #expect(appState.tasks.first?.isCompleted == true)
    }

    @Test("A pending completion never overwrites a newer App undo")
    @MainActor
    func pendingCompletionRespectsNewerAppState() async {
        let appState = AppState.makeForTesting()
        let reservedAt = Date().addingTimeInterval(-30)
        let task = TaskItem(
            id: "newer-app-undo-\(UUID().uuidString)",
            title: "Keep the undo",
            isCompleted: false,
            dueDate: Date(),
            lastModified: reservedAt.addingTimeInterval(10)
        )
        appState.tasks = [task]

        let operation = EventLog(
            eventType: .completeTask,
            taskId: task.id,
            operationID: 701,
            timestamp: reservedAt.addingTimeInterval(-5),
            hasDeviceTimestamp: true
        )
        let pending = TaskOperationLedgerEntry(
            deviceID: "test-device",
            action: .completeTask,
            operationID: 701,
            taskID: task.id,
            deviceTimestamp: UInt32(operation.timestamp.timeIntervalSince1970),
            result: .applied,
            state: .pending,
            recordedAt: reservedAt
        )
        let ledger = TaskOperationLedger(
            persistenceEnabled: false,
            initialEntries: [pending]
        )

        let processing = await BLEEventHandler.processEventLogs(
            [operation],
            service: .shared,
            focusService: makeFocusService(),
            persistLogs: false,
            operationLedger: ledger,
            deviceIDOverride: "test-device",
            appState: appState
        )

        #expect(processing.taskOperationReceipts.map(\.result) == [.supersededByApp])
        #expect(appState.tasks.first(where: { $0.id == task.id })?.isCompleted == false)
    }

    @Test("A first-seen delayed completion never overwrites a later App undo")
    @MainActor
    func delayedFirstSeenCompletionRespectsAppUndo() async {
        let appState = AppState.makeForTesting()
        let deviceTime = Date().addingTimeInterval(-60)
        let task = TaskItem(
            id: "delayed-complete-\(UUID().uuidString)",
            title: "Keep App undo",
            isCompleted: false,
            dueDate: Date(),
            lastModified: deviceTime.addingTimeInterval(30)
        )
        appState.tasks = [task]
        let operation = EventLog(
            eventType: .completeTask,
            taskId: task.id,
            operationID: 706,
            timestamp: deviceTime,
            hasDeviceTimestamp: true
        )

        let processing = await BLEEventHandler.processEventLogs(
            [operation],
            service: .shared,
            focusService: makeFocusService(),
            isReplay: true,
            persistLogs: false,
            operationLedger: TaskOperationLedger(persistenceEnabled: false),
            deviceIDOverride: "test-device",
            appState: appState
        )

        #expect(processing.taskOperationReceipts.map(\.result) == [.supersededByApp])
        #expect(appState.tasks.first?.isCompleted == false)
    }

    @Test("A first-seen delayed Skip never ends a newer session for the same task")
    @MainActor
    func delayedNewSkipProtectsNewerSession() async {
        let appState = AppState.makeForTesting()
        let task = TaskItem(id: "delayed-new-skip-\(UUID().uuidString)", title: "New session", dueDate: Date())
        appState.tasks = [task]

        let focus = makeFocusService()
        let sessionStart = Date()
        await focus.startSession(taskId: task.id, taskTitle: task.title, startTime: sessionStart)
        let operation = EventLog(
            eventType: .skipTask,
            taskId: task.id,
            operationID: 702,
            timestamp: sessionStart.addingTimeInterval(-60),
            hasDeviceTimestamp: true
        )

        let processing = await BLEEventHandler.processEventLogs(
            [operation],
            service: .shared,
            focusService: focus,
            isReplay: true,
            persistLogs: false,
            operationLedger: TaskOperationLedger(persistenceEnabled: false),
            deviceIDOverride: "test-device",
            appState: appState
        )

        #expect(processing.taskOperationReceipts.map(\.result) == [.supersededByApp])
        #expect(focus.activeSession?.id != nil)
    }

    @Test("An implausible future Skip never uses RTC skew to end the current session")
    @MainActor
    func futureSkipProtectsCurrentSession() async {
        let appState = AppState.makeForTesting()
        let task = TaskItem(id: "future-skip-\(UUID().uuidString)", title: "Current session", dueDate: Date())
        appState.tasks = [task]

        let focus = makeFocusService()
        let sessionStart = Date()
        await focus.startSession(taskId: task.id, taskTitle: task.title, startTime: sessionStart)
        let operation = EventLog(
            eventType: .skipTask,
            taskId: task.id,
            operationID: 703,
            timestamp: sessionStart.addingTimeInterval(3_600),
            hasDeviceTimestamp: true
        )

        let processing = await BLEEventHandler.processEventLogs(
            [operation],
            service: .shared,
            focusService: focus,
            isReplay: true,
            persistLogs: false,
            operationLedger: TaskOperationLedger(persistenceEnabled: false),
            deviceIDOverride: "test-device",
            appState: appState
        )

        #expect(processing.taskOperationReceipts.map(\.result) == [.supersededByApp])
        #expect(focus.activeSession?.id != nil)
    }

    @Test("A newer focus start during reservation survives the older operation")
    @MainActor
    func newerFocusDuringReservationWins() async {
        let appState = AppState.makeForTesting()
        let task = TaskItem(
            id: "focus-during-reserve-\(UUID().uuidString)",
            title: "New focus survives",
            dueDate: Date()
        )
        appState.tasks = [task]
        let focus = makeFocusService()
        await focus.startSession(
            taskId: task.id,
            taskTitle: task.title,
            startTime: Date().addingTimeInterval(-60)
        )
        let originalSessionID = focus.activeSession?.id
        let persistence = RecoveryBlockingLedgerPersistence()
        let operation = EventLog(
            eventType: .skipTask,
            taskId: task.id,
            operationID: 713,
            timestamp: Date(),
            hasDeviceTimestamp: true
        )
        let processing = Task { @MainActor in
            await BLEEventHandler.processEventLogs(
                [operation],
                service: .shared,
                focusService: focus,
                persistLogs: false,
                operationLedger: TaskOperationLedger(
                    persistenceEnabled: true,
                    initialEntries: [],
                    persistence: persistence
                ),
                deviceIDOverride: "test-device",
                appState: appState
            )
        }

        await persistence.waitForFirstSaveToStart()
        focus.endSession(reason: .manual)
        await focus.startSession(taskId: task.id, taskTitle: task.title)
        let newerSessionID = focus.activeSession?.id
        await persistence.releaseFirstSave()

        #expect(await processing.value.taskOperationReceipts.map(\.result) == [.supersededByApp])
        #expect(newerSessionID != originalSessionID)
        #expect(focus.activeSession?.id == newerSessionID)
    }

    @Test("A live pending retry cannot end a same-task focus started one second later")
    @MainActor
    func pendingLiveRetryProtectsNewerFocusWithoutClockTolerance() async {
        let appState = AppState.makeForTesting()
        let task = TaskItem(
            id: "focus-after-failed-reserve-\(UUID().uuidString)",
            title: "Replacement focus",
            dueDate: Date()
        )
        appState.tasks = [task]
        let focus = makeFocusService()
        await focus.startSession(
            taskId: task.id,
            taskTitle: task.title,
            startTime: Date().addingTimeInterval(-60)
        )
        let persistence = RecoveryFirstSaveFailingLedgerPersistence()
        let ledger = TaskOperationLedger(
            persistenceEnabled: true,
            initialEntries: [],
            persistence: persistence
        )
        let operation = EventLog(
            eventType: .skipTask,
            taskId: task.id,
            operationID: 716,
            timestamp: Date(),
            hasDeviceTimestamp: true
        )

        let first = await BLEEventHandler.processEventLogs(
            [operation],
            service: .shared,
            focusService: focus,
            persistLogs: false,
            operationLedger: ledger,
            deviceIDOverride: "test-device",
            appState: appState
        )
        #expect(first.taskOperationReceipts.map(\.result) == [.internalError])

        focus.endSession(reason: .manual)
        await focus.startSession(
            taskId: task.id,
            taskTitle: task.title,
            startTime: Date().addingTimeInterval(1)
        )
        let replacementID = focus.activeSession?.id

        let retry = await BLEEventHandler.processEventLogs(
            [operation],
            service: .shared,
            focusService: focus,
            persistLogs: false,
            operationLedger: ledger,
            deviceIDOverride: "test-device",
            appState: appState
        )

        #expect(retry.taskOperationReceipts.map(\.result) == [.supersededByApp])
        #expect(focus.activeSession?.id == replacementID)
    }

    @Test("A pending operation keeps its first timestamp authority across another carrier")
    func pendingOperationKeepsFirstTimestampAuthority() async throws {
        let deliveries: [
            (UInt32, TaskOperationTimestampAuthority, TaskOperationTimestampAuthority)
        ] = [
            (714, .appReceipt, .deviceClock),
            (715, .deviceClock, .appReceipt),
        ]
        for (operationID, first, retry) in deliveries {
            let operation = EventLog(
                eventType: .completeTask,
                taskId: "carrier-\(operationID)",
                operationID: operationID,
                timestamp: Date().addingTimeInterval(-8 * 60 * 60),
                hasDeviceTimestamp: true
            )
            let ledger = TaskOperationLedger(persistenceEnabled: false)
            guard case .new(let entry) = await ledger.reserve(
                event: operation,
                deviceID: "test-device",
                result: .applied,
                timestampAuthority: first
            ) else {
                Issue.record("The first delivery must reserve a pending entry")
                continue
            }

            let persisted = try JSONDecoder().decode(
                TaskOperationLedgerEntry.self,
                from: JSONEncoder().encode(entry)
            )
            let restarted = TaskOperationLedger(
                persistenceEnabled: false,
                initialEntries: [persisted]
            )
            guard case .resume(let resumed) = await restarted.reserve(
                event: operation,
                deviceID: "test-device",
                result: .applied,
                timestampAuthority: retry
            ) else {
                Issue.record("The retry must resume the persisted pending entry")
                continue
            }

            #expect(resumed.timestampAuthority == first)
        }

        let legacyEntry = TaskOperationLedgerEntry(
            deviceID: "test-device",
            action: .completeTask,
            operationID: 716,
            taskID: "legacy-carrier",
            deviceTimestamp: 1_700_000_000,
            result: .applied,
            state: .pending,
            recordedAt: Date(),
            timestampAuthority: .appReceipt
        )
        var legacyJSON = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(legacyEntry))
                as? [String: Any]
        )
        legacyJSON.removeValue(forKey: "timestampAuthority")
        let decodedLegacy = try JSONDecoder().decode(
            TaskOperationLedgerEntry.self,
            from: JSONSerialization.data(withJSONObject: legacyJSON)
        )
        #expect(decodedLegacy.timestampAuthority == .deviceClock)
    }

    @Test("Committed operation receipts are not silently evicted after 256 newer operations")
    func committedReceiptsRemainDurable() async {
        let ledger = TaskOperationLedger(persistenceEnabled: false, initialEntries: [])
        var first: EventLog?
        for operationID in UInt32(1)...UInt32(300) {
            let event = EventLog(
                eventType: .completeTask,
                taskId: "task-\(operationID)",
                operationID: operationID,
                timestamp: Date(timeIntervalSince1970: TimeInterval(operationID)),
                hasDeviceTimestamp: true
            )
            if operationID == 1 { first = event }
            #expect(await ledger.record(event: event, deviceID: "test-device", result: .applied))
        }

        let firstDecision = await ledger.decision(for: first!, deviceID: "test-device")
        #expect(firstDecision == .duplicate(.applied))
    }

    @Test("Concurrent reservations persist both operation IDs without a lost update")
    func concurrentReservationsAreSerialized() async {
        let persistence = RecoveryBlockingLedgerPersistence()
        let ledger = TaskOperationLedger(
            persistenceEnabled: true,
            initialEntries: [],
            persistence: persistence
        )
        let first = EventLog(
            eventType: .completeTask,
            taskId: "task-a",
            operationID: 301,
            timestamp: Date(timeIntervalSince1970: 301),
            hasDeviceTimestamp: true
        )
        let second = EventLog(
            eventType: .completeTask,
            taskId: "task-b",
            operationID: 302,
            timestamp: Date(timeIntervalSince1970: 302),
            hasDeviceTimestamp: true
        )

        async let firstDecision = ledger.reserve(
            event: first,
            deviceID: "test-device",
            result: .applied
        )
        await persistence.waitForFirstSaveToStart()
        async let secondDecision = ledger.reserve(
            event: second,
            deviceID: "test-device",
            result: .applied
        )
        await persistence.releaseFirstSave()

        guard case .new(let firstEntry) = await firstDecision,
              case .new(let secondEntry) = await secondDecision else {
            Issue.record("Both operations must reserve as new")
            return
        }
        #expect(firstEntry.operationID == 301)
        #expect(secondEntry.operationID == 302)
        #expect(Set(await persistence.latestEntries().map(\.operationID)) == [301, 302])
    }

    @Test("Cold-start ledger load is single-flight and cannot overwrite a reservation")
    func concurrentFirstLoadPreservesBothReservations() async {
        let persistence = RecoveryBlockingLoadLedgerPersistence()
        let ledger = TaskOperationLedger(persistenceEnabled: true, persistence: persistence)
        let first = EventLog(
            eventType: .completeTask,
            taskId: "cold-task-a",
            operationID: 303,
            timestamp: Date(timeIntervalSince1970: 303),
            hasDeviceTimestamp: true
        )
        let second = EventLog(
            eventType: .completeTask,
            taskId: "cold-task-b",
            operationID: 304,
            timestamp: Date(timeIntervalSince1970: 304),
            hasDeviceTimestamp: true
        )

        async let firstDecision = ledger.reserve(
            event: first,
            deviceID: "test-device",
            result: .applied
        )
        await persistence.waitForLoadToStart()
        async let secondDecision = ledger.reserve(
            event: second,
            deviceID: "test-device",
            result: .applied
        )
        await Task.yield()
        await persistence.releaseLoads()

        guard case .new = await firstDecision,
              case .new = await secondDecision else {
            Issue.record("Both cold-start operations must reserve as new")
            return
        }
        #expect(await persistence.loadCount() == 1)
        #expect(Set(await persistence.latestEntries().map(\.operationID)) == [303, 304])
    }

    @Test("A failed committed write stays pending and the same-process retry flushes it")
    func failedCommitWriteRetriesInSameProcess() async {
        let persistence = RecoverySecondSaveFailingLedgerPersistence()
        let ledger = TaskOperationLedger(
            persistenceEnabled: true,
            initialEntries: [],
            persistence: persistence
        )
        let operation = EventLog(
            eventType: .completeTask,
            taskId: "commit-retry",
            operationID: 305,
            timestamp: Date(timeIntervalSince1970: 305),
            hasDeviceTimestamp: true
        )

        guard case .new = await ledger.reserve(
            event: operation,
            deviceID: "test-device",
            result: .applied
        ) else {
            Issue.record("The first delivery must reserve a pending receipt")
            return
        }
        #expect(await ledger.commit(event: operation, deviceID: "test-device") == false)

        guard case .resume = await ledger.reserve(
            event: operation,
            deviceID: "test-device",
            result: .applied
        ) else {
            Issue.record("A failed commit must remain resumable in memory")
            return
        }
        #expect(await ledger.commit(event: operation, deviceID: "test-device"))
        #expect(await ledger.decision(for: operation, deviceID: "test-device") == .duplicate(.applied))
        #expect(await persistence.latestEntries().first?.state == .committed)
    }

    @Test("An App undo during the task write is revalidated and repaired on disk")
    @MainActor
    func appUndoDuringTaskWriteWins() async {
        let appState = AppState.makeForTesting()
        let persistence = RecoveryBlockingTaskStatePersistence()
        let eventTime = Date()
        let task = TaskItem(
            id: "undo-during-task-write-\(UUID().uuidString)",
            title: "Undo during write",
            dueDate: Date(),
            lastModified: eventTime.addingTimeInterval(-30)
        )
        appState.tasks = [task]
        let originalPet = appState.pet

        let operation = Task { @MainActor in
            await appState.persistHardwareTaskCompletion(
                taskID: task.id,
                operationKey: "test-device|17|707",
                deviceTimestamp: UInt32(eventTime.timeIntervalSince1970),
                reservedAt: eventTime,
                source: .hardwareReplay,
                persistence: persistence
            )
        }
        await persistence.waitForFirstTaskWrite()
        guard var completed = appState.tasks.first else {
            Issue.record("Hardware completion did not mutate memory")
            return
        }
        completed.isCompleted = false
        completed.hardwareCompletionOperationKey = nil
        completed.lastModified = Date()
        appState.tasks = [completed]
        appState.pet = originalPet
        await persistence.releaseFirstTaskWrite()

        #expect(await operation.value == .supersededByApp)
        #expect(appState.tasks.first?.isCompleted == false)
        #expect(await persistence.latestTasks().first?.isCompleted == false)
    }

    @Test("An App content edit during the task write supersedes the hardware completion")
    @MainActor
    func appEditDuringTaskWriteWins() async {
        let appState = AppState.makeForTesting()
        let persistence = RecoveryBlockingTaskStatePersistence()
        let eventTime = Date()
        let task = TaskItem(
            id: "edit-during-task-write-\(UUID().uuidString)",
            title: "Original title",
            dueDate: Date(),
            lastModified: eventTime.addingTimeInterval(-30)
        )
        appState.tasks = [task]

        let operation = Task { @MainActor in
            await appState.persistHardwareTaskCompletion(
                taskID: task.id,
                operationKey: "test-device|17|708",
                deviceTimestamp: UInt32(eventTime.timeIntervalSince1970),
                reservedAt: eventTime,
                source: .hardwareReplay,
                persistence: persistence
            )
        }
        await persistence.waitForFirstTaskWrite()
        guard var edited = appState.tasks.first else {
            Issue.record("Hardware completion did not mutate memory")
            return
        }
        edited.title = "App-edited title"
        edited.lastModified = Date()
        appState.tasks = [edited]
        await persistence.releaseFirstTaskWrite()

        #expect(await operation.value == .supersededByApp)
        #expect(appState.tasks.first?.title == "App-edited title")
        #expect(await persistence.latestTasks().first?.title == "App-edited title")
    }

    @Test("An App undo during WAL persistence supersedes an initially already-completed result")
    @MainActor
    func appUndoDuringReservationWins() async {
        let appState = AppState.makeForTesting()
        let task = TaskItem(
            id: "undo-during-reserve-\(UUID().uuidString)",
            title: "Undo wins",
            isCompleted: true,
            dueDate: Date(),
            lastModified: Date().addingTimeInterval(-60)
        )
        appState.tasks = [task]

        let persistence = RecoveryBlockingLedgerPersistence()
        let ledger = TaskOperationLedger(
            persistenceEnabled: true,
            initialEntries: [],
            persistence: persistence
        )
        let operation = EventLog(
            eventType: .completeTask,
            taskId: task.id,
            operationID: 704,
            timestamp: Date(),
            hasDeviceTimestamp: true
        )
        let processing = Task { @MainActor in
            await BLEEventHandler.processEventLogs(
                [operation],
                service: .shared,
                focusService: makeFocusService(),
                persistLogs: false,
                operationLedger: ledger,
                deviceIDOverride: "test-device",
                appState: appState
            )
        }

        await persistence.waitForFirstSaveToStart()
        if let index = appState.tasks.firstIndex(where: { $0.id == task.id }) {
            appState.tasks[index].isCompleted = false
            appState.tasks[index].hardwareCompletionOperationKey = nil
            appState.tasks[index].lastModified = Date()
        }
        await persistence.releaseFirstSave()
        let result = await processing.value

        #expect(result.taskOperationReceipts.map(\.result) == [.supersededByApp])
        #expect(appState.tasks.first(where: { $0.id == task.id })?.isCompleted == false)
    }

    @Test("An App task edit during the committed WAL write is cached as superseded")
    @MainActor
    func appEditDuringCommitWinsAndIsCached() async {
        let appState = AppState.makeForTesting()
        let task = TaskItem(
            id: "edit-during-commit-\(UUID().uuidString)",
            title: "Original",
            dueDate: Date(),
            lastModified: Date().addingTimeInterval(-60)
        )
        appState.tasks = [task]
        let persistence = RecoverySecondSaveBlockingLedgerPersistence()
        let ledger = TaskOperationLedger(
            persistenceEnabled: true,
            initialEntries: [],
            persistence: persistence
        )
        let operation = EventLog(
            eventType: .skipTask,
            taskId: task.id,
            operationID: 709,
            timestamp: Date(),
            hasDeviceTimestamp: true
        )

        let processing = Task { @MainActor in
            await BLEEventHandler.processEventLogs(
                [operation],
                service: .shared,
                focusService: makeFocusService(),
                persistLogs: false,
                operationLedger: ledger,
                deviceIDOverride: "test-device",
                appState: appState
            )
        }
        await persistence.waitForSecondSaveToStart()
        appState.tasks[0].title = "App wins"
        appState.tasks[0].lastModified = Date()
        await persistence.releaseSecondSave()

        #expect(await processing.value.taskOperationReceipts.map(\.result) == [.supersededByApp])
        #expect(await ledger.decision(for: operation, deviceID: "test-device") == .duplicate(.supersededByApp))
    }

    @Test("A newer same-task focus start during the committed WAL write is cached as superseded")
    @MainActor
    func newerFocusDuringCommitWinsAndIsCached() async {
        let appState = AppState.makeForTesting()
        let task = TaskItem(
            id: "focus-during-commit-\(UUID().uuidString)",
            title: "Focus task",
            dueDate: Date()
        )
        appState.tasks = [task]
        let focus = makeFocusService()
        await focus.startSession(
            taskId: task.id,
            taskTitle: task.title,
            startTime: Date().addingTimeInterval(-60)
        )
        let persistence = RecoverySecondSaveBlockingLedgerPersistence()
        let ledger = TaskOperationLedger(
            persistenceEnabled: true,
            initialEntries: [],
            persistence: persistence
        )
        let operation = EventLog(
            eventType: .skipTask,
            taskId: task.id,
            operationID: 710,
            timestamp: Date(),
            hasDeviceTimestamp: true
        )

        let processing = Task { @MainActor in
            await BLEEventHandler.processEventLogs(
                [operation],
                service: .shared,
                focusService: focus,
                persistLogs: false,
                operationLedger: ledger,
                deviceIDOverride: "test-device",
                appState: appState
            )
        }
        await persistence.waitForSecondSaveToStart()
        await focus.startSession(taskId: task.id, taskTitle: task.title)
        await persistence.releaseSecondSave()

        #expect(await processing.value.taskOperationReceipts.map(\.result) == [.supersededByApp])
        #expect(focus.activeSession?.taskId == task.id)
        #expect(await ledger.decision(for: operation, deviceID: "test-device") == .duplicate(.supersededByApp))
    }

    @Test("A task-saved pet-missing crash repairs the reward exactly once")
    @MainActor
    func splitTaskPetWriteRepairsOnce() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let appState = AppState.makeForTesting()
            let storage = LocalStorage.shared
            let storedTasks = try await storage.loadTasks()
            let storedPet = try await storage.loadPet()
            let operationKey = "test-device|17|705"
            let task = TaskItem(
                id: "split-write-\(UUID().uuidString)",
                title: "Repair reward",
                isCompleted: true,
                dueDate: Date(),
                lastModified: Date().addingTimeInterval(-10),
                hardwareCompletionOperationKey: operationKey
            )
            appState.tasks = [task]
            appState.pet.lastHardwareTaskOperationKey = nil
            let baselinePoints = appState.pet.points
            let baselineAdventures = appState.pet.adventuresCount

            let first = await appState.persistHardwareTaskCompletion(
                taskID: task.id,
                operationKey: operationKey,
                reservedAt: Date(),
                source: .hardwareReplay
            )
            let second = await appState.persistHardwareTaskCompletion(
                taskID: task.id,
                operationKey: operationKey,
                reservedAt: Date(),
                source: .hardwareReplay
            )

            #expect(first == .applied)
            #expect(second == .applied)
            #expect(appState.pet.points == baselinePoints + ProgressConstants.pointsPerTask)
            #expect(appState.pet.adventuresCount == baselineAdventures + 1)

            if let storedTasks {
                try await storage.saveTasks(storedTasks)
            } else {
                try await storage.deleteFile(named: "tasks.json")
            }
            if let storedPet {
                try await storage.savePet(storedPet)
            } else {
                try await storage.deleteFile(named: "pet.json")
            }
        }
    }

    @MainActor
    private func makeFocusService() -> FocusSessionService {
        FocusSessionService.makeForTesting(
            focusGuardService: TaskOperationFocusGuardStub(),
            persistenceEnabled: false
        )
    }

    private static func loadLaggingClockFixture() throws -> LaggingClockFixture {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureURL = repositoryRoot
            .appendingPathComponent("test/fixtures/ios-fix/ble-live-complete-lagging-rtc.json")
        return try JSONDecoder().decode(
            LaggingClockFixture.self,
            from: Data(contentsOf: fixtureURL)
        )
    }
}

private struct LaggingClockFixture: Decodable {
    let hardwareClockLagSeconds: TimeInterval
    let sessionElapsedSeconds: TimeInterval
    let taskModifiedSecondsAgo: TimeInterval
    let minimumSettledSeconds: TimeInterval
}

private actor RecoveryBlockingLedgerPersistence: TaskOperationLedgerPersisting {
    private var snapshots: [[TaskOperationLedgerEntry]] = []
    private var hasBlockedFirstSave = false
    private var firstSaveStartedContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func loadTaskOperationLedger() async throws -> [TaskOperationLedgerEntry]? {
        snapshots.last
    }

    func saveTaskOperationLedger(_ entries: [TaskOperationLedgerEntry]) async throws {
        if !hasBlockedFirstSave {
            hasBlockedFirstSave = true
            firstSaveStartedContinuation?.resume()
            firstSaveStartedContinuation = nil
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
            }
        }
        snapshots.append(entries)
    }

    func waitForFirstSaveToStart() async {
        guard !hasBlockedFirstSave else { return }
        await withCheckedContinuation { continuation in
            firstSaveStartedContinuation = continuation
        }
    }

    func releaseFirstSave() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func latestEntries() -> [TaskOperationLedgerEntry] {
        snapshots.last ?? []
    }
}

private actor RecoveryBlockingLoadLedgerPersistence: TaskOperationLedgerPersisting {
    private var loads = 0
    private var didStartLoad = false
    private var isReleased = false
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var loadContinuations: [CheckedContinuation<Void, Never>] = []
    private var snapshots: [[TaskOperationLedgerEntry]] = []

    func loadTaskOperationLedger() async throws -> [TaskOperationLedgerEntry]? {
        loads += 1
        didStartLoad = true
        startContinuation?.resume()
        startContinuation = nil
        if !isReleased {
            await withCheckedContinuation { continuation in
                loadContinuations.append(continuation)
            }
        }
        return []
    }

    func saveTaskOperationLedger(_ entries: [TaskOperationLedgerEntry]) async throws {
        snapshots.append(entries)
    }

    func waitForLoadToStart() async {
        guard !didStartLoad else { return }
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }

    func releaseLoads() {
        isReleased = true
        for continuation in loadContinuations {
            continuation.resume()
        }
        loadContinuations.removeAll()
    }

    func loadCount() -> Int { loads }
    func latestEntries() -> [TaskOperationLedgerEntry] { snapshots.last ?? [] }
}

private actor RecoverySecondSaveFailingLedgerPersistence: TaskOperationLedgerPersisting {
    private var saveCount = 0
    private var snapshots: [[TaskOperationLedgerEntry]] = []

    func loadTaskOperationLedger() async throws -> [TaskOperationLedgerEntry]? {
        snapshots.last
    }

    func saveTaskOperationLedger(_ entries: [TaskOperationLedgerEntry]) async throws {
        saveCount += 1
        if saveCount == 2 {
            throw RecoveryLedgerPersistenceError.injectedCommitFailure
        }
        snapshots.append(entries)
    }

    func latestEntries() -> [TaskOperationLedgerEntry] { snapshots.last ?? [] }
}

private actor RecoveryFirstSaveFailingLedgerPersistence: TaskOperationLedgerPersisting {
    private var saveCount = 0
    private var snapshots: [[TaskOperationLedgerEntry]] = []

    func loadTaskOperationLedger() async throws -> [TaskOperationLedgerEntry]? {
        snapshots.last
    }

    func saveTaskOperationLedger(_ entries: [TaskOperationLedgerEntry]) async throws {
        saveCount += 1
        if saveCount == 1 {
            throw RecoveryLedgerPersistenceError.injectedCommitFailure
        }
        snapshots.append(entries)
    }
}

private actor RecoverySecondSaveBlockingLedgerPersistence: TaskOperationLedgerPersisting {
    private var saveCount = 0
    private var didStartSecondSave = false
    private var didReleaseSecondSave = false
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var snapshots: [[TaskOperationLedgerEntry]] = []

    func loadTaskOperationLedger() async throws -> [TaskOperationLedgerEntry]? {
        snapshots.last
    }

    func saveTaskOperationLedger(_ entries: [TaskOperationLedgerEntry]) async throws {
        saveCount += 1
        if saveCount == 2 {
            didStartSecondSave = true
            startContinuation?.resume()
            startContinuation = nil
            if !didReleaseSecondSave {
                await withCheckedContinuation { continuation in
                    releaseContinuation = continuation
                }
            }
        }
        snapshots.append(entries)
    }

    func waitForSecondSaveToStart() async {
        guard !didStartSecondSave else { return }
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }

    func releaseSecondSave() {
        didReleaseSecondSave = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private enum RecoveryLedgerPersistenceError: Error {
    case injectedCommitFailure
}

private actor RecoveryBlockingTaskStatePersistence: HardwareTaskStatePersisting {
    private var didStartFirstTaskWrite = false
    private var didReleaseFirstTaskWrite = false
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var taskSnapshots: [[TaskItem]] = []
    private var petSnapshots: [Pet] = []

    func saveTasks(_ tasks: [TaskItem]) async throws {
        if !didStartFirstTaskWrite {
            didStartFirstTaskWrite = true
            startContinuation?.resume()
            startContinuation = nil
            if !didReleaseFirstTaskWrite {
                await withCheckedContinuation { continuation in
                    releaseContinuation = continuation
                }
            }
        }
        taskSnapshots.append(tasks)
    }

    func savePet(_ pet: Pet) async throws {
        petSnapshots.append(pet)
    }

    func waitForFirstTaskWrite() async {
        guard !didStartFirstTaskWrite else { return }
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }

    func releaseFirstTaskWrite() {
        didReleaseFirstTaskWrite = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func latestTasks() -> [TaskItem] { taskSnapshots.last ?? [] }
}

@MainActor
private final class TaskOperationFocusGuardStub: FocusGuardService {
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
