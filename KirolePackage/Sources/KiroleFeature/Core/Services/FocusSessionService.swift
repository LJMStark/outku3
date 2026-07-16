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

    /// 当前会话是否按 60 倍虚拟时间运行。仅保存在内存中，新会话与 App 重启都会恢复正常速度。
    public private(set) var isFocusTimeAccelerated = false

    // MARK: - Focus Enforcement Mode

    /// Controls how strictly the app enforces focus: .standard (suggestion) or .deepFocus (screen-time block).
    /// Owned here rather than in AppState so BLEEventHandler can read it without depending on AppState.
    public var focusEnforcementMode: FocusEnforcementMode = .standard

    // MARK: - Private Properties

    private let localStorage: LocalStorage
    private let focusGuardService: any FocusGuardService
    private let interruptionDetector: any FocusInterruptionDetecting
    private let persistenceEnabled: Bool
    /// 当前会话内已检测到的打断（由 interruptionDetector 产出）。
    /// v2.5.20 打断判定重做：打断 = 专注期间使用自选分心 App；
    /// 旧的「Kirole 回前台即打断」ScreenActivityTracker 路径已整体移除（spec D-2 禁止回退）。
    private var sessionInterruptions: [ScreenUnlockEvent] = []
    /// App 回前台可能早于异步恢复旧会话。恢复完成前先暂存检测器回调，避免它们在
    /// `activeSession == nil` 时被丢弃；恢复时与 App Group 中尚未取出的记录一起合并。
    private var preRecoveryInterruptions: [ScreenUnlockEvent] = []
    private var hasCompletedLaunchRecovery: Bool
    private var launchRecoveryTask: Task<Void, Never>?
    private var pendingSessionPersistenceTask: Task<Void, Never>?
    private var focusDisplaySyncTask: Task<Void, Never>?
    var debugTimeline: FocusDebugTimeline?

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
        interruptionDetector: (any FocusInterruptionDetecting)? = nil,
        persistenceEnabled: Bool = true,
        loadOnInit: Bool = true,
        launchRecoveryCompleted: Bool? = nil
    ) {
        self.localStorage = localStorage
        self.focusGuardService = focusGuardService
        self.interruptionDetector = interruptionDetector ?? ScreenTimeInterruptionDetector.shared
        self.persistenceEnabled = persistenceEnabled
        self.hasCompletedLaunchRecovery = launchRecoveryCompleted ?? !loadOnInit

        // Push + persist the moment an interruption is detected: the on-device fill resets
        // immediately, and the active session is re-persisted so a crash recovery sees the
        // interruption instead of over-crediting.
        self.interruptionDetector.onInterruption = { [weak self] timestamp, duration in
            self?.handleDetectedInterruption(startingAt: timestamp, duration: duration)
        }

        guard loadOnInit else { return }
        launchRecoveryTask = Task { @MainActor in
            await loadFocusEnforcementMode()
            await loadTodaySessions()
            await recoverSessionOnLaunchIfNeeded()
        }
    }

    static func makeForTesting(
        focusGuardService: any FocusGuardService,
        interruptionDetector: (any FocusInterruptionDetecting)? = nil,
        persistenceEnabled: Bool = false,
        launchRecoveryCompleted: Bool = true
    ) -> FocusSessionService {
        FocusSessionService(
            localStorage: .shared,
            focusGuardService: focusGuardService,
            interruptionDetector: interruptionDetector,
            persistenceEnabled: persistenceEnabled,
            loadOnInit: false,
            launchRecoveryCompleted: launchRecoveryCompleted
        )
    }

    func bootstrapForTesting() async {
        await loadTodaySessions()
        await recoverSessionOnLaunchIfNeeded()
    }

    func installLaunchRecoveryBarrierForTesting(_ task: Task<Void, Never>) {
        launchRecoveryTask = task
        hasCompletedLaunchRecovery = false
    }

    /// 打断检测当前状态（专注界面据此明示"检测是否开启"，spec D-2）。
    public var interruptionDetectionState: FocusInterruptionDetectionState {
        interruptionDetector.detectionState
    }

    /// 检测源回报一次打断（打断 = 专注期间使用了自选分心 App）。
    private func handleDetectedInterruption(startingAt timestamp: Date, duration: TimeInterval) {
        guard hasCompletedLaunchRecovery else {
            preRecoveryInterruptions.append(
                ScreenUnlockEvent(timestamp: timestamp, duration: duration)
            )
            return
        }
        guard let session = activeSession else { return }
        // 时间戳夹进会话窗口，防御检测源的时钟漂移/迟到回报。
        let clamped = max(timestamp, session.startTime)
        sessionInterruptions.append(ScreenUnlockEvent(timestamp: clamped, duration: duration))
        // 测试实例（persistenceEnabled=false）跳过设备推送与持久化副作用，
        // 与本类其余持久化函数同一守卫策略（防止并行测试污染全局状态）。
        guard persistenceEnabled else { return }
        Task { @MainActor in
            await AppState.shared.syncFocusHardwareDisplay(session: self.activeSession)
            await self.persistActiveSessionWithInterruptions()
        }
    }

    /// 被 BLE 后台唤醒（0x20/0x30）后调用：先补取挂起期间累积到 App Group 的打断，再由调用方
    /// 现算并推 0x14——保证后台推给硬件的瓶子/段位已反映应归零的打断（息屏后台链路）。
    public func refreshInterruptionsFromAppGroup() {
        interruptionDetector.drainPendingInterruptions()
    }

    private func startFocusDisplaySyncLoop() {
        focusDisplaySyncTask?.cancel()
        guard persistenceEnabled else {
            focusDisplaySyncTask = nil
            return
        }
        focusDisplaySyncTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await AppState.shared.syncFocusHardwareDisplay(session: self.activeSession)
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(self.nextFocusDisplaySyncDelay()))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await AppState.shared.syncFocusHardwareDisplay(session: self.activeSession)
            }
        }
    }

    /// Seconds until the next live focus push: the sooner of the next energy bottle completing in
    /// the current uninterrupted segment (so the "bottle collected" effect lands on time) and a
    /// 60-second periodic refresh ceiling.
    private func nextFocusDisplaySyncDelay(now: Date = Date()) -> TimeInterval {
        let rate = debugTimeline?.rate ?? 1
        let periodicCeiling = 60 / rate
        guard activeSession != nil else { return periodicCeiling }
        let segmentSeconds = progressSnapshot(now: now).segmentSeconds
        let remainder = segmentSeconds.truncatingRemainder(dividingBy: Constants.focusThresholdSeconds)
        let virtualSecondsToNextBottle = Constants.focusThresholdSeconds - remainder
        return max(0.25, min(periodicCeiling, virtualSecondsToNextBottle / rate))
    }

    private func stopFocusDisplaySyncLoop() {
        focusDisplaySyncTask?.cancel()
        focusDisplaySyncTask = nil
    }

    // MARK: - Focus Debug Timeline

    /// 在当前真实会话上切换 60 倍虚拟时间；检查点会保住切换瞬间已有进度。
    public func setFocusTimeAcceleration(_ enabled: Bool, now: Date = Date()) {
        guard AppBuildEnvironment.showsHardwareDebugTools,
              activeSession != nil,
              isFocusTimeAccelerated != enabled,
              var timeline = debugTimeline else { return }
        timeline.setRate(enabled ? 60 : 1, at: now)
        debugTimeline = timeline
        isFocusTimeAccelerated = enabled
        startFocusDisplaySyncLoop()
    }

    /// 在当前真实会话的虚拟时间轴上前进指定秒数，不改 `startTime` / `endTime`。
    public func advanceFocusTime(by seconds: TimeInterval, now: Date = Date()) {
        guard AppBuildEnvironment.showsHardwareDebugTools,
              activeSession != nil,
              seconds > 0,
              var timeline = debugTimeline else { return }
        timeline.advance(by: seconds, at: now)
        debugTimeline = timeline
        pushCurrentFocusDisplayImmediately()
    }

    private func pushCurrentFocusDisplayImmediately() {
        guard persistenceEnabled else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            await AppState.shared.syncFocusHardwareDisplay(session: self.activeSession)
        }
    }

    private func resetDebugTimeline(sessionStart: Date? = nil) {
        isFocusTimeAccelerated = false
        debugTimeline = sessionStart.map(FocusDebugTimeline.init)
    }

    // MARK: - Session Management

    /// 开始新的专注会话（当收到 EnterTaskIn 事件时调用）
    public func startSession(
        taskId: String,
        taskTitle: String,
        mode requestedMode: FocusEnforcementMode = .standard,
        startTime: Date = Date()
    ) async {
        // Cold-start recovery owns the active-session file until it has loaded, settled, cleared,
        // and saved the previous session. Starting sooner can make recovery settle or delete the
        // brand-new session that arrived from hardware during launch.
        await launchRecoveryTask?.value

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
        sessionInterruptions.removeAll()
        resetDebugTimeline(sessionStart: startTime)
        interruptionDetector.startMonitoring()
        startFocusDisplaySyncLoop()
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
        interruptionDetector.stopMonitoring()

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

        // 获取会话期间检测到的打断事件（自选分心 App 使用）
        let unlockEvents = currentUnlockEvents(until: endTime)
        session.screenUnlockEvents = unlockEvents

        let settlementEvaluationDate = debugTimeline?.settlementEvaluationDate(for: endTime) ?? endTime
        let progress = progressSnapshot(
            for: session,
            now: settlementEvaluationDate,
            screenUnlockEvents: unlockEvents
        )
        session.calculatedFocusTime = progress.countableFocusTime
        session.earnedEnergyBottles = progress.earnedEnergyBottles
        completeSession(session, endTime: endTime, clearPersistedActiveSession: true)
    }

    /// Interruption events recorded so far in the active session window.
    /// The live hardware push uses these so the on-device fill/phase reflect interruptions in
    /// real time, instead of a wall-clock count that never resets on a detected interruption.
    func currentUnlockEvents(until end: Date) -> [ScreenUnlockEvent] {
        guard let session = activeSession else { return [] }
        return sessionInterruptions.filter { $0.timestamp >= session.startTime && $0.timestamp <= end }
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

    /// 上次统计计算所属自然日（startOfDay）。统计只在加载/结算时重算，App 跨午夜后
    /// 缓存的 todayFocusTime 仍是昨日值——回前台时据此判断换日重算（联审 2026-07-16
    /// F10 相邻缺陷：口径不变，只修缓存不换日）。
    private var statisticsReferenceDay: Date?

    /// 换日后重算统计缓存；同日或从未计算过为 no-op。只应在非渲染时机调用（回前台等），
    /// 渲染路径读 Today 用 `todayFocusTimeIncludingActive(now:)`（纯读不改缓存）。
    public func refreshStatisticsIfDayChanged(now: Date = Date()) {
        guard let referenceDay = statisticsReferenceDay,
              !Calendar.current.isDate(now, inSameDayAs: referenceDay) else { return }
        updateStatistics(now: now)
    }

    /// 专注页 Today 行口径：按 now 判日的今日已结算时长 + 当前活跃会话整段可计时长。
    /// 整段按 endTime 归属（与 updateStatistics 口径一致）：若现在结束即整体归今天，
    /// 因此不做午夜切分，避免结算瞬间总数跳变。纯函数，渲染路径安全。
    public func todayFocusTimeIncludingActive(now: Date = Date()) -> TimeInterval {
        let calendar = Calendar.current
        let settledToday = todaySessions
            .filter { session in
                guard let endTime = session.endTime else { return false }
                return calendar.isDate(endTime, inSameDayAs: now)
            }
            .compactMap(\.calculatedFocusTime)
            .reduce(0, +)
        return settledToday + progressSnapshot(now: now).countableFocusTime
    }

    func updateStatistics(now: Date = Date()) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        statisticsReferenceDay = today

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
        guard persistenceEnabled else {
            preRecoveryInterruptions.removeAll()
            hasCompletedLaunchRecovery = true
            return
        }

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
        let pendingInterruptions = takeLaunchRecoveryInterruptions()
        guard let recovered else {
            hasCompletedLaunchRecovery = true
            return
        }

        applyRecoveredSession(
            recovered,
            pendingInterruptions: pendingInterruptions,
            wasShieldActive: wasShieldActive,
            endTime: Date()
        )

        await clearPersistedActiveSessionIfNeeded()
        await saveSessions()
        hasCompletedLaunchRecovery = true
    }

    func recoverPersistedSessionForTesting(
        _ persistedSession: FocusSession,
        wasShieldActive: Bool,
        endTime: Date = Date()
    ) {
        if wasShieldActive {
            focusGuardService.clearShield()
        }
        let pendingInterruptions = takeLaunchRecoveryInterruptions()
        applyRecoveredSession(
            persistedSession,
            pendingInterruptions: pendingInterruptions,
            wasShieldActive: wasShieldActive,
            endTime: endTime
        )
        hasCompletedLaunchRecovery = true
    }

    private func takeLaunchRecoveryInterruptions() -> [ScreenUnlockEvent] {
        let pending = preRecoveryInterruptions + interruptionDetector.takePendingInterruptions()
        preRecoveryInterruptions.removeAll()
        return pending
    }

    private func applyRecoveredSession(
        _ persistedSession: FocusSession,
        pendingInterruptions: [ScreenUnlockEvent],
        wasShieldActive: Bool,
        endTime: Date
    ) {
        var recovered = persistedSession
        recovered.endTime = endTime
        recovered.endReason = .recoveredOnLaunch
        // Merge the last persisted snapshot with App Group records written after that snapshot.
        // Recovery consumes these records without the live callback, so no intermediate hardware
        // push or duplicate persistence runs while the old session is being finalized.
        let recoveredUnlocks = mergeRecoveredInterruptions(
            persisted: persistedSession.screenUnlockEvents,
            pending: pendingInterruptions,
            sessionStart: recovered.startTime,
            sessionEnd: endTime
        )
        recovered.screenUnlockEvents = recoveredUnlocks
        recovered.calculatedFocusTime = calculateFocusTime(
            sessionStart: recovered.startTime,
            sessionEnd: endTime,
            screenUnlockEvents: recoveredUnlocks
        )
        recovered.earnedEnergyBottles = FocusTimeCalculator.countableBottles(
            sessionStart: recovered.startTime,
            sessionEnd: endTime,
            screenUnlockEvents: recoveredUnlocks
        )
        if wasShieldActive || recovered.protectionState == .protected {
            recovered.mode = .standard
            recovered.protectionState = .fallback
            recovered.interruptionSource = .recoveredOnLaunch
        }

        completeSession(recovered, endTime: endTime, clearPersistedActiveSession: false)
    }

    private func mergeRecoveredInterruptions(
        persisted: [ScreenUnlockEvent],
        pending: [ScreenUnlockEvent],
        sessionStart: Date,
        sessionEnd: Date
    ) -> [ScreenUnlockEvent] {
        let pendingInSession = pending.filter {
            $0.timestamp >= sessionStart && $0.timestamp <= sessionEnd
        }
        var seenTimestampSeconds = Set<Int64>()
        return (persisted + pendingInSession)
            .sorted { $0.timestamp < $1.timestamp }
            .filter {
                let timestampSecond = Int64($0.timestamp.timeIntervalSince1970.rounded(.down))
                return seenTimestampSeconds.insert(timestampSecond).inserted
            }
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
    func calculateFocusTime(
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
        resetDebugTimeline()
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

// ScreenActivityTracker（「Kirole 回前台即打断」的旧信号）已于 v2.5.20 整体删除：
// 该判定与产品设计相反（打开 Kirole 查看进度反被记打断、使用其它 App 检测不到）。
// 新判定源见 FocusInterruptionDetector.swift；spec D-2 禁止保留任何回退路径。

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
