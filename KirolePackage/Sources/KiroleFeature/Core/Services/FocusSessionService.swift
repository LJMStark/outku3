// NOTE: try? is discouraged in this codebase. Use do-try-catch + ErrorReporter.log instead.
// See: ErrorReporter.swift for logging conventions.
import Foundation

#if canImport(UIKit)
import UIKit
#endif

enum HardwareFocusSettlementResult: Sendable, Equatable {
    case durable
    case supersededByApp
    case persistenceFailed
}

// MARK: - Focus Session Service

/// 专注会话服务，管理任务专注时间追踪
@Observable
@MainActor
public final class FocusSessionService {
    public static let shared = FocusSessionService()

    // MARK: - State

    /// 当前活跃的专注会话
    public internal(set) var activeSession: FocusSession?

    /// 今日所有专注会话
    public internal(set) var todaySessions: [FocusSession] = []

    /// 专注统计数据
    public private(set) var statistics: FocusStatistics = FocusStatistics()

    /// 当前会话是否按 60 倍虚拟时间运行。仅保存在内存中，新会话与 App 重启都会恢复正常速度。
    public private(set) var isFocusTimeAccelerated = false

    // MARK: - Focus Enforcement Mode

    /// Controls how strictly the app enforces focus: .standard (suggestion) or .deepFocus (screen-time block).
    /// Owned here rather than in AppState so BLEEventHandler can read it without depending on AppState.
    public var focusEnforcementMode: FocusEnforcementMode = .standard

    // MARK: - Private Properties

    let localStorage: LocalStorage
    let focusPersistence: any FocusSessionPersisting
    let taskOperationLedger: TaskOperationLedger
    let focusGuardService: any FocusGuardService
    let interruptionDetector: any FocusInterruptionDetecting
    let persistenceEnabled: Bool
    /// 当前会话内已检测到的打断（由 interruptionDetector 产出）。
    /// v2.5.20 打断判定重做：打断 = 专注期间使用自选分心 App；
    /// 旧的「Kirole 回前台即打断」ScreenActivityTracker 路径已整体移除（spec D-2 禁止回退）。
    var sessionInterruptions: [ScreenUnlockEvent] = []
    /// App 回前台可能早于异步恢复旧会话。恢复完成前先暂存检测器回调，避免它们在
    /// `activeSession == nil` 时被丢弃；恢复时与 App Group 中尚未取出的记录一起合并。
    var preRecoveryInterruptions: [ScreenUnlockEvent] = []
    var hasCompletedLaunchRecovery: Bool
    private var launchRecoveryTask: Task<Void, Never>?
    struct PendingFocusSettlement {
        let session: FocusSession
        let endTime: Date
        let clearPersistedActiveSession: Bool
        let operationKey: String?
        let historyAlreadyPersisted: Bool
    }

    var pendingFocusSettlement: PendingFocusSettlement?
    var loadedFocusSessionHistory: [UUID: FocusSession] = [:]
    var pendingSessionPersistenceTask: Task<Bool, Never>?
    private var focusDisplaySyncTask: Task<Void, Never>?
    var debugTimeline: FocusDebugTimeline?
    /// In-memory monotonic clock used only to detect a same-task session that starts while a
    /// versioned Complete/Skip transaction is suspended in persistence.
    @ObservationIgnored private var sessionStartGenerations: [String: UInt64] = [:]

    // MARK: - Constants

    private enum Constants {
        /// 专注时间阈值：30分钟未点亮手机才算专注
        static let focusThresholdMinutes: Int = 30
        static let focusThresholdSeconds: TimeInterval = TimeInterval(focusThresholdMinutes * 60)
    }

    // MARK: - Initialization

