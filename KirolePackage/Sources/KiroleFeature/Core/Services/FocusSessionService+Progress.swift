import Foundation

extension FocusSessionService {
    /// 当前会话在指定真实时刻的统一进度。
    public func progressSnapshot(now: Date = Date()) -> FocusProgressSnapshot {
        progressSnapshot(for: activeSession, now: now)
    }

    func progressSnapshot(
        for session: FocusSession?,
        now: Date = Date(),
        screenUnlockEvents overrideInterruptions: [ScreenUnlockEvent]? = nil
    ) -> FocusProgressSnapshot {
        guard let session else { return .idle }
        let realEnd = max(now, session.startTime)
        let realInterruptions: [ScreenUnlockEvent]
        if let overrideInterruptions {
            realInterruptions = overrideInterruptions
        } else if activeSession?.id == session.id {
            realInterruptions = currentUnlockEvents(until: realEnd)
        } else {
            realInterruptions = session.screenUnlockEvents.filter {
                $0.timestamp >= session.startTime && $0.timestamp <= realEnd
            }
        }

        let timeline = activeSession?.id == session.id ? debugTimeline : nil
        let calculationEnd = timeline?.virtualDate(for: realEnd) ?? realEnd
        let calculationInterruptions = timeline.map { timeline in
            realInterruptions.map(timeline.virtualized)
        } ?? realInterruptions
        let segmentStart = FocusTimeCalculator.currentSegmentStart(
            sessionStart: session.startTime,
            now: calculationEnd,
            screenUnlockEvents: calculationInterruptions
        )
        let elapsedSeconds = max(0, calculationEnd.timeIntervalSince(session.startTime))
        let segmentSeconds = max(0, calculationEnd.timeIntervalSince(segmentStart))
        let elapsedMinutes = Int(elapsedSeconds / 60)
        let segmentMinutes = Int(segmentSeconds / 60)

        return FocusProgressSnapshot(
            elapsedSeconds: elapsedSeconds,
            segmentSeconds: segmentSeconds,
            elapsedMinutes: elapsedMinutes,
            segmentMinutes: segmentMinutes,
            phase: FocusPhase.from(elapsedMinutes: segmentMinutes),
            earnedEnergyBottles: FocusTimeCalculator.countableBottles(
                sessionStart: session.startTime,
                sessionEnd: calculationEnd,
                screenUnlockEvents: calculationInterruptions
            ),
            countableFocusTime: calculateFocusTime(
                sessionStart: session.startTime,
                sessionEnd: calculationEnd,
                screenUnlockEvents: calculationInterruptions
            )
        )
    }
}
