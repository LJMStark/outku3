import Foundation

/// 专注页、硬件状态和结束结算共用的单次进度计算结果。
public struct FocusProgressSnapshot: Sendable, Equatable {
    public let elapsedSeconds: TimeInterval
    public let segmentSeconds: TimeInterval
    public let elapsedMinutes: Int
    public let segmentMinutes: Int
    public let phase: FocusPhase
    public let earnedEnergyBottles: Int
    public let countableFocusTime: TimeInterval

    static let idle = FocusProgressSnapshot(
        elapsedSeconds: 0,
        segmentSeconds: 0,
        elapsedMinutes: 0,
        segmentMinutes: 0,
        phase: .idle,
        earnedEnergyBottles: 0,
        countableFocusTime: 0
    )
}
