import Foundation

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Focus Session Service

/// 专注会话服务，管理任务专注时间追踪
@Observable
@MainActor
public final class FocusSessionService: @unchecked Sendable {
    public static let shared = FocusSessionService()

    // MARK: - State

    /// 当前活跃的专注会话
    public private(set) var activeSession: FocusSession?

    /// 今日所有专注会话
    public private(set) var todaySessions: [FocusSession] = []

    /// 专注统计数据
    public private(set) var statistics: FocusStatistics = FocusStatistics()

    // MARK: - Private Properties

    private let localStorage = LocalStorage.shared
    private var screenActivityTracker: ScreenActivityTracker?

    // MARK: - Constants

    private enum Constants {
        /// 专注时间阈值：30分钟未点亮手机才算专注
        static let focusThresholdMinutes: Int = 30
        static let focusThresholdSeconds: TimeInterval = TimeInterval(focusThresholdMinutes * 60)
    }

    // MARK: - Initialization

    private init() {
        Task { @MainActor in
            await loadTodaySessions()
            setupScreenTracking()
        }
    }

    private func setupScreenTracking() {
        screenActivityTracker = ScreenActivityTracker()
        screenActivityTracker?.startTracking()
    }

    // MARK: - Session Management

    /// 开始新的专注会话（当收到 EnterTaskIn 事件时调用）
    public func startSession(taskId: String, taskTitle: String) {
        // 如果有活跃会话，先结束它
        if activeSession != nil {
            endSession(reason: .timeout)
        }

        let session = FocusSession(
            taskId: taskId,
            taskTitle: taskTitle,
            startTime: Date()
        )

        activeSession = session
        screenActivityTracker?.markSessionStart()
    }

    /// 结束当前专注会话（当收到 CompleteTask 或 SkipTask 事件时调用）
    public func endSession(reason: FocusEndReason) {
        guard var session = activeSession else { return }

        let endTime = Date()
        session.endTime = endTime
        session.endReason = reason

        // 获取会话期间的屏幕解锁事件
        let unlockEvents = screenActivityTracker?.getUnlockEventsDuring(
            start: session.startTime,
            end: endTime
        ) ?? []
        session.screenUnlockEvents = unlockEvents

        // 计算专注时间
        session.calculatedFocusTime = calculateFocusTime(
            sessionStart: session.startTime,
            sessionEnd: endTime,
            screenUnlockEvents: unlockEvents
        )

        // 保存会话
        todaySessions.append(session)
        activeSession = nil

        // 更新统计
        updateStatistics()

        // 持久化
        Task {
            await saveSessions()
        }
    }

    /// 完成任务（短按滚轮）
    public func completeTask(taskId: String) {
        guard let session = activeSession, session.taskId == taskId else { return }
        endSession(reason: .completed)
    }

    /// 跳过任务（长按滚轮）
    public func skipTask(taskId: String) {
        guard let session = activeSession, session.taskId == taskId else { return }
        endSession(reason: .skipped)
    }

    /// 设备断开连接时结束会话
    public func handleDeviceDisconnected() {
        if activeSession != nil {
            endSession(reason: .disconnected)
        }
    }

    // MARK: - Statistics

    private func updateStatistics() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let todayCompletedSessions = todaySessions.filter { session in
            guard let endTime = session.endTime else { return false }
            return calendar.isDate(endTime, inSameDayAs: today)
        }

        let focusTimes = todayCompletedSessions.compactMap { $0.calculatedFocusTime }
        let todayFocusTime = focusTimes.reduce(0, +)

        let averageMinutes: Int = focusTimes.isEmpty ? 0 : Int(focusTimes.reduce(0, +) / Double(focusTimes.count) / 60)
        let longestMinutes: Int = Int((focusTimes.max() ?? 0) / 60)
        let interruptions = todayCompletedSessions.reduce(0) { $0 + $1.screenUnlockEvents.count }
        let peakHour = computePeakFocusHour(sessions: todayCompletedSessions, calendar: calendar)

        statistics = FocusStatistics(
            todayFocusTime: todayFocusTime,
            todaySessions: todayCompletedSessions.count,
            averageSessionMinutes: averageMinutes,
            longestSessionMinutes: longestMinutes,
            interruptionCount: interruptions,
            peakFocusHour: peakHour,
            focusTrendDirection: .stable
        )

