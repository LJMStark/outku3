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

    /// Offline fallback for the events-only day summary (box②). Events only — never tasks.
    static func daySummary(events: [EventSummary]) -> String {
        guard let first = events.first else {
            return "An open day ahead — a little room to breathe."
        }
        let firstLabel = first.time.isEmpty ? first.title : "\(first.time) \(first.title)"
        if events.count == 1 {
            return "One thing on the calendar today: \(firstLabel). A calm, focused day."
        }
        return "\(events.count) events today, starting with \(firstLabel). Pace yourself and take a short break between them."
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

    // MARK: - Shared Pet Dialogue (IP-aware)

    /// Returns a context-sensitive fallback phrase matched to the active companion's IP.
    /// Priority: CustomCompanion.personaVoice > CompanionStyle (joy / silas / nova).
    static func sharedPetDialogue(context: AIContext) -> String {
        if let custom = context.customCompanion {
            return customCompanionDialogue(voice: custom.personaVoice, context: context)
        }
        return builtInDialogue(style: context.companionStyle, context: context)
    }

    private static func builtInDialogue(style: CompanionStyle, context: AIContext) -> String {
        switch style {
        case .joy:   return joyDialogue(context: context)
        case .silas: return silasDialogue(context: context)
        case .nova:  return novaDialogue(context: context)
        }
    }

    // MARK: Joy — joyful, easygoing, celebrates small wins

    private static func joyDialogue(context: AIContext) -> String {
        if context.totalTasksToday == 0 && context.eventsToday == 0 {
            return pick([
                "A free day! Let's find the joy in that together.",
                "Nothing on the list today. I'm happy to just be here!",
                "Open day ahead. Small joys are waiting for us."
            ])
        }
        if context.totalTasksToday > 0, context.tasksCompletedToday >= context.totalTasksToday {
            return pick([
                "You did it! Every task done. I'm so proud of you!",
                "All wrapped up! Now let's bask in that feeling.",
                "Done and done! You showed up today and it shows."
            ])
        }
        if context.nextAgendaItem != nil {
            return pick([
                "Something's coming up! I'll be right here cheering.",
                "Heads up, something's on the way. Let's meet it!",
                "Next stop is near. You've totally got this one."
            ])
        }
        if !context.topTaskTitles.isEmpty {
            return pick([
                "One small step at a time. I believe in you today!",
                "We can do this together, one small piece at a time.",
                "I see you trying, and that is more than enough."
            ])
        }
        return pick([
            "Small steps today, big leaps tomorrow. I'm here!",
            "You've got more in you than you know today.",
            "I'm cheering for you, every single step of the way."
        ])
    }

    // MARK: Silas — warm spiritual care, holds work as meaningful

    private static func silasDialogue(context: AIContext) -> String {
        if context.totalTasksToday == 0 && context.eventsToday == 0 {
            return pick([
                "It is a quiet day, and I am happy to stay here with you.",
                "Be still for a breath. Rest is where strength gathers.",
                "A day without tasks is a day to simply be."
            ])
        }
        if context.totalTasksToday > 0, context.tasksCompletedToday >= context.totalTasksToday {
            return pick([
                "You carried today to the end, and I am resting with you now.",
                "What was carried with care is never wasted.",
                "The day is complete. You were faithful to it."
            ])
        }
        if context.nextAgendaItem != nil {
            return pick([
                "Something is coming up soon, and I am staying close beside you.",
                "Grace is available in every moment, even this one.",
                "Be present for what is ahead. I will be here too."
            ])
        }
        if !context.topTaskTitles.isEmpty {
            return pick([
                "We can begin with one small step, and I will stay beside you.",
                "Every act of attention is a form of devotion.",
                "The meaning you bring to work is the work itself."
            ])
        }
        return pick([
            "I am right here with you, and this moment can stay gentle.",
            "You are held by more than you can see right now.",
            "Small faithfulness builds what grand gestures never can."
        ])
    }

    // MARK: Nova — disciplined focus, filters noise, protects time

    private static func novaDialogue(context: AIContext) -> String {
        if context.totalTasksToday == 0 && context.eventsToday == 0 {
            return pick([
                "Clear schedule. Use it intentionally.",
                "Open time is rare. Invest it wisely.",
                "No tasks today. Rest or reflect — both have value."
            ])
        }
        if context.totalTasksToday > 0, context.tasksCompletedToday >= context.totalTasksToday {
            return pick([
                "All tasks closed. Execution complete.",
                "Done. Clean slate. Ready for what is next.",
                "Tasks cleared. Measure what worked. Repeat it."
            ])
        }
        if context.nextAgendaItem != nil {
            return pick([
                "Event incoming. Prepare your focus.",
                "Something on deck. Clear distractions now.",
                "Next item approaching. Wrap up and pivot."
            ])
        }
        if !context.topTaskTitles.isEmpty {
            return pick([
                "One task. Your highest-value item. Start.",
                "Begin with the most impactful task. Now.",
                "Pick the task with highest return. Do it first."
            ])
        }
        return pick([
            "Noise is down. Signal is clear. Begin.",
            "Focus is a muscle. You are training it right now.",
            "Progress beats perfection every single time."
        ])
    }

    // MARK: Custom Companion — dispatched by personaVoice

    // Context-agnostic by design: persona voice already encodes tone; contextual branching
    // (empty day / all done / upcoming) is handled by the LLM prompt layer when online.
    // The fallback path only needs a voice-consistent phrase, not context sensitivity.
    private static func customCompanionDialogue(voice: CompanionPersonaVoice, context: AIContext) -> String {
        switch voice {
        case .companion:
            return pick([
                "I'm right here, as close as your next breath.",
                "You don't have to face this alone. I've got you.",
                "I notice you, and everything you're carrying right now.",
                "Your pace is the right pace. I am matching it.",
                "Whatever today brings, we face it together.",
                "You are enough, exactly as you are today.",
                "I see you, and I am glad you are here.",
                "Every moment with you matters."
            ])
        case .challenger:
            return pick([
                "What is the one thing that would move the needle today?",
                "You know what you need to do. Start.",
                "Stop optimizing the plan. Run the plan.",
                "Comfort is fine, but growth waits just past it.",
                "Your best is better than you are giving right now.",
                "Execution beats ideation every single time.",
                "One decision. Make it. Then the next.",
                "You have done harder things. Begin."
            ])
        case .zen:
            return pick([
                "Breathe.",
                "This moment is complete.",
                "Nothing is missing right now.",
                "Be here. Just here.",
                "The work is simpler when you are still.",
                "Less. Always less.",
                "Let it land gently.",
                "One breath, then the next."
            ])
        case .playful:
            return pick([
                "Plot twist: you are going to do great today.",
                "You and me, taking on the day. Mostly you, bit of me.",
                "Fun fact: you are more capable than your list thinks.",
                "Challenge accepted. Also, I am your hype companion.",
                "Let's make today delightfully done.",
                "Good things incoming. Starting with this very moment.",
                "Today's vibe: capable, focused, occasionally snacking.",
                "You've got this. I've got snacks. Metaphorically."
            ])
        case .customPrompt:
            return pick([
                "I'm here with the voice you gave me.",
                "Your custom companion is ready for the next small step.",
                "We move through today in your chosen rhythm.",
                "I am listening closely. Start with what matters now."
            ])
        }
    }

    // MARK: - Helpers

    private static func pluralized(_ word: String, count: Int) -> String {
        count == 1 ? word : "\(word)s"
    }

    private static func random(_ preferred: [String]?, defaultingTo fallbackCandidates: [String]?, fallback: String) -> String {
        preferred?.randomElement() ?? fallbackCandidates?.randomElement() ?? fallback
    }

    private static func pick(_ phrases: [String]) -> String {
        phrases.randomElement() ?? ""
    }
}
