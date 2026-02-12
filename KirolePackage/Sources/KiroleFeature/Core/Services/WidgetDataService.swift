import Foundation
import WidgetKit

// MARK: - Widget Data Service

public final class WidgetDataService: Sendable {
    public static let shared = WidgetDataService()

    private let suiteName = "group.com.kirole.app"

    private init() {}

    // MARK: - Update Widget Data

    public func updateWidgetData(
        petName: String,
        petMood: String,
        currentStreak: Int,
        todayCompleted: Int,
        todayTotal: Int
    ) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }

        defaults.set(petName, forKey: "petName")
        defaults.set(petMood, forKey: "petMood")
        defaults.set(currentStreak, forKey: "currentStreak")
        defaults.set(todayCompleted, forKey: "todayCompleted")
        defaults.set(todayTotal, forKey: "todayTotal")
        defaults.set(Date(), forKey: "lastUpdated")

        WidgetCenter.shared.reloadAllTimelines()
    }

    public func updateFromAppState(pet: Pet, streak: Streak, statistics: TaskStatistics) {
        updateWidgetData(
            petName: pet.name,
            petMood: pet.mood.rawValue,
            currentStreak: streak.currentStreak,
            todayCompleted: statistics.todayCompleted,
            todayTotal: statistics.todayTotal
        )
    }
}
