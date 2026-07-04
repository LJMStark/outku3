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
        let tracker = ScreenActivityTracker()
        // Push + persist the moment an interruption is recorded: the on-device fill resets
        // immediately, and the active session is re-persisted so a crash recovery sees the
        // interruption instead of over-crediting. The tracker appends the unlock event before
        // invoking this, so both already reflect the interruption.
        tracker.onInterruptionRecorded = { [weak self] in
            guard let self, self.activeSession != nil else { return }
            Task { @MainActor in
                await AppState.shared.syncFocusHardwareDisplay(session: self.activeSession)
                await self.persistActiveSessionWithInterruptions()
            }
        }
        // When an interruption closes, re-persist so the recovered session carries the resolved
        // duration. The periodic loop stops once the app backgrounds, so this is the last write
        // before a possible kill.
        tracker.onInterruptionClosed = { [weak self] in
            guard let self, self.activeSession != nil else { return }
            Task { @MainActor in
                await self.persistActiveSessionWithInterruptions()
            }
        }
        tracker.startTracking()
        screenActivityTracker = tracker
    }

    private func startFocusDisplaySyncLoop() {
        focusDisplaySyncTask?.cancel()
        focusDisplaySyncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await AppState.shared.syncFocusHardwareDisplay(session: self.activeSession)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self.nextFocusDisplaySyncDelay()))
                guard !Task.isCancelled else { return }
                await AppState.shared.syncFocusHardwareDisplay(session: self.activeSession)
            }
        }
    }

    /// Seconds until the next live focus push: the sooner of the next energy bottle completing in
    /// the current uninterrupted segment (so the "bottle collected" effect lands on time) and a
    /// 60-second periodic refresh ceiling.
    private func nextFocusDisplaySyncDelay(now: Date = Date()) -> TimeInterval {
        let periodicCeiling: TimeInterval = 60
        guard let session = activeSession else { return periodicCeiling }
        let segmentStart = FocusTimeCalculator.currentSegmentStart(
            sessionStart: session.startTime,
            now: now,
            screenUnlockEvents: currentUnlockEvents(until: now)
        )
        let secondsToNextBottle = FocusTimeCalculator.secondsUntilNextBottle(
            segmentStart: segmentStart,
            now: now,
            blockSeconds: Constants.focusThresholdSeconds
        )
        return max(1, min(periodicCeiling, secondsToNextBottle))
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
        // 幂等保护：同一任务已有活跃会话时，重复投递的 enterTaskIn（BLE 重传 / 固件重发）
        // 不应切断当前会话再以 .timeout 重开——那会写入一个假的 timeout 会话、污染专注统计。
        // 实时事件路径不再做高水位去重（见 BLEEventHandler.handleEventLogs），故这里必须自带幂等。
        // 仅当切换到“不同”任务时才结束旧会话。
        if let active = activeSession {
            if active.taskId == taskId {
                return
            }
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
        // 结束时间不得早于会话开始：固件 RTC 错乱时 completeTask/skipTask 可能携带远古时间戳
        // （1970 级），而 live 开始时间已被夹到 now-2h——不夹结束侧会算出**负专注时长**写进
        // 结算（FocusTimeCalculator 无解锁事件时直接 end-start）。单点防御全部结束路径
        // （Codex review P1, 2026-07-04）。
        let endTime = max(endTime, session.startTime)
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

        session.earnedEnergyBottles = FocusTimeCalculator.countableBottles(
            sessionStart: session.startTime,
            sessionEnd: endTime,
            screenUnlockEvents: unlockEvents
        )
        completeSession(session, endTime: endTime, clearPersistedActiveSession: true)
    }

    /// Screen-unlock (interruption) events recorded so far in the active session window.
    /// The live hardware push uses these so the on-device fill/phase reflect interruptions in
    /// real time, instead of a wall-clock count that never resets when the user picks up the phone.
    func currentUnlockEvents(until end: Date) -> [ScreenUnlockEvent] {
        guard let session = activeSession else { return [] }
        return screenActivityTracker?.getUnlockEventsDuring(start: session.startTime, end: end) ?? []
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
            async let trend = computeTrendDirection()
            async let historicalTimes = computeHistoricalFocusTimes()
            let (resolvedTrend, (week, month)) = await (trend, historicalTimes)
            statistics.focusTrendDirection = resolvedTrend
            statistics.pastWeekFocusTime = week
            statistics.last30DaysFocusTime = month
        }
    }

    private func computeHistoricalFocusTimes() async -> (week: TimeInterval, month: TimeInterval) {
        guard persistenceEnabled else { return (0, 0) }
        do {
            let monthSessions = try await localStorage.loadFocusSessionsForPastDays(30)
            let cutoff7 = Calendar.current.date(byAdding: .day, value: -7, to: Calendar.current.startOfDay(for: Date())) ?? .distantPast
            let week = monthSessions
                .filter { $0.startTime >= cutoff7 }
                .compactMap(\.calculatedFocusTime)
                .reduce(0, +)
            let month = monthSessions
                .compactMap(\.calculatedFocusTime)
                .reduce(0, +)
            return (week, month)
        } catch {
            return (0, 0)
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

    /// Persists the active session with the interruptions recorded so far, so a crash recovery
    /// settles against the real interruption history instead of assuming an uninterrupted session
    /// (which over-credits bottles). Best practice: persist in-progress state early.
    private func persistActiveSessionWithInterruptions(now: Date = Date()) async {
        guard persistenceEnabled, let session = activeSession else { return }
        var snapshot = session
        snapshot.screenUnlockEvents = currentUnlockEvents(until: now)
        await persistActiveSessionIfNeeded(snapshot)
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
        // Settle against the interruptions persisted before the kill, not an empty list — assuming
        // an uninterrupted session would over-credit bottles.
        let persistedUnlocks = persistedSession.screenUnlockEvents
        recovered.screenUnlockEvents = persistedUnlocks
        recovered.calculatedFocusTime = calculateFocusTime(
            sessionStart: recovered.startTime,
            sessionEnd: endTime,
            screenUnlockEvents: persistedUnlocks
        )
        recovered.earnedEnergyBottles = FocusTimeCalculator.countableBottles(
            sessionStart: recovered.startTime,
            sessionEnd: endTime,
            screenUnlockEvents: persistedUnlocks
        )
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
            // metrics 只累计次数；不记错误内容的话，线上无法区分权限问题和 ScreenTime API 故障。
            ErrorReporter.log(
                .sync(component: "FocusGuard.applyShield", underlying: error.localizedDescription),
                context: "FocusSessionService.resolveProtectionContext"
            )
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
        FocusTimeCalculator.countableFocusTime(
            sessionStart: sessionStart,
            sessionEnd: sessionEnd,
            screenUnlockEvents: screenUnlockEvents,
            thresholdSeconds: Constants.focusThresholdSeconds
        )
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
        // 与本类其余持久化函数同一守卫策略：persistenceEnabled=false 的测试实例
        // 不得读写全局 UserDefaults 里的能量瓶/庆祝水位，否则污染并行测试。
        guard persistenceEnabled else { return (0, []) }
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

    /// Invoked right after an interruption is recorded during a session, so the live hardware
    /// display can immediately reset the in-progress bottle fill instead of waiting for the next
    /// periodic sync tick. Ordered guarantee: the unlock event is appended before this fires.
    public var onInterruptionRecorded: (@MainActor () -> Void)?

    /// Invoked right after an interruption closes (the app resigns active and the unlock event's
    /// duration is filled in). The periodic sync loop is suspended once the app backgrounds, so
    /// this is the last chance to re-persist the session with the resolved duration before a
    /// possible kill — without it, recovery would treat a closed interruption as still open.
    public var onInterruptionClosed: (@MainActor () -> Void)?

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
        onInterruptionRecorded?()
    }

    private func handleWillResignActive() {
        guard let activeTime = lastBecameActiveTime, let lastEvent = unlockEvents.last else { return }
        let duration = Date().timeIntervalSince(activeTime)
        unlockEvents.removeLast()
        unlockEvents.append(ScreenUnlockEvent(timestamp: lastEvent.timestamp, duration: duration))
        lastBecameActiveTime = nil
        onInterruptionClosed?()
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
