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

    // Haiku
    public var currentHaiku: Haiku = .placeholder

    // Integrations
    public var integrations: [Integration] = Integration.defaultIntegrations

    // User Profile
    public var userProfile: UserProfile = .default

    // Onboarding Profile
    public var onboardingProfile: OnboardingProfile?

    // Device Mode
    public var deviceMode: DeviceMode = .interactive
    public var isDemoMode: Bool = false

    // UI State
    public var selectedEvent: CalendarEvent?
    public var isEventDetailPresented: Bool = false
    public var showEvolutionAnimation: Bool = false
    public var evolutionFromStage: PetStage?
    public var evolutionToStage: PetStage?

    // Loading State
    public var isLoading: Bool = false
    public var lastError: String?
    public var lastGoogleSyncDebug: String = "Not synced yet"
    public var hasCompletedInitialHomeLoad: Bool = false

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
    let widgetDataService = WidgetDataService.shared

    // Managers
    let petManager = PetManager()
    let taskManager = TaskManager()
    let integrationCoordinator = IntegrationCoordinator()

    private init() {
        Task { @MainActor in
            await loadLocalData()
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
            Integration(name: "Todoist", iconName: "checklist.checked", isConnected: false, type: .todoist)
        ]
    }
}
