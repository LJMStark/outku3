import Foundation
import Testing
@testable import KiroleFeature

@Suite("Focus reconnect Bugbot fixes")
struct FocusReconnectFixTests {
    @Test("Focus freeze leases release only their own ownership")
    @MainActor
    func focusFreezeLeasesDoNotPrematurelyUnlock() {
        let service = FocusSessionService.makeForTesting(
            focusGuardService: ReconnectFixFocusGuard(),
            persistenceEnabled: false
        )

        let initialEpoch = service.focusStatusFreezeEpoch
        let deviceWakeLease = service.acquireFocusStatusFreeze()
        let deviceWakeEpoch = service.focusStatusFreezeEpoch
        let offlineSyncLease = service.acquireFocusStatusFreeze()
        #expect(service.isFocusStatusPushFrozen)
        #expect(deviceWakeEpoch > initialEpoch)
        #expect(service.focusStatusFreezeEpoch > deviceWakeEpoch)

        service.releaseFocusStatusFreeze(deviceWakeLease)
        #expect(service.isFocusStatusPushFrozen)

        service.releaseFocusStatusFreeze(deviceWakeLease)
        #expect(service.isFocusStatusPushFrozen)

        service.releaseFocusStatusFreeze(offlineSyncLease)
        #expect(service.isFocusStatusPushFrozen == false)

        let lateDeviceWakeLease = service.acquireFocusStatusFreeze()
        let cancelledOfflineSyncLease = service.acquireFocusStatusFreeze()
        service.releaseFocusStatusFreeze(cancelledOfflineSyncLease)
        #expect(service.isFocusStatusPushFrozen)
        service.releaseFocusStatusFreeze(lateDeviceWakeLease)
        #expect(service.isFocusStatusPushFrozen == false)
    }

    @Test("Legacy boolean unlock cannot release an explicit Focus freeze lease")
    @MainActor
    func legacyUnlockPreservesExplicitLease() {
        let service = FocusSessionService.makeForTesting(
            focusGuardService: ReconnectFixFocusGuard(),
            persistenceEnabled: false
        )

        let lease = service.acquireFocusStatusFreeze()
        service.isFocusStatusPushFrozen = true
        service.isFocusStatusPushFrozen = false

        #expect(service.isFocusStatusPushFrozen)
        service.releaseFocusStatusFreeze(lease)
        #expect(service.isFocusStatusPushFrozen == false)
    }

    @Test("Preview only suppresses a visible start and does not mutate the session")
    @MainActor
    func previewDoesNotAdoptOrEnd() async throws {
        let service = FocusSessionService.makeForTesting(
            focusGuardService: ReconnectFixFocusGuard(),
            persistenceEnabled: false
        )

        let activeSnapshot = FocusWireFixtures.focusState(revision: 38)
        try await service.applyReconnectPreview(activeSnapshot)
        #expect(service.activeSession == nil)
        #expect(service.suppressVisibleFocusStart == false)
        #expect(service.todaySessions.isEmpty)
        #expect(service.lastAppliedFocusRevision == activeSnapshot.focusRevision)

        try await service.applyReconnectPreview(
            FocusWireFixtures.focusState(
                focusState: .endedPending,
                end: FocusWireFixtures.timestamp + 400,
                elapsed: 400,
                endReason: .complete
            )
        )
        #expect(service.activeSession == nil)
        #expect(service.suppressVisibleFocusStart == true)
        #expect(service.todaySessions.isEmpty)
    }

    @Test("Ordinary active restore uses the device snapshot as its revision floor")
    @MainActor
    func ordinaryActiveRestoreUsesDeviceRevisionFloor() async throws {
        let service = FocusSessionService.makeForTesting(
            focusGuardService: ReconnectFixFocusGuard(),
            persistenceEnabled: false
        )
        await service.startSession(
            taskId: "local-active",
            taskTitle: "Local active",
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            focusSessionId: FocusSessionId(bootSessionID: 1, startOperationID: 1)
        )
        let localRevision = try #require(service.activeSession?.focusRevision)
        let deviceSnapshot = FocusWireFixtures.focusState(
            revision: localRevision + 37,
            sessionId: .idle,
            focusState: .idle,
            taskID: "",
            start: 0,
            end: 0,
            elapsed: 0,
            lastOperationID: 0,
            endReason: .none
        )

        try await service.applyReconnectPreview(deviceSnapshot)

        #expect(service.ordinaryFocusRevisionFloor(for: service.activeSession) == deviceSnapshot.focusRevision)
    }

