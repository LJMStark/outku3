import Foundation

enum FallbackText {
    private static let morningGreetings: [PetMood: [String]] = [
        .happy: ["Good morning! Ready for today?", "Rise and shine! Let's go!", "Morning! Today will be great!"],
        .excited: ["Good morning! So excited!", "Let's make today amazing!", "Can't wait to start the day!"],
        .focused: ["Morning. Let's get to work.", "Ready to tackle today's tasks.", "Time to focus and achieve."],
        .sleepy: ["Morning... still waking up...", "Good morning... yawn...", "Let's ease into today..."],
        .missing: ["Good morning! Missed you!", "So glad you're here today!", "Morning! Let's catch up!"]
    ]

    private static let companionPhrases: [TimeOfDay: [String]] = [
        .morning: ["You've got this today!", "One step at a time.", "Let's make it count!"],
        .afternoon: ["Keep going, you're doing great!", "Halfway there!", "Stay focused, stay strong."],
        .evening: ["Almost done for today!", "Great work today!", "Time to wind down."],
        .night: ["Rest well tonight.", "Tomorrow is a new day.", "Sweet dreams ahead."]
    ]

    private static let taskEncouragements = [
        "You can do this!",
        "Focus and conquer!",
        "One task at a time.",
        "Let's get it done!",
        "Believe in yourself!",
        "Small steps, big wins.",
        "Stay focused!",
        "You're capable of this."
    ]

    static func morningGreeting(for mood: PetMood) -> String {
        random(morningGreetings[mood], defaultingTo: morningGreetings[.happy], fallback: "Good morning!")
    }

    static func dailySummary(tasksCount: Int, eventsCount: Int) -> String {
        switch (tasksCount, eventsCount) {
        case (0, 0):
            return "A free day! Time to relax."
        case (0, _):
            return "\(eventsCount) \(pluralized("event", count: eventsCount)) today."
        case (_, 0):
            return "\(tasksCount) \(pluralized("task", count: tasksCount)) to tackle today."
        default:
            return "\(tasksCount) \(pluralized("task", count: tasksCount)), \(eventsCount) \(pluralized("event", count: eventsCount)) today."
        }
    }

    static func companionPhrase(for timeOfDay: TimeOfDay) -> String {
        random(companionPhrases[timeOfDay], defaultingTo: companionPhrases[.morning], fallback: "You've got this!")
    }

    static func taskEncouragement() -> String {
        taskEncouragements.randomElement() ?? "You've got this!"
    }

    static func settlementMessage(tasksCompleted: Int, tasksTotal: Int) -> String {
        let rate = tasksTotal > 0 ? Double(tasksCompleted) / Double(tasksTotal) : 0
        switch rate {
        case 1.0...:
            return "Perfect! All \(tasksTotal) tasks done!"
        case 0.7..<1.0:
            return "Great job! \(tasksCompleted)/\(tasksTotal) completed."
        case 0.3..<0.7:
            return "Good effort! \(tasksCompleted)/\(tasksTotal) done."
        case 0.0..<0.3 where tasksCompleted > 0:
            return "You started! \(tasksCompleted)/\(tasksTotal) tasks."
        default:
            return "Tomorrow is a fresh start!"
        }
    }

    static func smartReminder(reason: ReminderReason, petName: String, taskTitle: String?) -> String {
        switch reason {
        case .idle:
            return "\(petName) misses you! Time to get back on track."
        case .deadline:
            guard let taskTitle else {
                return "You have a task due soon!"
            }
            return "\(taskTitle) is due soon. Let's finish it!"
        case .gentleNudge:
            return "Ready for the next task? \(petName) believes in you."
        }
    }

    static func sharedPetDialogue(context: AIContext) -> String {
        if context.totalTasksToday == 0 && context.eventsToday == 0 {
            return "It is a quiet day, and I am happy to stay here with you."
        }

        if context.totalTasksToday > 0, context.tasksCompletedToday >= context.totalTasksToday {
            return "You carried today to the end, and I am resting here with you now."
        }

        if context.nextAgendaItem != nil {
            return "Something is coming up soon, and I am staying close beside you."
        }

        if !context.topTaskTitles.isEmpty {
            return "We can begin with one small step, and I will stay beside you through it."
        }

        return "I am right here with you, and this moment can stay gentle."
    }

    private static func pluralized(_ word: String, count: Int) -> String {
        count == 1 ? word : "\(word)s"
    }

    private static func random(_ preferred: [String]?, defaultingTo fallbackCandidates: [String]?, fallback: String) -> String {
        preferred?.randomElement() ?? fallbackCandidates?.randomElement() ?? fallback
    }
}
