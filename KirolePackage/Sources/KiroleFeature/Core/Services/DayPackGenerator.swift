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
        weather: Weather, deviceMode: DeviceMode,
        userProfile: UserProfile = .default,
        screenSize: ScreenSize = .fourInch,
        petDialogue: String = ""
    ) async -> DayPack {
        let todayTasks = tasks.filter { $0.dueDate.map { Calendar.current.isDateInToday($0) } ?? false }
        let todayEvents = events
            .filter { Calendar.current.isDateInToday($0.startTime) }
            .sorted { $0.startTime < $1.startTime }

        // v2.5.0: one pet bubble, sourced from the App's currentPetDialogue (the same line the
        // App home shows). Fall back to a phase-appropriate companion line if not yet computed.
        let bubble = petDialogue.isEmpty
            ? await textService.generateCompanionPhrase(petMood: pet.mood, timeOfDay: TimeOfDay.current(), userProfile: userProfile)
            : petDialogue

        let eventSummaries = todayEvents.prefix(8).map { EventSummary(from: $0) }

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
            petDialogue: bubble,
            events: Array(eventSummaries),
            topTasks: Array(topTasks),
            settlementData: await generateSettlementData(tasks: todayTasks, pet: pet, userProfile: userProfile)
        )
    }

    public func generateTaskInPage(task: TaskItem, pet: Pet, userProfile: UserProfile = .default) async -> TaskInPageData {
        let encouragement = await textService.generateTaskEncouragement(taskTitle: task.title, petName: pet.name, petMood: pet.mood, userProfile: userProfile)
        return TaskInPageData(
            taskId: task.id, taskTitle: task.title,
            encouragement: encouragement
        )
    }

    // MARK: - Private Helpers

    private func generateSettlementData(tasks: [TaskItem], pet: Pet, userProfile: UserProfile = .default) async -> SettlementData {
        let completed = tasks.filter { $0.isCompleted }.count
        let total = tasks.count
        let rate = total > 0 ? Double(completed) / Double(total) : 0
        let focusStats = FocusSessionService.shared.statistics
        let energyBottles = await LocalStorage.shared.loadEnergyBottles()

        let aiMessage = await textService.generateSettlementMessage(
            tasksCompleted: completed,
            tasksTotal: total,
            petName: pet.name,
            focusTimeToday: Int(focusStats.todayFocusTime / 60),
            energyBottles: energyBottles, // Loaded actual energy bottles score
            userProfile: userProfile
        )

        let (summary, encouragement): (String, String) = {
            switch rate {
            case 1.0...: return ("Perfect day! All tasks completed!", aiMessage)
            case 0.7..<1.0: return ("Great progress today!", aiMessage)
            case 0.3..<0.7: return ("Good effort today.", aiMessage)
            case 0.0..<0.3 where completed > 0: return ("You made a start today.", aiMessage)
            default: return ("Rest day?", aiMessage)
            }
        }()

        return SettlementData(
            tasksCompleted: completed, tasksTotal: total, pointsEarned: completed * 10,
            petMood: pet.mood.rawValue,
            summaryMessage: summary, encouragementMessage: encouragement,
            totalFocusMinutes: Int(focusStats.todayFocusTime / 60),
            focusSessionCount: focusStats.todaySessions,
            longestFocusMinutes: focusStats.longestSessionMinutes,
            interruptionCount: focusStats.interruptionCount,
            totalEnergyBottles: energyBottles
        )
    }

}
