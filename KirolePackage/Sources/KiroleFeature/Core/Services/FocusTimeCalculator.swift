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
            lastEventEnd = event.timestamp.addingTimeInterval(event.duration ?? 60)
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
}
