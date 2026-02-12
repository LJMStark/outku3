import Foundation

// MARK: - Focus Session

/// 专注会话记录，追踪用户在 E-ink 设备上的任务专注时间
public struct FocusSession: Identifiable, Codable, Sendable {
    public let id: UUID
    public let taskId: String
    public let taskTitle: String
    public let startTime: Date
    public var endTime: Date?
    public var endReason: FocusEndReason?
    public var calculatedFocusTime: TimeInterval?
    public var screenUnlockEvents: [ScreenUnlockEvent]

    public init(
        id: UUID = UUID(),
        taskId: String,
        taskTitle: String,
        startTime: Date = Date(),
        endTime: Date? = nil,
        endReason: FocusEndReason? = nil,
        calculatedFocusTime: TimeInterval? = nil,
        screenUnlockEvents: [ScreenUnlockEvent] = []
    ) {
        self.id = id
        self.taskId = taskId
        self.taskTitle = taskTitle
        self.startTime = startTime
        self.endTime = endTime
        self.endReason = endReason
        self.calculatedFocusTime = calculatedFocusTime
        self.screenUnlockEvents = screenUnlockEvents
    }

    /// 会话总时长（从进入到退出）
    public var totalDuration: TimeInterval? {
        guard let endTime = endTime else { return nil }
        return endTime.timeIntervalSince(startTime)
    }

    /// 是否为活跃会话（尚未结束）
    public var isActive: Bool {
        endTime == nil
    }
}

// MARK: - Focus End Reason

/// 专注会话结束原因
public enum FocusEndReason: String, Codable, Sendable {
    /// 任务完成（短按滚轮）
    case completed = "completed"
    /// 任务跳过（长按滚轮）
    case skipped = "skipped"
    /// 会话超时
    case timeout = "timeout"
    /// 设备断开连接
    case disconnected = "disconnected"
}

// MARK: - Screen Unlock Event

/// 手机屏幕解锁事件
public struct ScreenUnlockEvent: Codable, Sendable {
    public let timestamp: Date
    public let duration: TimeInterval?

    public init(timestamp: Date, duration: TimeInterval? = nil) {
        self.timestamp = timestamp
        self.duration = duration
    }
}

// MARK: - Trend Direction

/// 专注趋势方向
public enum TrendDirection: String, Codable, Sendable {
    case up
    case down
    case stable
}

// MARK: - Attention Summary

/// 注意力镜像摘要，用于 Attention Mirror 反馈
public struct AttentionSummary: Codable, Sendable {
    public let totalFocusMinutes: Int
    public let sessionCount: Int
    public let longestSessionMinutes: Int
    public let interruptionCount: Int
    public let peakHour: Int?
    public let trend: TrendDirection

    public init(
        totalFocusMinutes: Int,
        sessionCount: Int,
        longestSessionMinutes: Int,
        interruptionCount: Int,
        peakHour: Int?,
        trend: TrendDirection
    ) {
        self.totalFocusMinutes = totalFocusMinutes
        self.sessionCount = sessionCount
        self.longestSessionMinutes = longestSessionMinutes
        self.interruptionCount = interruptionCount
        self.peakHour = peakHour
        self.trend = trend
    }
}

// MARK: - Focus Statistics

/// 专注时间统计
public struct FocusStatistics: Codable, Sendable {
    public var todayFocusTime: TimeInterval
    public var todaySessions: Int
    public var averageSessionMinutes: Int
    public var longestSessionMinutes: Int
    public var interruptionCount: Int
    public var peakFocusHour: Int?
    public var focusTrendDirection: TrendDirection

    public init(
        todayFocusTime: TimeInterval = 0,
        todaySessions: Int = 0,
        averageSessionMinutes: Int = 0,
        longestSessionMinutes: Int = 0,
        interruptionCount: Int = 0,
        peakFocusHour: Int? = nil,
        focusTrendDirection: TrendDirection = .stable
    ) {
        self.todayFocusTime = todayFocusTime
        self.todaySessions = todaySessions
        self.averageSessionMinutes = averageSessionMinutes
        self.longestSessionMinutes = longestSessionMinutes
        self.interruptionCount = interruptionCount
        self.peakFocusHour = peakFocusHour
        self.focusTrendDirection = focusTrendDirection
    }
}
