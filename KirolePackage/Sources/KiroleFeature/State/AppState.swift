import SwiftUI

// MARK: - Constants

enum ProgressConstants {
    static let pointsPerTask: Int = 10
}

typealias CustomAvatarConnectionProvider = @MainActor () -> (isConnected: Bool, deviceID: UUID?)
typealias CustomAvatarFrameSender = @MainActor (
    UInt32,
    UUID,
    Data,
    @escaping @MainActor @Sendable (Int, Int) -> Void
) async throws -> Void
typealias AvatarControlSender = @MainActor (AvatarControlCommand) async throws -> Void
typealias SharedPetDialogueGenerator = @MainActor (AIContext, AITextType) async -> String
typealias BLESyncSleeper = @MainActor (Duration) async throws -> Void

struct AvatarControlResultWaiter {
    let operationID: UInt32
    let expectedStatus: AvatarControlStatus
    let continuation: CheckedContinuation<AvatarControlResult, any Error>
}

// MARK: - Home Companion Display Mode

public enum HomeCompanionDisplayMode: String, Codable, Sendable {
    case dailyHaiku
    case petDialogue
}

// MARK: - Scene Unlock Celebration Signal

/// 跨阈值即时反馈的"信号包"。AppState 发出，HomeView 监听。
public struct SceneCelebration: Equatable, Sendable {
    public let sceneId: String
    public let presentedAt: Date

    public init(sceneId: String, presentedAt: Date = Date()) {
        self.sceneId = sceneId
        self.presentedAt = presentedAt
    }
}

// MARK: - App State

@Observable
@MainActor
public final class AppState {
    public static let shared = AppState()

    // Navigation
    public var selectedTab: AppTab = .home
    public var selectedDate: Date = Date()

    // Pet
    public var pet: Pet = Pet()

    // Tasks & Events
    public var events: [CalendarEvent] = [] {
        didSet {
            guard !suppressesDailyContentChangeTracking else { return }
            recordDailyContentChanges(from: oldValue, to: events)
        }
    }
    public var tasks: [TaskItem] = [] {
        didSet {
            recordTaskMutations(from: oldValue, to: tasks)
            guard !suppressesTaskLibraryChangeTracking else { return }
            recordTaskLibraryChanges(from: oldValue, to: tasks)
            prepareChangedTaskLibraryPhaseTexts(from: oldValue, to: tasks)
        }
    }
    public var statistics: TaskStatistics = TaskStatistics()

    /// Per-task monotonic clock for App-authoritative mutations. Hardware completion writes are
    /// excluded explicitly, so a BLE transaction can tell whether an App edit/undo/delete landed
    /// while one of its persistence awaits was suspended.
    @ObservationIgnored private var taskMutationGenerations: [String: UInt64] = [:]
    /// Status-only authority clock (`isCompleted` / `pendingDeletion`). Content edits bump
    /// `taskMutationGenerations` but must not supersede offline Complete/Skip (issue #25).
    @ObservationIgnored private var taskStatusMutationGenerations: [String: UInt64] = [:]
    /// Monotonic version of the complete task state. Unlike the per-task authority clocks above,
    /// this also advances for hardware-owned mutations because companion text and DayPack content
    /// must describe the same task snapshot regardless of which side initiated the change.
    @ObservationIgnored private(set) var taskStateVersion: UInt64 = 0
    @ObservationIgnored private var suppressesTaskMutationTracking = false

    // Weather & Sun
    public var weather: Weather = Weather()
    public var sunTimes: SunTimes = .default

    // Haiku & Companion Text
    public var currentHaiku: Haiku = .placeholder
    public var currentPetDialogue: String = ""
    public var homeCompanionDisplayMode: HomeCompanionDisplayMode = .dailyHaiku
    /// Short-lived semantic animation request consumed by the visible App companion surface.
    public var pendingCompanionMotionTrigger: CompanionMotionTrigger?

    // Integrations
    public var integrations: [Integration] = Integration.defaultIntegrations
    /// Once connection preferences have been loaded or bootstrapped, auth scopes must not
    /// silently turn a user-disabled integration back on.
    @ObservationIgnored var hasExplicitIntegrationConnectionPreferences = false

    // User Profile
    public var userProfile: UserProfile = .default {
        didSet {
            recordTaskLibraryPersonaChange(
                oldProfile: oldValue,
                oldCustomCompanions: customCompanions,
                newProfile: userProfile,
                newCustomCompanions: customCompanions
            )
        }
    }
    /// User-created companions (4th option alongside Joy/Silas/Nova).
    /// Loaded from disk on app start; mutated through AppState+Companion methods.
    public var customCompanions: [CustomCompanion] = [] {
        didSet {
            recordTaskLibraryPersonaChange(
                oldProfile: userProfile,
                oldCustomCompanions: oldValue,
                newProfile: userProfile,
                newCustomCompanions: customCompanions
            )
        }
    }