    @Test("Reconnect restore bypasses the ordinary two-second FocusStatus dedup window")
    @MainActor
    func reconnectRestoreBypassesRecentFocusStatusDedup() {
        #expect(AppState.shouldDeduplicateFocusStatus(
            mustAdvanceRevisionBeyondFloor: false,
            isSamePayload: true,
            elapsedSinceLastSend: 0.5
        ))
        #expect(AppState.shouldDeduplicateFocusStatus(
            mustAdvanceRevisionBeyondFloor: true,
            isSamePayload: true,
            elapsedSinceLastSend: 0.5
        ) == false)
    }

    @Test("Same task with a different session id replaces the active session")
    @MainActor
    func conflictingSessionIdReplacesActiveSession() async {
        let service = FocusSessionService.makeForTesting(
            focusGuardService: ReconnectFixFocusGuard(),
            persistenceEnabled: false
        )
        let first = FocusSessionId(bootSessionID: 1, startOperationID: 1)
        let second = FocusSessionId(bootSessionID: 1, startOperationID: 2)

        await service.startSession(
            taskId: "same-task",
            taskTitle: "Same",
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            focusSessionId: first
        )
        await service.startSession(
            taskId: "same-task",
            taskTitle: "Same",
            startTime: Date(timeIntervalSince1970: 1_700_000_120),
            focusSessionId: second
        )

        #expect(service.activeSession?.focusSessionId == second)
        #expect(service.activeSession?.startTime == Date(timeIntervalSince1970: 1_700_000_120))
        #expect(service.todaySessions.contains { $0.focusSessionId == first && $0.endReason == .timeout })
    }

    @Test("Complete uses device elapsed instead of App wall-clock math")
    @MainActor
    func completeUsesAuthoritativeElapsed() async {
        let service = FocusSessionService.makeForTesting(
            focusGuardService: ReconnectFixFocusGuard(),
            persistenceEnabled: false
        )
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        await service.startSession(
            taskId: "elapsed-task",
            taskTitle: "Elapsed",
            startTime: start
        )

        let ended = service.completeTask(
            taskId: "elapsed-task",
            endTime: start.addingTimeInterval(12),
            authoritativeElapsedSeconds: 3_600
        )

        #expect(ended)
        #expect(service.activeSession == nil)
        let settled = service.todaySessions.last { $0.taskId == "elapsed-task" }
        #expect(settled?.calculatedFocusTime == 3_600)
        #expect(settled?.earnedEnergyBottles == 2)
    }

    @Test("Complete and Skip require a matching FocusSessionId when the frame carries one")
    @MainActor
    func completeAndSkipMatchFocusSessionId() async {
        let service = FocusSessionService.makeForTesting(
            focusGuardService: ReconnectFixFocusGuard(),
            persistenceEnabled: false
        )
        let activeId = FocusSessionId(bootSessionID: 7, startOperationID: 3)
        let otherId = FocusSessionId(bootSessionID: 7, startOperationID: 4)
        await service.startSession(
            taskId: "session-task",
            taskTitle: "Session",
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            focusSessionId: activeId
        )

        #expect(service.completeTask(taskId: "session-task", focusSessionId: otherId) == false)
        #expect(service.activeSession?.focusSessionId == activeId)
        #expect(service.skipTask(taskId: "session-task", focusSessionId: otherId) == false)
        #expect(service.activeSession?.focusSessionId == activeId)

        #expect(service.completeTask(taskId: "other-task", focusSessionId: activeId))
        #expect(service.activeSession == nil)
        #expect(service.todaySessions.contains { $0.focusSessionId == activeId && $0.endReason == .completed })
    }

    @Test("Same payload reuses ResolveID; a changed verdict or session gets a new one")
    @MainActor
    func resolveIDFollowsPayloadNotJustSession() async throws {
        let service = FocusSessionService.makeForTesting(
            focusGuardService: ReconnectFixFocusGuard(),
            persistenceEnabled: false
        )
        let samePayload = dummyResolve(resolveID: 11, elapsed: 120)
        let first = service.reuseOrMakeResolveID(
            for: FocusWireFixtures.sessionId,
            proposed: 11,
            matching: samePayload
        )
        let retry = service.reuseOrMakeResolveID(
            for: FocusWireFixtures.sessionId,
            proposed: 99,
            matching: dummyResolve(resolveID: 99, elapsed: 120)
        )
        let changed = service.reuseOrMakeResolveID(
            for: FocusWireFixtures.sessionId,
            proposed: 33,
            matching: dummyResolve(resolveID: 33, elapsed: 180)
        )
        let other = service.reuseOrMakeResolveID(
            for: FocusSessionId(bootSessionID: 2, startOperationID: 9),
            proposed: 7,
            matching: dummyResolve(
                resolveID: 7,
                sessionId: FocusSessionId(bootSessionID: 2, startOperationID: 9)
            )
        )

        #expect(first == 11)
        #expect(retry == 11)
        #expect(changed == 33)
        #expect(other == 7)

        let reconnecting = FocusSessionService.makeForTesting(
            focusGuardService: ReconnectFixFocusGuard(),
            persistenceEnabled: false
        )
        let firstCommand = try await reconnecting.resolveReconnect(
            FocusWireFixtures.focusState(),
            resolveID: 22
        )
        let sameSnapshotRetry = try await reconnecting.resolveReconnect(
            FocusWireFixtures.focusState(),
            resolveID: 33
        )
        let changedSnapshot = try await reconnecting.resolveReconnect(
            FocusWireFixtures.focusState(elapsed: 180),
            resolveID: 44
        )
        #expect(firstCommand.resolveID == 22)
        #expect(sameSnapshotRetry.resolveID == 22)
        #expect(sameSnapshotRetry.matchesPayload(of: firstCommand))
        #expect(changedSnapshot.resolveID == 44)
        #expect(firstCommand.focusRevision == 4)
        #expect(sameSnapshotRetry.focusRevision == 4)
        #expect(changedSnapshot.focusRevision == 5)
        #expect(changedSnapshot.matchesPayload(of: firstCommand) == false)
        #expect(reconnecting.activeSession == nil)
    }

    @Test("A new ResolveID after restart receives a new durable revision")
    @MainActor
    func restartedResolveAttemptDoesNotReuseRevisionWithDifferentBytes() async throws {
        let persistence = VolatileFocusRevisionLedgerPersistence()
        let ledger = FocusRevisionLedger(persistence: persistence)
        let firstService = FocusSessionService.makeForTesting(
            focusGuardService: ReconnectFixFocusGuard(),
            focusRevisionLedger: ledger
        )
        let first = try await firstService.resolveReconnect(
            FocusWireFixtures.focusState(),
            resolveID: 22
        )

        let restartedService = FocusSessionService.makeForTesting(
            focusGuardService: ReconnectFixFocusGuard(),
            focusRevisionLedger: ledger
        )
        let restarted = try await restartedService.resolveReconnect(
            FocusWireFixtures.focusState(),
            resolveID: 33
        )

        #expect(first.resolveID == 22)
        #expect(restarted.resolveID == 33)
        #expect(restarted.focusRevision == first.focusRevision + 1)
    }

    @Test("INVALID_STATE invalidates the frozen attempt even when the semantic verdict is unchanged")
    @MainActor
    func invalidStateForcesNewResolveRevision() async throws {
        let service = FocusSessionService.makeForTesting(
            focusGuardService: ReconnectFixFocusGuard()
        )
        let snapshot = FocusWireFixtures.focusState()
        let first = try await service.resolveReconnect(snapshot, resolveID: 10)

        service.invalidatePendingReconnectAfterInvalidState()
        let second = try await service.resolveReconnect(snapshot, resolveID: 20)

        #expect(first.resolveID == 10)
        #expect(second.resolveID == 20)
        #expect(second.focusRevision == first.focusRevision + 1)
    }

    @Test("FOCUS_STATE identity fields are stamped only after RESULT/COMMITTED")
    @MainActor
    func resolveStampsFirmwareIdentity() async throws {
        let service = FocusSessionService.makeForTesting(
            focusGuardService: ReconnectFixFocusGuard(),
            persistenceEnabled: false
        )
        let snapshot = FocusWireFixtures.focusState(
            startSource: .deviceOffline,
            lastOperationID: 9
        )
        let command = try await service.resolveReconnect(snapshot, resolveID: 1)
        #expect(service.activeSession == nil)

        try await service.commitReconnectAfterResolve(from: snapshot, resolve: command)

        #expect(service.activeSession?.focusSessionId == snapshot.sessionId)
        #expect(service.activeSession?.bootSessionId == snapshot.bootSessionID)
        #expect(service.activeSession?.startSource == .deviceOffline)
        #expect(service.activeSession?.lastOperationId == 9)
        #expect(service.activeSession?.focusRevision == snapshot.focusRevision + 1)
    }

    @Test("Post-gate BLE restore is separate from the durable reconnect commit")
    @MainActor
    func durableCommitDoesNotRequireBLEPostRestore() async throws {
        let service = FocusSessionService.makeForTesting(
            focusGuardService: ReconnectFixFocusGuard(),
            persistenceEnabled: false
        )
        let snapshot = FocusWireFixtures.focusState()
        let command = try await service.resolveReconnect(snapshot, resolveID: 1)
        let freezeLease = service.acquireFocusStatusFreeze()
        defer { service.releaseFocusStatusFreeze(freezeLease) }

        try await service.commitReconnectAfterResolve(from: snapshot, resolve: command)

        #expect(service.activeSession?.focusRevision == command.focusRevision)
        #expect(service.activeSession?.focusSessionId == command.sessionId)
    }

    @Test("Committed reconnect identity is persisted before durable commit returns")
    @MainActor
    func committedReconnectIdentityIsPersisted() async throws {
        let persistence = ReconnectPersistenceRecorder()
        let service = FocusSessionService.makeForTesting(
            focusGuardService: ReconnectFixFocusGuard(),
            interruptionDetector: ReconnectNoopInterruptionDetector(),
            persistenceEnabled: true,
            focusPersistence: persistence
        )
        let snapshot = FocusWireFixtures.focusState()
        let command = try await service.resolveReconnect(snapshot, resolveID: 1)
        let freezeLease = service.acquireFocusStatusFreeze()
        defer { service.releaseFocusStatusFreeze(freezeLease) }

        try await service.commitReconnectAfterResolve(from: snapshot, resolve: command)

        let saved = await persistence.savedActiveSessions()
        #expect(saved.last?.focusRevision == command.focusRevision)
        #expect(saved.last?.focusSessionId == command.sessionId)
        #expect(saved.last?.bootSessionId == snapshot.bootSessionID)
    }

    @Test("Hardware task id remap keeps the v2 session fields")
    @MainActor
    func remappedCompleteKeepsSessionFields() async {
        let task = TaskItem(
            id: "provider-\(String(repeating: "segment-", count: 4))",
            title: "Remapped"
        )
        let focusService = FocusSessionService.makeForTesting(
            focusGuardService: ReconnectFixFocusGuard(),
            persistenceEnabled: false
        )
        await focusService.startSession(
            taskId: task.id,
            taskTitle: task.title,
            startTime: Date(timeIntervalSince1970: TimeInterval(FocusWireFixtures.timestamp)),
            focusSessionId: FocusWireFixtures.sessionId
        )

        let event = EventLog(
            eventType: .completeTask,
            taskId: task.hardwareIdentifier,
            operationID: 8,
            timestamp: Date(timeIntervalSince1970: TimeInterval(FocusWireFixtures.timestamp + 600)),
            hasDeviceTimestamp: true,
            focusSessionId: FocusWireFixtures.sessionId,
            elapsedSeconds: 3_600
        )
        let resolved = BLEEventHandler.resolvingTaskIdentifier(in: event, tasks: [task])

        #expect(resolved.taskId == task.id)
        #expect(resolved.focusSessionId == FocusWireFixtures.sessionId)
        #expect(resolved.elapsedSeconds == 3_600)
    }
}

