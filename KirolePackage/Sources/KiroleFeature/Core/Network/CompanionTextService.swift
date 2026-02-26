import Foundation

// MARK: - Companion Text Service

/// 文案生成服务 - 生成早安问候、日程总结、陪伴短句等
/// 优先使用 OpenAI 生成个性化文案，无 API Key 或失败时回退到本地模板
@MainActor
public final class CompanionTextService {
    public static let shared = CompanionTextService()

    private let openAI = OpenAIService.shared
    private let localStorage = LocalStorage.shared

    private init() {}

    // MARK: - Morning Greeting

    public func generateMorningGreeting(
        petName: String, petMood: PetMood, weather: Weather,
        userProfile: UserProfile = .default
    ) async -> String {
        if let aiText = await generateAIText(
            type: .morningGreeting,
            petName: petName, petMood: petMood,
            userProfile: userProfile
        ) {
            return aiText
        }

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

    public func generateDailySummary(
        tasksCount: Int, eventsCount: Int, petName: String,
        userProfile: UserProfile = .default
    ) async -> String {
        if let aiText = await generateAIText(
            type: .dailySummary,
            petName: petName, petMood: .happy,
            userProfile: userProfile,
            totalTasks: tasksCount, events: eventsCount
        ) {
            return aiText
        }

        switch (tasksCount, eventsCount) {
        case (0, 0): return "A free day! Time to relax."
        case (0, _): return "\(eventsCount) event\(eventsCount == 1 ? "" : "s") today."
        case (_, 0): return "\(tasksCount) task\(tasksCount == 1 ? "" : "s") to tackle today."
        default: return "\(tasksCount) task\(tasksCount == 1 ? "" : "s"), \(eventsCount) event\(eventsCount == 1 ? "" : "s") today."
        }
    }

    // MARK: - Companion Phrase

    public func generateCompanionPhrase(
        petMood: PetMood, timeOfDay: TimeOfDay,
        userProfile: UserProfile = .default
    ) async -> String {
        if let aiText = await generateAIText(
            type: .companionPhrase,
            petName: "", petMood: petMood,
            userProfile: userProfile
        ) {
            return aiText
        }

        let phrases: [TimeOfDay: [String]] = [
            .morning: ["You've got this today!", "One step at a time.", "Let's make it count!"],
            .afternoon: ["Keep going, you're doing great!", "Halfway there!", "Stay focused, stay strong."],
            .evening: ["Almost done for today!", "Great work today!", "Time to wind down."],
            .night: ["Rest well tonight.", "Tomorrow is a new day.", "Sweet dreams ahead."]
        ]
        return (phrases[timeOfDay] ?? phrases[.morning]!).randomElement() ?? "You've got this!"
    }

    // MARK: - Task Encouragement

    public func generateTaskEncouragement(
        taskTitle: String, petName: String, petMood: PetMood,
        userProfile: UserProfile = .default
    ) async -> String {
        if let aiText = await generateAIText(
            type: .taskEncouragement,
            petName: petName, petMood: petMood,
            userProfile: userProfile
        ) {
            return aiText
        }

        return ["You can do this!", "Focus and conquer!", "One task at a time.", "Let's get it done!",
                "Believe in yourself!", "Small steps, big wins.", "Stay focused!", "You're capable of this."]
            .randomElement() ?? "You've got this!"
    }

    // MARK: - Task Verbalization

    public func verbalizeTask(taskTitle: String) async -> String { taskTitle }

    // MARK: - Settlement Message

    public func generateSettlementMessage(
        tasksCompleted: Int, tasksTotal: Int, streakDays: Int, petName: String,
        userProfile: UserProfile = .default
    ) async -> String {
        if let aiText = await generateAIText(
            type: .settlementSummary,
            petName: petName, petMood: .happy,
            userProfile: userProfile,
            completedTasks: tasksCompleted, totalTasks: tasksTotal,
            streak: streakDays
        ) {
            return aiText
        }

        let rate = tasksTotal > 0 ? Double(tasksCompleted) / Double(tasksTotal) : 0
        switch rate {
        case 1.0...: return "Perfect! All \(tasksTotal) tasks done!"
        case 0.7..<1.0: return "Great job! \(tasksCompleted)/\(tasksTotal) completed."
        case 0.3..<0.7: return "Good effort! \(tasksCompleted)/\(tasksTotal) done."
        case 0.0..<0.3 where tasksCompleted > 0: return "You started! \(tasksCompleted)/\(tasksTotal) tasks."
        default: return "Tomorrow is a fresh start!"
        }
    }

    // MARK: - Smart Reminder

    public func generateSmartReminder(
        reason: ReminderReason,
        petName: String, petMood: PetMood,
        taskTitle: String?,
        streakDays: Int,
        userProfile: UserProfile = .default
    ) async -> String {
        if let aiText = await generateAIText(
            type: .smartReminder,
            petName: petName, petMood: petMood,
            userProfile: userProfile,
            streak: streakDays
        ) {
            return String(aiText.prefix(60))
        }

        return smartReminderFallback(reason: reason, petName: petName, taskTitle: taskTitle, streakDays: streakDays)
    }

    private func smartReminderFallback(reason: ReminderReason, petName: String, taskTitle: String?, streakDays: Int) -> String {
        switch reason {
        case .idle:
            return "\(petName) misses you! Time to get back on track."
        case .deadline:
            if let title = taskTitle {
                return "\(title) is due soon. Let's finish it!"
            }
            return "You have a task due soon!"
        case .streakProtect:
            return "Your \(streakDays)-day streak is at risk! Do one task."
        case .gentleNudge:
            return "Ready for the next task? \(petName) believes in you."
        }
    }

    // MARK: - AI Text Generation

    private func generateAIText(
        type: AITextType,
        petName: String, petMood: PetMood,
        userProfile: UserProfile,
        completedTasks: Int = 0, totalTasks: Int = 0,
        events: Int = 0, streak: Int = 0
    ) async -> String? {
        guard await openAI.isConfigured else { return nil }

        let recentTexts = await loadRecentTexts(type: type)
        let behaviorSummary = try? await localStorage.loadBehaviorSummary()

        let weeklyRate: Double
        if let rates = behaviorSummary?.weeklyCompletionRates, let last = rates.last {
            weeklyRate = last
        } else {
            weeklyRate = totalTasks > 0 ? Double(completedTasks) / Double(totalTasks) : 0
        }

        let context = AIContext(
            companionStyle: userProfile.companionStyle,
            workType: userProfile.workType,
            primaryGoals: userProfile.primaryGoals,
            petName: petName,
            petMood: petMood,
            tasksCompletedToday: completedTasks,
            totalTasksToday: totalTasks,
            eventsToday: events,
            currentStreak: streak,
            recentCompletionRate: weeklyRate,
            behaviorSummary: behaviorSummary,
            recentTexts: recentTexts
        )

        do {
            let text = try await openAI.generateCompanionText(type: type, context: context)
            await saveInteraction(type: type, text: text, petName: petName, petMood: petMood, completionRate: weeklyRate)
            return text
        } catch {
            #if DEBUG
            print("[CompanionText] AI generation failed for \(type.rawValue): \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    // MARK: - Interaction Persistence

    private func loadRecentTexts(type: AITextType) async -> [String] {
        guard let interactions = try? await localStorage.loadAIInteractions() else { return [] }
        return interactions
            .filter { $0.type == type }
            .suffix(3)
            .map(\.generatedText)
    }

    private func saveInteraction(
        type: AITextType, text: String,
        petName: String, petMood: PetMood,
        completionRate: Double
    ) async {
        let interaction = AIInteraction(
            type: type,
            completionRate: completionRate,
            petMood: petMood.rawValue,
            timeOfDay: TimeOfDay.current().rawValue,
            generatedText: text,
            petName: petName
        )

        do {
            let existing = (try? await localStorage.loadAIInteractions()) ?? []
            try await localStorage.saveAIInteractions(existing + [interaction])
        } catch {
            ErrorReporter.log(
                .persistence(operation: "save", target: "ai_interactions.json", underlying: error.localizedDescription),
                context: "CompanionTextService.saveInteraction"
            )
        }
    }
}
