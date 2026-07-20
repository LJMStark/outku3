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

    /// Offline fallback for the events-only day summary (box②). Events only — never tasks.
    /// 客户规则（2026-07-20）：繁忙给休息建议，不繁忙提醒喝水。v2.5.33 复审修订：两场以上
    /// 不再一律判"繁忙"——相邻间隔 <60 分钟（紧凑）或 ≥4 场才给休息建议；上午晚上各一场
    /// 的松散日提醒喝水。仅离线降级用，精细判断在 AI 路径（digest 带完整时段）。
    static func daySummary(events: [EventSummary]) -> String {
        guard let first = events.first else {
            return "An open day ahead - a little room to breathe. Remember to drink some water."
        }
        let firstLabel = first.time.isEmpty ? first.title : "\(first.time) \(first.title)"
        if events.count == 1 {
            return "One thing on the calendar today: \(firstLabel). A calm day - keep some water nearby."
        }
        if events.count >= 4 || hasTightGap(events) {
            return "\(events.count) events today, starting with \(firstLabel). Pace yourself and take a short break between them."
        }
        return "\(events.count) events today, starting with \(firstLabel). Looks manageable - remember to drink some water."
    }

    /// 相邻两场间隔 <60 分钟（前一场 endTime → 后一场 time）判紧凑；含全天事件或
    /// "HH:mm" 解析失败时按紧凑保守处理（宁给休息建议，不误报清闲）。
    static func hasTightGap(_ events: [EventSummary]) -> Bool {
        let spans = events.compactMap { event -> (start: Int, end: Int)? in
            guard let start = minutesOfDay(event.time) else { return nil }
            return (start, minutesOfDay(event.endTime) ?? start)
        }.sorted { $0.start < $1.start }
        guard spans.count == events.count, spans.count >= 2 else { return true }
        for index in 1..<spans.count where spans[index].start - spans[index - 1].end < 60 {
            return true
        }
        return false
    }

    private static func minutesOfDay(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2, let hours = Int(parts[0]), let minutes = Int(parts[1]) else { return nil }
        return hours * 60 + minutes
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

    // MARK: - Settlement page texts（硬件"页面四 每日总结"，v2.5.30）

    /// Deterministic review that ALWAYS satisfies the two client hard rules: mentions a deadline
    /// item when one exists, and states the focus duration when it exceeds 2h. The LLM path only
    /// promises these at prompt level; this template is the guarantee.
    static func settlementReview(
        deadlineTitles: [String], focusMinutes: Int,
        tasksCompleted: Int, tasksTotal: Int
    ) -> String {
        var parts: [String] = []
        parts.append(tasksTotal > 0
            ? "Today you completed \(tasksCompleted) of \(tasksTotal) planned items."
            : "A light day with nothing planned.")
        // 预算感知（v2.5.32）：死线标题截 ≤60B——三句合计恒 <180B，专注句永不被编码器
        // 的 180B 截断挤掉。v2.5.33（复审 P1）：先按 wire 同款 ASCII 净化预览——全 CJK
        // 标题（如"合同付款截止"）净化后为空，硬插原文只会在硬件上剩 "On the deadline
        // side: ."；此时退化为通用表述，保住"必提死线"这件事本身。
        let deadline = deadlineTitles
            .map { $0.asciiSanitizedForEInk().trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        if let deadline {
            parts.append("On the deadline side: \(CompanionTextService.enforceByteBudget(deadline, maxBytes: 60)).")
        } else if deadlineTitles.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            parts.append("Don't forget today's deadline item.")
        }
        if focusMinutes > DayPackGenerator.focusMentionThresholdMinutes {
            parts.append("You focused for \(DayPackGenerator.focusDurationLabel(minutes: focusMinutes)) today.")
        }
        return parts.joined(separator: " ")
    }

    /// 全部完成 → 庆祝收尾（离线兜底；在线走人格管线）。
    static func settlementQuoteCelebration(
        style: CompanionStyle?, customVoice: CompanionPersonaVoice? = nil
    ) -> String {
        if let customVoice {
            switch customVoice {
            case .companion:
                return "Every plan is complete. I noticed your steady effort, and I'm proud of you."
            case .challenger:
                return "Full completion. You set the bar, then cleared it. Raise it wisely tomorrow."
            case .zen:
                return "Everything is complete. Let the day settle; you can rest now."
            case .playful:
                return "You cleared the whole board. That deserves a tiny victory dance."
            case .customPrompt:
                return "Everything is complete. Your companion is here to celebrate with you."
            }
        }
        switch style {
        case .joy:
            return pick([
                "You did it - every single one! I'm so proud of you!",
                "All done! Let's soak up that finished feeling together.",
                "Everything wrapped - today deserves a little celebration!"
            ])
        case .silas:
            return pick([
                "The day is complete, and you were faithful to all of it.",
                "Everything you carried today reached its end. Rest well.",
                "All is finished. Let the evening be gentle with you."
            ])
        case .nova:
            return pick([
                "All tasks and events closed. Clean execution.",
                "Everything cleared. That is how a day is done.",
                "Full completion. Note what worked - repeat it tomorrow."
            ])
        case nil:
            return pick([
                "Everything done - today was a win worth savoring!",
                "All clear! You finished everything you set out to do.",
                "A full sweep today. Great work, truly."
            ])
        }
    }

    /// 未完成但投入 > 4h → 客户指定的方向（"今天已努力，任务定多了，明天减量、从稳定完成开始"）。
    static func settlementQuoteOverloaded(
        style: CompanionStyle?, customVoice: CompanionPersonaVoice? = nil
    ) -> String {
        if let customVoice {
            switch customVoice {
            case .companion:
                return "You gave today plenty. The plan was too full; choose less tomorrow and let steady wins carry you."
            case .challenger:
                return "The effort was real; the plan was not. Cut tomorrow's list and finish what matters."
            case .zen:
                return "You did enough. The plan held too much; choose less tomorrow and finish with ease."
            case .playful:
                return "You worked hard; the list got greedy. Feed it less tomorrow and collect a steady win."
            case .customPrompt:
                return "You worked hard today. The plan was too full; choose less tomorrow and build from steady wins."
            }
        }
        switch style {
        case .joy:
            return "You worked so hard today! The list was just a bit much - let's plan a lighter one tomorrow and win it together."
        case .silas:
            return "You gave today real effort; the plan was heavier than one day can hold. Choose less tomorrow and finish in peace."
        case .nova:
            return "Effort was there. The plan was overloaded. Cut tomorrow's list and start from steady completion."
        case nil:
            return "You really worked hard today - the plan was just packed. Try fewer or easier tasks tomorrow and start from steady wins."
        }
    }

    /// 未完成且投入 ≤ 4h → 客户逐字指定的建议，固定文案，不走 AI。
    static func settlementQuoteFullSchedule() -> String {
        "When the schedule is full, plan fewer tasks to leave room for focus."
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
                "No tasks today. Rest or reflect - both have value."
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

    private static func random(_ preferred: [String]?, defaultingTo fallbackCandidates: [String]?, fallback: String) -> String {
        preferred?.randomElement() ?? fallbackCandidates?.randomElement() ?? fallback
    }

    private static func pick(_ phrases: [String]) -> String {
        phrases.randomElement() ?? ""
    }
}
