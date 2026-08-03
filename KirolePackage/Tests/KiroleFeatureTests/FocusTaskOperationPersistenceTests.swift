import Foundation
import Testing
@testable import KiroleFeature

@Suite("Hardware task focus persistence", .serialized)
struct FocusTaskOperationPersistenceTests {
    @Test("Skipping a long session keeps focus time but awards no energy")
    @MainActor
    func skipNeverAwardsEnergy() async {
        let persistence = FocusPersistenceFailureStub()
        let service = makeService(persistence: persistence)
        let start = Date().addingTimeInterval(-31 * 60)
        await service.startSession(
            taskId: "focus-skip-no-energy",
            taskTitle: "Skip without reward",
            startTime: start
        )

        service.endSession(reason: .skipped, endTime: start.addingTimeInterval(31 * 60))
        await service.waitForPendingPersistenceForTesting()

        #expect(abs((service.todaySessions.last?.calculatedFocusTime ?? 0) - 31 * 60) < 0.001)
        #expect(service.todaySessions.last?.earnedEnergyBottles == 0)
        #expect(await persistence.energyTotal() == 0)
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

    @Test("Active session save failure does not return started or leave an unrecovered session")
    @MainActor
    func activeSaveFailureDoesNotReportStarted() async {
        let persistence = FocusPersistenceFailureStub(failActiveSaves: 1)
        let service = makeService(persistence: persistence)

        let result = await service.startSession(
            taskId: "focus-active-save",
            taskTitle: "Must persist",
            startTime: Date().addingTimeInterval(-30)
        )

        guard case .persistenceUnavailable = result else {
            Issue.record("Expected .persistenceUnavailable, got \(result)")
            return
        }
        #expect(service.activeSession == nil)
        #expect(await persistence.activeSession() == nil)
    }

    @Test("A stale same-task Deep Focus start clears the unused shield it applied")
    @MainActor
    func staleSameTaskDeepFocusStartClearsUnusedShield() async {
        await SharedPersistenceTestLock.shared.withLock {
            await LocalStorage.shared.saveDeepFocusShieldActive(false)
            let persistence = FocusPersistenceFailureStub()
            let guardService = BlockingFocusPersistenceGuardStub()
            let service = makeService(
                persistence: persistence,
                focusGuardService: guardService
            )

            let deepStart = Task { @MainActor in
                await service.startSession(
                    taskId: "focus-same-task",
                    taskTitle: "Same task",
                    mode: .deepFocus
                )
            }
            for _ in 0..<100 where !guardService.refreshStarted {
                await Task.yield()
            }
            #expect(guardService.refreshStarted)

            let replacement = await service.startSession(
                taskId: "focus-same-task",
                taskTitle: "Same task",
                mode: .standard
            )
            guard case .started(let replacementSession) = replacement else {
                Issue.record("Expected the standard replacement session to start")
                guardService.releaseRefresh()
                return
            }

            guardService.releaseRefresh()
            let staleResult = await deepStart.value

            guard case .alreadyActive(let active) = staleResult else {
                Issue.record("Expected the stale Deep Focus start to reuse the active session")
                return
            }
            #expect(active.id == replacementSession.id)
            #expect(service.activeSession?.id == replacementSession.id)
            #expect(guardService.applyShieldCalls == 1)
            #expect(guardService.clearShieldCalls == 1)

            service.endSession(reason: .timeout)
            await service.waitForPendingPersistenceForTesting()
            await LocalStorage.shared.saveDeepFocusShieldActive(false)
        }
    }

    @Test("A late failed start cannot clear a replacement Deep Focus shield")
    @MainActor
    func lateFailedStartKeepsReplacementShield() async {
        await SharedPersistenceTestLock.shared.withLock {
            await LocalStorage.shared.saveDeepFocusShieldActive(false)
            let activeSaveBarrier = FocusLaunchBarrier()
            let persistence = FocusPersistenceFailureStub(
                failActiveSaves: 1,
                activeSaveBarrier: activeSaveBarrier
            )
            let guardService = FocusProtectionTrackingGuardStub()
            let service = makeService(
                persistence: persistence,
                focusGuardService: guardService
            )

            let staleStart = Task { @MainActor in
                await service.startSession(
                    taskId: "focus-stale-save",
                    taskTitle: "Stale save",
                    mode: .deepFocus
                )
            }
            for _ in 0..<100 where !(await persistence.hasStartedActiveSave()) {
                await Task.yield()
            }
            #expect(await persistence.hasStartedActiveSave())

            let replacement = await service.startSession(
                taskId: "focus-replacement-save",
                taskTitle: "Replacement save",
                mode: .deepFocus
            )
            await activeSaveBarrier.release()
            let staleResult = await staleStart.value

            guard case .started(let replacementSession) = replacement else {
                Issue.record("Expected the replacement Deep Focus session to start")
                return
            }
            guard case .persistenceUnavailable = staleResult else {
                Issue.record("Expected the stale active save to fail")
                return
            }
            #expect(service.activeSession?.id == replacementSession.id)
            #expect(await persistence.activeSession()?.id == replacementSession.id)
            #expect(guardService.applyShieldCalls == 2)
            #expect(guardService.clearShieldCalls == 1)
            #expect(guardService.isShieldApplied)

            service.endSession(reason: .timeout)
            await service.waitForPendingPersistenceForTesting()
            await LocalStorage.shared.saveDeepFocusShieldActive(false)
        }
    }

    @Test("Active marker clear skips when a replacement session owns the file")
    func replacementSessionBlocksStaleActiveClear() {
        let settled = UUID()
        let replacement = UUID()

        #expect(
            FocusSessionService.shouldClearActiveSessionMarker(
                settledSessionID: settled,
                liveActiveSessionID: nil,
                diskActiveSessionID: settled
            )
        )
        #expect(
            !FocusSessionService.shouldClearActiveSessionMarker(
                settledSessionID: settled,
                liveActiveSessionID: replacement,
                diskActiveSessionID: settled
            )
        )
        #expect(
            !FocusSessionService.shouldClearActiveSessionMarker(
                settledSessionID: settled,
                liveActiveSessionID: nil,
                diskActiveSessionID: replacement
            )
        )
        #expect(
            FocusSessionService.shouldClearActiveSessionMarker(
                settledSessionID: settled,
                liveActiveSessionID: nil,
                diskActiveSessionID: nil
            )
        )
    }

    @Test("Late settlement for a prior focus does not delete a replacement active marker")
    @MainActor
    func latePriorSettlementKeepsReplacementMarker() async throws {
        // First settlement attempt fails history once so the clear step can run later, after a
        // replacement focus has already claimed focus_session_active.json.
        let persistence = FocusPersistenceFailureStub(failHistorySaves: 1)
        let service = makeService(persistence: persistence)
        let firstStart = Date().addingTimeInterval(-180)
        let secondStart = Date().addingTimeInterval(-30)

        let first = await service.startSession(
            taskId: "focus-marker-a",
            taskTitle: "A",
            startTime: firstStart
        )
        guard case .started(let sessionA) = first else {
            Issue.record("Expected first session to start")
            return
        }
        #expect(await persistence.activeSession()?.id == sessionA.id)

        service.endSession(reason: .timeout, endTime: secondStart)
        await service.waitForPendingPersistenceForTesting()
        #expect(service.pendingFocusSettlement?.session.id == sessionA.id)

        let sessionB = FocusSession(
            taskId: "focus-marker-b",
            taskTitle: "B",
            startTime: secondStart
        )
        try await persistence.saveActiveSession(sessionB)
        service.activeSession = sessionB

        #expect(await service.retryPendingFocusSettlementIfNeeded())
        #expect(service.pendingFocusSettlement == nil)
        #expect(await persistence.activeSession()?.id == sessionB.id)
        #expect(service.activeSession?.id == sessionB.id)
    }

    @Test("Task switch ends the previous session with hardware presentation suppressed")
    @MainActor
    func taskSwitchSuppressesIdleHardwarePresentation() async throws {
        // Keep the prior session's settlement pending so we can inspect the suppress flag
        // before handleFocusSessionDidEnd runs. retryPendingFocusSettlementIfNeeded will attempt
        // again after the first failure, so the failure budget must survive that second attempt.
        let persistence = FocusPersistenceFailureStub(failHistorySaves: 5)
        let service = makeService(persistence: persistence)
        let firstStart = Date().addingTimeInterval(-120)
        let secondStart = Date().addingTimeInterval(-30)

        let first = await service.startSession(
            taskId: "focus-switch-a",
            taskTitle: "A",
            startTime: firstStart
        )
        guard case .started = first else {
            Issue.record("Expected first session to start")
            return
        }

        // Ending A for a switch parks settlement with suppressHardwarePresentation. The
        // failed history write blocks B from starting — that is expected and still proves the
        // flag that prevents idle 0x14 from racing a later 0x11.
        let second = await service.startSession(
            taskId: "focus-switch-b",
            taskTitle: "B",
            startTime: secondStart
        )
        guard case .persistenceUnavailable = second else {
            Issue.record("Expected settlement barrier to block the replacement start, got \(second)")
            return
        }

        let pending = try #require(service.pendingFocusSettlement)
        #expect(pending.session.taskId == "focus-switch-a")
        #expect(pending.session.endReason == .timeout)
        #expect(pending.suppressHardwarePresentation)
        #expect(service.activeSession == nil)
    }

    @Test("A failed post-protection settlement barrier clears the unused Deep Focus shield")
    @MainActor
    func failedSecondSettlementBarrierClearsResolvedProtection() async {
        await SharedPersistenceTestLock.shared.withLock {
            await LocalStorage.shared.saveDeepFocusShieldActive(false)
            let persistence = FocusPersistenceFailureStub(failHistorySaves: 3)
            let guardService = BlockingFocusPersistenceGuardStub()
            let service = makeService(
                persistence: persistence,
                focusGuardService: guardService
            )

            let deepStart = Task { @MainActor in
                await service.startSession(
                    taskId: "focus-deep-waiting",
                    taskTitle: "Deep waiting",
                    mode: .deepFocus
                )
            }
            for _ in 0..<100 where !guardService.refreshStarted {
                await Task.yield()
            }
            #expect(guardService.refreshStarted)

            let replacement = await service.startSession(
                taskId: "focus-standard-replacement",
                taskTitle: "Standard replacement",
                mode: .standard
            )
            guard case .started = replacement else {
                Issue.record("Expected the replacement session to start")
                guardService.releaseRefresh()
                return
            }

            guardService.releaseRefresh()
            let result = await deepStart.value
            await LocalStorage.shared.saveDeepFocusShieldActive(false)

            guard case .persistenceUnavailable = result else {
                Issue.record("Expected the failed settlement barrier to reject the new session")
                return
            }
            #expect(service.activeSession == nil)
            #expect(guardService.applyShieldCalls == 1)
            #expect(guardService.clearShieldCalls == 1)
        }
    }

    @Test("A protected session that appears during the failed barrier keeps its shield")
    @MainActor
    func failedBarrierDoesNotClearNewProtectedSessionShield() async {
        await SharedPersistenceTestLock.shared.withLock {
            await LocalStorage.shared.saveDeepFocusShieldActive(false)
            let historyBarrier = FocusLaunchBarrier()
            let persistence = FocusPersistenceFailureStub(
                failHistorySaves: 3,
                historySaveBarrier: historyBarrier
            )
            let guardService = BlockingFocusPersistenceGuardStub()
            let service = makeService(
                persistence: persistence,
                focusGuardService: guardService
            )

            let deepStart = Task { @MainActor in
                await service.startSession(
                    taskId: "focus-deep-stale-cleanup",
                    taskTitle: "Deep stale cleanup",
                    mode: .deepFocus
                )
            }
            for _ in 0..<100 where !guardService.refreshStarted {
                await Task.yield()
            }
            _ = await service.startSession(
                taskId: "focus-standard-before-barrier",
                taskTitle: "Standard before barrier",
                mode: .standard
            )

            guardService.releaseRefresh()
            for _ in 0..<100 where !(await persistence.hasStartedHistorySave()) {
                await Task.yield()
            }
            let protectedReplacement = FocusSession(
                taskId: "focus-protected-during-barrier",
                taskTitle: "Protected during barrier",
                startTime: Date(),
                mode: .deepFocus,
                protectionState: .protected
            )
            service.activeSession = protectedReplacement
            await historyBarrier.release()

            let result = await deepStart.value
            guard case .persistenceUnavailable = result else {
                Issue.record("Expected the failed barrier to reject the stale Deep Focus start")
                return
            }
            #expect(service.activeSession?.id == protectedReplacement.id)
            #expect(guardService.clearShieldCalls == 0)

            guardService.clearShield()
            service.activeSession = nil
            await LocalStorage.shared.saveDeepFocusShieldActive(false)
        }
    }

    @Test("Overlapping Deep Focus starts preserve the replacement session's shield")
    @MainActor
    func overlappingDeepFocusStartsPreserveReplacementShield() async {
        await SharedPersistenceTestLock.shared.withLock {
            await LocalStorage.shared.saveDeepFocusShieldActive(false)
            let persistence = FocusPersistenceFailureStub()
            let guardService = InterleavingFocusGuardStub()
            let service = makeService(
                persistence: persistence,
                focusGuardService: guardService
            )

            let firstStart = Task { @MainActor in
                await service.startSession(
                    taskId: "focus-overlap-a",
                    taskTitle: "Overlap A",
                    mode: .deepFocus
                )
            }
            for _ in 0..<100 where guardService.refreshCallCount < 1 {
                await Task.yield()
            }

            let replacementStart = Task { @MainActor in
                await service.startSession(
                    taskId: "focus-overlap-b",
                    taskTitle: "Overlap B",
                    mode: .deepFocus
                )
            }
            for _ in 0..<100 where guardService.refreshCallCount < 2 {
                await Task.yield()
            }
            #expect(guardService.refreshCallCount == 2)

            // A applies generation 1, then the guard releases B so generation 2 is claimed while
            // A is suspended on shield-state persistence. A must not adopt B's newer generation.
            guardService.releaseFirstRefresh()
            _ = await firstStart.value
            let replacementResult = await replacementStart.value

            guard case .started = replacementResult else {
                Issue.record("Expected the replacement Deep Focus session to start")
                return
            }
            #expect(service.activeSession?.taskId == "focus-overlap-b")
            #expect(service.activeSession?.protectionState == .protected)
            #expect(guardService.isShieldApplied)
            #expect(guardService.clearShieldCalls == 0)

            service.endSession(reason: .manual)
            await service.waitForPendingPersistenceForTesting()
            #expect(guardService.clearShieldCalls == 1)
            await LocalStorage.shared.saveDeepFocusShieldActive(false)
        }
    }

    @Test("Testing services route live sync and settlement presentation through injected exits")
    @MainActor
    func testingServiceUsesInjectedHardwareExits() async {
        let persistence = FocusPersistenceFailureStub()
        let recorder = FocusHardwareExitRecorder()
        let service = makeService(
            persistence: persistence,
            hardwareDisplaySyncExecutor: { session in
                recorder.recordDisplaySync(session)
            },
            sessionEndPresentationExecutor: {
                total, newlyUnlocked, now, defersPresentation in
                recorder.recordSettlement(
                    total: total,
                    newlyUnlocked: newlyUnlocked,
                    now: now,
                    defersPresentation: defersPresentation
                )
            }
        )

        _ = await service.startSession(
            taskId: "focus-injected-output",
            taskTitle: "Injected output"
        )
        for _ in 0..<100 where recorder.displaySyncCount == 0 {
            await Task.yield()
        }
        service.endSession(reason: .manual)
        await service.waitForPendingPersistenceForTesting()

        #expect(recorder.displaySyncCount == 1)
        #expect(recorder.settlementCount == 1)
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
        focusGuardService: any FocusGuardService = FocusPersistenceGuardStub(),
        ledger: TaskOperationLedger = TaskOperationLedger(
            persistenceEnabled: false,
            initialEntries: []
        ),
        launchRecoveryCompleted: Bool = true,
        hardwareDisplaySyncExecutor: @escaping FocusHardwareDisplaySyncExecutor = { _ in },
        sessionEndPresentationExecutor: @escaping FocusSessionEndPresentationExecutor = {
            _, _, _, _ in
        }
    ) -> FocusSessionService {
        FocusSessionService.makeForTesting(
            focusGuardService: focusGuardService,
            persistenceEnabled: true,
            launchRecoveryCompleted: launchRecoveryCompleted,
            focusPersistence: persistence,
            taskOperationLedger: ledger,
            hardwareDisplaySyncExecutor: hardwareDisplaySyncExecutor,
            sessionEndPresentationExecutor: sessionEndPresentationExecutor
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