    // Onboarding Profile
    public var onboardingProfile: OnboardingProfile?

    // Device Mode
    public var deviceMode: DeviceMode = .interactive
    public var isDemoMode: Bool = false

    /// Forwards to FocusSessionService — owned there so BLEEventHandler doesn't depend on AppState.
    public var focusEnforcementMode: FocusEnforcementMode {
        FocusSessionService.shared.focusEnforcementMode
    }

    // UI State
    public var selectedEvent: CalendarEvent?
    public var isEventDetailPresented: Bool = false
    /// 最近一次的"场景解锁庆祝"信号；HomeView onChange 时炸 confetti + 展示横幅，
    /// ~3s 后由 UI 层置回 nil。nil = 当前没有待展示的庆祝。
    public var pendingSceneCelebration: SceneCelebration?
    /// True while the focus-settlement sheet is on screen. The sheet shows its own
    /// "New Scene Unlocked!" highlight, so the top SceneUnlockBanner is suppressed
    /// during that window to avoid two competing unlock notices.
    public var isFocusSettlementPresented: Bool = false

    // Loading State
    public var isLoading: Bool = false
    public var lastError: String?
    /// Remote sync error per provider ("Google", "Notion", "Taskade", "Apple Calendar", "Apple Reminders").
    /// Set on failure, cleared on next successful sync for that provider.
    public var remoteSyncErrors: [String: String] = [:]
    /// 部分失败/降级提示（黄色）。红色阻塞错误在 remoteSyncErrors；本字典不点亮齿轮红点。
    public var remoteSyncWarnings: [String: String] = [:]
    /// 各集成最近一次成功应用数据的时间，key 与 remoteSyncErrors 的 provider 显示名一致。
    public var integrationLastSyncedAt: [String: Date] = [:]
    /// The only user-visible custom-avatar operation. Firmware confirmation, not GATT ACK,
    /// decides when identity and local assets are committed.
    public internal(set) var customAvatarOperationState: CustomAvatarOperationState = .idle
    /// Durable mirror of `pending_custom_avatar_operation.json` for launch recovery and UI.
    public internal(set) var pendingCustomAvatarOperation: PendingCustomAvatarOperation?
    /// The single in-flight v2.7 0x15 transfer. A new operation is rejected while this exists.
    @ObservationIgnored var customAvatarPushTask: Task<Void, any Error>?
    @ObservationIgnored var avatarControlResultWaiter: AvatarControlResultWaiter?
    @ObservationIgnored var bufferedAvatarControlResults: [UInt32: [AvatarControlResult]] = [:]
    @ObservationIgnored var avatarControlExpectedBufferedStatus: AvatarControlStatus?
    @ObservationIgnored var avatarControlTimeoutTask: Task<Void, Never>?
    @ObservationIgnored var customAvatarOperationGeneration: UInt64 = 0
    @ObservationIgnored var isCustomAvatarRetryRunning = false
    @ObservationIgnored var customAvatarOperationIDProvider: @MainActor () -> UInt32 = {
        UInt32.random(in: 1...UInt32.max)
    }
    @ObservationIgnored var customAvatarConnectionProvider: CustomAvatarConnectionProvider = {
        (
            BLEService.shared.connectionState.isConnected,
            BLEService.shared.lastKnownDeviceID
        )
    }
    /// BLE 分包传输（0x15）。WiFi 传输失败/不可用时的回退通道；`.bleOnly` 偏好也直接用它。
    @ObservationIgnored var bleCustomAvatarFrameSender: CustomAvatarFrameSender = {
        operationID, avatarID, kriData, progress in
        try await BLEService.shared.sendCustomAvatarKRIFrame(
            operationID: operationID,
            avatarID: avatarID,
            kriData: kriData,
            progress: progress
        )
    }
    /// 头像帧传输 seam。默认 BLE；生产实例在 init 里 `installCustomAvatarTransportRouter()`
    /// 换成 WiFi-优先路由（失败自动回退 `bleCustomAvatarFrameSender`）。
    @ObservationIgnored var customAvatarFrameSender: CustomAvatarFrameSender = {
        operationID, avatarID, kriData, progress in
        try await BLEService.shared.sendCustomAvatarKRIFrame(
            operationID: operationID,
            avatarID: avatarID,
            kriData: kriData,
            progress: progress
        )
    }
    /// WiFi(SoftAP) 头像传输编排器（可注入 mock）。
    @ObservationIgnored var wifiAvatarTransport: any WiFiAvatarTransporting = WiFiAvatarTransferService()
    /// WiFi vs BLE 传输偏好。生产 install 时从 UserDefaults 加载；默认 WiFi 优先。
    @ObservationIgnored var avatarTransferPreference: AvatarTransferPreference = .wifiPreferred
    @ObservationIgnored var avatarControlSender: AvatarControlSender = { command in
        try await BLEService.shared.sendAvatarControl(command)
    }
    @ObservationIgnored var taskExternalSyncQueue = KeyedSerialTaskQueue<String>()
    /// Set when the device timezone changes at runtime. UI shows a banner asking the user
    /// whether to re-sync events. Cleared on user action (adjust or keep).
    public var pendingTimezoneChangeName: String? = nil
    /// Tracks which sync sources are currently in-flight to prevent same-source re-entrancy.
    var activeSyncs: Set<ExternalSyncTarget> = []
    public var lastGoogleSyncDebug: String = "Not synced yet"
    public var hasCompletedInitialHomeLoad: Bool = false
    /// In-flight shared-dialogue refresh. Re-entrant callers await it instead of returning
    /// with the stale `currentPetDialogue` — BLE sync once shipped the stale line to hardware,
    /// then re-pushed 3s later when the LLM finished (double E-ink refresh, 2026-07-03联调).
    var dialogueRefreshTask: Task<Void, Never>?
    /// Task version represented by `currentPetDialogue`. BLE may only pair the text with this
    /// exact task version; a mismatch means generation must finish again before 0x10 is sent.
    @ObservationIgnored var currentPetDialogueTaskStateVersion: UInt64?
    /// A force request that arrives while generation is in flight is folded into that same task,
    /// keeping every waiter behind one final dialogue instead of starting a parallel generation.
    @ObservationIgnored var dialogueForceRefreshRequested = false
    @ObservationIgnored var sharedPetDialogueGenerator: SharedPetDialogueGenerator = { context, type in
        await CompanionTextService.shared.generateSharedPetDialogue(
            baseContext: context,
            type: type
        )
    }
    @ObservationIgnored var companionMotionClearTask: Task<Void, Never>?
    /// FocusStatus(0x14) 短窗去重：前台化会被两个观察者（ScreenActivityTracker 打断记录 +
    /// scenePhase.active 状态对齐）各触发一次，同内容背靠背两帧 → 硬件重复刷屏。
    /// 记上一帧摘要+时间，2 秒窗内同内容跳过（2026-07-04 审计 B2）。
    var lastFocusStatusDedupKey: String?
    var lastFocusStatusSentAt: Date?

