import Foundation
import Testing
@testable import KiroleFeature

@Suite("AppDeviceScenarioTests", .serialized)
@MainActor
struct AppDeviceScenarioTests {
    @Test("Device refresh still commits the current Overview through the production responder")
    func requestRefreshBaselineCommitsCurrentOverview() async throws {
        let scenario = AppDeviceScenario(now: Self.startDate)
        let task = TaskItem(
            id: "baseline-task",
            title: "Baseline task",
            dueDate: Self.startDate,
            priority: .high
        )

        await scenario.replaceAppTasks([task])
        scenario.connect()
        let outcome = try await scenario.deviceRequestsTaskRefresh(operationID: 41)

        let snapshot = await scenario.snapshot()
        let transaction = try #require(snapshot.outboundTransactions.last)
        #expect(outcome == .sent)
        #expect(snapshot.appTasks.map(\.id) == ["baseline-task"])
        #expect(snapshot.committedVersion == TaskListSnapshotVersion(epoch: 1, revision: 1))
        #expect(snapshot.pendingVersion == nil)
        #expect(snapshot.taskQueue == ["baseline-task"])
        #expect(transaction.type == BLEDataType.taskListSnapshotAck.rawValue)
        #expect(transaction.result == .delivered)
    }

    @Test("Current DayPack still crosses the production wire contract")
    func currentDayPackBaseline() async throws {
        let scenario = AppDeviceScenario(now: Self.startDate)
        let dayPack = ProtocolFixtures().dayPack

        scenario.connect()
        try scenario.sendDayPack(dayPack, messageID: 0x6101, maxChunkSize: 24)

        let snapshot = await scenario.snapshot()
        let transaction = try #require(snapshot.outboundTransactions.last)
        let received = try #require(transaction.receivedPacket)
        let parsed = try received.parseDayPack()

        #expect(snapshot.connectionState == .connected)
        #expect(transaction.type == BLEDataType.dayPack.rawValue)
        #expect(transaction.packetCount > 1)
        #expect(transaction.writtenPacketCount == transaction.packetCount)
        #expect(transaction.result == .delivered)
        #expect(parsed.date == (year: 2026, month: 5, day: 7))
        #expect(parsed.petDialogue == dayPack.petDialogue)
        #expect(parsed.events.map(\.title) == dayPack.events.map(\.title))
        #expect(parsed.topTasks.map(\.id) == dayPack.topTasks.map(\.id))
    }

    @Test("One clock crosses the sync window, focus phases, and midnight without waiting")
    func controllableClockDrivesAllTimeBoundaries() async {
        let scenario = AppDeviceScenario(now: Self.minuteBeforeMidnight)
        #expect(Self.deviceCalendar.component(.day, from: await scenario.snapshot().now) == 7)

        await scenario.requestBLESync(reason: "edited-task", debounce: .seconds(180))
        await scenario.advance(by: .seconds(179))
        #expect(await scenario.snapshot().executedSyncTriggers.isEmpty)

        await scenario.advance(by: .seconds(1))
        #expect(await scenario.snapshot().executedSyncTriggers == [.automatic])
        #expect(Self.deviceCalendar.component(.day, from: await scenario.snapshot().now) == 8)

        await scenario.startFocus(taskID: "task-clock", title: "Clock boundaries")
        #expect(await scenario.snapshot().focus?.phase == .warmup)

        await scenario.advance(by: .seconds(5 * 60))
        #expect(await scenario.snapshot().focus?.phase == .warmup)

        await scenario.advance(by: .seconds(60))
        #expect(await scenario.snapshot().focus?.phase == .building)

        await scenario.advance(by: .seconds(10 * 60))
        #expect(await scenario.snapshot().focus?.phase == .deep)
    }

