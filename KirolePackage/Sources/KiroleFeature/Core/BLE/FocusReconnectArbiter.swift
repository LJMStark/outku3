import Foundation

public struct FocusReconnectAppSnapshot: Sendable {
    public let active: FocusSession?
    public let history: [FocusSession]
    public let activeElapsedSeconds: UInt32
    public let activeSegmentSeconds: UInt32
    public let activePhase: FocusPhase
    public let activeBottles: UInt8
    public let currentRevision: UInt32

    public init(
        active: FocusSession?,
        history: [FocusSession] = [],
        activeElapsedSeconds: UInt32 = 0,
        activeSegmentSeconds: UInt32 = 0,
        activePhase: FocusPhase = .idle,
        activeBottles: UInt8 = 0,
        currentRevision: UInt32 = 0
    ) {
        self.active = active
        self.history = history
        self.activeElapsedSeconds = activeElapsedSeconds
        self.activeSegmentSeconds = activeSegmentSeconds
        self.activePhase = activePhase
        self.activeBottles = activeBottles
        self.currentRevision = currentRevision
    }
}

public enum FocusReconnectAction: Sendable, Equatable {
    case none
    case adopt(taskId: String, start: Date, sessionId: FocusSessionId)
    case keepExisting
    case endActive(reason: FocusEndReason, endTime: Date)
    case settleHistorical(
        taskId: String,
        start: Date,
        end: Date,
        reason: FocusEndReason,
        sessionId: FocusSessionId,
        elapsedSeconds: UInt32
    )
    case replaceWithDevice(taskId: String, start: Date, sessionId: FocusSessionId, oldEnd: Date)
}

public struct FocusReconnectDecision: Sendable, Equatable {
    public let command: OfflineFocusResolve
    public let action: FocusReconnectAction
}

