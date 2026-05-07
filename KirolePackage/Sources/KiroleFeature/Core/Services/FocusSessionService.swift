// NOTE: try? is discouraged in this codebase. Use do-try-catch + ErrorReporter.log instead.
// See: ErrorReporter.swift for logging conventions.
import Foundation

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Focus Session Service

/// 专注会话服务，管理任务专注时间追踪
@Observable
@MainActor
public final class FocusSessionService {
    public static let shared = FocusSessionService()

    // MARK: - State

    /// 当前活跃的专注会话
    public private(set) var activeSession: FocusSession?

    /// 今日所有专注会话
    public private(set) var todaySessions: [FocusSession] = []

    /// 专注统计数据
    public private(set) var statistics: FocusStatistics = FocusStatistics()

    // MARK: - Focus Enforcement Mode

    /// Controls how strictly the app enforces focus: .standard (suggestion) or .deepFocus (screen-time block).
    /// Owned here rather than in AppState so BLEEventHandler can read it without depending on AppState.
    public var focusEnforcementMode: FocusEnforcementMode = .standard

    // MARK: - Private Properties

    private let localStorage: LocalStorage
    private let focusGuardService: any FocusGuardService
    private let persistenceEnabled: Bool
    private var screenActivityTracker: ScreenActivityTracker?
    private var pendingSessionPersistenceTask: Task<Void, Never>?
    private var focusDisplaySyncTask: Task<Void, Never>?

    // MARK: - Constants

    private enum Constants {
        /// 专注时间阈值：30分钟未点亮手机才算专注
        static let focusThresholdMinutes: Int = 30
        static let focusThresholdSeconds: TimeInterval = TimeInterval(focusThresholdMinutes * 60)
    }

    // MARK: - Initialization

    private init(
        localStorage: LocalStorage = .shared,
        focusGuardService: any FocusGuardService = ScreenTimeFocusGuardService.shared,
        persistenceEnabled: Bool = true,
        loadOnInit: Bool = true
    ) {
        self.localStorage = localStorage
        self.focusGuardService = focusGuardService
        self.persistenceEnabled = persistenceEnabled

        guard loadOnInit else { return }
        Task { @MainActor in
            await loadFocusEnforcementMode()
            await loadTodaySessions()
            await recoverSessionOnLaunchIfNeeded()
            setupScreenTracking()
        }
    }

    static func makeForTesting(
        focusGuardService: any FocusGuardService,
        persistenceEnabled: Bool = false
    ) -> FocusSessionService {
        FocusSessionService(
            localStorage: .shared,
            focusGuardService: focusGuardService,
            persistenceEnabled: persistenceEnabled,
            loadOnInit: false
        )
    }

    func bootstrapForTesting() async {
        await loadTodaySessions()
        await recoverSessionOnLaunchIfNeeded()
        setupScreenTracking()
    }

    private func setupScreenTracking() {
        screenActivityTracker = ScreenActivityTracker()
        screenActivityTracker?.startTracking()
    }