    @Test("Midnight hides yesterday content while task records survive App and device restarts")
    func dailyContentRolloverSurvivesRestarts() async throws {
        let scenario = AppDeviceScenario(now: Self.minuteBeforeMidnight)
        let phaseTexts = TaskLibraryPhaseTexts.localFallback(for: .joy)
        let taskRecord = TaskLibraryRecord(
            taskID: "persistent-task",
            order: 0,
            title: "Persistent task",
            detail: "Keep this across midnight.",
            phaseTexts: phaseTexts
        )
        let taskLibrary = TaskLibraryTransaction(
            version: TaskLibraryVersion(epoch: 1, revision: 1),
            records: [taskRecord]
        )
        let yesterdayPackage = Self.dailyPackage(
            at: Self.minuteBeforeMidnight,
            eventTitle: "Yesterday event"
        )

        scenario.connect()
        _ = try scenario.sendTaskLibrary(taskLibrary, messageID: 0x7101, maxChunkSize: 24)
        _ = try scenario.sendDailyContent(
            DailyContentTransaction(
                version: DailyContentVersion(epoch: 1, revision: 1),
                package: yesterdayPackage
            ),
            messageID: 0x7102,
            maxChunkSize: 24
        )
        await scenario.startDailyContentRolloverMonitoring()
        var snapshot = await scenario.snapshot()
        #expect(snapshot.dailyContentVisiblePackage?.events.map(\.title) == ["Yesterday event"])
        #expect(snapshot.taskLibraryRecords.map(\.taskID) == ["persistent-task"])

        await scenario.advance(by: .seconds(60))
        snapshot = await scenario.snapshot()
        #expect(snapshot.dailyContentCommittedDate == yesterdayPackage.localDate)
        #expect(snapshot.dailyContentVisiblePackage == nil)
        #expect(snapshot.taskLibraryRecords.map(\.taskID) == ["persistent-task"])
        #expect(snapshot.executedSyncTriggers == [.automatic])

        scenario.restartDevice()
        snapshot = await scenario.snapshot()
        #expect(snapshot.dailyContentVisiblePackage == nil)
        #expect(snapshot.taskLibraryRecords.map(\.taskID) == ["persistent-task"])

        await scenario.restartApp()
        await scenario.startDailyContentRolloverMonitoring()
        scenario.reconnect()
        snapshot = await scenario.snapshot()
        #expect(snapshot.dailyContentVisiblePackage == nil)
        #expect(snapshot.taskLibraryRecords.map(\.taskID) == ["persistent-task"])
        #expect(snapshot.executedSyncTriggers == [.automatic])

        let todayPackage = Self.dailyPackage(
            at: snapshot.now,
            eventTitle: "Today event"
        )
        _ = try scenario.sendDailyContent(
            DailyContentTransaction(
                version: DailyContentVersion(epoch: 1, revision: 2),
                package: todayPackage
            ),
            messageID: 0x7103,
            maxChunkSize: 24
        )
        snapshot = await scenario.snapshot()
        #expect(snapshot.dailyContentVisiblePackage?.events.map(\.title) == ["Today event"])
        #expect(snapshot.taskLibraryRecords.map(\.taskID) == ["persistent-task"])
    }

    @Test("Replacing a scheduled wait starts from the newest request")
    func controllableClockTracksReplacementSleeper() async {
        let scenario = AppDeviceScenario(now: Self.startDate)

        await scenario.requestBLESync(reason: "first-edit", debounce: .seconds(180))
        await scenario.advance(by: .seconds(120))
        await scenario.requestBLESync(reason: "second-edit", debounce: .seconds(180))

        await scenario.advance(by: .seconds(60))
        #expect(await scenario.snapshot().executedSyncTriggers.isEmpty)

        await scenario.advance(by: .seconds(119))
        #expect(await scenario.snapshot().executedSyncTriggers.isEmpty)

        await scenario.advance(by: .seconds(1))
        #expect(await scenario.snapshot().executedSyncTriggers == [.automatic])
    }

    @Test("Zero stabilization runs immediately without hanging")
    func zeroStabilizationWindowRunsImmediately() async {
        let scenario = AppDeviceScenario(now: Self.startDate)

        await scenario.requestBLESync(reason: "immediate-edit", debounce: .zero)

        #expect(await scenario.snapshot().executedSyncTriggers == [.automatic])
    }

