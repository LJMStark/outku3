import Foundation
import Testing
@testable import KiroleFeature

@Suite("Focus reconnect Bugbot fixes")
struct FocusReconnectFixTests {
    @Test("Preview only suppresses a visible start and does not mutate the session")
    @MainActor
    func previewDoesNotAdoptOrEnd() async {
        let service = FocusSessionService.makeForTesting(
            focusGuardService: ReconnectFixFocusGuard(),
            persistenceEnabled: false
        )

        await service.applyReconnectPreview(FocusWireFixtures.focusState())
        #expect(service.activeSession == nil)
        #expect(service.suppressVisibleFocusStart == false)
        #expect(service.todaySessions.isEmpty)

        await service.applyReconnectPreview(
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
    func resolveIDFollowsPayloadNotJustSession() async {
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
        let firstCommand = await reconnecting.resolveReconnect(
            FocusWireFixtures.focusState(),
            resolveID: 22
        )
        let sameSnapshotRetry = await reconnecting.resolveReconnect(
            FocusWireFixtures.focusState(),
            resolveID: 33
        )
        let changedSnapshot = await reconnecting.resolveReconnect(
            FocusWireFixtures.focusState(elapsed: 180),
            resolveID: 44
        )
        #expect(firstCommand.resolveID == 22)
        #expect(sameSnapshotRetry.resolveID == 22)
        #expect(sameSnapshotRetry.matchesPayload(of: firstCommand))
        #expect(changedSnapshot.resolveID == 44)
        #expect(changedSnapshot.matchesPayload(of: firstCommand) == false)
        #expect(reconnecting.activeSession == nil)
    }

    @Test("FOCUS_STATE identity fields are stamped only after RESULT/COMMITTED")
    @MainActor
    func resolveStampsFirmwareIdentity() async {
        let service = FocusSessionService.makeForTesting(
            focusGuardService: ReconnectFixFocusGuard(),
            persistenceEnabled: false
        )
        let snapshot = FocusWireFixtures.focusState(
            startSource: .deviceOffline,
            lastOperationID: 9
        )
        let command = await service.resolveReconnect(snapshot, resolveID: 1)
        #expect(service.activeSession == nil)

        await service.commitPendingReconnect(from: snapshot, resolve: command)

        #expect(service.activeSession?.focusSessionId == snapshot.sessionId)
        #expect(service.activeSession?.bootSessionId == snapshot.bootSessionID)
        #expect(service.activeSession?.startSource == .deviceOffline)
        #expect(service.activeSession?.lastOperationId == 9)
        #expect(service.activeSession?.focusRevision == snapshot.focusRevision &+ 1)
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
