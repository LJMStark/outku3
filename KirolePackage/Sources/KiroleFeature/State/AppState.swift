import SwiftUI

// MARK: - Constants

private enum ProgressConstants {
    static let taskCompletionIncrement: Double = 0.02  // 2% progress per task
    static let pointsPerTask: Int = 10  // Base points per task completion
}

private enum EvolutionMultipliers {
    static let weight: Double = 1.2       // 20% increase per evolution
    static let height: Double = 1.15      // 15% increase per evolution
    static let tailLength: Double = 1.1   // 10% increase per evolution
}

// MARK: - App State

@Observable
public final class AppState: @unchecked Sendable {
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

    // Services
    private let syncManager = SyncManager.shared
    private let localStorage = LocalStorage.shared
    private let petStateService = PetStateService.shared
    private let haikuService = HaikuService.shared
    private let googleCalendarAPI = GoogleCalendarAPI.shared
    private let googleTasksAPI = GoogleTasksAPI.shared
    private let googleSyncEngine = GoogleSyncEngine.shared
    private let eventKitService = EventKitService.shared
    private let appleSyncEngine = AppleSyncEngine.shared
    private let widgetDataService = WidgetDataService.shared
    private let cloudKitService = CloudKitService.shared

    private init() {
        Task { @MainActor in
            await loadLocalData()
        }
    }

    // MARK: - Task Filtering

    public func tasksForToday() -> [TaskItem] {
        tasks.filter { $0.dueDate.map { Calendar.current.isDateInToday($0) } ?? false }
    }

    public func completedTasksForToday() -> [TaskItem] {
        tasksForToday().filter { $0.isCompleted }
    }

    // MARK: - Data Loading

    @MainActor
    private func loadLocalData() async {
        if let savedPet = try? await localStorage.loadPet() {
            pet = savedPet
        } else {
            pet = Pet(
                name: "Baby Waffle",
                pronouns: .theyThem,
                adventuresCount: 0,
                age: 0,
                status: .happy,
                mood: .happy,
                scene: .indoor,
                stage: .baby,
                progress: 0,
                weight: 50,
                height: 5.0,
                tailLength: 2.0,
                lastInteraction: Date(),
                points: 0
            )
        }

        if let savedStreak = try? await localStorage.loadStreak() {
            streak = savedStreak
        }

        if let savedTasks = try? await localStorage.loadTasks() {
            tasks = savedTasks
        }

        if let savedEvents = try? await localStorage.loadEvents() {
            events = savedEvents
        }

        if let savedProfile = try? await localStorage.loadUserProfile() {
            userProfile = savedProfile
        }

        if let savedOnboardingProfile = try? await localStorage.loadOnboardingProfile() {
            onboardingProfile = savedOnboardingProfile
        }

        await updatePetState()
        updateStatistics()
    }

    @MainActor
    public func refreshData(userId: String?) async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        // Supabase sync
        if let userId = userId {
            let result = await syncManager.performFullSync(userId: userId)
            if case .partial(_, let failed) = result, failed > 0 {
                lastError = "Some data failed to sync"
            } else if case .failure(let error) = result {
                lastError = error.localizedDescription
            }
        }

        // CloudKit sync
        await syncWithCloudKit()

