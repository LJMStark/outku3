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

    @Test("The same FocusSessionId reuses ResolveID and a new session gets a fresh one")
    @MainActor
    func resolveIDIsReusedForTheSameSession() async {
        let service = FocusSessionService.makeForTesting(
            focusGuardService: ReconnectFixFocusGuard(),
            persistenceEnabled: false
        )
        let first = service.reuseOrMakeResolveID(
            for: FocusWireFixtures.sessionId,
            proposed: 11
        )
        let retry = service.reuseOrMakeResolveID(
            for: FocusWireFixtures.sessionId,
            proposed: 99
        )
        let other = service.reuseOrMakeResolveID(
            for: FocusSessionId(bootSessionID: 2, startOperationID: 9),
            proposed: 7
        )

        #expect(first == 11)
        #expect(retry == 11)
        #expect(other == 7)

        let reconnecting = FocusSessionService.makeForTesting(
            focusGuardService: ReconnectFixFocusGuard(),
            persistenceEnabled: false
        )
        let firstCommand = await reconnecting.resolveReconnect(
            FocusWireFixtures.focusState(),
            resolveID: 22
        )
        let retriedCommand = await reconnecting.resolveReconnect(
            FocusWireFixtures.focusState(elapsed: 180),
            resolveID: 33
        )
        #expect(firstCommand.resolveID == 22)
        #expect(retriedCommand.resolveID == 22)
    }

    @Test("FOCUS_STATE identity fields are stamped onto the adopted session")
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
        _ = await service.resolveReconnect(snapshot, resolveID: 1)

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