    // Services
    let syncManager = SyncManager.shared
    let localStorage = LocalStorage.shared
    let petStateService = PetStateService.shared
    let haikuService = HaikuService.shared
    let googleCalendarAPI = GoogleCalendarAPI.shared
    let googleTasksAPI = GoogleTasksAPI.shared
    let googleSyncEngine = GoogleSyncEngine.shared
    let eventKitService = EventKitService.shared
    let appleSyncEngine = AppleSyncEngine.shared
    let notionSyncEngine = NotionSyncEngine.shared
    let taskadeSyncEngine = TaskadeSyncEngine.shared
    #if os(iOS)
    let weatherService = WeatherService.shared
    #endif

    // Managers
    let petManager = PetManager()
    let taskManager = TaskManager()
    let integrationCoordinator = IntegrationCoordinator()

    // Internal coordination state — debounce handle for BLE sync requests.
    var pendingBLESyncTask: Task<Void, Never>?
    var pendingBLESyncTrigger: BLESyncTrigger?
    var pendingBLESyncRequestGeneration: UInt64 = 0
    /// Held across a Complete/Skip presentation so identity/manual PetStatus rounds are not lost
    /// when the ordinary debounced request is cancelled for that atomic DayPack→0x1B window.
    var deferredBLESyncTriggerAfterTaskAction: BLESyncTrigger?
    /// Production runs `BLESyncCoordinator.shared.performSync`. Tests install a no-op so
    /// `AppState.makeForTesting()` cannot open real CoreBluetooth sessions from debounce timers.
    var bleSyncExecutor: (@MainActor (BLESyncTrigger) async -> Void)?
    /// Production waits on the continuous clock. Acceptance scenarios replace this boundary so
    /// stabilization windows can advance without sleeping for wall-clock minutes.
    var bleSyncSleeper: BLESyncSleeper = { duration in
        try await Task.sleep(for: duration)
    }
    @ObservationIgnored var taskLibraryStabilityState = TaskLibraryStabilityState()
    @ObservationIgnored var taskLibraryStabilityTask: Task<Void, Never>?
    @ObservationIgnored var taskLibraryNowProvider: @MainActor () -> Date = { Date() }
    @ObservationIgnored var taskLibraryPhasePreparationTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored var preparedTaskLibraryPhaseTexts: [String: PreparedTaskLibraryPhaseText] = [:]
    @ObservationIgnored var immediateTaskLibraryRemovalMutations: Set<String> = []
    @ObservationIgnored var immediateTaskLibraryQueueReorderMutations: Set<String> = []
    /// Frozen task projection used by DayPack while ordinary task edits are inside the three-minute
    /// stability window. The App shows edits immediately; hardware keeps its previous rows until
    /// the same update becomes eligible for the task-library transaction.
    @ObservationIgnored var taskLibraryHardwareTasksBaseline: [TaskItem]?
    @ObservationIgnored var taskLibraryHardwarePetDialogueBaseline = ""
    @ObservationIgnored var suppressesTaskLibraryChangeTracking = false
    @ObservationIgnored var dailyContentStabilityState = DailyContentStabilityState()
    @ObservationIgnored var dailyContentStabilityTask: Task<Void, Never>?
    @ObservationIgnored var dailyContentNowProvider: @MainActor () -> Date = { Date() }
    @ObservationIgnored var dailyContentCalendarProvider: @MainActor () -> Calendar = {
        Calendar.current
    }
    @ObservationIgnored var dailyContentDayRolloverSleeper: BLESyncSleeper = { duration in
        try await Task.sleep(for: duration)
    }
    @ObservationIgnored var dailyContentDayRolloverTask: Task<Void, Never>?
    @ObservationIgnored var dailyContentObservedDate: DailyContentDate?
    @ObservationIgnored var dailyContentDayRolloverInProgressDate: DailyContentDate?
    @ObservationIgnored var dailyContentDayRefreshExecutor: (@MainActor () async -> Void)?
    /// The last committed schedule projection remains visible while the App accepts new edits.
    @ObservationIgnored var dailyContentHardwareEventsBaseline: [CalendarEvent]?
    @ObservationIgnored var suppressesDailyContentChangeTracking = false
    var externalSyncWaiters: [ExternalSyncTarget: [CheckedContinuation<Void, Never>]] = [:]