public enum FocusReconnectArbiter {
    public static func decide(
        device: OfflineFocusState,
        app: FocusReconnectAppSnapshot,
        resolveID: UInt32,
        now: Date = Date()
    ) -> FocusReconnectDecision {
        let revision = max(app.currentRevision, device.focusRevision) &+ 1
        let matchedActive = matchingSession(device.sessionId, in: app.active.map { [$0] } ?? [])
        let matchedHistory = matchingSession(device.sessionId, in: app.history)

        if device.focusState == .idle && device.sessionId.isIdle {
            return decision(
                resolveID: resolveID,
                sessionId: .idle,
                focusState: .idle,
                result: .accepted,
                start: 0,
                end: 0,
                elapsed: 0,
                revision: revision,
                phase: .idle,
                bottles: 0,
                action: .none
            )
        }

        switch (device.focusState, matchedActive, matchedHistory) {
        case (.active, .some, _):
            if let active = matchedActive, sameSession(active, device: device) {
                noteElapsedAnomaly(device: device, appElapsed: app.activeElapsedSeconds)
                return decision(
                    resolveID: resolveID,
                    sessionId: device.sessionId,
                    focusState: .active,
                    result: .accepted,
                    start: authoritativeStart(device, appStart: active.startTime),
                    end: 0,
                    elapsed: app.activeElapsedSeconds,
                    revision: revision,
                    phase: app.activePhase == .idle ? .warmup : app.activePhase,
                    bottles: app.activeBottles,
                    action: .keepExisting
                )
            }
            let oldEnd = Date(timeIntervalSince1970: TimeInterval(device.startTimestamp))
            return decision(
                resolveID: resolveID,
                sessionId: device.sessionId,
                focusState: .active,
                result: .conflictResolved,
                start: device.startTimestamp,
                end: 0,
                elapsed: device.elapsedSeconds,
                revision: revision,
                phase: phase(fromElapsed: device.elapsedSeconds),
                bottles: displayBottles(device.elapsedSeconds),
                action: .replaceWithDevice(
                    taskId: device.taskId,
                    start: date(device.startTimestamp, fallback: now),
                    sessionId: device.sessionId,
                    oldEnd: oldEnd > Date(timeIntervalSince1970: 0) ? oldEnd : now
                )
            )

        case (.active, nil, .some(let ended)):
            noteElapsedAnomaly(
                device: device,
                appElapsed: UInt32(clamping: Int(ended.calculatedFocusTime ?? 0))
            )
            return decision(
                resolveID: resolveID,
                sessionId: ended.focusSessionId ?? device.sessionId,
                focusState: .idle,
                result: .closed,
                start: unix(ended.startTime),
                end: unix(ended.endTime ?? now),
                elapsed: UInt32(clamping: Int(ended.calculatedFocusTime ?? 0)),
                revision: revision,
                phase: .idle,
                bottles: UInt8(clamping: ended.earnedEnergyBottles),
                action: .none
            )

        case (.active, nil, nil):
            if app.active != nil {
                let oldEnd = Date(timeIntervalSince1970: TimeInterval(device.startTimestamp))
                return decision(
                    resolveID: resolveID,
                    sessionId: device.sessionId,
                    focusState: .active,
                    result: .conflictResolved,
                    start: device.startTimestamp,
                    end: 0,
                    elapsed: device.elapsedSeconds,
                    revision: revision,
                    phase: phase(fromElapsed: device.elapsedSeconds),
                    bottles: displayBottles(device.elapsedSeconds),
                    action: .replaceWithDevice(
                        taskId: device.taskId,
                        start: date(device.startTimestamp, fallback: now),
                        sessionId: device.sessionId,
                        oldEnd: oldEnd > Date(timeIntervalSince1970: 0) ? oldEnd : now
                    )
                )
            }
            return decision(
                resolveID: resolveID,
                sessionId: device.sessionId,
                focusState: .active,
                result: .accepted,
                start: authoritativeStart(device, appStart: nil),
                end: 0,
                elapsed: device.elapsedSeconds,
                revision: revision,
                phase: phase(fromElapsed: device.elapsedSeconds),
                bottles: displayBottles(device.elapsedSeconds),
                action: .adopt(
                    taskId: device.taskId,
                    start: date(authoritativeStart(device, appStart: nil), fallback: now),
                    sessionId: device.sessionId
                )
            )

        case (.endedPending, .some, _):
            noteElapsedAnomaly(device: device, appElapsed: app.activeElapsedSeconds)
            let reason = device.endReason.focusEndReason ?? .completed
            return decision(
                resolveID: resolveID,
                sessionId: device.sessionId,
                focusState: .idle,
                result: .closed,
                start: authoritativeStart(device, appStart: matchedActive?.startTime),
                end: device.endTimestamp,
                elapsed: device.elapsedSeconds,
                revision: revision,
                phase: .idle,
                bottles: displayBottles(device.elapsedSeconds),
                action: .endActive(
                    reason: reason,
                    endTime: date(device.endTimestamp, fallback: now)
                )
            )

        case (.endedPending, nil, .some):
            let ended = matchedHistory
            return decision(
                resolveID: resolveID,
                sessionId: device.sessionId,
                focusState: .idle,
                result: .closed,
                start: unix(ended?.startTime ?? date(device.startTimestamp, fallback: now)),
                end: earlierEnd(ended?.endTime, device.endTimestamp, now: now),
                elapsed: device.elapsedSeconds,
                revision: revision,
                phase: .idle,
                bottles: displayBottles(device.elapsedSeconds),
                action: .none
            )

        case (.endedPending, nil, nil):
            let reason = device.endReason.focusEndReason ?? .completed
            return decision(
                resolveID: resolveID,
                sessionId: device.sessionId,
                focusState: .idle,
                result: .closed,
                start: device.startTimestamp,
                end: device.endTimestamp,
                elapsed: device.elapsedSeconds,
                revision: revision,
                phase: .idle,
                bottles: displayBottles(device.elapsedSeconds),
                action: .settleHistorical(
                    taskId: device.taskId,
                    start: date(device.startTimestamp, fallback: now),
                    end: date(device.endTimestamp, fallback: now),
                    reason: reason,
                    sessionId: device.sessionId,
                    elapsedSeconds: device.elapsedSeconds
                )
            )

        default:
            return decision(
                resolveID: resolveID,
                sessionId: device.sessionId,
                focusState: .idle,
                result: .rejected,
                start: device.startTimestamp,
                end: device.endTimestamp,
                elapsed: device.elapsedSeconds,
                revision: revision,
                phase: .idle,
                bottles: 0,
                action: .none
            )
        }
    }