        await loadLocalData()
    }

    @MainActor
    public func syncWithCloudKit() async {
        do {
            // Sync pet data
            let syncedPet = try await cloudKitService.syncPet(local: pet)
            pet = syncedPet
            try? await localStorage.savePet(pet)

            // Sync streak data
            let syncedStreak = try await cloudKitService.syncStreak(local: streak)
            streak = syncedStreak
            try? await localStorage.saveStreak(streak)
        } catch {
            // CloudKit sync is optional, don't show error to user
        }
    }

    @MainActor
    private func updatePetState() async {
        let completedToday = completedTasksForToday().count
        let totalToday = tasksForToday().count

        pet.mood = await petStateService.calculateMood(
            lastInteraction: pet.lastInteraction,
            tasksCompletedToday: completedToday,
            totalTasksToday: totalToday
        )

        pet.scene = await petStateService.calculateScene(
            currentTime: Date(),
            hasTasks: totalToday > completedToday
        )
    }

    private func updateStatistics() {
        let calendar = Calendar.current
        let today = Date()

        let todayTasks = tasksForToday()
        let todayCompleted = todayTasks.filter { $0.isCompleted }.count

        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        let weekTasks = tasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return dueDate >= weekStart && dueDate <= today
        }
        let weekCompleted = weekTasks.filter { $0.isCompleted }.count

        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: today)!
        let monthTasks = tasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return dueDate >= thirtyDaysAgo && dueDate <= today
        }
        let monthCompleted = monthTasks.filter { $0.isCompleted }.count

        statistics = TaskStatistics(
            todayCompleted: todayCompleted,
            todayTotal: todayTasks.count,
            pastWeekCompleted: weekCompleted,
            pastWeekTotal: weekTasks.count,
            last30DaysCompleted: monthCompleted,
            last30DaysTotal: monthTasks.count
        )

        // Update widget data
        widgetDataService.updateFromAppState(pet: pet, streak: streak, statistics: statistics)
    }

    @MainActor
    public func loadTodayHaiku() async {
        let context = HaikuContext(
            currentTime: Date(),
            tasksCompletedToday: statistics.todayCompleted,
            totalTasksToday: statistics.todayTotal,
            petMood: pet.mood,
            currentStreak: streak.currentStreak
        )
        currentHaiku = await haikuService.getTodayHaiku(context: context)
    }

    // MARK: - Google APIs Integration

    @MainActor
    public func loadGoogleCalendarEvents() async {
        await syncGoogleData()
    }

    @MainActor
    public func loadGoogleTasks() async {
        await syncGoogleData()
    }

    @MainActor
    public func syncGoogleData() async {
        guard AuthManager.shared.isGoogleConnected else { return }

        do {
            let googleEvents = events.filter { $0.source == .google }
            let googleTasks = tasks.filter { $0.source == .google }

            let (syncedEvents, syncedTasks) = try await googleSyncEngine.performFullSync(
                currentEvents: googleEvents,
                currentTasks: googleTasks
            )

            // Merge: keep non-google items, add synced google items
            let nonGoogleEvents = events.filter { $0.source != .google }
            events = nonGoogleEvents + syncedEvents

            let nonGoogleTasks = tasks.filter { $0.source != .google }
            tasks = nonGoogleTasks + syncedTasks

            updateStatistics()
            try await localStorage.saveEvents(events)
            try await localStorage.saveTasks(tasks)
        } catch {
            print("Google sync error: \(error)")
            lastError = error.localizedDescription
        }

        await updatePetState()
    }

    // MARK: - Apple EventKit Integration

    @MainActor
    private func isIntegrationConnected(_ type: IntegrationType) -> Bool {
        integrations.first(where: { $0.type == type })?.isConnected == true
    }

    @MainActor
    public var isAnyAppleIntegrationConnected: Bool {
        isIntegrationConnected(.appleCalendar) || isIntegrationConnected(.appleReminders)
    }

    @MainActor
    public func loadAppleCalendarEvents() async {
        guard isIntegrationConnected(.appleCalendar) else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: Date())
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            let appleEvents = try await appleSyncEngine.fetchCalendarEvents(from: startOfDay, to: endOfDay)
            let otherEvents = events.filter { $0.source != .apple }
            events = otherEvents + appleEvents
            try? await localStorage.saveEvents(events)
        } catch {
            lastError = "Failed to load Apple Calendar: \(error.localizedDescription)"
        }
    }

    @MainActor
    public func loadAppleReminders() async {
        guard isIntegrationConnected(.appleReminders) else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let appleTasks = tasks.filter { $0.source == .apple }
            let syncedTasks = try await appleSyncEngine.syncReminders(currentTasks: appleTasks)
            let otherTasks = tasks.filter { $0.source != .apple }
            tasks = otherTasks + syncedTasks
            try? await localStorage.saveTasks(tasks)
            updateStatistics()
        } catch {
            lastError = "Failed to load Apple Reminders: \(error.localizedDescription)"
        }
    }

    @MainActor
    public func syncAppleData() async {
        let shouldSyncCalendar = isIntegrationConnected(.appleCalendar)
        let shouldSyncReminders = isIntegrationConnected(.appleReminders)

        if shouldSyncCalendar {
            await loadAppleCalendarEvents()
        }

        if shouldSyncReminders {
            await loadAppleReminders()
        }

        await updatePetState()
    }

    @MainActor
    public func requestAppleCalendarAccess() async -> Bool {
        await eventKitService.requestCalendarAccess()
    }

    @MainActor
    public func requestAppleRemindersAccess() async -> Bool {
        await eventKitService.requestRemindersAccess()
    }

    @MainActor
    public func setupAppleChangeObserver() async {
        await appleSyncEngine.startObservingChanges { [weak self] in
            await self?.syncAppleData()
        }
    }

    // MARK: - Actions

    @MainActor
    public func toggleTaskCompletion(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }

        let original = tasks[index]
        var updatedTask = original
        updatedTask.isCompleted.toggle()
        updatedTask.lastModified = Date()
        tasks[index] = updatedTask
        let isCompleted = updatedTask.isCompleted

        // Play sound and haptic feedback
        if isCompleted {
            SoundService.shared.playWithHaptic(.taskComplete, haptic: .success)
            pet.adventuresCount += 1
            pet.progress = min(1.0, pet.progress + ProgressConstants.taskCompletionIncrement)
            pet.points += ProgressConstants.pointsPerTask
            updateStreak()
        } else {
            SoundService.shared.playWithHaptic(.taskUncomplete, haptic: .light)
            pet.adventuresCount = max(0, pet.adventuresCount - 1)
            pet.progress = max(0, pet.progress - ProgressConstants.taskCompletionIncrement)
            pet.points = max(0, pet.points - ProgressConstants.pointsPerTask)
        }

        pet.lastInteraction = Date()
        updateStatistics()

        // Check for evolution
        if isCompleted {
            Task { @MainActor in
                await checkAndTriggerEvolution()
            }
        }

        Task {
            try? await localStorage.saveTasks(tasks)
            try? await localStorage.savePet(pet)
            try? await localStorage.saveStreak(streak)

            // Sync to external services
            switch updatedTask.source {
            case .google:
                await googleSyncEngine.enqueueChange(task: updatedTask, action: .updateStatus)
                try? await googleTasksAPI.syncTaskCompletion(updatedTask)
            case .apple:
                do {
                    try await appleSyncEngine.pushReminderUpdate(updatedTask)
                } catch {
                    print("Apple Reminders sync error: \(error)")
                }
            default:
                break
            }
        }

        Task { @MainActor in
            await updatePetState()
        }

        if isCompleted {
            Task { @MainActor in
                currentHaiku = await haikuService.generateCompletionHaiku(
                    tasksCompleted: statistics.todayCompleted,
                    totalTasks: statistics.todayTotal,
                    petMood: pet.mood,
                    streak: streak.currentStreak
                )
            }
        }
    }

    private func updateStreak() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if let lastActive = streak.lastActiveDate {
            let lastActiveDay = calendar.startOfDay(for: lastActive)

            if calendar.isDate(lastActiveDay, inSameDayAs: today) {
                return
            } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                      calendar.isDate(lastActiveDay, inSameDayAs: yesterday) {
                streak.currentStreak += 1
            } else {
                streak.currentStreak = 1
            }
        } else {
            streak.currentStreak = 1
        }

        streak.lastActiveDate = today
        streak.longestStreak = max(streak.longestStreak, streak.currentStreak)
    }

    public func selectEvent(_ event: CalendarEvent) {
        selectedEvent = event
        isEventDetailPresented = true
    }

    public func dismissEventDetail() {
        isEventDetailPresented = false
        selectedEvent = nil
    }

    public func setPetForm(_ form: PetForm) {
        pet.currentForm = form
        Task {
            try? await localStorage.savePet(pet)
        }
    }

    @MainActor
    public func addTask(_ task: TaskItem) {
        tasks.append(task)
        updateStatistics()
        Task {
            try? await localStorage.saveTasks(tasks)
        }
    }

    @MainActor
    public func deleteTask(_ task: TaskItem) {
        tasks.removeAll { $0.id == task.id }
        updateStatistics()
        Task {
            try? await localStorage.saveTasks(tasks)
        }
    }

    @MainActor
    public func updateEvents(_ newEvents: [CalendarEvent]) {
        events = newEvents
        Task {
            try? await localStorage.saveEvents(events)
        }
    }

    @MainActor
    public func updateTasks(_ newTasks: [TaskItem]) {
        tasks = newTasks
        updateStatistics()
        Task {
            try? await localStorage.saveTasks(tasks)
        }
    }

    // MARK: - Evolution

    @MainActor
    private func checkAndTriggerEvolution() async {
        let canEvolve = await petStateService.canEvolve(pet: pet)
        guard canEvolve, let nextStage = pet.stage.nextStage else { return }

        evolutionFromStage = pet.stage
        evolutionToStage = nextStage
        showEvolutionAnimation = true
    }

    @MainActor
    public func completeEvolution() {
        guard let toStage = evolutionToStage else { return }

        pet.stage = toStage
        pet.progress = 0.0
        pet.weight *= EvolutionMultipliers.weight
        pet.height *= EvolutionMultipliers.height
        pet.tailLength *= EvolutionMultipliers.tailLength

        showEvolutionAnimation = false
        evolutionFromStage = nil
        evolutionToStage = nil

        Task {
            try? await localStorage.savePet(pet)
        }
    }

    @MainActor
    public func dismissEvolution() {
        showEvolutionAnimation = false
        evolutionFromStage = nil
        evolutionToStage = nil
    }

    // MARK: - Integration Management

    @MainActor
    public func updateIntegrationStatus(_ type: IntegrationType, isConnected: Bool) {
        if let index = integrations.firstIndex(where: { $0.type == type }) {
            integrations[index].isConnected = isConnected
        } else if isConnected {
            integrations.append(Integration(
                name: type.rawValue,
                iconName: type.iconName,
                isConnected: true,
                type: type
            ))
        }

        // Clean up data when disconnecting Apple integrations
        if !isConnected {
            switch type {
            case .appleCalendar:
                events = events.filter { $0.source != .apple }
                Task { try? await localStorage.saveEvents(events) }
            case .appleReminders:
                tasks = tasks.filter { $0.source != .apple }
                updateStatistics()
                Task {
                    try? await localStorage.saveTasks(tasks)
                }
            default:
                break
            }
        }

        if type == .appleCalendar || type == .appleReminders {
            if isAnyAppleIntegrationConnected {
                if isConnected {
                    Task { @MainActor in
                        await setupAppleChangeObserver()
                    }
                }
            } else {
                Task {
                    await appleSyncEngine.stopObservingChanges()
                }
            }
        }
    }

    // MARK: - User Profile Management

    @MainActor
    public func updateUserProfile(_ profile: UserProfile) {
        userProfile = profile
        Task {
            try? await localStorage.saveUserProfile(profile)
        }
    }

    @MainActor
    public func completeOnboarding(with profile: OnboardingProfile) {
        var completedProfile = profile
        completedProfile.onboardingCompletedAt = Date()
        onboardingProfile = completedProfile
        Task {
            try? await localStorage.saveOnboardingProfile(completedProfile)
        }
    }

    public var isOnboardingCompleted: Bool {
        onboardingProfile?.onboardingCompletedAt != nil || userProfile.onboardingCompletedAt != nil
    }

    @MainActor
    public func resetOnboarding() async {
        onboardingProfile = nil
        userProfile.onboardingCompletedAt = nil
        do {
            try await localStorage.deleteFile(named: "onboarding_profile.json")
            try await localStorage.saveUserProfile(userProfile)
        } catch {
            print("[AppState] Failed to reset onboarding: \(error)")
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