    /// 启动本地加载任务句柄；ensureInitialLoadComplete() 等它完成，避免首轮外部同步 / Apple observer
    /// 抢在集成连接状态恢复之前按 defaultIntegrations(Apple=true) 同步、把已断开/已清掉的数据写回。
    private var initialLoadTask: Task<Void, Never>?

    private init(loadLocalDataOnInit: Bool = true) {
        guard loadLocalDataOnInit else { return }
        installCustomAvatarTransportRouter()
        initialLoadTask = Task { @MainActor in
            await loadLocalData(trackTaskChanges: false)
            await restorePendingCustomAvatarOperation()
            BLEService.shared.onAvatarControlResult = { [weak self] result in
                self?.handleAvatarControlResult(result)
            }
            BLEService.shared.onTaskLibraryCommitAcknowledgement = { acknowledgement in
                let destinationID = BLEService.shared.taskListSnapshotDestinationID
                Task { @MainActor in
                    await BLESyncCoordinator.shared.handleTaskLibraryCommitAcknowledgement(
                        acknowledgement,
                        destinationID: destinationID
                    )
                }
            }
            BLEService.shared.onDailyContentCommitAcknowledgement = { acknowledgement in
                let destinationID = BLEService.shared.taskListSnapshotDestinationID
                Task { @MainActor in
                    await BLESyncCoordinator.shared.handleDailyContentCommitAcknowledgement(
                        acknowledgement,
                        destinationID: destinationID
                    )
                }
            }
        }
    }

    /// 等待启动本地加载（含集成连接状态恢复）完成。任何首轮外部同步 / observer 挂载前必须先 await。
    public func ensureInitialLoadComplete() async {
        await initialLoadTask?.value
    }

    static func makeForTesting() -> AppState {
        let state = AppState(loadLocalDataOnInit: false)
        // Debounced requestBLESync must not reach BLESyncCoordinator.shared in unit tests.
        state.bleSyncExecutor = { _ in }
        return state
    }

    func taskMutationGeneration(for taskID: String) -> UInt64 {
        taskMutationGenerations[taskID, default: 0]
    }

    func taskStatusMutationGeneration(for taskID: String) -> UInt64 {
        taskStatusMutationGenerations[taskID, default: 0]
    }

