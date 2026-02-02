import Foundation

// MARK: - Demo Mode Service

/// Demo 模式服务 - 提供模拟数据用于展示和测试
@MainActor
public final class DemoModeService {
    public static let shared = DemoModeService()

    private init() {}

    // MARK: - Demo Data Generation

    public func generateDemoDayPack() -> DayPack {
        let tasks = generateDemoTasks()
        let weather = generateDemoWeather()
        return DayPack(
            date: Date(),
            weather: WeatherInfo(from: weather),
            deviceMode: .interactive,
            focusChallengeEnabled: false,
            morningGreeting: "Good morning! Ready for a great day?",
            dailySummary: "3 tasks, 2 events today.",
            firstItem: "09:00 - Team standup",
            currentScheduleSummary: "2 events remaining",
            topTasks: tasks.filter { !$0.isCompleted }.map { TaskSummary(from: $0) },
            companionPhrase: "You've got this!",
            settlementData: SettlementData(
                tasksCompleted: 1, tasksTotal: 4, pointsEarned: 10, streakDays: 7,
                petMood: "Happy", summaryMessage: "Good start today!", encouragementMessage: "Keep up the momentum!"
            )
        )
    }

    public func generateDemoTasks() -> [TaskItem] {
        let today = Date()
        return [
            TaskItem(id: "demo-task-1", title: "Review project proposal", isCompleted: true, dueDate: today, source: .apple, priority: .high),
            TaskItem(id: "demo-task-2", title: "Send weekly report", isCompleted: false, dueDate: today, source: .google, priority: .high),
            TaskItem(id: "demo-task-3", title: "Update documentation", isCompleted: false, dueDate: today, source: .apple, priority: .medium),
            TaskItem(id: "demo-task-4", title: "Schedule team meeting", isCompleted: false, dueDate: today, source: .google, priority: .low)
        ]
    }

    public func generateDemoEvents() -> [CalendarEvent] {
        let today = Date()
        let cal = Calendar.current
        return [
            CalendarEvent(
                id: "demo-event-1", title: "Team standup",
                startTime: cal.date(bySettingHour: 9, minute: 0, second: 0, of: today)!,
                endTime: cal.date(bySettingHour: 9, minute: 30, second: 0, of: today)!,
                source: .google, participants: [Participant(name: "Alice Chen"), Participant(name: "Bob Smith")]
            ),
            CalendarEvent(
                id: "demo-event-2", title: "Product review",
                startTime: cal.date(bySettingHour: 14, minute: 0, second: 0, of: today)!,
                endTime: cal.date(bySettingHour: 15, minute: 0, second: 0, of: today)!,
                source: .apple, participants: [Participant(name: "Carol Davis"), Participant(name: "David Lee"), Participant(name: "Eve Wilson")]
            )
        ]
    }

    public func generateDemoPet() -> Pet {
        Pet(name: "Pixel", pronouns: .theyThem, adventuresCount: 42, age: 30, status: .happy,
            mood: .happy, scene: .indoor, stage: .teen, progress: 0.65, weight: 120, height: 12,
            tailLength: 5, currentForm: .cat, lastInteraction: Date(), points: 420)
    }

    public func generateDemoStreak() -> Streak {
        Streak(currentStreak: 7, longestStreak: 14, lastActiveDate: Date())
    }

    public func generateDemoWeather() -> Weather {
        Weather(temperature: 22, highTemp: 26, lowTemp: 18, condition: .partlyCloudy, location: "San Francisco")
    }

    public func simulateEventLog(type: EventLogType, taskId: String? = nil) -> EventLog {
        EventLog(eventType: type, taskId: taskId, timestamp: Date())
    }
}

// MARK: - AppState Demo Mode Extension

extension AppState {
    @MainActor
    public func enableDemoMode() {
        let demo = DemoModeService.shared
        isDemoMode = true
        pet = demo.generateDemoPet()
        tasks = demo.generateDemoTasks()
        events = demo.generateDemoEvents()
        streak = demo.generateDemoStreak()
        weather = demo.generateDemoWeather()
    }

    @MainActor
    public func disableDemoMode() async {
        isDemoMode = false
        await refreshData(userId: AuthManager.shared.currentUser?.id)
    }
}