    @Test("A cancelled clock wait stays cancelled even if time advances immediately")
    func clockCancellationWinsAdvanceRace() async {
        let clock = MutableScenarioClock(now: Self.startDate)
        let registration = await clock.latestSleeperRegistration()
        let sleeper = Task {
            try await clock.sleep(for: .seconds(60))
        }
        await clock.waitUntilSleeperIsScheduled(after: registration)

        sleeper.cancel()
        _ = await clock.advance(by: .seconds(60))

        do {
            try await sleeper.value
            Issue.record("Expected the cancelled clock wait to throw")
        } catch is CancellationError {
            // Expected even when advancing races the asynchronous cancellation callback.
        } catch {
            Issue.record("Unexpected clock cancellation error: \(error)")
        }
    }

    @Test("AI attempts can succeed, fail repeatedly, or finish after a controlled delay")
    func scriptedAIControlsEveryOutcome() async throws {
        let scenario = AppDeviceScenario(
            now: Self.startDate,
            aiResponses: [
                .success("first attempt"),
                .failure(.unavailable),
                .success("retry succeeded"),
                .failure(.unavailable),
                .failure(.unavailable),
                .suspended(id: "late-request"),
            ]
        )

        #expect(try await scenario.generateAIText() == "first attempt")
        await expectAIError(.unavailable) { try await scenario.generateAIText() }
        #expect(try await scenario.generateAIText() == "retry succeeded")
        await expectAIError(.unavailable) { try await scenario.generateAIText() }
        await expectAIError(.unavailable) { try await scenario.generateAIText() }

        let lateResult = Task { @MainActor in
            try await scenario.generateAIText()
        }
        await scenario.waitUntilAIRequestIsSuspended(id: "late-request")
        await scenario.advance(by: .seconds(181))
        await scenario.resolveAIRequest(id: "late-request", with: .success("late result"))

        #expect(try await lateResult.value == "late result")
    }