    /// Runs one synchronous hardware-owned task mutation without advancing the App-authoritative
    /// generation. Awaiting work must stay outside this closure.
    func performHardwareTaskMutation(_ mutation: () -> Void) {
        let previous = suppressesTaskMutationTracking
        suppressesTaskMutationTracking = true
        defer { suppressesTaskMutationTracking = previous }
        mutation()
    }

    private func recordTaskMutations(from oldTasks: [TaskItem], to newTasks: [TaskItem]) {
        var oldFingerprints: [String: TaskMutationFingerprint] = [:]
        var newFingerprints: [String: TaskMutationFingerprint] = [:]
        for task in oldTasks {
            oldFingerprints[task.id] = TaskMutationFingerprint(task)
        }
        for task in newTasks {
            newFingerprints[task.id] = TaskMutationFingerprint(task)
        }

        let changedTaskIDs = Set(oldFingerprints.keys).union(newFingerprints.keys)
            .filter { oldFingerprints[$0] != newFingerprints[$0] }
        guard !changedTaskIDs.isEmpty else { return }

        taskStateVersion = taskStateVersion == .max ? .max : taskStateVersion + 1
        guard !suppressesTaskMutationTracking else { return }

        for taskID in changedTaskIDs {
            let current = taskMutationGenerations[taskID, default: 0]
            taskMutationGenerations[taskID] = current == .max ? .max : current + 1

            let oldFingerprint = oldFingerprints[taskID]
            let newFingerprint = newFingerprints[taskID]
            let statusUnchanged = oldFingerprint?.isCompleted == newFingerprint?.isCompleted
                && oldFingerprint?.pendingDeletion == newFingerprint?.pendingDeletion
            guard !statusUnchanged else { continue }
            let statusCurrent = taskStatusMutationGenerations[taskID, default: 0]
            taskStatusMutationGenerations[taskID] = statusCurrent == .max ? .max : statusCurrent + 1
        }
    }

    private func recordTaskLibraryChanges(from oldTasks: [TaskItem], to newTasks: [TaskItem]) {
        let immediateRemovals = immediateTaskLibraryRemovalMutations
        immediateTaskLibraryRemovalMutations.removeAll()
        let immediateQueueReorders = immediateTaskLibraryQueueReorderMutations
        immediateTaskLibraryQueueReorderMutations.removeAll()
        if !immediateRemovals.isEmpty, taskLibraryHardwareTasksBaseline != nil {
            taskLibraryHardwareTasksBaseline?.removeAll {
                immediateRemovals.contains($0.hardwareIdentifier)
            }
        }
        if !immediateQueueReorders.isEmpty,
           var baseline = taskLibraryHardwareTasksBaseline {
            for taskID in immediateQueueReorders.sorted() {
                guard let index = baseline.firstIndex(where: {
                    $0.hardwareIdentifier == taskID
                }) else { continue }
                baseline.append(baseline.remove(at: index))
            }
            taskLibraryHardwareTasksBaseline = baseline
        }
        let alreadyHadStableChanges = !taskLibraryStabilityState.stableTaskIDs.isEmpty
        let recordedStableChanges = taskLibraryStabilityState.recordTaskChanges(
            from: oldTasks,
            to: newTasks,
            at: taskLibraryNowProvider(),
            calendar: dailyContentCalendarProvider(),
            immediateRemovalTaskIDs: immediateRemovals,
            immediateQueueReorderTaskIDs: immediateQueueReorders
        )
        if recordedStableChanges, !alreadyHadStableChanges {
            taskLibraryHardwareTasksBaseline = oldTasks.filter {
                !immediateRemovals.contains($0.hardwareIdentifier)
            }
            if !immediateQueueReorders.isEmpty,
               var baseline = taskLibraryHardwareTasksBaseline {
                for taskID in immediateQueueReorders.sorted() {
                    guard let index = baseline.firstIndex(where: {
                        $0.hardwareIdentifier == taskID
                    }) else { continue }
                    baseline.append(baseline.remove(at: index))
                }
                taskLibraryHardwareTasksBaseline = baseline
            }
            taskLibraryHardwarePetDialogueBaseline = currentPetDialogue
        }
        if !immediateQueueReorders.isEmpty {
            taskLibraryStabilityState.promoteImmediateHardwareQueueUpdate()
        }
        guard recordedStableChanges || !immediateQueueReorders.isEmpty else { return }
        persistTaskLibraryStabilityCheckpoint()
        scheduleTaskLibraryStabilityDeadline()
        if !immediateQueueReorders.isEmpty {
            requestBLESync(reason: "taskLibraryHardwareQueue", debounce: .zero)
        }
    }

