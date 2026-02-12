import Foundation

// MARK: - Time of Day

public enum TimeOfDay: String, Sendable {
    case morning, afternoon, evening, night

    /// Determine time of day from a given date (defaults to now)
    public static func current(at date: Date = Date()) -> TimeOfDay {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: return .morning
        case 12..<17: return .afternoon
        case 17..<21: return .evening
        default: return .night
        }
    }
}

// MARK: - Day Pack Generator

/// 生成发送到 E-ink 设备的 Day Pack 数据
@MainActor
public final class DayPackGenerator {
    public static let shared = DayPackGenerator()
    private let textService = CompanionTextService.shared

    private init() {}

    public func generateDayPack(
        pet: Pet, tasks: [TaskItem], events: [CalendarEvent],
        weather: Weather, streak: Streak, deviceMode: DeviceMode,
        userProfile: UserProfile = .default,
        screenSize: ScreenSize = .fourInch
    ) async -> DayPack {
        let todayTasks = tasks.filter { $0.dueDate.map { Calendar.current.isDateInToday($0) } ?? false }
        let todayEvents = events.filter { Calendar.current.isDateInToday($0.startTime) }

        async let greeting = textService.generateMorningGreeting(petName: pet.name, petMood: pet.mood, weather: weather, userProfile: userProfile)
        async let summary = textService.generateDailySummary(tasksCount: todayTasks.count, eventsCount: todayEvents.count, petName: pet.name, userProfile: userProfile)
        async let phrase = textService.generateCompanionPhrase(petMood: pet.mood, timeOfDay: TimeOfDay.current(), userProfile: userProfile)

        let topTasks = todayTasks
            .filter { !$0.isCompleted }
            .sorted { $0.priority.rawValue > $1.priority.rawValue }
            .prefix(screenSize.maxTasks)
            .map { TaskSummary(from: $0) }

        return DayPack(
            date: Date(),
            weather: WeatherInfo(from: weather),
            deviceMode: deviceMode,
            focusChallengeEnabled: false,
            morningGreeting: await greeting,
            dailySummary: await summary,
            firstItem: generateFirstItem(tasks: todayTasks, events: todayEvents),
            currentScheduleSummary: generateScheduleSummary(events: todayEvents),
            topTasks: Array(topTasks),
            companionPhrase: await phrase,
            settlementData: generateSettlementData(tasks: todayTasks, pet: pet, streak: streak)
        )
    }

    public func generateTaskInPage(task: TaskItem, pet: Pet, userProfile: UserProfile = .default) async -> TaskInPageData {
        let encouragement = await textService.generateTaskEncouragement(taskTitle: task.title, petName: pet.name, petMood: pet.mood, userProfile: userProfile)
        return TaskInPageData(taskId: task.id, taskTitle: task.title, encouragement: encouragement)
    }

    // MARK: - Private Helpers

    private func generateFirstItem(tasks: [TaskItem], events: [CalendarEvent]) -> String {
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        // Check for upcoming events in the next hour
        if let event = events.first(where: { $0.startTime > now && $0.startTime < now.addingTimeInterval(3600) }) {
            return "\(formatter.string(from: event.startTime)) - \(event.title)"
        }

        // Otherwise, show first incomplete task
        if let task = tasks.filter({ !$0.isCompleted }).sorted(by: { $0.priority.rawValue > $1.priority.rawValue }).first {
            return task.title
        }

        return "No tasks for today"
    }

    private func generateScheduleSummary(events: [CalendarEvent]) -> String? {
        let count = events.filter { $0.startTime > Date() }.count
        guard count > 0 else { return nil }
        return "\(count) event\(count == 1 ? "" : "s") remaining"
    }

    private func generateSettlementData(tasks: [TaskItem], pet: Pet, streak: Streak) -> SettlementData {
        let completed = tasks.filter { $0.isCompleted }.count
        let total = tasks.count
        let rate = total > 0 ? Double(completed) / Double(total) : 0

        let (summary, encouragement): (String, String) = {
            switch rate {
            case 1.0...: return ("Perfect day! All tasks completed!", "\(pet.name) is so proud of you!")
            case 0.7..<1.0: return ("Great progress today!", "Keep up the momentum!")
            case 0.3..<0.7: return ("Good effort today.", "Every step counts!")
            case 0.0..<0.3 where completed > 0: return ("You made a start today.", "Tomorrow is a new opportunity!")
            default: return ("Rest day?", "\(pet.name) is here for you.")
            }
        }()

        return SettlementData(
            tasksCompleted: completed, tasksTotal: total, pointsEarned: completed * 10,
            streakDays: streak.currentStreak, petMood: pet.mood.rawValue,
            summaryMessage: summary, encouragementMessage: encouragement
        )
    }

}
