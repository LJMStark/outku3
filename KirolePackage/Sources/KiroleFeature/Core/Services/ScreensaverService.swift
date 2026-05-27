import Foundation

@MainActor
public final class ScreensaverService {
    public static let shared = ScreensaverService()
    
    private let openAIService: OpenAIService
    
    private init(openAIService: OpenAIService = .shared) {
        self.openAIService = openAIService
    }
    
    /// Generates or fetches the screensaver config for the current day.
    /// `customCompanion`, when set, replaces the built-in character as the quote's author
    /// and rewrites the persona digest fed to the AI quote generator.
    public func getScreensaverConfig(
        usageDays: Int,
        currentSceneId: String,
        userProfile: UserProfile,
        topTaskTitles: [String],
        upcomingEventTitles: [String],
        customCompanion: CustomCompanion? = nil
    ) async -> ScreensaverConfig {
        let isPostcardDay = Self.isPostcardDay(usageDays: usageDays)
        let quote = await fetchScreensaverQuote(
            isPostcard: isPostcardDay,
            usageDays: usageDays,
            userProfile: userProfile,
            topTaskTitles: topTaskTitles,
            upcomingEventTitles: upcomingEventTitles,
            customCompanion: customCompanion
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
    
    private func fetchScreensaverQuote(
        isPostcard: Bool,
        usageDays: Int,
        userProfile: UserProfile,
        topTaskTitles: [String],
        upcomingEventTitles: [String],
        customCompanion: CustomCompanion?
    ) async -> String {
        // Fallback static quotes
        let defaultQuotes = [
            "Rest is a part of the journey.",
            "Take a deep breath and relax.",
            "You did great today."
        ]

        let isConfig = await openAIService.isConfigured
        if !isConfig {
            return defaultQuotes.randomElement() ?? "Rest is a part of the journey."
        }

        let workDigest = buildWorkDigest(
            topTaskTitles: topTaskTitles,
            upcomingEventTitles: upcomingEventTitles
        )
        let profileDigest = buildProfileDigest(userProfile: userProfile, customCompanion: customCompanion)

        do {
            return try await openAIService.generateScreensaverQuote(
                isPostcard: isPostcard,
                usageDays: usageDays,
                workContext: workDigest,
                profileContext: profileDigest
            )
        } catch {
            return defaultQuotes.randomElement()!
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
            let roastSuffix = custom.roastModeEnabled ? " · Roast Mode" : ""
            characterBlock = """
                Character: \(safeName) (custom companion)
                Relationship: \(custom.relationship.displayName)
                Voice: \(custom.personaVoice.displayName)\(roastSuffix)
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