    private func recordTaskLibraryPersonaChange(
        oldProfile: UserProfile,
        oldCustomCompanions: [CustomCompanion],
        newProfile: UserProfile,
        newCustomCompanions: [CustomCompanion]
    ) {
        guard !taskLibraryStabilityState.stableTaskIDs.isEmpty else { return }
        let oldPersona = TaskLibraryPhaseSourceFingerprint.persona(
            userProfile: oldProfile,
            customCompanions: oldCustomCompanions
        )
        let newPersona = TaskLibraryPhaseSourceFingerprint.persona(
            userProfile: newProfile,
            customCompanions: newCustomCompanions
        )
        guard oldPersona != newPersona else { return }
        prepareChangedTaskLibraryPhaseTexts(from: [], to: tasks)
        persistTaskLibraryStabilityCheckpoint()
    }

    private func recordDailyContentChanges(
        from oldEvents: [CalendarEvent],
        to newEvents: [CalendarEvent]
    ) {
        let hadPendingChanges = !dailyContentStabilityState.changedEventIDs.isEmpty
        guard dailyContentStabilityState.recordChanges(
            from: oldEvents,
            to: newEvents,
            at: dailyContentNowProvider()
        ) else { return }
        if !hadPendingChanges {
            dailyContentHardwareEventsBaseline = oldEvents
        }
        persistDailyContentStabilityCheckpoint()
        scheduleDailyContentStabilityDeadline()
    }

    func persistTaskLibraryStabilityCheckpoint() {
        guard !taskLibraryStabilityState.stableTaskIDs.isEmpty
                || !taskLibraryStabilityState.urgentRemovalTaskIDs.isEmpty
                || taskLibraryStabilityState.hasUrgentHardwareQueueUpdate
                || taskLibraryStabilityState.hasUrgentCompleteUpdate else {
            LocalStorage.clearTaskLibraryStabilityCheckpoint()
            return
        }
        do {
            try LocalStorage.saveTaskLibraryStabilityCheckpoint(
                TaskLibraryStabilityCheckpoint(
                    state: taskLibraryStabilityState,
                    hardwareTasksBaseline: taskLibraryHardwareTasksBaseline,
                    hardwarePetDialogueBaseline: taskLibraryHardwarePetDialogueBaseline,
                    sourceFingerprint: TaskLibrarySourceFingerprint.make(
                        tasks: tasks,
                        userProfile: userProfile,
                        customCompanions: customCompanions,
                        now: taskLibraryNowProvider(),
                        calendar: dailyContentCalendarProvider()
                    ),
                    sourceDay: DailyContentDate(
                        date: taskLibraryNowProvider(),
                        calendar: dailyContentCalendarProvider()
                    )
                )
            )
        } catch {
            ErrorReporter.log(error, context: "AppState.persistTaskLibraryStabilityCheckpoint")
        }
    }

    func persistDailyContentStabilityCheckpoint() {
        guard !dailyContentStabilityState.changedEventIDs.isEmpty else {
            LocalStorage.clearDailyContentStabilityCheckpoint()
            return
        }
        do {
            try LocalStorage.saveDailyContentStabilityCheckpoint(
                DailyContentStabilityCheckpoint(
                    state: dailyContentStabilityState,
                    hardwareEventsBaseline: dailyContentHardwareEventsBaseline,
                    sourceFingerprint: DailyContentSource.sourceFingerprint(
                        events: events,
                        at: dailyContentNowProvider(),
                        userProfile: userProfile,
                        customCompanions: customCompanions
                    )
                )
            )
        } catch {
            ErrorReporter.log(error, context: "AppState.persistDailyContentStabilityCheckpoint")
        }
    }

    func restoreDailyContentStabilityCheckpoint() {
        do {
            guard let checkpoint = try LocalStorage.loadDailyContentStabilityCheckpoint() else {
                return
            }
            let currentFingerprint = DailyContentSource.sourceFingerprint(
                events: events,
                at: dailyContentNowProvider(),
                userProfile: userProfile,
                customCompanions: customCompanions
            )
            guard checkpoint.sourceFingerprint == currentFingerprint else {
                LocalStorage.clearDailyContentStabilityCheckpoint()
                return
            }
            dailyContentStabilityState = checkpoint.state
            dailyContentHardwareEventsBaseline = checkpoint.hardwareEventsBaseline
            if dailyContentStabilityState.readyGeneration(
                at: dailyContentNowProvider()
            ) != nil {
                requestBLESync(reason: "restoredDailyContentUpdate", debounce: .zero)
            } else {
                scheduleDailyContentStabilityDeadline()
            }
        } catch {
            LocalStorage.clearDailyContentStabilityCheckpoint()
            ErrorReporter.log(error, context: "AppState.restoreDailyContentStabilityCheckpoint")
        }
    }

