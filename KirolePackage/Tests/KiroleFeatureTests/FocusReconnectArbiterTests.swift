import Foundation
import Testing
@testable import KiroleFeature

@Suite("Focus reconnect conflict rules")
struct FocusReconnectArbiterTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_600)

    @Test("Offline new enter while App is idle adopts the device session")
    func adoptDeviceOfflineStart() {
        let device = FocusWireFixtures.focusState(elapsed: 90)
        let decision = FocusReconnectArbiter.decide(
            device: device,
            app: FocusReconnectAppSnapshot(active: nil),
            resolveID: 9,
            now: now
        )
        #expect(decision.command.result == .accepted)
        #expect(decision.command.focusState == .active)
        #expect(decision.command.startTimestamp == device.startTimestamp)
        #expect(decision.command.endTimestamp == 0)
        #expect(decision.command.elapsedSeconds == 90)
        #expect(decision.action == .adopt(
            taskId: device.taskId,
            start: Date(timeIntervalSince1970: TimeInterval(device.startTimestamp)),
            sessionId: device.sessionId
        ))
    }

    @Test("Offline start-then-end while App is idle settles once without opening a session")
    func settleEndedPendingHistorically() {
        let device = FocusWireFixtures.focusState(
            focusState: .endedPending,
            end: 1_700_000_400,
            elapsed: 400,
            endReason: .complete
        )
        let decision = FocusReconnectArbiter.decide(
            device: device,
            app: FocusReconnectAppSnapshot(active: nil),
            resolveID: 9,
            now: now
        )
        #expect(decision.command.result == .closed)
        #expect(decision.command.focusState == .idle)
        guard case .settleHistorical(_, _, _, let reason, _, let elapsed) = decision.action else {
            Issue.record("Expected historical settlement")
            return
        }
        #expect(reason == .completed)
        #expect(elapsed == 400)
    }

    @Test("Same session still active on both sides keeps the App start time")
    func keepAppEstablishedSession() {
        let start = Date(timeIntervalSince1970: 1_699_999_000)
        let active = FocusSession(
            taskId: FocusWireFixtures.taskID,
            taskTitle: "Plan",
            startTime: start,
            focusSessionId: FocusWireFixtures.sessionId,
            focusRevision: 2
        )
        let device = FocusWireFixtures.focusState(
            startSource: .appEstablished,
            start: 1_700_000_000,
            elapsed: 200
        )
        let decision = FocusReconnectArbiter.decide(
            device: device,
            app: FocusReconnectAppSnapshot(
                active: active,
                activeElapsedSeconds: 1600,
                activeSegmentSeconds: 400,
                activePhase: .deep,
                activeBottles: 2,
                currentRevision: 2
            ),
            resolveID: 9,
            now: now
        )
        #expect(decision.command.result == .accepted)
        #expect(decision.command.startTimestamp == UInt32(start.timeIntervalSince1970))
        #expect(decision.command.elapsedSeconds == 1600)
        #expect(decision.action == .keepExisting)
    }

    @Test("Device already ended while App is still active ends the App session")
    func deviceEndWinsOverActiveApp() {
        let active = FocusSession(
            taskId: FocusWireFixtures.taskID,
            taskTitle: "Plan",
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            focusSessionId: FocusWireFixtures.sessionId
        )
        let device = FocusWireFixtures.focusState(
            focusState: .endedPending,
            end: 1_700_000_300,
            elapsed: 300,
            endReason: .skip
        )
        let decision = FocusReconnectArbiter.decide(
            device: device,
            app: FocusReconnectAppSnapshot(active: active),
            resolveID: 9,
            now: now
        )
        #expect(decision.command.result == .closed)
        #expect(decision.action == .endActive(
            reason: .skipped,
            endTime: Date(timeIntervalSince1970: 1_700_000_300)
        ))
    }

    @Test("App already ended the same session while the device is still active closes the device")
    func appEndWinsOverActiveDevice() {
        var ended = FocusSession(
            taskId: FocusWireFixtures.taskID,
            taskTitle: "Plan",
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            focusSessionId: FocusWireFixtures.sessionId
        )
        ended.endTime = Date(timeIntervalSince1970: 1_700_000_180)
        ended.endReason = .manual
        ended.calculatedFocusTime = 180
        ended.earnedEnergyBottles = 0
        let device = FocusWireFixtures.focusState(elapsed: 240)
        let decision = FocusReconnectArbiter.decide(
            device: device,
            app: FocusReconnectAppSnapshot(active: nil, history: [ended]),
            resolveID: 9,
            now: now
        )
        #expect(decision.command.result == .closed)
        #expect(decision.command.focusState == .idle)
        #expect(decision.action == .none)
    }

    @Test("Two different active sessions keep the device start and close the old App session")
    func differentActiveSessionsConflict() {
        let old = FocusSession(
            taskId: "old-task",
            taskTitle: "Old",
            startTime: Date(timeIntervalSince1970: 1_699_000_000),
            focusSessionId: FocusSessionId(bootSessionID: 1, startOperationID: 1)
        )
        let device = FocusWireFixtures.focusState()
        let decision = FocusReconnectArbiter.decide(
            device: device,
            app: FocusReconnectAppSnapshot(active: old),
            resolveID: 9,
            now: now
        )
        #expect(decision.command.result == .conflictResolved)
        guard case .replaceWithDevice(let taskId, _, let sessionId, _) = decision.action else {
            Issue.record("Expected replaceWithDevice")
            return
        }
        #expect(taskId == device.taskId)
        #expect(sessionId == device.sessionId)
    }

    @Test("Bottles come from authoritative elapsed and never add both sides")
    func bottlesFromElapsedOnly() {
        #expect(FocusReconnectArbiter.displayBottles(1_799) == 0)
        #expect(FocusReconnectArbiter.displayBottles(1_800) == 1)
        #expect(FocusReconnectArbiter.displayBottles(9_000) == 5)
        #expect(FocusReconnectArbiter.displayBottles(20_000) == 5)
    }

    @Test("Same task without a FocusSessionId is not treated as the same session")
    func taskIdDoesNotMatchSessions() {
        let active = FocusSession(
            taskId: FocusWireFixtures.taskID,
            taskTitle: "Plan",
            startTime: Date(timeIntervalSince1970: 1_699_999_000)
        )
        let device = FocusWireFixtures.focusState()
        let decision = FocusReconnectArbiter.decide(
            device: device,
            app: FocusReconnectAppSnapshot(active: active),
            resolveID: 9,
            now: now
        )
        #expect(decision.command.result == .conflictResolved)
        guard case .replaceWithDevice = decision.action else {
            Issue.record("Expected replaceWithDevice when FocusSessionId is missing")
            return
        }
    }

    @Test("deviceOffline start source keeps the device start on a matching session")
    func deviceOfflineStartUsesDeviceTime() {
        let start = Date(timeIntervalSince1970: 1_699_999_000)
        let active = FocusSession(
            taskId: FocusWireFixtures.taskID,
            taskTitle: "Plan",
            startTime: start,
            focusSessionId: FocusWireFixtures.sessionId
        )
        let device = FocusWireFixtures.focusState(
            startSource: .deviceOffline,
            start: 1_700_000_000,
            elapsed: 200
        )
        let decision = FocusReconnectArbiter.decide(
            device: device,
            app: FocusReconnectAppSnapshot(
                active: active,
                activeElapsedSeconds: 180,
                currentRevision: 2
            ),
            resolveID: 9,
            now: now
        )
        #expect(decision.command.result == .accepted)
        #expect(decision.command.startTimestamp == 1_700_000_000)
        #expect(decision.action == .keepExisting)
    }

    @Test("Elapsed delta above 120s is anomalous and does not create a session")
    func elapsedAnomalyDoesNotCreateSession() {
        #expect(!FocusReconnectArbiter.isElapsedAnomaly(device: 100, app: 200))
        #expect(!FocusReconnectArbiter.isElapsedAnomaly(device: 200, app: 80))
        #expect(FocusReconnectArbiter.isElapsedAnomaly(device: 400, app: 200))
        #expect(FocusReconnectArbiter.isElapsedAnomaly(device: 10, app: 200))

        let active = FocusSession(
            taskId: FocusWireFixtures.taskID,
            taskTitle: "Plan",
            startTime: Date(timeIntervalSince1970: 1_699_999_000),
            focusSessionId: FocusWireFixtures.sessionId
        )
        let device = FocusWireFixtures.focusState(
            startSource: .appEstablished,
            elapsed: 2_000
        )
        let decision = FocusReconnectArbiter.decide(
            device: device,
            app: FocusReconnectAppSnapshot(
                active: active,
                activeElapsedSeconds: 1_600,
                currentRevision: 2
            ),
            resolveID: 9,
            now: now
        )
        #expect(decision.action == .keepExisting)
        #expect(decision.command.focusState == .active)
    }
}