private actor ReconnectPersistenceRecorder: FocusSessionPersisting {
    private var activeSessions: [FocusSession] = []
    private var sessions: [FocusSession] = []

    func loadSessions() async throws -> [FocusSession]? { sessions }

    func saveSessions(_ sessions: [FocusSession], date: Date) async throws {
        self.sessions = sessions
    }

    func loadActiveSession() async throws -> FocusSession? {
        activeSessions.last
    }

    func saveActiveSession(_ session: FocusSession) async throws {
        activeSessions.append(session)
    }

    func clearActiveSession() async throws {}

    func applyEnergyReward(receiptID: UUID, bottles: Int) async throws -> Int {
        bottles
    }

    func savedActiveSessions() -> [FocusSession] {
        activeSessions
    }
}

@MainActor
private final class ReconnectNoopInterruptionDetector: FocusInterruptionDetecting {
    var detectionState: FocusInterruptionDetectionState = .selectionEmpty
    var onInterruption: ((Date, TimeInterval) -> Void)?

    func startMonitoring() {}
    func stopMonitoring() {}
}

private func dummyResolve(
    resolveID: UInt32,
    sessionId: FocusSessionId = FocusWireFixtures.sessionId,
    elapsed: UInt32 = 120
) -> OfflineFocusResolve {
    OfflineFocusResolve(
        resolveID: resolveID,
        sessionId: sessionId,
        focusState: .active,
        result: .accepted,
        startTimestamp: FocusWireFixtures.timestamp,
        endTimestamp: 0,
        elapsedSeconds: elapsed,
        focusRevision: 4,
        phase: .warmup,
        bottles: 0
    )
}

@MainActor
private final class ReconnectFixFocusGuard: FocusGuardService {
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
