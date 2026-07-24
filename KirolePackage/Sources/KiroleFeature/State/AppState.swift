import SwiftUI

// MARK: - Constants

enum ProgressConstants {
    static let pointsPerTask: Int = 10
}

typealias CompanionIdentityStatusSender = @MainActor (
    Pet, CompanionCharacter, Bool
) async throws -> Void

typealias CustomAvatarConnectionProvider = @MainActor () -> (isConnected: Bool, deviceID: UUID?)
typealias CustomAvatarFrameSender = @MainActor (
    UInt32,
    UUID,
    Data,
    @escaping @MainActor @Sendable (Int, Int) -> Void
) async throws -> Void
typealias AvatarControlSender = @MainActor (AvatarControlCommand) async throws -> Void

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
    public var events: [CalendarEvent] = []
    public var tasks: [TaskItem] = []
    public var statistics: TaskStatistics = TaskStatistics()

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
    public var userProfile: UserProfile = .default
    /// User-created companions (4th option alongside Joy/Silas/Nova).
    /// Loaded from disk on app start; mutated through AppState+Companion methods.
    public var customCompanions: [CustomCompanion] = []

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
    /// Serializes immediate identity-status frames so rapid companion switches cannot finish
    /// out of order and leave hardware showing an older identity.
    @ObservationIgnored var companionIdentityStatusSendTask: Task<Void, Never>?
    @ObservationIgnored var companionIdentityStatusSender: CompanionIdentityStatusSender = {
        pet, character, customActive in
        guard BLEService.shared.connectionState.isConnected else { return }
        try await BLEService.shared.sendPetStatus(
            pet, companionCharacter: character, customActive: customActive
        )
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

    /// 启动本地加载任务句柄；ensureInitialLoadComplete() 等它完成，避免首轮外部同步 / Apple observer
    /// 抢在集成连接状态恢复之前按 defaultIntegrations(Apple=true) 同步、把已断开/已清掉的数据写回。
    private var initialLoadTask: Task<Void, Never>?

    private init(loadLocalDataOnInit: Bool = true) {
        guard loadLocalDataOnInit else { return }
        installCustomAvatarTransportRouter()
        initialLoadTask = Task { @MainActor in
            await loadLocalData()
            await restorePendingCustomAvatarOperation()
            BLEService.shared.onAvatarControlResult = { [weak self] result in
                self?.handleAvatarControlResult(result)
            }
        }
    }

    /// 等待启动本地加载（含集成连接状态恢复）完成。任何首轮外部同步 / observer 挂载前必须先 await。
    public func ensureInitialLoadComplete() async {
        await initialLoadTask?.value
    }

    static func makeForTesting() -> AppState {
        AppState(loadLocalDataOnInit: false)
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
