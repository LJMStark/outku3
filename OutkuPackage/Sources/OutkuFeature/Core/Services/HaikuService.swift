import Foundation

// MARK: - Haiku Service

/// Haiku 业务逻辑服务
public actor HaikuService {
    public static let shared = HaikuService()

    private let openAIService = OpenAIService.shared
    private let localStorage = LocalStorage.shared

    private init() {}

    // MARK: - Get Today's Haiku

    /// 获取今日 Haiku（优先使用缓存）
    /// - Parameters:
    ///   - context: Haiku 生成上下文
    ///   - forceRefresh: 是否强制刷新
    /// - Returns: Haiku
    public func getTodayHaiku(
        context: HaikuContext,
        forceRefresh: Bool = false
    ) async -> Haiku {
        let today = Date()

        // 检查缓存
        if !forceRefresh {
            if let cached = try? await localStorage.getCachedHaiku(for: today) {
                return cached
            }
        }

        // 生成新的 Haiku
        do {
            let haiku = try await openAIService.generateHaiku(context: context)

            // 缓存
            try? await localStorage.cacheHaiku(haiku, for: today)

            return haiku
        } catch {
            // 生成失败，返回默认 Haiku
            return getDefaultHaiku(for: context)
        }
    }

    // MARK: - Generate on Task Completion

    /// 任务完成时生成 Haiku
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

    /// 根据上下文获取默认 Haiku
    private func getDefaultHaiku(for context: HaikuContext) -> Haiku {
        let hour = Calendar.current.component(.hour, from: context.currentTime)

        if hour < 6 {
            return Haiku(lines: [
                "Stars fade to morning",
                "A new day waits patiently",
                "Dreams become actions"
            ])
        } else if hour < 12 {
            return Haiku(lines: [
                "Morning light arrives",
                "Tasks await with gentle hope",
                "One step at a time"
            ])
        } else if hour < 17 {
            return Haiku(lines: [
                "Afternoon sun glows",
                "Progress blooms like spring flowers",
                "Keep moving forward"
            ])
        } else if hour < 21 {
            return Haiku(lines: [
                "Evening shadows fall",
                "Today's work finds its ending",
                "Rest well, start again"
            ])
        } else {
            return Haiku(lines: [
                "Night wraps the world soft",
                "Tomorrow holds new promise",
                "Sleep brings renewal"
            ])
        }
    }

    /// 任务完成时的默认 Haiku
    private func getCompletionHaiku(tasksCompleted: Int, totalTasks: Int) -> Haiku {
        if tasksCompleted == totalTasks && totalTasks > 0 {
            // 全部完成
            return Haiku(lines: [
                "All tasks completed",
                "Like petals falling gently",
                "Achievement blooms bright"
            ])
        } else if tasksCompleted > totalTasks / 2 {
            // 过半
            return Haiku(lines: [
                "Halfway through the day",
                "Each task a stepping stone placed",
                "The path grows clearer"
            ])
        } else {
            // 刚开始
            return Haiku(lines: [
                "One task at a time",
                "Small streams become great rivers",
                "Progress flows steady"
            ])
        }
    }

    // MARK: - Seasonal Haikus

    /// 获取季节性 Haiku
    public func getSeasonalHaiku() -> Haiku {
        let month = Calendar.current.component(.month, from: Date())

        switch month {
        case 3...5: // Spring
            return Haiku(lines: [
                "Cherry blossoms fall",
                "New beginnings take their root",
                "Growth comes with patience"
            ])
        case 6...8: // Summer
            return Haiku(lines: [
                "Summer sun burns bright",
                "Energy flows like warm breeze",
                "Seize the longest days"
            ])
        case 9...11: // Fall
            return Haiku(lines: [
                "Leaves turn gold and red",
                "Harvest time for all your work",
                "Reap what you have sown"
            ])
        default: // Winter
            return Haiku(lines: [
                "Snow blankets the earth",
                "Quiet reflection brings peace",
                "Spring waits underneath"
            ])
        }
    }
}
