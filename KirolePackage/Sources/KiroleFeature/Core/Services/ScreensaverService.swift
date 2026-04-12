import Foundation

@MainActor
public final class ScreensaverService {
    public static let shared = ScreensaverService()
    
    private let openAIService: OpenAIService
    
    private init(openAIService: OpenAIService = .shared) {
        self.openAIService = openAIService
    }
    
    /// Generates or fetches the screensaver config for the current day
    public func getScreensaverConfig(
        usageDays: Int,
        currentSceneId: String,
        userProfile: UserProfile,
        topTaskTitles: [String],
        upcomingEventTitles: [String]
    ) async -> ScreensaverConfig {
        let isPostcardDay = Self.isPostcardDay(usageDays: usageDays)
        let quote = await fetchScreensaverQuote(
            isPostcard: isPostcardDay,
            usageDays: usageDays,
            userProfile: userProfile,
            topTaskTitles: topTaskTitles,
            upcomingEventTitles: upcomingEventTitles
        )

        return ScreensaverConfig(
            type: isPostcardDay ? .postcard : .normal,
            quote: quote,
            author: userProfile.companionCharacter.displayName,
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
        upcomingEventTitles: [String]
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
        let profileDigest = buildProfileDigest(userProfile: userProfile)

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
        let tasksText = topTaskTitles.isEmpty
            ? "No notable tasks"
            : "Tasks: \(topTaskTitles.prefix(3).joined(separator: ", "))"
        let eventsText = upcomingEventTitles.isEmpty
            ? "No upcoming events"
            : "Events: \(upcomingEventTitles.prefix(2).joined(separator: ", "))"
        return "\(tasksText). \(eventsText)."
    }

    private func buildProfileDigest(userProfile: UserProfile) -> String {
        let goals = userProfile.primaryGoals.map(\.displayName).joined(separator: ", ")
        let goalsText = goals.isEmpty ? "No explicit goals" : goals
        return """
            Character: \(userProfile.companionCharacter.displayName)
            Stage: \(userProfile.intimacyStage.displayName)
            Work type: \(userProfile.workType.displayName)
            Goals: \(goalsText)
            """
    }
}
