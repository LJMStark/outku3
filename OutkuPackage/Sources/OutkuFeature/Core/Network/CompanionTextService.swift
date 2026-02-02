import Foundation

// MARK: - Companion Text Service

/// 文案生成服务 - 生成早安问候、日程总结、陪伴短句等
@MainActor
public final class CompanionTextService {
    public static let shared = CompanionTextService()

    private init() {}

    // MARK: - Morning Greeting

    public func generateMorningGreeting(petName: String, petMood: PetMood, weather: Weather) async -> String {
        let greetings: [PetMood: [String]] = [
            .happy: ["Good morning! Ready for today?", "Rise and shine! Let's go!", "Morning! Today will be great!"],
            .excited: ["Good morning! So excited!", "Let's make today amazing!", "Can't wait to start the day!"],
            .focused: ["Morning. Let's get to work.", "Ready to tackle today's tasks.", "Time to focus and achieve."],
            .sleepy: ["Morning... still waking up...", "Good morning... yawn...", "Let's ease into today..."],
            .missing: ["Good morning! Missed you!", "So glad you're here today!", "Morning! Let's catch up!"]
        ]
        return (greetings[petMood] ?? greetings[.happy]!).randomElement() ?? "Good morning!"
    }

    // MARK: - Daily Summary

    public func generateDailySummary(tasksCount: Int, eventsCount: Int, petName: String) async -> String {
        switch (tasksCount, eventsCount) {
        case (0, 0): return "A free day! Time to relax."
        case (0, _): return "\(eventsCount) event\(eventsCount == 1 ? "" : "s") today."
        case (_, 0): return "\(tasksCount) task\(tasksCount == 1 ? "" : "s") to tackle today."
        default: return "\(tasksCount) task\(tasksCount == 1 ? "" : "s"), \(eventsCount) event\(eventsCount == 1 ? "" : "s") today."
        }
    }

    // MARK: - Companion Phrase

    public func generateCompanionPhrase(petMood: PetMood, timeOfDay: TimeOfDay) async -> String {
        let phrases: [TimeOfDay: [String]] = [
            .morning: ["You've got this today!", "One step at a time.", "Let's make it count!"],
            .afternoon: ["Keep going, you're doing great!", "Halfway there!", "Stay focused, stay strong."],
            .evening: ["Almost done for today!", "Great work today!", "Time to wind down."],
            .night: ["Rest well tonight.", "Tomorrow is a new day.", "Sweet dreams ahead."]
        ]
        return (phrases[timeOfDay] ?? phrases[.morning]!).randomElement() ?? "You've got this!"
    }

    // MARK: - Task Encouragement

    public func generateTaskEncouragement(taskTitle: String, petName: String, petMood: PetMood) async -> String {
        ["You can do this!", "Focus and conquer!", "One task at a time.", "Let's get it done!",
         "Believe in yourself!", "Small steps, big wins.", "Stay focused!", "You're capable of this."]
            .randomElement() ?? "You've got this!"
    }

    // MARK: - Task Verbalization

    public func verbalizeTask(taskTitle: String) async -> String { taskTitle }

    // MARK: - Settlement Message

    public func generateSettlementMessage(tasksCompleted: Int, tasksTotal: Int, streakDays: Int, petName: String) async -> String {
        let rate = tasksTotal > 0 ? Double(tasksCompleted) / Double(tasksTotal) : 0
        switch rate {
        case 1.0...: return "Perfect! All \(tasksTotal) tasks done!"
        case 0.7..<1.0: return "Great job! \(tasksCompleted)/\(tasksTotal) completed."
        case 0.3..<0.7: return "Good effort! \(tasksCompleted)/\(tasksTotal) done."
        case 0.0..<0.3 where tasksCompleted > 0: return "You started! \(tasksCompleted)/\(tasksTotal) tasks."
        default: return "Tomorrow is a fresh start!"
        }
    }
}
