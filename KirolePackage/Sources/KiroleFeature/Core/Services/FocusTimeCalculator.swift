import Foundation

enum FocusTimeCalculator {
    static func countableFocusTime(
        sessionStart: Date,
        sessionEnd: Date,
        screenUnlockEvents: [ScreenUnlockEvent],
        thresholdSeconds: TimeInterval
    ) -> TimeInterval {
        guard !screenUnlockEvents.isEmpty else {
            return sessionEnd.timeIntervalSince(sessionStart)
        }

        let sortedEvents = screenUnlockEvents.sorted { $0.timestamp < $1.timestamp }
        var focusTime: TimeInterval = 0
        var lastEventEnd = sessionStart

        for event in sortedEvents {
            focusTime += countableDuration(from: lastEventEnd, to: event.timestamp, thresholdSeconds: thresholdSeconds)
            lastEventEnd = max(lastEventEnd, interruptionEnd(of: event, windowEnd: sessionEnd))
        }

        return focusTime + countableDuration(from: lastEventEnd, to: sessionEnd, thresholdSeconds: thresholdSeconds)
    }

    private static func countableDuration(
        from start: Date,
        to end: Date,
        thresholdSeconds: TimeInterval
    ) -> TimeInterval {
        let duration = end.timeIntervalSince(start)
        guard duration >= thresholdSeconds else { return 0 }
        return duration
    }

    /// Energy bottles earned, credited **per uninterrupted segment**.
    ///
    /// Each screen-unlock event splits the session; within every segment the bottles are
    /// `floor(segmentMinutes / 30)` and the sub-30-minute remainder is discarded. Crucially the
    /// remainder is NOT carried across an interruption to combine with a later segment — an
    /// interruption resets the in-progress bottle fill to zero (spec: 满30分钟收一瓶；
    /// 打断一次→当前装填进度归零，零头不跨段合并).
    ///
    /// This deliberately differs from `countableFocusTime`, which sums whole surviving segment
    /// durations and is kept intact for focus-time statistics: pooling-then-flooring there would
    /// let two 15-minute remainders straddling an interruption mint a spurious extra bottle.
    static func countableBottles(
        sessionStart: Date,
        sessionEnd: Date,
        screenUnlockEvents: [ScreenUnlockEvent]
    ) -> Int {
        guard !screenUnlockEvents.isEmpty else {
            return bottles(forSeconds: sessionEnd.timeIntervalSince(sessionStart))
        }

        let sortedEvents = screenUnlockEvents.sorted { $0.timestamp < $1.timestamp }
        var total = 0
        var lastEventEnd = sessionStart

        for event in sortedEvents {
            total += bottles(forSeconds: event.timestamp.timeIntervalSince(lastEventEnd))
            lastEventEnd = max(lastEventEnd, interruptionEnd(of: event, windowEnd: sessionEnd))
        }

        return total + bottles(forSeconds: sessionEnd.timeIntervalSince(lastEventEnd))
    }

    private static func bottles(forSeconds seconds: TimeInterval) -> Int {
        guard seconds > 0 else { return 0 }
        return FocusEnergyCalculator.bottlesEarned(minutes: Int(seconds / 60))
    }

    /// End of an interruption, clamped to the focus window `[event.timestamp, windowEnd]`.
    ///
    /// A `nil` duration means the interruption is still open at the window end (the user is still
    /// on their phone — `handleDidBecomeActive` records the unlock with `duration: nil` until a
    /// later `willResignActive` closes it), so it extends to `windowEnd` and no focus is credited
    /// after it. A known duration ends it normally. Clamping keeps overlapping or out-of-window
    /// events from moving the segment boundary backward or past the window end.
    private static func interruptionEnd(of event: ScreenUnlockEvent, windowEnd: Date) -> Date {
        let openDuration = max(0, windowEnd.timeIntervalSince(event.timestamp))
        let end = event.timestamp.addingTimeInterval(event.duration ?? openDuration)
        return min(windowEnd, max(event.timestamp, end))
    }

    /// Start of the current uninterrupted focus segment: the end of the most recent interruption,
    /// or the session start if there has been none. The live on-device fill bar and phase are
    /// measured from here so they reset to zero after each interruption instead of climbing on a
    /// wall-clock count that ignores the user picking up their phone.
    static func currentSegmentStart(
        sessionStart: Date,
        now: Date,
        screenUnlockEvents: [ScreenUnlockEvent]
    ) -> Date {
        let lastInterruptionEnd = screenUnlockEvents
            .filter { $0.timestamp <= now }
            .map { interruptionEnd(of: $0, windowEnd: now) }
            .max()
        return max(sessionStart, lastInterruptionEnd ?? sessionStart)
    }

    /// Seconds from `now` until the next energy bottle completes within the current uninterrupted
    /// segment. Used to wake the live display loop exactly when a bottle is collected, so the
    /// on-device "bottle collected" effect lands on time instead of up to a periodic tick late.
    static func secondsUntilNextBottle(
        segmentStart: Date,
        now: Date,
        blockSeconds: TimeInterval
    ) -> TimeInterval {
        guard blockSeconds > 0 else { return blockSeconds }
        let secondsIntoSegment = max(0, now.timeIntervalSince(segmentStart))
        let remainder = secondsIntoSegment.truncatingRemainder(dividingBy: blockSeconds)
        return blockSeconds - remainder
    }
}