        // Compute trend asynchronously and update
        Task {
            let trend = await computeTrendDirection()
            statistics = FocusStatistics(
                todayFocusTime: statistics.todayFocusTime,
                todaySessions: statistics.todaySessions,
                averageSessionMinutes: statistics.averageSessionMinutes,
                longestSessionMinutes: statistics.longestSessionMinutes,
                interruptionCount: statistics.interruptionCount,
                peakFocusHour: statistics.peakFocusHour,
                focusTrendDirection: trend
            )
        }
    }

    private func computePeakFocusHour(sessions: [FocusSession], calendar: Calendar) -> Int? {
        guard !sessions.isEmpty else { return nil }

        var hourBuckets: [Int: TimeInterval] = [:]
        for session in sessions {
            guard let focusTime = session.calculatedFocusTime, focusTime > 0 else { continue }
            let hour = calendar.component(.hour, from: session.startTime)
            hourBuckets[hour, default: 0] += focusTime
        }

        return hourBuckets.max(by: { $0.value < $1.value })?.key
    }

    private func computeTrendDirection() async -> TrendDirection {
        let calendar = Calendar.current
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date())) else {
            return .stable
        }

        do {
            let yesterdaySessions = try await localStorage.loadFocusSessionsForDate(yesterday) ?? []
            let yesterdayFocusTime = yesterdaySessions.compactMap { $0.calculatedFocusTime }.reduce(0, +)

            guard yesterdayFocusTime > 0 else {
                return statistics.todayFocusTime > 0 ? .up : .stable
            }

            let ratio = statistics.todayFocusTime / yesterdayFocusTime
            if ratio > 1.1 { return .up }
            if ratio < 0.9 { return .down }
            return .stable
        } catch {
            return .stable
        }
    }

    // MARK: - Attention Summary

    /// 生成注意力镜像摘要
    public func generateAttentionSummary() -> AttentionSummary {
        AttentionSummary(
            totalFocusMinutes: Int(statistics.todayFocusTime / 60),
            sessionCount: statistics.todaySessions,
            longestSessionMinutes: statistics.longestSessionMinutes,
            interruptionCount: statistics.interruptionCount,
            peakHour: statistics.peakFocusHour,
            trend: statistics.focusTrendDirection
        )
    }

    // MARK: - Persistence

    private func loadTodaySessions() async {
        do {
            if let sessions = try await localStorage.loadFocusSessions() {
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: Date())
                todaySessions = sessions.filter { session in
                    calendar.isDate(session.startTime, inSameDayAs: today)
                }
                updateStatistics()
            }
        } catch {
            // 静默处理加载失败
        }
    }

    private func saveSessions() async {
        try? await localStorage.saveFocusSessions(todaySessions)
        try? await localStorage.saveFocusSessionsForDate(todaySessions, date: Date())
    }

    // MARK: - Focus Time Calculation

    /// 计算专注时间：只有超过阈值的无屏幕活动时段才计入
    private func calculateFocusTime(
        sessionStart: Date,
        sessionEnd: Date,
        screenUnlockEvents: [ScreenUnlockEvent]
    ) -> TimeInterval {
        guard !screenUnlockEvents.isEmpty else {
            return sessionEnd.timeIntervalSince(sessionStart)
        }

        let sortedEvents = screenUnlockEvents.sorted { $0.timestamp < $1.timestamp }
        var focusTime: TimeInterval = 0
        var lastEventEnd = sessionStart

        for event in sortedEvents {
            let gapDuration = event.timestamp.timeIntervalSince(lastEventEnd)
            if gapDuration >= Constants.focusThresholdSeconds {
                focusTime += gapDuration
            }

            let duration = event.duration ?? 60
            lastEventEnd = event.timestamp.addingTimeInterval(duration)
        }

        let finalGap = sessionEnd.timeIntervalSince(lastEventEnd)
        if finalGap >= Constants.focusThresholdSeconds {
            focusTime += finalGap
        }

        return focusTime
    }
}

// MARK: - Screen Activity Tracker

/// 屏幕活动追踪器
@MainActor
public final class ScreenActivityTracker {
    private var unlockEvents: [ScreenUnlockEvent] = []
    private var sessionStartTime: Date?
    private var lastBecameActiveTime: Date?
    private var observers: [Any] = []

    public init() {}

    public func startTracking() {
        #if canImport(UIKit)
        let activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleDidBecomeActive()
            }
        }

        let resignObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleWillResignActive()
            }
        }

        observers = [activeObserver, resignObserver]
        #endif
    }

    public func stopTracking() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }

    public func markSessionStart() {
        sessionStartTime = Date()
        unlockEvents.removeAll()
    }

    public func getUnlockEventsDuring(start: Date, end: Date) -> [ScreenUnlockEvent] {
        unlockEvents.filter { $0.timestamp >= start && $0.timestamp <= end }
    }

    private func handleDidBecomeActive() {
        guard sessionStartTime != nil else { return }
        lastBecameActiveTime = Date()
        unlockEvents.append(ScreenUnlockEvent(timestamp: Date(), duration: nil))
    }

    private func handleWillResignActive() {
        guard let activeTime = lastBecameActiveTime, let lastEvent = unlockEvents.last else { return }
        let duration = Date().timeIntervalSince(activeTime)
        unlockEvents.removeLast()
        unlockEvents.append(ScreenUnlockEvent(timestamp: lastEvent.timestamp, duration: duration))
        lastBecameActiveTime = nil
    }
}
