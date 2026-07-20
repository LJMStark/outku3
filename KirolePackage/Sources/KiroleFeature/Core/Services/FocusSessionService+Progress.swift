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
        // 活跃会话恒不报 idle：会话第 0 分钟与打断后段清零的那一分钟都属 warmup（客户
        // 三阶段 0-5 分钟从 0 起算；协议侧 Phase 0=idle 是"无会话"，固件以 Phase≠0 判
        // 会话活跃——§8.7 问题 5）。真 idle 只走顶部的 `guard let session` 分支。
        let rawPhase = FocusPhase.from(elapsedMinutes: segmentMinutes)

        return FocusProgressSnapshot(
            elapsedSeconds: elapsedSeconds,
            segmentSeconds: segmentSeconds,
            elapsedMinutes: elapsedMinutes,
            segmentMinutes: segmentMinutes,
            phase: rawPhase == .idle ? .warmup : rawPhase,
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
