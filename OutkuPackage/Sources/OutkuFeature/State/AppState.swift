import SwiftUI

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

    // UI State
    public var selectedEvent: CalendarEvent?
    public var isEventDetailPresented: Bool = false

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

    private init() {
        // 初始化时加载本地数据
        Task { @MainActor in
            await loadLocalData()
        }
    }

    // MARK: - Data Loading

    /// 从本地存储加载数据
    @MainActor
    private func loadLocalData() async {
        // 加载宠物数据
        if let savedPet = try? await localStorage.loadPet() {
            pet = savedPet
        } else {
            // 首次使用，创建默认宠物
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
                lastInteraction: Date()
            )
        }

        // 加载连续打卡数据
        if let savedStreak = try? await localStorage.loadStreak() {
            streak = savedStreak
        }

        // 加载任务
        if let savedTasks = try? await localStorage.loadTasks() {
            tasks = savedTasks
        }

        // 加载事件
        if let savedEvents = try? await localStorage.loadEvents() {
            events = savedEvents
        }

        // 更新宠物状态
        await updatePetState()

        // 更新统计数据
        updateStatistics()
    }

    /// 刷新所有数据（从远程同步）
    @MainActor
    public func refreshData(userId: String?) async {
        isLoading = true
        lastError = nil

        defer { isLoading = false }

        // 如果有用户 ID，执行完整同步
        if let userId = userId {
            let result = await syncManager.performFullSync(userId: userId)

            switch result {
            case .success:
                break
            case .partial(_, let failed):
                if failed > 0 {
                    lastError = "Some data failed to sync"
                }
            case .failure(let error):
                lastError = error.localizedDescription
            }
        }

        // 重新加载本地数据
        await loadLocalData()
    }

    /// 更新宠物状态（心情和场景）
    @MainActor
    private func updatePetState() async {
        let completedToday = tasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return Calendar.current.isDateInToday(dueDate) && task.isCompleted
        }.count

        let totalToday = tasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return Calendar.current.isDateInToday(dueDate)
        }.count

        let newMood = await petStateService.calculateMood(
            lastInteraction: pet.lastInteraction,
            tasksCompletedToday: completedToday,
            totalTasksToday: totalToday
        )

        let newScene = await petStateService.calculateScene(
            currentTime: Date(),
            hasTasks: totalToday > completedToday
        )

        pet.mood = newMood
        pet.scene = newScene
    }

    /// 更新统计数据
    private func updateStatistics() {
        let calendar = Calendar.current
        let today = Date()

        // 今日统计
        let todayTasks = tasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return calendar.isDateInToday(dueDate)
        }
        let todayCompleted = todayTasks.filter { $0.isCompleted }.count

        // 本周统计
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        let weekTasks = tasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return dueDate >= weekStart && dueDate <= today
        }
        let weekCompleted = weekTasks.filter { $0.isCompleted }.count

        // 30天统计
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
    }

    /// 加载今日 Haiku
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

    /// 从 Google Calendar 加载事件
    @MainActor
    public func loadGoogleCalendarEvents() async {
        guard AuthManager.shared.hasCalendarAccess else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let googleEvents = try await googleCalendarAPI.getTodayEvents()

            // 合并 Google 事件与本地事件（保留非 Google 来源的事件）
            let localEvents = events.filter { $0.source != .google }
            events = localEvents + googleEvents

            // 保存到本地
            try? await localStorage.saveEvents(events)
        } catch {
            lastError = "Failed to load calendar events: \(error.localizedDescription)"
        }
    }

    /// 从 Google Tasks 加载任务
    @MainActor
    public func loadGoogleTasks() async {
        guard AuthManager.shared.hasTasksAccess else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let googleTasks = try await googleTasksAPI.getAllTasks()

            // 合并 Google 任务与本地任务（保留非 Google 来源的任务）
            let localTasks = tasks.filter { $0.source != .google }
            tasks = localTasks + googleTasks

            // 保存到本地
            try? await localStorage.saveTasks(tasks)

            // 更新统计
            updateStatistics()
        } catch {
            lastError = "Failed to load tasks: \(error.localizedDescription)"
        }
    }

    /// 同步所有 Google 数据
    @MainActor
    public func syncGoogleData() async {
        await loadGoogleCalendarEvents()
        await loadGoogleTasks()
        await updatePetState()
    }

    // MARK: - Actions

    @MainActor
    public func toggleTaskCompletion(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }

        tasks[index].isCompleted.toggle()
        let isCompleted = tasks[index].isCompleted
        let updatedTask = tasks[index]

        if isCompleted {
            pet.adventuresCount += 1
            pet.progress = min(1.0, pet.progress + 0.02)

            // 更新连续打卡
            updateStreak()
        } else {
            pet.adventuresCount = max(0, pet.adventuresCount - 1)
            pet.progress = max(0, pet.progress - 0.02)
        }

        pet.lastInteraction = Date()

        // 更新统计
        updateStatistics()

        // 保存到本地
        Task {
            try? await localStorage.saveTasks(tasks)
            try? await localStorage.savePet(pet)
            try? await localStorage.saveStreak(streak)

            // 如果是 Google 任务，同步到 Google
            if updatedTask.source == .google {
                try? await googleTasksAPI.syncTaskCompletion(updatedTask)
            }
        }

        // 更新宠物状态
        Task { @MainActor in
            await updatePetState()
        }

        // 任务完成时生成新 Haiku
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

    /// 更新连续打卡
    private func updateStreak() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if let lastActive = streak.lastActiveDate {
            let lastActiveDay = calendar.startOfDay(for: lastActive)

            if calendar.isDate(lastActiveDay, inSameDayAs: today) {
                // 今天已经打卡过，不更新
                return
            } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
                      calendar.isDate(lastActiveDay, inSameDayAs: yesterday) {
                // 昨天打卡过，连续打卡 +1
                streak.currentStreak += 1
            } else {
                // 断了，重新开始
                streak.currentStreak = 1
            }
        } else {
            // 首次打卡
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

    /// 添加新任务
    @MainActor
    public func addTask(_ task: TaskItem) {
        tasks.append(task)
        updateStatistics()
        Task {
            try? await localStorage.saveTasks(tasks)
        }
    }

    /// 删除任务
    @MainActor
    public func deleteTask(_ task: TaskItem) {
        tasks.removeAll { $0.id == task.id }
        updateStatistics()
        Task {
            try? await localStorage.saveTasks(tasks)
        }
    }

    /// 更新事件列表
    @MainActor
    public func updateEvents(_ newEvents: [CalendarEvent]) {
        events = newEvents
        Task {
            try? await localStorage.saveEvents(events)
        }
    }

    /// 更新任务列表
    @MainActor
    public func updateTasks(_ newTasks: [TaskItem]) {
        tasks = newTasks
        updateStatistics()
        Task {
            try? await localStorage.saveTasks(tasks)
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