    func restoreTaskLibraryStabilityCheckpoint() {
        do {
            guard let checkpoint = try LocalStorage.loadTaskLibraryStabilityCheckpoint() else {
                return
            }
            guard applyTaskLibraryStabilityCheckpoint(checkpoint) else {
                LocalStorage.clearTaskLibraryStabilityCheckpoint()
                return
            }
        } catch {
            LocalStorage.clearTaskLibraryStabilityCheckpoint()
            ErrorReporter.log(error, context: "AppState.restoreTaskLibraryStabilityCheckpoint")
        }
    }

    @discardableResult
    func applyTaskLibraryStabilityCheckpoint(
        _ checkpoint: TaskLibraryStabilityCheckpoint
    ) -> Bool {
        let now = taskLibraryNowProvider()
        let calendar = dailyContentCalendarProvider()
        let today = DailyContentDate(date: now, calendar: calendar)
        if checkpoint.sourceDay != today {
            // 跨日失配不是「源已变 → 丢弃」：窗内的编辑都活在 tasks.json 里，整库重算是它们的
            // 超集。立即就绪一次 complete 重算，不静默丢弃重启前的待发意图。
            invalidateTaskLibraryWindowForNewLocalDay()
            return true
        }
        let currentFingerprint = TaskLibrarySourceFingerprint.make(
            tasks: tasks,
            userProfile: userProfile,
            customCompanions: customCompanions,
            now: now,
            calendar: calendar
        )
        guard checkpoint.sourceFingerprint == currentFingerprint else { return false }
        taskLibraryStabilityState = checkpoint.state
        taskLibraryHardwareTasksBaseline = checkpoint.hardwareTasksBaseline
        taskLibraryHardwarePetDialogueBaseline = checkpoint.hardwarePetDialogueBaseline
        prepareChangedTaskLibraryPhaseTexts(
            from: checkpoint.hardwareTasksBaseline ?? tasks,
            to: tasks
        )
        if taskLibraryStabilityState.readyScope(at: taskLibraryNowProvider()) != nil {
            requestBLESync(reason: "restoredTaskLibraryUpdate", debounce: .zero)
        } else {
            scheduleTaskLibraryStabilityDeadline()
        }
        return true
    }

    private func prepareChangedTaskLibraryPhaseTexts(
        from oldTasks: [TaskItem],
        to newTasks: [TaskItem]
    ) {
        let now = taskLibraryNowProvider()
        let calendar = dailyContentCalendarProvider()
        var oldByID: [String: TaskItem] = [:]
        var newByID: [String: TaskItem] = [:]
        for task in oldTasks where oldByID[task.hardwareIdentifier] == nil {
            oldByID[task.hardwareIdentifier] = task
        }
        for task in newTasks where newByID[task.hardwareIdentifier] == nil {
            newByID[task.hardwareIdentifier] = task
        }
        let allIDs = Set(oldByID.keys).union(newByID.keys)
        // 本函数刻意用**两套口径**，别当成不一致给"修"掉：
        //  · 驱逐（取消在途生成 + 删缓存）用未截断的 isEligibleForHardwareTaskLibrary——只有任务
        //    真的离开今天才该丢弃已烧的 token。用 20 条口径的话，一次插入把第 20 条挤到第 21 位
        //    就会杀掉它的在途 LLM 请求，用户再删一条又要重烧。
        //  · 点火（决定要不要生成）用截断后的成员集——上不了 wire 的不烧配额。
        let memberIDs = TaskLibraryMembership.memberIDs(of: newTasks, on: now, calendar: calendar)
        let oldMemberIDs = TaskLibraryMembership.memberIDs(of: oldTasks, on: now, calendar: calendar)
        for taskID in allIDs {
            guard let task = newByID[taskID],
                  task.isEligibleForHardwareTaskLibrary(on: now, calendar: calendar) else {
                taskLibraryPhasePreparationTasks[taskID]?.cancel()
                taskLibraryPhasePreparationTasks.removeValue(forKey: taskID)
                preparedTaskLibraryPhaseTexts.removeValue(forKey: taskID)
                continue
            }
            // 被 20 条上限挤出去：不点火，但**不驱逐**——它回到前 20 时能直接复用已有缓存。
            guard memberIDs.contains(taskID) else { continue }
            let oldTask = oldByID[taskID]
            // 进入设备成员集（手动设为今天 / 改期到今天 / 前面的任务腾位后被提拔进前 20）与新增
            // 任务同构：立即点火文案准备，与 180 秒稳定窗并行，窗到期时大概率已就绪。
            let enteredLibrary = oldTask.map { _ in !oldMemberIDs.contains(taskID) } ?? false
            guard oldTask == nil
                    || enteredLibrary
                    || oldTask?.title != task.title
                    || oldTask?.notes != task.notes else {
                continue
            }
            let fingerprint = TaskLibraryPhaseSourceFingerprint.make(
                task: task,
                userProfile: userProfile,
                customCompanions: customCompanions
            )
            taskLibraryPhasePreparationTasks[taskID]?.cancel()
            taskLibraryPhasePreparationTasks[taskID] = Task { @MainActor [weak self] in
                guard let self else { return }
                let prepared = await TaskLibraryPhaseTextService.shared.prepare(
                    tasks: [task],
                    userProfile: userProfile,
                    customCompanions: customCompanions,
                    now: now,
                    calendar: calendar
                )
                guard !Task.isCancelled,
                      let current = tasks.first(where: { $0.hardwareIdentifier == taskID }),
                      TaskLibraryPhaseSourceFingerprint.make(
                        task: current,
                        userProfile: userProfile,
                        customCompanions: customCompanions
                      ) == fingerprint else {
                    return
                }
                if let texts = prepared[taskID] {
                    preparedTaskLibraryPhaseTexts[taskID] = PreparedTaskLibraryPhaseText(
                        fingerprint: fingerprint,
                        texts: texts
                    )
                }
                taskLibraryPhasePreparationTasks.removeValue(forKey: taskID)
            }
        }
    }

}

