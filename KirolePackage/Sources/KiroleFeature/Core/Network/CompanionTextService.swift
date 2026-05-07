import Foundation

enum CompanionTextGenerationMode {
    case live
    case preview

    var shouldPersistInteractions: Bool {
        self == .live
    }
}

// MARK: - Companion Text Service

/// 文案生成服务 - 生成早安问候、日程总结、陪伴短句等
/// 优先使用 OpenAI 生成个性化文案，无 API Key 或失败时回退到本地模板
@MainActor
public final class CompanionTextService {
    public static let shared = CompanionTextService()

    private let openAI = OpenAIService.shared
    private let localStorage = LocalStorage.shared
    nonisolated private static let dialogueMaxAttempts = 3
    nonisolated private static let dialogueInvalidBackoffMs: [UInt64] = [250, 700]
    nonisolated private static let dialogueErrorBackoffMs: [UInt64] = [800, 1800]
    nonisolated private static let dialogueRateLimitBackoffMs: [UInt64] = [1800, 3600]

    private init() {}

    // MARK: - Morning Greeting

    public func generateMorningGreeting(
        petName: String, petMood: PetMood, weather: Weather,
        userProfile: UserProfile = .default
    ) async -> String {
        let memory = "The user has just woken up and is starting their day."
        if let aiText = await generateAIText(
            type: .morningGreeting,
            petName: petName, petMood: petMood,
            userProfile: userProfile,
            episodicMemories: [memory]
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
        let payload = Self.taskEncouragementPromptPayload(taskTitle: taskTitle)
        if let aiText = await generateAIText(
            type: .taskEncouragement,
            petName: petName, petMood: petMood,
            userProfile: userProfile,
            episodicMemories: [payload.memory],
            nextAgendaItem: payload.nextAgendaItem,
            activeTaskTitle: payload.activeTaskTitle
        ) {
            return aiText
        }

        return ["You can do this!", "Focus and conquer!", "One task at a time.", "Let's get it done!",
                "Believe in yourself!", "Small steps, big wins.", "Stay focused!", "You're capable of this."]
            .randomElement() ?? "You've got this!"
    }

    nonisolated static func taskEncouragementPromptPayload(taskTitle: String) -> (
        memory: String,
        nextAgendaItem: String,
        activeTaskTitle: String
    ) {
        (
            memory: "The user has actively entered the focus task: \(taskTitle)",
            nextAgendaItem: taskTitle,
            activeTaskTitle: taskTitle
        )
    }

    // MARK: - Settlement Message

    public func generateSettlementMessage(
        tasksCompleted: Int, tasksTotal: Int, petName: String,
        focusTimeToday: Int = 0, energyBottles: Int = 0,
        userProfile: UserProfile = .default
    ) async -> String {
        let memory = "The user has completed their daily work. Settling today's tasks."
        if let aiText = await generateAIText(
            type: .settlementSummary,
            petName: petName, petMood: .happy,
            userProfile: userProfile,
            completedTasks: tasksCompleted, totalTasks: tasksTotal,
            episodicMemories: [memory],
            focusTimeToday: focusTimeToday,
            energyBottles: energyBottles
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
        userProfile: UserProfile = .default
    ) async -> String {
        if let aiText = await generateAIText(
            type: .smartReminder,
            petName: petName, petMood: petMood,
            userProfile: userProfile
        ) {
            return aiText
        }

        return smartReminderFallback(reason: reason, petName: petName, taskTitle: taskTitle)
    }

    private func smartReminderFallback(reason: ReminderReason, petName: String, taskTitle: String?) -> String {
        switch reason {
        case .idle:
            return "\(petName) misses you! Time to get back on track."
        case .deadline:
            if let title = taskTitle {
                return "\(title) is due soon. Let's finish it!"
            }
            return "You have a task due soon!"
        case .gentleNudge:
            return "Ready for the next task? \(petName) believes in you."
        }
    }

    public func generateSharedPetDialogue(
        baseContext: AIContext,
        type: AITextType = .smartReminder
    ) async -> String {
        await generateSharedPetDialogue(baseContext: baseContext, type: type, mode: .live)
    }

    public func previewSharedPetDialogue(baseContext: AIContext, type: AITextType = .smartReminder) async -> String {
        await generateSharedPetDialogue(baseContext: baseContext, type: type, mode: .preview)
    }

    private func generateSharedPetDialogue(
        baseContext: AIContext,
        type: AITextType = .smartReminder,
        mode: CompanionTextGenerationMode
    ) async -> String {
        let enrichedBaseContext = await enrichedContext(for: type, baseContext: baseContext)
        let historyTexts = enrichedBaseContext.recentTexts
        var rejectedTexts: [String] = []

        for attempt in 0..<Self.dialogueMaxAttempts {
            let attemptContext = dialogueAttemptContext(
                from: enrichedBaseContext,
                historyTexts: historyTexts,
                rejectedTexts: rejectedTexts
            )

            do {
                let aiText = try await openAI.generateCompanionText(type: type, context: attemptContext)
                let normalized = CompanionDialogueDisplayPolicy.normalized(aiText)

                if CompanionDialogueDisplayPolicy.isValidForDisplay(normalized) {
                    if mode.shouldPersistInteractions {
                        await saveInteraction(
                            type: type,
                            text: normalized,
                            petName: attemptContext.petName,
                            petMood: attemptContext.petMood,
                            completionRate: attemptContext.recentCompletionRate
                        )
                    }
                    return normalized
                }

                rejectedTexts.append(normalized)

                if attempt < Self.dialogueMaxAttempts - 1 {
                    try? await Task.sleep(
                        for: .milliseconds(Self.dialogueInvalidBackoffMs[attempt])
                    )
                }
            } catch {
                #if DEBUG
                print("[CompanionText] Shared dialogue generation failed for \(type.rawValue): \(error.localizedDescription)")
                #endif
                guard attempt < Self.dialogueMaxAttempts - 1,
                      Self.shouldRetrySharedDialogue(after: error) else {
                    break
                }

                try? await Task.sleep(
                    for: .milliseconds(Self.dialogueErrorBackoff(for: error, attempt: attempt))
                )
            }
        }

        let fallback = CompanionDialogueDisplayPolicy.normalized(sharedPetDialogueFallback(baseContext))
        if CompanionDialogueDisplayPolicy.isValidForDisplay(fallback) {
            return fallback
        }

        return "I am right here with you, and this moment can stay gentle."
    }

    private func dialogueAttemptContext(
        from baseContext: AIContext,
        historyTexts: [String],
        rejectedTexts: [String]
    ) -> AIContext {
        let recentTexts = Array((historyTexts + rejectedTexts).suffix(3))

        return AIContext(
            companionCharacter: baseContext.companionCharacter,
            intimacyStage: baseContext.intimacyStage,
            workType: baseContext.workType,
            primaryGoals: baseContext.primaryGoals,
            petName: baseContext.petName,
            petMood: baseContext.petMood,
            currentTime: baseContext.currentTime,
            tasksCompletedToday: baseContext.tasksCompletedToday,
            totalTasksToday: baseContext.totalTasksToday,
            eventsToday: baseContext.eventsToday,
            recentCompletionRate: baseContext.recentCompletionRate,
            behaviorSummary: baseContext.behaviorSummary,
            recentTexts: recentTexts,
            focusTimeToday: baseContext.focusTimeToday,
            energyBottles: baseContext.energyBottles,
            currentSceneName: baseContext.currentSceneName,
            hardwareConnected: baseContext.hardwareConnected,
            nextAgendaItem: baseContext.nextAgendaItem,
            activeTaskTitle: baseContext.activeTaskTitle,
            topTaskTitles: baseContext.topTaskTitles,
            episodicMemories: baseContext.episodicMemories,
            dimensionalEmotion: baseContext.dimensionalEmotion,
            psychologicalObjective: baseContext.psychologicalObjective,
            userDefinedLearnText: baseContext.userDefinedLearnText
        )
    }

    nonisolated static func shouldRetrySharedDialogue(after error: Error) -> Bool {
        switch error {
        case let urlError as URLError:
            switch urlError.code {
            case .timedOut,
                 .networkConnectionLost,
                 .cannotConnectToHost,
                 .cannotFindHost,
                 .dnsLookupFailed:
                return true
            default:
                return false
            }
        case let networkError as NetworkError:
            switch networkError {
            case .rateLimited, .serverError, .invalidResponse:
                return true
            default:
                return false
            }
        case let openAIError as OpenAIError:
            switch openAIError {
            case .emptyResponse, .rateLimited:
                return true
            default:
                return false
            }
        default:
            return false
        }
    }

    nonisolated private static func dialogueErrorBackoff(for error: Error, attempt: Int) -> UInt64 {
        let clampedAttempt = min(attempt, dialogueErrorBackoffMs.count - 1)

        if case NetworkError.rateLimited = error {
            return dialogueRateLimitBackoffMs[clampedAttempt]
        }

        if case OpenAIError.rateLimited = error {
            return dialogueRateLimitBackoffMs[clampedAttempt]
        }

        return dialogueErrorBackoffMs[clampedAttempt]
    }

    // MARK: - AI Text Generation

    private func generateAIText(
        type: AITextType,
        petName: String, petMood: PetMood,
        userProfile: UserProfile,
        mode: CompanionTextGenerationMode = .live,
        completedTasks: Int = 0, totalTasks: Int = 0,
        events: Int = 0,
        episodicMemories: [String] = [],
        nextAgendaItem: String? = nil,
        activeTaskTitle: String? = nil,
        focusTimeToday: Int = 0,
        energyBottles: Int = 0
    ) async -> String? {
        guard await openAI.isConfigured else { return nil }

        let behaviorSummary: UserBehaviorSummary?
        do {
            behaviorSummary = try await localStorage.loadBehaviorSummary()
        } catch {
            ErrorReporter.log(
                .persistence(operation: "load", target: "behavior_summary", underlying: error.localizedDescription),
                context: "CompanionTextService.generateCompanionText"
            )
            behaviorSummary = nil
        }
        let weeklyRate = resolvedWeeklyRate(
            behaviorSummary: behaviorSummary,
            completedTasks: completedTasks,
            totalTasks: totalTasks
        )

        let baseContext = AIContext(
            companionCharacter: userProfile.companionCharacter,
            intimacyStage: userProfile.intimacyStage,
            workType: userProfile.workType,
            primaryGoals: userProfile.primaryGoals,
            petName: petName,
            petMood: petMood,
            tasksCompletedToday: completedTasks,
            totalTasksToday: totalTasks,
            eventsToday: events,
            recentCompletionRate: weeklyRate,
            behaviorSummary: behaviorSummary,
            recentTexts: [],
            focusTimeToday: focusTimeToday,
            energyBottles: energyBottles,
            nextAgendaItem: nextAgendaItem,
            activeTaskTitle: activeTaskTitle,
            episodicMemories: episodicMemories
        )

        return await generateAIText(type: type, baseContext: baseContext, mode: mode)
    }

    private func generateAIText(
        type: AITextType,
        baseContext: AIContext,
        mode: CompanionTextGenerationMode = .live
    ) async -> String? {
        guard await openAI.isConfigured else { return nil }
        let context = await enrichedContext(for: type, baseContext: baseContext)

        do {
            let text = try await openAI.generateCompanionText(type: type, context: context)
            if mode.shouldPersistInteractions {
                await saveInteraction(
                    type: type,
                    text: text,
                    petName: context.petName,
                    petMood: context.petMood,
                    completionRate: context.recentCompletionRate
                )
            }
            return text
        } catch {
            #if DEBUG
            print("[CompanionText] AI generation failed for \(type.rawValue): \(error.localizedDescription)")
            return "[Error] \(error.localizedDescription)"
            #else
            return nil
            #endif
        }
    }

    private func enrichedContext(for type: AITextType, baseContext: AIContext) async -> AIContext {
        let recentTexts = baseContext.recentTexts.isEmpty ? await loadRecentTexts(type: type) : baseContext.recentTexts
        let behaviorSummary: UserBehaviorSummary?
        if let existingSummary = baseContext.behaviorSummary {
            behaviorSummary = existingSummary
        } else {
            do {
                behaviorSummary = try await localStorage.loadBehaviorSummary()
            } catch {
                ErrorReporter.log(
                    .persistence(operation: "load", target: "behavior_summary", underlying: error.localizedDescription),
                    context: "CompanionTextService.enrichedContext"
                )
                behaviorSummary = nil
            }
        }
        let weeklyRate = resolvedWeeklyRate(
            behaviorSummary: behaviorSummary,
            completedTasks: baseContext.tasksCompletedToday,
            totalTasks: baseContext.totalTasksToday,
            preferredRate: baseContext.recentCompletionRate
        )

        return AIContext(
            companionCharacter: baseContext.companionCharacter,
            intimacyStage: baseContext.intimacyStage,
            workType: baseContext.workType,
            primaryGoals: baseContext.primaryGoals,
            petName: baseContext.petName,
            petMood: baseContext.petMood,
            currentTime: baseContext.currentTime,
            tasksCompletedToday: baseContext.tasksCompletedToday,
            totalTasksToday: baseContext.totalTasksToday,
            eventsToday: baseContext.eventsToday,
            recentCompletionRate: weeklyRate,
            behaviorSummary: behaviorSummary,
            recentTexts: recentTexts,
            focusTimeToday: baseContext.focusTimeToday,
            energyBottles: baseContext.energyBottles,
            currentSceneName: baseContext.currentSceneName,
            hardwareConnected: baseContext.hardwareConnected,
            nextAgendaItem: baseContext.nextAgendaItem,
            activeTaskTitle: baseContext.activeTaskTitle,
            topTaskTitles: baseContext.topTaskTitles,
            episodicMemories: baseContext.episodicMemories,
            dimensionalEmotion: baseContext.dimensionalEmotion,
            psychologicalObjective: baseContext.psychologicalObjective,
            userDefinedLearnText: baseContext.userDefinedLearnText
        )
    }

    private func resolvedWeeklyRate(
        behaviorSummary: UserBehaviorSummary?,
        completedTasks: Int,
        totalTasks: Int,
        preferredRate: Double? = nil
    ) -> Double {
        if let preferredRate, preferredRate > 0 {
            return preferredRate
        }

        if let rates = behaviorSummary?.weeklyCompletionRates, let last = rates.last {
            return last
        }

        guard totalTasks > 0 else { return 0 }
        return Double(completedTasks) / Double(totalTasks)
    }

    private func sharedPetDialogueFallback(_ context: AIContext) -> String {
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

    // MARK: - Interaction Persistence

    private func loadRecentTexts(type: AITextType) async -> [String] {
        let interactions: [AIInteraction]
        do {
            interactions = (try await localStorage.loadAIInteractions()) ?? []
        } catch {
            ErrorReporter.log(
                .persistence(operation: "load", target: "ai_interactions.json", underlying: error.localizedDescription),
                context: "CompanionTextService.loadRecentTexts"
            )
            return []
        }
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
            let existing: [AIInteraction]
            do {
                existing = (try await localStorage.loadAIInteractions()) ?? []
            } catch {
                ErrorReporter.log(
                    .persistence(operation: "load", target: "ai_interactions.json", underlying: error.localizedDescription),
                    context: "CompanionTextService.saveInteraction"
                )
                existing = []
            }
            try await localStorage.saveAIInteractions(existing + [interaction])
        } catch {
            ErrorReporter.log(
                .persistence(operation: "save", target: "ai_interactions.json", underlying: error.localizedDescription),
                context: "CompanionTextService.saveInteraction"
            )
        }
    }
}