    @Test("Task cancellation wins an immediately resolved AI timeout race")
    func scriptedAITimeoutRejectsLateResult() async {
        let scenario = AppDeviceScenario(
            now: Self.startDate,
            aiResponses: [.suspended(id: "timed-out-request")]
        )
        let request = Task { @MainActor in
            try await scenario.generateAIText()
        }

        await scenario.waitUntilAIRequestIsSuspended(id: "timed-out-request")
        await scenario.advance(by: .seconds(180))
        request.cancel()
        _ = await scenario.resolveAIRequest(
            id: "timed-out-request",
            with: .success("too late")
        )

        do {
            _ = try await request.value
            Issue.record("Expected the timed-out AI request to be cancelled")
        } catch is CancellationError {
            // Expected: cancellation wins even if resolution entered the actor first.
        } catch {
            Issue.record("Unexpected timeout error: \(error)")
        }

        #expect(await !scenario.resolveAIRequest(
            id: "timed-out-request",
            with: .success("later still")
        ))
    }

    @Test("A failed task-snapshot transaction keeps the old commit and exposes its own pending version")
    func failedTaskSnapshotKeepsCommittedStateAtomic() async throws {
        let scenario = AppDeviceScenario(now: Self.startDate)
        let oldTask = TaskItem(
            id: "old-task",
            title: "Old task",
            dueDate: Self.startDate,
            lastModified: Self.startDate.addingTimeInterval(-60)
        )
        let newTask = TaskItem(
            id: "new-task",
            title: "A newer task snapshot that must span several BLE packets",
            dueDate: Self.startDate,
            lastModified: Self.startDate
        )

        await scenario.replaceAppTasks([oldTask])
        scenario.connect()
        _ = try await scenario.deviceRequestsTaskRefresh(operationID: 41)
        await scenario.replaceAppTasks([newTask])
        scenario.configureTaskSnapshotTransport(maxWriteLength: 40)
        scenario.failNextWrite(atChunk: 1)
        scenario.failNextWrite(atChunk: 1)

        let outcome = try await scenario.deviceRequestsTaskRefresh(operationID: 42)

        var snapshot = await scenario.snapshot()
        let failedAttempts = Array(snapshot.outboundTransactions.suffix(2))
        #expect(outcome == .failed)
        #expect(snapshot.appTasks.map(\.id) == [newTask.id])
        #expect(snapshot.committedVersion == TaskListSnapshotVersion(epoch: 1, revision: 1))
        #expect(snapshot.pendingVersion == TaskListSnapshotVersion(epoch: 1, revision: 2))
        #expect(snapshot.taskQueue == [oldTask.id])
        #expect(failedAttempts.count == 2)
        #expect(failedAttempts.allSatisfy {
            $0.type == BLEDataType.taskListSnapshotAck.rawValue
                && $0.packetCount > 1
                && $0.writtenPacketCount == 1
                && $0.result == .failed(chunkIndex: 1)
        })

        scenario.restartDevice()
        snapshot = await scenario.snapshot()
        #expect(snapshot.connectionState == .disconnected)
        #expect(snapshot.committedVersion == TaskListSnapshotVersion(epoch: 1, revision: 1))
        #expect(snapshot.pendingVersion == nil)
        #expect(snapshot.taskQueue == [oldTask.id])
    }

    @Test("A task-snapshot retry commits the frozen version after one chunk failure")
    func taskSnapshotRetryCommitsFrozenVersion() async throws {
        let scenario = AppDeviceScenario(now: Self.startDate)
        let oldTask = TaskItem(
            id: "retry-old",
            title: "Retry old",
            dueDate: Self.startDate
        )
        let newTask = TaskItem(
            id: "retry-new",
            title: "Retry snapshot with enough bytes to require chunking",
            dueDate: Self.startDate
        )

        await scenario.replaceAppTasks([oldTask])
        scenario.connect()
        _ = try await scenario.deviceRequestsTaskRefresh(operationID: 51)
        await scenario.replaceAppTasks([newTask])
        scenario.configureTaskSnapshotTransport(maxWriteLength: 40)
        scenario.failNextWrite(atChunk: 1)

        let outcome = try await scenario.deviceRequestsTaskRefresh(operationID: 52)

        let snapshot = await scenario.snapshot()
        let attempts = Array(snapshot.outboundTransactions.suffix(2))
        #expect(outcome == .sent)
        #expect(attempts.map(\.result) == [.failed(chunkIndex: 1), .delivered])
        #expect(snapshot.committedVersion == TaskListSnapshotVersion(epoch: 1, revision: 2))
        #expect(snapshot.pendingVersion == nil)
        #expect(snapshot.taskQueue == [newTask.id])
    }

    @Test("A failed first snapshot reuses revision one when the same request returns")
    func firstSnapshotFailureRetriesSameFrozenVersion() async throws {
        let scenario = AppDeviceScenario(now: Self.startDate)
        let task = TaskItem(
            id: "first-retry",
            title: "First snapshot must keep revision one across reconnect",
            dueDate: Self.startDate
        )

        await scenario.replaceAppTasks([task])
        scenario.connect()
        scenario.configureTaskSnapshotTransport(maxWriteLength: 40)
        scenario.failNextWrite(atChunk: 1)
        scenario.failNextWrite(atChunk: 1)

        let failed = try await scenario.deviceRequestsTaskRefresh(operationID: 61)
        var snapshot = await scenario.snapshot()
        #expect(failed == .failed)
        #expect(snapshot.committedVersion == nil)
        #expect(snapshot.pendingVersion == TaskListSnapshotVersion(epoch: 1, revision: 1))

        await scenario.restartApp()
        scenario.restartDevice()
        scenario.connect()
        let retried = try await scenario.deviceRequestsTaskRefresh(operationID: 61)

        snapshot = await scenario.snapshot()
        #expect(retried == .sent)
        #expect(snapshot.committedVersion == TaskListSnapshotVersion(epoch: 1, revision: 1))
        #expect(snapshot.pendingVersion == nil)
        #expect(snapshot.taskQueue == [task.id])
        let attempts = Array(snapshot.outboundTransactions.suffix(3))
        #expect(attempts.map(\.result) == [
            .failed(chunkIndex: 1),
            .failed(chunkIndex: 1),
            .delivered,
        ])
        let acknowledgement = try #require(attempts.last?.receivedPacket)
            .parseTaskListSnapshotAck()
        #expect(acknowledgement.revision == 1)
    }

    @Test("A configured DayPack chunk failure and reconnect stay observable")
    func dayPackChunkFailureAndReconnectAreObservable() async throws {
        let scenario = AppDeviceScenario(now: Self.startDate)
        scenario.showDevicePage(.dailySummary)
        scenario.connect()
        scenario.failNextWrite(atChunk: 1)

        do {
            try scenario.sendDayPack(
                ProtocolFixtures().dayPack,
                messageID: 0x6201,
                maxChunkSize: 24
            )
            Issue.record("Expected the configured chunk write to fail")
        } catch let error as AppDeviceScenarioError {
            #expect(error == .chunkWriteFailed(index: 1))
        }

        var snapshot = await scenario.snapshot()
        let failed = try #require(snapshot.outboundTransactions.last)
        #expect(failed.result == .failed(chunkIndex: 1))
        #expect(failed.writtenPacketCount == 1)

        scenario.disconnect()
        snapshot = await scenario.snapshot()
        #expect(snapshot.connectionState == .disconnected)
        #expect(snapshot.currentPage == .dailySummary)
        scenario.reconnect()
        snapshot = await scenario.snapshot()
        #expect(snapshot.connectionState == .connected)
        #expect(snapshot.currentPage == .dailySummary)
    }

    @Test("App restart restores durable tasks, settles focus, and cancels runtime AI")
    func appRestartSeparatesPersistentAndRuntimeState() async throws {
        let scenario = AppDeviceScenario(
            now: Self.startDate,
            aiResponses: [.suspended(id: "restart-request")]
        )
        let task = TaskItem(
            id: "durable-task",
            title: "Durable task",
            dueDate: Self.startDate,
            lastModified: Self.startDate.addingTimeInterval(-60)
        )

        await scenario.replaceAppTasks([task])
        scenario.connect()
        scenario.showDevicePage(.focus(taskID: task.id))
        scenario.setDeviceFocus(.init(taskID: task.id, startedAt: Self.startDate))
        await scenario.startFocus(taskID: task.id, title: task.title)
        let aiRequest = Task { @MainActor in
            try await scenario.generateAIText()
        }
        await scenario.waitUntilAIRequestIsSuspended(id: "restart-request")
        #expect(await scenario.snapshot().focus != nil)

        let previousAppState = scenario.appState
        await scenario.restartApp()
        #expect(previousAppState !== scenario.appState)
        let snapshot = await scenario.snapshot()
        #expect(snapshot.connectionState == .disconnected)
        #expect(snapshot.appTasks.map(\.id) == [task.id])
        #expect(snapshot.focus == nil)
        #expect(snapshot.focusHistory.last?.taskId == task.id)
        #expect(snapshot.focusHistory.last?.endReason == .recoveredOnLaunch)
        #expect(snapshot.currentPage == .focus(taskID: task.id))
        #expect(snapshot.deviceFocus?.taskID == task.id)

        do {
            _ = try await aiRequest.value
            Issue.record("Expected App restart to cancel the runtime AI request")
        } catch is CancellationError {
            // Expected: an in-flight request is process state, not persisted App state.
        } catch {
            Issue.record("Unexpected restart cancellation error: \(error)")
        }
    }

    @Test("Offline device bytes replay through the production parser, processor, ledger, and responder")
    func offlineTaskActionUsesRealReplayPath() async throws {
        let scenario = AppDeviceScenario(now: Self.startDate)
        let task = TaskItem(
            id: "provider-task-that-still-fits",
            title: "Offline completion",
            dueDate: Self.startDate,
            lastModified: Self.startDate.addingTimeInterval(-60)
        )

        await scenario.replaceAppTasks([task])
        try scenario.recordOfflineTaskAction(
            .completeTask,
            task: task,
            operationID: 91,
            at: Self.startDate
        )
        var snapshot = await scenario.snapshot()
        #expect(snapshot.offlineActions.map(\.operationID) == [91])
        #expect(snapshot.appTasks.first?.isCompleted == false)
        #expect(snapshot.appOperationLedger.isEmpty)
        #expect(snapshot.outboundTransactions.isEmpty)

        scenario.restartDevice()
        #expect(await scenario.snapshot().offlineActions.map(\.operationID) == [91])
        scenario.connect()
        let outcome = try await scenario.replayOfflineActions()

        snapshot = await scenario.snapshot()
        #expect(outcome == .sent)
        #expect(snapshot.appTasks.first?.isCompleted == true)
        #expect(snapshot.appTasks.first?.lastModified == Self.startDate)
        #expect(snapshot.offlineActions.isEmpty)
        #expect(snapshot.appOperationLedger.count == 1)
        #expect(snapshot.appOperationLedger.first?.action == .completeTask)
        #expect(snapshot.appOperationLedger.first?.operationID == 91)
        #expect(snapshot.appOperationLedger.first?.state == .committed)
        #expect(snapshot.appOperationLedger.first?.timestampAuthority == .deviceClock)
        #expect(snapshot.committedVersion == TaskListSnapshotVersion(epoch: 1, revision: 1))
        #expect(snapshot.pendingVersion == nil)
        #expect(snapshot.taskQueue.isEmpty)
        let transaction = try #require(snapshot.outboundTransactions.last)
        let acknowledgement = try #require(transaction.receivedPacket)
            .parseTaskListSnapshotAck()
        #expect(acknowledgement.action == .completeTask)
        #expect(acknowledgement.operationID == 91)
        #expect(acknowledgement.result == .applied)
    }

    private static let startDate = DateComponents(
        calendar: Calendar(identifier: .gregorian),
        timeZone: TimeZone(secondsFromGMT: 0),
        year: 2026,
        month: 5,
        day: 7,
        hour: 9
    ).date!

    private static let minuteBeforeMidnight = DateComponents(
        calendar: Calendar(identifier: .gregorian),
        timeZone: TimeZone(identifier: "Asia/Shanghai"),
        year: 2026,
        month: 5,
        day: 7,
        hour: 23,
        minute: 59
    ).date!

    private static var deviceCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private static func dailyPackage(at date: Date, eventTitle: String) -> DailyContentPackage {
        let timestamp = UInt64(date.timeIntervalSince1970)
        return DailyContentPackage(
            localDate: DailyContentDate(date: date, calendar: deviceCalendar),
            morningDialogue: "Morning",
            idleDialogue: "Idle",
            closingDialogue: "Closing",
            daySummary: "Summary",
            screensaverQuote: "Quote",
            screensaverAuthor: "Joy",
            settlementReview: "Review",
            settlementQuote: "Closing quote",
            events: [DailyContentEvent(
                eventID: "event-\(eventTitle)",
                startTimestamp: timestamp,
                endTimestamp: timestamp + 1_800,
                isAllDay: false,
                title: eventTitle,
                detail: "",
                category: .admin,
                companionDialogue: "Dialogue",
                supportText: "Support"
            )]
        )
    }

    private func expectAIError(
        _ expected: ScenarioAIError,
        operation: () async throws -> String
    ) async {
        do {
            _ = try await operation()
            Issue.record("Expected AI error \(expected)")
        } catch let error as ScenarioAIError {
            #expect(error == expected)
        } catch {
            Issue.record("Unexpected AI error: \(error)")
        }
    }
}