struct PreparedTaskLibraryPhaseText: Sendable, Equatable {
    let fingerprint: String
    let texts: TaskLibraryPhaseTexts
}

private struct TaskMutationFingerprint: Equatable {
    let title: String
    let isCompleted: Bool
    let dueDate: Date?
    let priority: TaskPriority
    let pendingDeletion: Bool
    let lastModified: Date
    let notes: String?
    let todayDisplayDate: Date?
    let hardwareCompletionOperationKey: String?
    let hardwareSkipOperationKey: String?
    let statusAuthorityAt: Date?

    init(_ task: TaskItem) {
        title = task.title
        isCompleted = task.isCompleted
        dueDate = task.dueDate
        priority = task.priority
        pendingDeletion = task.pendingDeletion
        lastModified = task.lastModified
        notes = task.notes
        todayDisplayDate = task.todayDisplayDate
        hardwareCompletionOperationKey = task.hardwareCompletionOperationKey
        hardwareSkipOperationKey = task.hardwareSkipOperationKey
        statusAuthorityAt = task.statusAuthorityAt
    }
}

// MARK: - Persistence Helpers

extension AppState {
    func persistTaskAndPetState(tasks: [TaskItem], pet: Pet, context: String) async {
        do {
            try await localStorage.saveTasks(tasks)
            try await localStorage.savePet(pet)
        } catch {
            reportPersistenceError(error, operation: "save", target: "tasks/pet")
            ErrorReporter.log(error, context: context)
        }
    }

    func persistPet(_ pet: Pet, context: String) async {
        do {
            try await localStorage.savePet(pet)
        } catch {
            reportPersistenceError(error, operation: "save", target: "pet.json")
            ErrorReporter.log(error, context: context)
        }
    }

    func persistTasks(_ tasks: [TaskItem], context: String) async {
        do {
            try await localStorage.saveTasks(tasks)
        } catch {
            reportPersistenceError(error, operation: "save", target: "tasks.json")
            ErrorReporter.log(error, context: context)
        }
    }

    func persistEvents(_ events: [CalendarEvent], context: String) async {
        do {
            try await localStorage.saveEvents(events)
        } catch {
            reportPersistenceError(error, operation: "save", target: "events.json")
            ErrorReporter.log(error, context: context)
        }
    }
}

// MARK: - Default Integrations

extension Integration {
    public static var defaultIntegrations: [Integration] {
        [
            Integration(name: "Apple Calendar", iconName: "calendar", isConnected: true, type: .appleCalendar),
            Integration(name: "Apple Reminders", iconName: "checklist", isConnected: true, type: .appleReminders),
            Integration(name: "Google Calendar", iconName: "calendar.badge.clock", isConnected: false, type: .googleCalendar),
            Integration(name: "Google Tasks", iconName: "checkmark.circle", isConnected: false, type: .googleTasks),
            Integration(name: "Todoist", iconName: "checklist.checked", isConnected: false, type: .todoist),
            Integration(name: "Notion", iconName: "doc.text", isConnected: false, type: .notion),
            Integration(name: "Taskade", iconName: "list.bullet.rectangle", isConnected: false, type: .taskade)
        ]
    }
}
