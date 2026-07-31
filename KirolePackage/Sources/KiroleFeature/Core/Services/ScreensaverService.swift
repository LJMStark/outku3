import Foundation

protocol ScreensaverQuoteGenerating: Sendable {
    func isConfiguredForScreensaverQuote() async -> Bool
    func generateScreensaverQuote(
        isPostcard: Bool,
        usageDays: Int,
        workContext: String,
        profileContext: String
    ) async throws -> String
}

extension OpenAIService: ScreensaverQuoteGenerating {
    func isConfiguredForScreensaverQuote() -> Bool {
        isConfigured
    }
}

@MainActor
public final class ScreensaverService {
    public static let shared = ScreensaverService()

    static let fallbackQuote = "Rest is a part of the journey."

    private struct QuoteCacheKey: Hashable {
        let isPostcard: Bool
        let usageDays: Int
        let workDigest: String
        let profileDigest: String
    }

    private let quoteGenerator: any ScreensaverQuoteGenerating
    private var quoteCache: [QuoteCacheKey: String] = [:]
    private var pendingGenerations: [QuoteCacheKey: Task<Void, Never>] = [:]

    private convenience init() {
        self.init(quoteGenerator: OpenAIService.shared)
    }

    init(quoteGenerator: any ScreensaverQuoteGenerating) {
        self.quoteGenerator = quoteGenerator
    }

    /// Returns a screensaver config without waiting for the network.
    ///
    /// A cache miss uses a deterministic local quote for the current sleep event and warms
    /// the matching AI quote in the background. The generated text is used only by a later
    /// sleep event, so a delayed response cannot redraw a device that has already woken up.
    /// `customCompanion`, when set, replaces the built-in character as the quote's author
    /// and rewrites the persona digest fed to the AI quote generator.
    public func getScreensaverConfig(
        usageDays: Int,
        currentSceneId: String,
        userProfile: UserProfile,
        topTaskTitles: [String],
        upcomingEventTitles: [String],
        customCompanion: CustomCompanion? = nil
    ) -> ScreensaverConfig {
        let isPostcardDay = Self.isPostcardDay(usageDays: usageDays)
        let workDigest = buildWorkDigest(
            topTaskTitles: topTaskTitles,
            upcomingEventTitles: upcomingEventTitles
        )
        let profileDigest = buildProfileDigest(
            userProfile: userProfile,
            customCompanion: customCompanion
        )
        let cacheKey = QuoteCacheKey(
            isPostcard: isPostcardDay,
            usageDays: usageDays,
            workDigest: workDigest,
            profileDigest: profileDigest
        )
        let quote = quoteCache[cacheKey] ?? Self.fallbackQuote

        scheduleQuoteGenerationIfNeeded(
            for: cacheKey,
            isPostcard: isPostcardDay,
            usageDays: usageDays,
            workDigest: workDigest,
            profileDigest: profileDigest
        )

        return ScreensaverConfig(
            type: isPostcardDay ? .postcard : .normal,
            quote: quote,
            author: customCompanion?.name ?? userProfile.companionCharacter.displayName,
            sceneId: currentSceneId,
            postcardDay: isPostcardDay ? usageDays : nil
        )
    }
    
    public static func isPostcardDay(usageDays: Int) -> Bool {
        [3, 7, 21].contains(usageDays)
    }

    func waitForPendingGeneration() async {
        let tasks = Array(pendingGenerations.values)
        for task in tasks {
            await task.value
        }
    }

    private func scheduleQuoteGenerationIfNeeded(
        for cacheKey: QuoteCacheKey,
        isPostcard: Bool,
        usageDays: Int,
        workDigest: String,
        profileDigest: String
    ) {
        guard quoteCache[cacheKey] == nil,
              pendingGenerations[cacheKey] == nil else {
            return
        }

        let generator = quoteGenerator
        pendingGenerations[cacheKey] = Task { [weak self] in
            guard await generator.isConfiguredForScreensaverQuote() else {
                self?.pendingGenerations[cacheKey] = nil
                return
            }

            do {
                let quote = try await generator.generateScreensaverQuote(
                    isPostcard: isPostcard,
                    usageDays: usageDays,
                    workContext: workDigest,
                    profileContext: profileDigest
                ).trimmingCharacters(in: .whitespacesAndNewlines)
                if !quote.isEmpty {
                    self?.quoteCache[cacheKey] = quote
                }
            } catch {
                // The immediate fallback has already been returned. Retry on a later sleep.
            }
            self?.pendingGenerations[cacheKey] = nil
        }
    }

    private func buildWorkDigest(topTaskTitles: [String], upcomingEventTitles: [String]) -> String {
        let safeTasks = topTaskTitles.prefix(3).map { PromptSanitizer.sanitize($0, maxLen: 60) }
        let safeEvents = upcomingEventTitles.prefix(2).map { PromptSanitizer.sanitize($0, maxLen: 60) }
        let tasksText = safeTasks.isEmpty ? "No notable tasks" : "Tasks: \(safeTasks.joined(separator: ", "))"
        let eventsText = safeEvents.isEmpty ? "No upcoming events" : "Events: \(safeEvents.joined(separator: ", "))"
        return "\(tasksText). \(eventsText)."
    }

    private func buildProfileDigest(userProfile: UserProfile, customCompanion: CustomCompanion?) -> String {
        let goals = userProfile.primaryGoals.map(\.displayName).joined(separator: ", ")
        let goalsText = goals.isEmpty ? "No explicit goals" : goals
        let characterBlock: String
        if let custom = customCompanion {
            let safeName = PromptSanitizer.sanitize(custom.name, maxLen: 60)
            characterBlock = """
                Character: \(safeName) (custom companion)
                Relationship: \(custom.relationship.displayName)
                Voice: \(custom.personaVoice.displayName)
                """
        } else {
            characterBlock = "Character: \(userProfile.companionCharacter.displayName)"
        }
        return """
            \(characterBlock)
            Stage: \(userProfile.intimacyStage.displayName)
            Work type: \(userProfile.workType.displayName)
            Goals: \(goalsText)
            """
    }
}