    private func startFocusDisplaySyncLoop() {
        focusDisplaySyncTask?.cancel()
        focusDisplaySyncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await AppState.shared.syncFocusHardwareDisplay(session: self.activeSession)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                await AppState.shared.syncFocusHardwareDisplay(session: self.activeSession)
            }
        }
    }

    private func stopFocusDisplaySyncLoop() {
        focusDisplaySyncTask?.cancel()
        focusDisplaySyncTask = nil
    }

    // MARK: - Session Management

    /// 开始新的专注会话（当收到 EnterTaskIn 事件时调用）
    public func startSession(
        taskId: String,
        taskTitle: String,
        mode requestedMode: FocusEnforcementMode = .standard,
        startTime: Date = Date()
    ) async {
        // 如果有活跃会话，先结束它
        if activeSession != nil {
            endSession(reason: .timeout, endTime: startTime)
        }

        let protectionContext = await resolveProtectionContext(requestedMode: requestedMode)
        let session = FocusSession(
            taskId: taskId,
            taskTitle: taskTitle,
            startTime: startTime,
            mode: protectionContext.mode,
            protectionState: protectionContext.protectionState,
            interruptionSource: protectionContext.interruptionSource
        )

        activeSession = session
        startFocusDisplaySyncLoop()
        screenActivityTracker?.markSessionStart()
        await waitForPendingSessionPersistence()
        await persistActiveSessionIfNeeded(session)
    }

    /// 结束当前专注会话（当收到 CompleteTask 或 SkipTask 事件时调用）
    public func endSession(reason: FocusEndReason, endTime: Date = Date()) {
        guard var session = activeSession else { return }
        stopFocusDisplaySyncLoop()

        if session.protectionState == .protected {
            focusGuardService.clearShield()
            if persistenceEnabled {
                Task {
                    await localStorage.saveDeepFocusShieldActive(false)
                }
            }
        }

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

        session.earnedEnergyBottles = earnedEnergyBottles(for: session.calculatedFocusTime)
        completeSession(session, endTime: endTime, clearPersistedActiveSession: true)
    }

    /// 完成任务（短按滚轮）
    public func completeTask(taskId: String, endTime: Date = Date()) {
        guard let session = activeSession, session.taskId == taskId else { return }
        endSession(reason: .completed, endTime: endTime)
    }

    /// 跳过任务（长按滚轮）
    public func skipTask(taskId: String, endTime: Date = Date()) {
        guard let session = activeSession, session.taskId == taskId else { return }
        endSession(reason: .skipped, endTime: endTime)
    }

    /// 设备断开连接时结束会话
    public func handleDeviceDisconnected() {
        if activeSession != nil {
            endSession(reason: .disconnected)
        }
    }

    /// 应用回到前台时，刷新深度专注权限并在必要时降级
    public func refreshProtectionStatus() async {
        guard var current = activeSession else { return }
        guard current.protectionState == .protected else { return }

        await focusGuardService.refreshAuthorizationStatus()
        guard focusGuardService.authorizationStatus != .approved else { return }

        focusGuardService.clearShield()
        if persistenceEnabled {
            await localStorage.saveDeepFocusShieldActive(false)
        }
        Task {
            await FocusMetricsService.shared.record(.sessionInterrupted)
        }
        current.mode = .standard
        current.protectionState = .fallback
        current.interruptionSource = .authorizationRevoked
        activeSession = current
        await persistActiveSessionIfNeeded(current)
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
        let protectedSessionCount = todayCompletedSessions.filter { $0.protectionState == .protected }.count

        let averageMinutes = focusTimes.isEmpty ? 0 : Int(focusTimes.reduce(0, +) / Double(focusTimes.count) / 60)
        let longestMinutes = Int((focusTimes.max() ?? 0) / 60)
        let interruptions = todayCompletedSessions.reduce(0) { $0 + $1.screenUnlockEvents.count }
        let peakHour = computePeakFocusHour(sessions: todayCompletedSessions, calendar: calendar)

        statistics = FocusStatistics(
            todayFocusTime: todayFocusTime,
            todaySessions: todayCompletedSessions.count,
            protectedSessionCount: protectedSessionCount,
            averageSessionMinutes: averageMinutes,
            longestSessionMinutes: longestMinutes,
            interruptionCount: interruptions,
            peakFocusHour: peakHour,
            focusTrendDirection: .stable
        )

        Task {
            let trend = await computeTrendDirection()
            statistics.focusTrendDirection = trend
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
        guard persistenceEnabled else { return .stable }

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
        guard persistenceEnabled else { return }

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
            ErrorReporter.log(
                .persistence(
                    operation: "load",
                    target: "focus_sessions.json",
                    underlying: error.localizedDescription
                ),
                context: "FocusSessionService.loadTodaySessions"
            )
        }
    }

    private func saveSessions() async {
        guard persistenceEnabled else { return }

        do {
            try await localStorage.saveFocusSessions(todaySessions)
            try await localStorage.saveFocusSessionsForDate(todaySessions, date: Date())
        } catch {
            ErrorReporter.log(
                .persistence(
                    operation: "save",
                    target: "focus_sessions",
                    underlying: error.localizedDescription
                ),
                context: "FocusSessionService.saveSessions"
            )
        }
    }

    private func scheduleSessionPersistence(_ operation: @escaping @MainActor () async -> Void) {
        let previousTask = pendingSessionPersistenceTask
        pendingSessionPersistenceTask = Task { @MainActor in
            _ = await previousTask?.result
            await operation()
        }
    }

    private func waitForPendingSessionPersistence() async {
        _ = await pendingSessionPersistenceTask?.result
    }

    func waitForPendingPersistenceForTesting() async {
        await waitForPendingSessionPersistence()
    }

    private func persistActiveSessionIfNeeded(_ session: FocusSession) async {
        guard persistenceEnabled else { return }

        do {
            try await localStorage.saveActiveFocusSession(session)
        } catch {
            ErrorReporter.log(
                .persistence(
                    operation: "save",
                    target: "focus_session_active.json",
                    underlying: error.localizedDescription
                ),
                context: "FocusSessionService.persistActiveSessionIfNeeded"
            )
        }
    }

    private func clearPersistedActiveSessionIfNeeded() async {
        guard persistenceEnabled else { return }

        do {
            try await localStorage.clearActiveFocusSession()
        } catch {
            ErrorReporter.log(
                .persistence(
                    operation: "delete",
                    target: "focus_session_active.json",
                    underlying: error.localizedDescription
                ),
                context: "FocusSessionService.clearPersistedActiveSessionIfNeeded"
            )
        }
    }

    private func recoverSessionOnLaunchIfNeeded() async {
        guard persistenceEnabled else { return }

        let wasShieldActive = await localStorage.loadDeepFocusShieldActive()
        if wasShieldActive {
            focusGuardService.clearShield()
            await localStorage.saveDeepFocusShieldActive(false)
        }

        let recovered: FocusSession?
        do {
            recovered = try await localStorage.loadActiveFocusSession()
        } catch {
            ErrorReporter.log(
                .persistence(operation: "load", target: "active_focus_session", underlying: error.localizedDescription),
                context: "FocusSessionService.recoverSessionOnLaunchIfNeeded"
            )
            recovered = nil
        }
        guard let recovered else {
            return
        }

        applyRecoveredSession(recovered, wasShieldActive: wasShieldActive, endTime: Date())

        await clearPersistedActiveSessionIfNeeded()
        await saveSessions()
    }

    func recoverPersistedSessionForTesting(
        _ persistedSession: FocusSession,
        wasShieldActive: Bool,
        endTime: Date = Date()
    ) {
        if wasShieldActive {
            focusGuardService.clearShield()
        }
        applyRecoveredSession(persistedSession, wasShieldActive: wasShieldActive, endTime: endTime)
    }

    private func applyRecoveredSession(
        _ persistedSession: FocusSession,
        wasShieldActive: Bool,
        endTime: Date
    ) {
        var recovered = persistedSession
        recovered.endTime = endTime
        recovered.endReason = .recoveredOnLaunch
        recovered.screenUnlockEvents = []
        recovered.calculatedFocusTime = calculateFocusTime(
            sessionStart: recovered.startTime,
            sessionEnd: endTime,
            screenUnlockEvents: []
        )
        recovered.earnedEnergyBottles = earnedEnergyBottles(for: recovered.calculatedFocusTime)
        if wasShieldActive || recovered.protectionState == .protected {
            recovered.mode = .standard
            recovered.protectionState = .fallback
            recovered.interruptionSource = .recoveredOnLaunch
        }

        completeSession(recovered, endTime: endTime, clearPersistedActiveSession: false)
    }

    // MARK: - Protection Resolution

    private struct ProtectionContext {
        var mode: FocusEnforcementMode
        var protectionState: FocusProtectionState
        var interruptionSource: FocusInterruptionSource?
    }

    private func resolveProtectionContext(requestedMode: FocusEnforcementMode) async -> ProtectionContext {
        guard requestedMode == .deepFocus else {
            return ProtectionContext(mode: .standard, protectionState: .unprotected, interruptionSource: nil)
        }

        guard focusGuardService.isDeepFocusFeatureEnabled else {
            Task {
                await FocusMetricsService.shared.record(.sessionFallback)
            }
            return ProtectionContext(mode: .standard, protectionState: .fallback, interruptionSource: .featureDisabled)
        }
        guard focusGuardService.isDeepFocusCapable else {
            Task {
                await FocusMetricsService.shared.record(.sessionFallback)
            }
            return ProtectionContext(mode: .standard, protectionState: .fallback, interruptionSource: .capabilityUnavailable)
        }

        await focusGuardService.refreshAuthorizationStatus()
        var status = focusGuardService.authorizationStatus
        if status == .notDetermined {
            Task {
                await FocusMetricsService.shared.record(.authorizationRequested)
            }
            status = await focusGuardService.requestAuthorization()
        }

        guard status == .approved else {
            Task {
                await FocusMetricsService.shared.record(.authorizationDenied)
                await FocusMetricsService.shared.record(.sessionFallback)
            }
            return ProtectionContext(mode: .standard, protectionState: .fallback, interruptionSource: .permissionDenied)
        }

        Task {
            await FocusMetricsService.shared.record(.authorizationApproved)
        }

        guard let selection = focusGuardService.currentSelection(), !selection.isEmpty else {
            Task {
                await FocusMetricsService.shared.record(.sessionFallback)
            }
            return ProtectionContext(mode: .standard, protectionState: .fallback, interruptionSource: .selectionMissing)
        }

        do {
            try focusGuardService.applyShield(selection: selection)
            if persistenceEnabled {
                await localStorage.saveDeepFocusShieldActive(true)
            }
            Task {
                await FocusMetricsService.shared.record(.protectionApplied)
            }
            return ProtectionContext(mode: .deepFocus, protectionState: .protected, interruptionSource: nil)
        } catch {
            Task {
                await FocusMetricsService.shared.record(.protectionApplyFailed)
                await FocusMetricsService.shared.record(.sessionFallback)
            }
            return ProtectionContext(mode: .standard, protectionState: .fallback, interruptionSource: .shieldApplyFailed)
        }
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

    private func earnedEnergyBottles(for focusTime: TimeInterval?) -> Int {
        let focusMinutes = Int((focusTime ?? 0) / 60)
        return FocusEnergyCalculator.bottlesEarned(minutes: focusMinutes)
    }

    private func completeSession(
        _ session: FocusSession,
        endTime: Date,
        clearPersistedActiveSession: Bool
    ) {
        todaySessions.append(session)
        activeSession = nil
        updateStatistics()

        let bottlesToAdd = session.earnedEnergyBottles
        scheduleSessionPersistence { [weak self] in
            guard let self else { return }
            let (totalEnergyBottles, newlyUnlocked) = await self.updateStoredEnergyBottles(adding: bottlesToAdd)
            if clearPersistedActiveSession {
                await self.clearPersistedActiveSessionIfNeeded()
            }
            await self.saveSessions()
            await AppState.shared.handleFocusSessionDidEnd(
                totalEnergyBottles: totalEnergyBottles,
                newlyUnlocked: newlyUnlocked,
                now: endTime
            )
        }
    }

    /// 累加能量瓶并诊断"这次累加是否跨过了未庆祝的解锁阈值"。
    /// 返回值的 newlyUnlocked 仅在还未庆祝过的解锁档触发，已庆祝的会被去重过滤。
    private func updateStoredEnergyBottles(
        adding bottlesToAdd: Int
    ) async -> (total: Int, newlyUnlocked: [String]) {
        let before = await localStorage.loadEnergyBottles()
        guard bottlesToAdd > 0 else {
            return (before, [])
        }

        let after = before + bottlesToAdd
        await localStorage.saveEnergyBottles(after)

        let alreadyCelebrated = await localStorage.loadLastCelebratedUnlockCount()
        let totalUnlockedNow = DisplayScene.unlockedScenes(for: after).count
        guard totalUnlockedNow > alreadyCelebrated else {
            return (after, [])
        }

        let newlyUnlocked = Array(
            DisplayScene.allCases
                .dropFirst(alreadyCelebrated)
                .prefix(totalUnlockedNow - alreadyCelebrated)
        ).map(\.rawValue)
        await localStorage.saveLastCelebratedUnlockCount(totalUnlockedNow)
        return (after, newlyUnlocked)
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

// MARK: - Focus Enforcement Mode Persistence

extension FocusSessionService {
    /// Loads the saved focus enforcement mode from UserDefaults and applies ScreenTime guard.
    func loadFocusEnforcementMode() async {
        let saved = await localStorage.loadFocusEnforcementMode() ?? .standard
        if saved == .deepFocus && !ScreenTimeFocusGuardService.shared.canShowDeepFocusEntry {
            focusEnforcementMode = .standard
            await localStorage.saveFocusEnforcementMode(.standard)
        } else {
            focusEnforcementMode = saved
        }
    }

    /// Sets the focus enforcement mode and persists it.
    public func setFocusEnforcementMode(_ mode: FocusEnforcementMode) {
        focusEnforcementMode = mode
        Task {
            await localStorage.saveFocusEnforcementMode(mode)
        }
    }
}
