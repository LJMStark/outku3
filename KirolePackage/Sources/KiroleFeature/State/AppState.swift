import SwiftUI

// MARK: - Constants

enum ProgressConstants {
    static let taskCompletionIncrement: Double = 0.02
    static let pointsPerTask: Int = 10
}

enum EvolutionMultipliers {
    static let weight: Double = 1.2
    static let height: Double = 1.15
    static let tailLength: Double = 1.1
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
    public var streak: Streak = Streak(currentStreak: 0)

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

    // Integrations
    public var integrations: [Integration] = Integration.defaultIntegrations

    // User Profile
    public var userProfile: UserProfile = .default

    // Onboarding Profile
    public var onboardingProfile: OnboardingProfile?

    // Device Mode
    public var deviceMode: DeviceMode = .interactive
    public var focusEnforcementMode: FocusEnforcementMode = .standard
    public var isDemoMode: Bool = false

    // UI State
    public var selectedEvent: CalendarEvent?
    public var isEventDetailPresented: Bool = false
    public var showEvolutionAnimation: Bool = false
    public var evolutionFromStage: PetStage?
    public var evolutionToStage: PetStage?

    /// 最近一次的"场景解锁庆祝"信号；HomeView onChange 时炸 confetti + 展示横幅，
    /// ~3s 后由 UI 层置回 nil。nil = 当前没有待展示的庆祝。
    public var pendingSceneCelebration: SceneCelebration?

    // Loading State
    public var isLoading: Bool = false
    public var lastError: String?
    /// Tracks which sync sources are currently in-flight to prevent same-source re-entrancy.
    var activeSyncs: Set<ExternalSyncTarget> = []
    public var lastGoogleSyncDebug: String = "Not synced yet"
    public var hasCompletedInitialHomeLoad: Bool = false
    /// Prevents concurrent dialogue generation (multiple sync callbacks triggering at once).
    var isRefreshingDialogue: Bool = false

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
    let widgetDataService = WidgetDataService.shared
    #if os(iOS)
    let weatherService = WeatherService.shared
    #endif

    // Managers
    let petManager = PetManager()
    let taskManager = TaskManager()
    let integrationCoordinator = IntegrationCoordinator()

    private init(loadLocalDataOnInit: Bool = true) {
        guard loadLocalDataOnInit else { return }
        Task { @MainActor in
            await loadLocalData()
        }
    }

    static func makeForTesting() -> AppState {
        AppState(loadLocalDataOnInit: false)
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
