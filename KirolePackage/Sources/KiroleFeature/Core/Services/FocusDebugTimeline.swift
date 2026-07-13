import Foundation

/// 当前专注会话的内存时间轴。只把真实时间映射为调试用虚拟时间，不修改会话的真实时间戳。
struct FocusDebugTimeline: Sendable {
    private struct Checkpoint: Sendable {
        let realDate: Date
        let virtualElapsed: TimeInterval
        let rate: Double
    }

    let sessionStart: Date
    private var checkpoints: [Checkpoint]
    private var latestAdvanceRealDate: Date?

    init(sessionStart: Date) {
        self.sessionStart = sessionStart
        checkpoints = [Checkpoint(realDate: sessionStart, virtualElapsed: 0, rate: 1)]
        latestAdvanceRealDate = nil
    }

    var rate: Double {
        checkpoints.last?.rate ?? 1
    }

    mutating func setRate(_ newRate: Double, at realDate: Date) {
        guard newRate > 0, newRate != rate else { return }
        let checkpointDate = max(realDate, sessionStart)
        let elapsed = virtualElapsed(at: checkpointDate)
        checkpoints.append(
            Checkpoint(realDate: checkpointDate, virtualElapsed: elapsed, rate: newRate)
        )
    }

    mutating func advance(by seconds: TimeInterval, at realDate: Date) {
        guard seconds > 0 else { return }
        let checkpointDate = max(realDate, sessionStart)
        let elapsed = virtualElapsed(at: checkpointDate) + seconds
        checkpoints.append(
            Checkpoint(realDate: checkpointDate, virtualElapsed: elapsed, rate: rate)
        )
        latestAdvanceRealDate = max(latestAdvanceRealDate ?? checkpointDate, checkpointDate)
    }

    /// 固件事件时间戳只有整秒。若同一秒内先手动快进、再收到被截断到整秒的结束时间，
    /// 结算计算至少推进到快进检查点，避免界面已显示的虚拟进度在结算时消失。
    func settlementEvaluationDate(for reportedEnd: Date) -> Date {
        max(reportedEnd, latestAdvanceRealDate ?? reportedEnd)
    }

    func virtualElapsed(at realDate: Date) -> TimeInterval {
        guard realDate > sessionStart else {
            return checkpoint(atOrBefore: realDate)?.virtualElapsed ?? 0
        }
        guard let checkpoint = checkpoint(atOrBefore: realDate) else { return 0 }
        let realElapsed = max(0, realDate.timeIntervalSince(checkpoint.realDate))
        return max(0, checkpoint.virtualElapsed + realElapsed * checkpoint.rate)
    }

    func virtualDate(for realDate: Date) -> Date {
        sessionStart.addingTimeInterval(virtualElapsed(at: realDate))
    }

    func virtualized(_ event: ScreenUnlockEvent) -> ScreenUnlockEvent {
        let timestamp = virtualDate(for: event.timestamp)
        let duration = event.duration.map { realDuration in
            let realEnd = event.timestamp.addingTimeInterval(max(0, realDuration))
            return max(0, virtualDate(for: realEnd).timeIntervalSince(timestamp))
        }
        return ScreenUnlockEvent(timestamp: timestamp, duration: duration)
    }

    private func checkpoint(atOrBefore realDate: Date) -> Checkpoint? {
        checkpoints.last { $0.realDate <= realDate }
    }
}