    private init(
        localStorage: LocalStorage = .shared,
        focusPersistence: (any FocusSessionPersisting)? = nil,
        taskOperationLedger: TaskOperationLedger = .shared,
        focusGuardService: any FocusGuardService = ScreenTimeFocusGuardService.shared,
        interruptionDetector: (any FocusInterruptionDetecting)? = nil,
        persistenceEnabled: Bool = true,
        loadOnInit: Bool = true,
        launchRecoveryCompleted: Bool? = nil
    ) {
        self.localStorage = localStorage
        self.focusPersistence = focusPersistence ?? LocalFocusSessionPersistence(storage: localStorage)
        self.taskOperationLedger = taskOperationLedger
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
        launchRecoveryCompleted: Bool = true,
        focusPersistence: (any FocusSessionPersisting)? = nil,
        taskOperationLedger: TaskOperationLedger = .shared
    ) -> FocusSessionService {
        FocusSessionService(
            localStorage: .shared,
            focusPersistence: focusPersistence,
            taskOperationLedger: taskOperationLedger,
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
        hasCompletedLaunchRecovery = false
        launchRecoveryTask = Task { @MainActor [weak self] in
            await task.value
            self?.hasCompletedLaunchRecovery = true
        }
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
        guard hasCompletedLaunchRecovery else {
            ErrorReporter.log(
                .persistence(
                    operation: "start",
                    target: "focus_session_active.json",
                    underlying: "previous focus settlement is not durable"
                ),
                context: "FocusSessionService.startSession"
            )
            return
        }

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

        // Never overwrite the active-session recovery file until the previous ended session has
        // reached history and that file has been removed successfully.
        guard await retryPendingFocusSettlementIfNeeded() else { return }

        let protectionContext = await resolveProtectionContext(requestedMode: requestedMode)
        let session = FocusSession(
            taskId: taskId,
            taskTitle: taskTitle,
            startTime: startTime,
            mode: protectionContext.mode,
            protectionState: protectionContext.protectionState,
            interruptionSource: protectionContext.interruptionSource
        )

        advanceSessionStartGeneration(for: taskId)
        activeSession = session
        sessionInterruptions.removeAll()
        resetDebugTimeline(sessionStart: startTime)
        interruptionDetector.startMonitoring()
        startFocusDisplaySyncLoop()
        await persistActiveSessionIfNeeded(session)
    }

    func sessionStartGeneration(for taskID: String) -> UInt64 {
        sessionStartGenerations[taskID, default: 0]
    }

    private func advanceSessionStartGeneration(for taskID: String) {
        let current = sessionStartGenerations[taskID, default: 0]
        sessionStartGenerations[taskID] = current == .max ? .max : current + 1
    }

    /// 结束当前专注会话（当收到 CompleteTask 或 SkipTask 事件时调用）
    public func endSession(reason: FocusEndReason, endTime: Date = Date()) {
        _ = endActiveSession(reason: reason, endTime: endTime, operationKey: nil)
    }

    @discardableResult
    private func endActiveSession(
        reason: FocusEndReason,
        endTime: Date,
        operationKey: String?
    ) -> Bool {
        guard var session = activeSession else { return false }
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
        completeSession(
            session,
            endTime: endTime,
            clearPersistedActiveSession: true,
            operationKey: operationKey
        )
        return true
    }

    /// Interruption events recorded so far in the active session window.
    /// The live hardware push uses these so the on-device fill/phase reflect interruptions in
    /// real time, instead of a wall-clock count that never resets on a detected interruption.
    func currentUnlockEvents(until end: Date) -> [ScreenUnlockEvent] {
        guard let session = activeSession else { return [] }
        return sessionInterruptions.filter { $0.timestamp >= session.startTime && $0.timestamp <= end }
    }

    /// 完成任务（短按滚轮）
    @discardableResult
    public func completeTask(taskId: String, endTime: Date = Date()) -> Bool {
        guard let session = activeSession, session.taskId == taskId else { return false }
        endSession(reason: .completed, endTime: endTime)
        return true
    }

    /// 跳过任务（长按滚轮）
    @discardableResult
    public func skipTask(taskId: String, endTime: Date = Date()) -> Bool {
        guard let session = activeSession, session.taskId == taskId else { return false }
        endSession(reason: .skipped, endTime: endTime)
        return true
    }

    /// Settles the focus portion of a versioned hardware task operation. This is called for both
    /// first delivery and exact retries, including retries after `activeSession` was cleared in
    /// memory but history persistence failed.
    func settleHardwareTaskOperation(
        _ entry: TaskOperationLedgerEntry
    ) async -> HardwareFocusSettlementResult {
        await launchRecoveryTask?.value
        if !hasCompletedLaunchRecovery {
            if pendingFocusSettlement != nil {
                hasCompletedLaunchRecovery = await retryPendingFocusSettlementIfNeeded()
            } else {
                await recoverSessionOnLaunchIfNeeded()
            }
        }
        guard hasCompletedLaunchRecovery else { return .persistenceFailed }

        if let pending = pendingFocusSettlement {
            guard pending.operationKey == entry.operationKey else {
                return await retryPendingFocusSettlementIfNeeded()
                    ? .durable
                    : .persistenceFailed
            }
            let persisted = await retryPendingFocusSettlementIfNeeded()
            if persisted { hasCompletedLaunchRecovery = true }
            return persisted ? .durable : .persistenceFailed
        }

        if focusOperationIsSuperseded(entry) {
            return .supersededByApp
        }

        guard let active = activeSession, active.taskId == entry.taskID else {
            return .durable
        }
        let reason: FocusEndReason = entry.action == .completeTask ? .completed : .skipped
        let eventTime = Date(timeIntervalSince1970: TimeInterval(entry.deviceTimestamp))
        let endTime = max(active.startTime, min(eventTime, min(entry.recordedAt, Date())))
        guard endActiveSession(
            reason: reason,
            endTime: endTime,
            operationKey: entry.operationKey
        ) else {
            return .durable
        }

        let persisted = await waitForPendingSessionPersistence()
        if persisted { hasCompletedLaunchRecovery = true }
        return persisted ? .durable : .persistenceFailed
    }

    private func focusOperationIsSuperseded(_ entry: TaskOperationLedgerEntry) -> Bool {
        let eventTime = Date(timeIntervalSince1970: TimeInterval(entry.deviceTimestamp))
        let orderingTolerance: TimeInterval = 2
        let futureTolerance: TimeInterval = 5 * 60
        guard eventTime <= entry.recordedAt.addingTimeInterval(futureTolerance) else {
            return true
        }

        let matchingStart = activeSession?.taskId == entry.taskID
            ? activeSession?.startTime
            : todaySessions
                .filter { $0.taskId == entry.taskID }
                .map(\.startTime)
                .max()
        guard let matchingStart else { return false }
        return eventTime.addingTimeInterval(orderingTolerance) < matchingStart
            || entry.recordedAt.addingTimeInterval(orderingTolerance) < matchingStart
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

    func completeSession(
        _ session: FocusSession,
        endTime: Date,
        clearPersistedActiveSession: Bool,
        operationKey: String?
    ) {
        var durableSession = session
        if persistenceEnabled, durableSession.energyAwardReceiptID == nil {
            durableSession.energyAwardReceiptID = durableSession.id
        }
        if let existingIndex = todaySessions.firstIndex(where: { $0.id == durableSession.id }) {
            todaySessions[existingIndex] = durableSession
        } else {
            todaySessions.append(durableSession)
        }
        activeSession = nil
        resetDebugTimeline()
        updateStatistics()

        pendingFocusSettlement = PendingFocusSettlement(
            session: durableSession,
            endTime: endTime,
            clearPersistedActiveSession: clearPersistedActiveSession,
            operationKey: operationKey,
            historyAlreadyPersisted: false
        )
        schedulePendingFocusSettlement()
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
