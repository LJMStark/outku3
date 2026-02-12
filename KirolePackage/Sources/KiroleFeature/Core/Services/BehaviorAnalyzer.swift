import Foundation

// MARK: - Behavior Analyzer

/// Analyzes user task behavior to generate summaries for AI personalization.
/// Pure value type with no side effects or singleton dependencies.
public struct BehaviorAnalyzer: Sendable {

    public init() {}

    /// Generate a behavior summary from user data
    public func generateSummary(
        tasks: [TaskItem],
        focusSessions: [FocusSession],
        streak: Streak
    ) -> UserBehaviorSummary {
        UserBehaviorSummary(
            weeklyCompletionRates: computeWeeklyCompletionRates(tasks: tasks),
            preferredWorkHours: computePreferredWorkHours(tasks: tasks),
            averageDailyTasks: computeAverageDailyTasks(tasks: tasks),
            topTaskCategories: computeTopTaskCategories(tasks: tasks),
            streakRecord: streak.longestStreak,
            lastUpdated: Date()
        )
    }

    // MARK: - Private Computations

    /// Last 4 weeks completion rates (oldest first).
    /// For each week, count tasks with dueDate in that week and compute completed/total.
    private func computeWeeklyCompletionRates(tasks: [TaskItem]) -> [Double] {
        let calendar = Calendar.current
        let now = Date()

        return (0..<4).reversed().map { weeksAgo -> Double in
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -weeksAgo - 1, to: now),
                  let weekEnd = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: now) else {
                return 0
            }

            let weekTasks = tasks.filter { task in
                guard let dueDate = task.dueDate else { return false }
                return dueDate >= weekStart && dueDate < weekEnd
            }

            guard !weekTasks.isEmpty else { return 0 }

            let completed = weekTasks.filter(\.isCompleted).count
            return Double(completed) / Double(weekTasks.count)
        }
    }

    /// Determine preferred work hours from completed tasks' lastModified timestamps.
    /// Finds the most common start and end hour range.
    private func computePreferredWorkHours(tasks: [TaskItem]) -> WorkHourRange {
        let completedTasks = tasks.filter(\.isCompleted)
        guard !completedTasks.isEmpty else {
            return WorkHourRange()
        }

        let calendar = Calendar.current
        let hours = completedTasks.map { calendar.component(.hour, from: $0.lastModified) }

        var hourCounts: [Int: Int] = [:]
        for hour in hours {
            hourCounts[hour, default: 0] += 1
        }

        let sortedHours = hourCounts.sorted { $0.value > $1.value }

        // Collect hours that account for significant activity (top hours covering >= 80% of tasks)
        let totalCount = hours.count
        var accumulated = 0
        var activeHours: [Int] = []
        for entry in sortedHours {
            activeHours.append(entry.key)
            accumulated += entry.value
            if Double(accumulated) / Double(totalCount) >= 0.8 {
                break
            }
        }

        activeHours.sort()

        let startHour = activeHours.first ?? 9
        let endHour = (activeHours.last ?? 17) + 1

        return WorkHourRange(start: startHour, end: min(endHour, 23))
    }

    /// Average number of tasks per day over the last 30 days.
    private func computeAverageDailyTasks(tasks: [TaskItem]) -> Int {
        let calendar = Calendar.current
        let now = Date()
        guard let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) else {
            return 0
        }

        let recentTasks = tasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return dueDate >= thirtyDaysAgo && dueDate <= now
        }

        return recentTasks.count / 30
    }

    /// Extract first word from task titles as rough categories, return top 3 by frequency.
    private func computeTopTaskCategories(tasks: [TaskItem]) -> [String] {
        var categoryCounts: [String: Int] = [:]

        for task in tasks {
            let firstWord = task.title
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: " ")
                .first
                .map(String.init) ?? ""

            guard !firstWord.isEmpty else { continue }

            let normalized = firstWord.lowercased().capitalized
            categoryCounts[normalized, default: 0] += 1
        }

        return categoryCounts
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map(\.key)
    }
}