    public static let elapsedAnomalyThresholdSeconds: UInt32 = 120

    public static func isElapsedAnomaly(device elapsed: UInt32, app: UInt32) -> Bool {
        let delta = elapsed > app ? elapsed - app : app - elapsed
        return delta > elapsedAnomalyThresholdSeconds
    }

    public static func displayBottles(_ elapsedSeconds: UInt32) -> UInt8 {
        UInt8(clamping: min(5, Int(elapsedSeconds / 1_800)))
    }

    public static func phase(fromElapsed seconds: UInt32) -> FocusPhase {
        let phase = FocusPhase.fromSegmentSeconds(seconds)
        return phase == .idle && seconds > 0 ? .warmup : phase
    }

    private static func decision(
        resolveID: UInt32,
        sessionId: FocusSessionId,
        focusState: FocusWireState,
        result: FocusResolveResult,
        start: UInt32,
        end: UInt32,
        elapsed: UInt32,
        revision: UInt32,
        phase: FocusPhase,
        bottles: UInt8,
        action: FocusReconnectAction
    ) -> FocusReconnectDecision {
        FocusReconnectDecision(
            command: OfflineFocusResolve(
                resolveID: resolveID,
                sessionId: sessionId,
                focusState: focusState,
                result: result,
                startTimestamp: start,
                endTimestamp: end,
                elapsedSeconds: elapsed,
                focusRevision: revision,
                phase: phase,
                bottles: bottles
            ),
            action: action
        )
    }

    private static func matchingSession(
        _ sessionId: FocusSessionId,
        in sessions: [FocusSession]
    ) -> FocusSession? {
        guard !sessionId.isIdle else { return nil }
        return sessions.first(where: { $0.focusSessionId == sessionId })
    }

    private static func sameSession(_ session: FocusSession, device: OfflineFocusState) -> Bool {
        guard let id = session.focusSessionId, !id.isIdle else { return false }
        return id == device.sessionId
    }

    private static func authoritativeStart(
        _ device: OfflineFocusState,
        appStart: Date?
    ) -> UInt32 {
        switch device.startSource {
        case .appEstablished:
            if let appStart { return unix(appStart) }
            return device.startTimestamp
        case .deviceOffline:
            return device.startTimestamp
        }
    }

    private static func noteElapsedAnomaly(device: OfflineFocusState, appElapsed: UInt32) {
        guard !device.sessionId.isIdle,
              isElapsedAnomaly(device: device.elapsedSeconds, app: appElapsed) else {
            return
        }
        ErrorReporter.log(
            .sync(
                component: "FocusReconnect",
                underlying: "elapsed delta \(device.elapsedSeconds) vs \(appElapsed) exceeds 120s; keeping session \(device.sessionId.bootSessionID)/\(device.sessionId.startOperationID)"
            ),
            context: "FocusReconnectArbiter.decide"
        )
    }

    private static func unix(_ date: Date) -> UInt32 {
        UInt32(clamping: Int(date.timeIntervalSince1970))
    }

    private static func date(_ timestamp: UInt32, fallback: Date) -> Date {
        timestamp == 0 ? fallback : Date(timeIntervalSince1970: TimeInterval(timestamp))
    }

    private static func earlierEnd(_ appEnd: Date?, _ deviceEnd: UInt32, now: Date) -> UInt32 {
        let device = deviceEnd == 0 ? unix(now) : deviceEnd
        guard let appEnd else { return device }
        return min(unix(appEnd), device)
    }
}
