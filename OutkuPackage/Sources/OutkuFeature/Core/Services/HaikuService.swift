import Foundation

// MARK: - Haiku Service

public actor HaikuService {
    public static let shared = HaikuService()

    private let openAIService = OpenAIService.shared
    private let localStorage = LocalStorage.shared

    private init() {}

    // MARK: - Get Today's Haiku

    public func getTodayHaiku(
        context: HaikuContext,
        forceRefresh: Bool = false
    ) async -> Haiku {
        let today = Date()

        if !forceRefresh, let cached = try? await localStorage.getCachedHaiku(for: today) {
            return cached
        }

        do {
            let haiku = try await openAIService.generateHaiku(context: context)
            try? await localStorage.cacheHaiku(haiku, for: today)
            return haiku
        } catch {
            return getDefaultHaiku(for: context)
        }
    }

    // MARK: - Generate on Task Completion

    public func generateCompletionHaiku(
        tasksCompleted: Int,
        totalTasks: Int,
        petMood: PetMood,
        streak: Int
    ) async -> Haiku {
        let context = HaikuContext(
            currentTime: Date(),
            tasksCompletedToday: tasksCompleted,
            totalTasksToday: totalTasks,
            petMood: petMood,
            currentStreak: streak
        )

        do {
            return try await openAIService.generateHaiku(context: context)
        } catch {
            return getCompletionHaiku(tasksCompleted: tasksCompleted, totalTasks: totalTasks)
        }
    }

    // MARK: - Default Haikus

    private func getDefaultHaiku(for context: HaikuContext) -> Haiku {
        let hour = Calendar.current.component(.hour, from: context.currentTime)

        switch hour {
        case 0..<6:
            return Haiku(lines: ["Stars fade to morning", "A new day waits patiently", "Dreams become actions"])
        case 6..<12:
            return Haiku(lines: ["Morning light arrives", "Tasks await with gentle hope", "One step at a time"])
        case 12..<17:
            return Haiku(lines: ["Afternoon sun glows", "Progress blooms like spring flowers", "Keep moving forward"])
        case 17..<21:
            return Haiku(lines: ["Evening shadows fall", "Today's work finds its ending", "Rest well, start again"])
        default:
            return Haiku(lines: ["Night wraps the world soft", "Tomorrow holds new promise", "Sleep brings renewal"])
        }
    }

    private func getCompletionHaiku(tasksCompleted: Int, totalTasks: Int) -> Haiku {
        if tasksCompleted == totalTasks && totalTasks > 0 {
            return Haiku(lines: ["All tasks completed", "Like petals falling gently", "Achievement blooms bright"])
        } else if tasksCompleted > totalTasks / 2 {
            return Haiku(lines: ["Halfway through the day", "Each task a stepping stone placed", "The path grows clearer"])
        } else {
            return Haiku(lines: ["One task at a time", "Small streams become great rivers", "Progress flows steady"])
        }
    }

    // MARK: - Seasonal Haikus

    public func getSeasonalHaiku() -> Haiku {
        let month = Calendar.current.component(.month, from: Date())

        switch month {
        case 3...5:
            return Haiku(lines: ["Cherry blossoms fall", "New beginnings take their root", "Growth comes with patience"])
        case 6...8:
            return Haiku(lines: ["Summer sun burns bright", "Energy flows like warm breeze", "Seize the longest days"])
        case 9...11:
            return Haiku(lines: ["Leaves turn gold and red", "Harvest time for all your work", "Reap what you have sown"])
        default:
            return Haiku(lines: ["Snow blankets the earth", "Quiet reflection brings peace", "Spring waits underneath"])
        }
    }
}
