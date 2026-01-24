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
    public var streak: Streak = Streak(currentStreak: 7)

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

    private init() {
        loadMockData()
    }

    private func loadMockData() {
        // Mock events for today
        let calendar = Calendar.current
        let today = Date()

        events = [
            CalendarEvent(
                title: "Team Standup",
                startTime: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today)!,
                endTime: calendar.date(bySettingHour: 9, minute: 30, second: 0, of: today)!,
                source: .google,
                participants: [
                    Participant(name: "Alex Chen"),
                    Participant(name: "Sarah Kim"),
                    Participant(name: "Mike Johnson")
                ],
                description: "Daily sync to discuss progress and blockers"
            ),
            CalendarEvent(
                title: "Design Review",
                startTime: calendar.date(bySettingHour: 11, minute: 0, second: 0, of: today)!,
                endTime: calendar.date(bySettingHour: 12, minute: 0, second: 0, of: today)!,
                source: .google,
                participants: [
                    Participant(name: "Emma Wilson"),
                    Participant(name: "David Lee")
                ],
                description: "Review new UI designs for the mobile app"
            ),
            CalendarEvent(
                title: "Lunch Break",
                startTime: calendar.date(bySettingHour: 12, minute: 30, second: 0, of: today)!,
                endTime: calendar.date(bySettingHour: 13, minute: 30, second: 0, of: today)!,
                source: .apple,
                description: "Take a break and recharge"
            ),
            CalendarEvent(
                title: "Client Call",
                startTime: calendar.date(bySettingHour: 14, minute: 0, second: 0, of: today)!,
                endTime: calendar.date(bySettingHour: 15, minute: 0, second: 0, of: today)!,
                source: .google,
                participants: [
                    Participant(name: "John Smith"),
                    Participant(name: "Lisa Brown")
                ],
                description: "Quarterly review with the client team"
            ),
            CalendarEvent(
                title: "Focus Time",
                startTime: calendar.date(bySettingHour: 15, minute: 30, second: 0, of: today)!,
                endTime: calendar.date(bySettingHour: 17, minute: 0, second: 0, of: today)!,
                source: .apple,
                description: "Deep work session - no meetings"
            )
        ]

        // Mock tasks
        tasks = [
            TaskItem(title: "Review pull requests", dueDate: today, source: .todoist, priority: .high),
            TaskItem(title: "Update documentation", dueDate: today, source: .apple, priority: .medium),
            TaskItem(title: "Send weekly report", dueDate: today, source: .google, priority: .high),
            TaskItem(title: "Plan next sprint", dueDate: calendar.date(byAdding: .day, value: 1, to: today), source: .todoist, priority: .medium),
            TaskItem(title: "Research new tools", dueDate: calendar.date(byAdding: .day, value: 2, to: today), source: .apple, priority: .low),
            TaskItem(title: "Organize files", source: .apple, priority: .low),
            TaskItem(title: "Read industry articles", source: .todoist, priority: .low)
        ]

        // Mock statistics
        statistics = TaskStatistics(
            todayCompleted: 3,
            todayTotal: 5,
            pastWeekCompleted: 28,
            pastWeekTotal: 35,
            last30DaysCompleted: 112,
            last30DaysTotal: 140
        )

        // Mock pet data
        pet = Pet(
            name: "Baby Waffle",
            pronouns: .theyThem,
            adventuresCount: 143,
            age: 23,
            status: .happy,
            stage: .child,
            progress: 0.65,
            weight: 85,
            height: 8.5,
            tailLength: 4.2
        )
    }

    // MARK: - Actions

    public func toggleTaskCompletion(_ task: TaskItem) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index].isCompleted.toggle()
            if tasks[index].isCompleted {
                pet.adventuresCount += 1
                pet.progress = min(1.0, pet.progress + 0.02)
                statistics.todayCompleted += 1
            } else {
                pet.adventuresCount = max(0, pet.adventuresCount - 1)
                pet.progress = max(0, pet.progress - 0.02)
                statistics.todayCompleted = max(0, statistics.todayCompleted - 1)
            }
        }
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
