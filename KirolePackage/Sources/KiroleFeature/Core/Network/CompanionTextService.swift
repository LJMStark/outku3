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

        return FallbackText.morningGreeting(for: petMood)
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

        return FallbackText.dailySummary(tasksCount: tasksCount, eventsCount: eventsCount)
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

        return FallbackText.companionPhrase(for: timeOfDay)
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

        return FallbackText.taskEncouragement()
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

        return FallbackText.settlementMessage(tasksCompleted: tasksCompleted, tasksTotal: tasksTotal)
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

        return FallbackText.smartReminder(reason: reason, petName: petName, taskTitle: taskTitle)
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

        return baseContext.replacing(recentTexts: recentTexts)
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

        return baseContext.replacing(
            recentCompletionRate: weeklyRate,
            behaviorSummary: behaviorSummary,
            recentTexts: recentTexts
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
        FallbackText.sharedPetDialogue(context: context)
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
