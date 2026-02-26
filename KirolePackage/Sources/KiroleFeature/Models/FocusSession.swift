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
    public var mode: FocusEnforcementMode
    public var protectionState: FocusProtectionState
    public var interruptionSource: FocusInterruptionSource?

    public init(
        id: UUID = UUID(),
        taskId: String,
        taskTitle: String,
        startTime: Date = Date(),
        endTime: Date? = nil,
        endReason: FocusEndReason? = nil,
        calculatedFocusTime: TimeInterval? = nil,
        screenUnlockEvents: [ScreenUnlockEvent] = [],
        mode: FocusEnforcementMode = .standard,
        protectionState: FocusProtectionState = .unprotected,
        interruptionSource: FocusInterruptionSource? = nil
    ) {
        self.id = id
        self.taskId = taskId
        self.taskTitle = taskTitle
        self.startTime = startTime
        self.endTime = endTime
        self.endReason = endReason
        self.calculatedFocusTime = calculatedFocusTime
        self.screenUnlockEvents = screenUnlockEvents
        self.mode = mode
        self.protectionState = protectionState
        self.interruptionSource = interruptionSource
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case taskId
        case taskTitle
        case startTime
        case endTime
        case endReason
        case calculatedFocusTime
        case screenUnlockEvents
        case mode
        case protectionState
        case interruptionSource
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        taskId = try container.decode(String.self, forKey: .taskId)
        taskTitle = try container.decode(String.self, forKey: .taskTitle)
        startTime = try container.decode(Date.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(Date.self, forKey: .endTime)
        endReason = try container.decodeIfPresent(FocusEndReason.self, forKey: .endReason)
        calculatedFocusTime = try container.decodeIfPresent(TimeInterval.self, forKey: .calculatedFocusTime)
        screenUnlockEvents = try container.decodeIfPresent([ScreenUnlockEvent].self, forKey: .screenUnlockEvents) ?? []
        mode = try container.decodeIfPresent(FocusEnforcementMode.self, forKey: .mode) ?? .standard
        protectionState = try container.decodeIfPresent(FocusProtectionState.self, forKey: .protectionState) ?? .unprotected
        interruptionSource = try container.decodeIfPresent(FocusInterruptionSource.self, forKey: .interruptionSource)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(taskId, forKey: .taskId)
        try container.encode(taskTitle, forKey: .taskTitle)
        try container.encode(startTime, forKey: .startTime)
        try container.encodeIfPresent(endTime, forKey: .endTime)
        try container.encodeIfPresent(endReason, forKey: .endReason)
        try container.encodeIfPresent(calculatedFocusTime, forKey: .calculatedFocusTime)
        try container.encode(screenUnlockEvents, forKey: .screenUnlockEvents)
        try container.encode(mode, forKey: .mode)
        try container.encode(protectionState, forKey: .protectionState)
        try container.encodeIfPresent(interruptionSource, forKey: .interruptionSource)
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

// MARK: - Focus Enforcement Mode

/// 专注执行模式：标准统计模式 vs 深度保护模式
public enum FocusEnforcementMode: String, Codable, Sendable, CaseIterable {
    case standard
    case deepFocus

    public var displayName: String {
        switch self {
        case .standard:
            return "Standard"
        case .deepFocus:
            return "Deep Focus"
        }
    }
}

// MARK: - Focus Protection State

/// 本次会话是否受到系统级保护
public enum FocusProtectionState: String, Codable, Sendable {
    case unprotected
    case protected
    case fallback
}

// MARK: - Focus Interruption Source

/// 专注保护中断/降级来源
public enum FocusInterruptionSource: String, Codable, Sendable {
    case permissionDenied
    case authorizationRevoked
    case selectionMissing
    case shieldApplyFailed
    case featureDisabled
    case capabilityUnavailable
    case recoveredOnLaunch
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
    /// 会话被系统中断
    case interrupted = "interrupted"
    /// 会话因权限问题被终止
    case permissionDenied = "permission_denied"
    /// 应用重启后恢复并终止旧会话
    case recoveredOnLaunch = "recovered_on_launch"
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
    public var protectedSessionCount: Int
    public var averageSessionMinutes: Int
    public var longestSessionMinutes: Int
    public var interruptionCount: Int
    public var peakFocusHour: Int?
    public var focusTrendDirection: TrendDirection

    public init(
        todayFocusTime: TimeInterval = 0,
        todaySessions: Int = 0,
        protectedSessionCount: Int = 0,
        averageSessionMinutes: Int = 0,
        longestSessionMinutes: Int = 0,
        interruptionCount: Int = 0,
        peakFocusHour: Int? = nil,
        focusTrendDirection: TrendDirection = .stable
    ) {
        self.todayFocusTime = todayFocusTime
        self.todaySessions = todaySessions
        self.protectedSessionCount = protectedSessionCount
        self.averageSessionMinutes = averageSessionMinutes
        self.longestSessionMinutes = longestSessionMinutes
        self.interruptionCount = interruptionCount
        self.peakFocusHour = peakFocusHour
        self.focusTrendDirection = focusTrendDirection
    }
}
