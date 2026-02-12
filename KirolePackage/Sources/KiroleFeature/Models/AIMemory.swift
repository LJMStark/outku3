import Foundation

// MARK: - AI Text Type

public enum AITextType: String, Codable, Sendable {
    case morningGreeting
    case dailySummary
    case companionPhrase
    case taskEncouragement
    case settlementSummary
    case smartReminder
}

// MARK: - AI Context

public struct AIContext: Sendable {
    public let companionStyle: CompanionStyle
    public let workType: WorkType
    public let primaryGoals: [UserGoal]
    public let petName: String
    public let petMood: PetMood
    public let currentTime: Date
    public let tasksCompletedToday: Int
    public let totalTasksToday: Int
    public let eventsToday: Int
    public let currentStreak: Int
    public let recentCompletionRate: Double
    public let behaviorSummary: UserBehaviorSummary?
    public let recentTexts: [String]

    public init(
        companionStyle: CompanionStyle = .encouraging,
        workType: WorkType = .other,
        primaryGoals: [UserGoal] = [],
        petName: String = "Baby Waffle",
        petMood: PetMood = .happy,
        currentTime: Date = Date(),
        tasksCompletedToday: Int = 0,
        totalTasksToday: Int = 0,
        eventsToday: Int = 0,
        currentStreak: Int = 0,
        recentCompletionRate: Double = 0,
        behaviorSummary: UserBehaviorSummary? = nil,
        recentTexts: [String] = []
    ) {
        self.companionStyle = companionStyle
        self.workType = workType
        self.primaryGoals = primaryGoals
        self.petName = petName
        self.petMood = petMood
        self.currentTime = currentTime
        self.tasksCompletedToday = tasksCompletedToday
        self.totalTasksToday = totalTasksToday
        self.eventsToday = eventsToday
        self.currentStreak = currentStreak
        self.recentCompletionRate = recentCompletionRate
        self.behaviorSummary = behaviorSummary
        self.recentTexts = recentTexts
    }
}

// MARK: - AI Interaction

public struct AIInteraction: Identifiable, Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let type: AITextType
    public let completionRate: Double
    public let petMood: String
    public let timeOfDay: String
    public let generatedText: String
    public let petName: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        type: AITextType,
        completionRate: Double = 0,
        petMood: String = "",
        timeOfDay: String = "",
        generatedText: String,
        petName: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.completionRate = completionRate
        self.petMood = petMood
        self.timeOfDay = timeOfDay
        self.generatedText = generatedText
        self.petName = petName
    }
}

// MARK: - User Behavior Summary

public struct UserBehaviorSummary: Codable, Sendable {
    public let weeklyCompletionRates: [Double]
    public let preferredWorkHours: WorkHourRange
    public let averageDailyTasks: Int
    public let topTaskCategories: [String]
    public let streakRecord: Int
    public let lastUpdated: Date

    public init(
        weeklyCompletionRates: [Double] = [],
        preferredWorkHours: WorkHourRange = WorkHourRange(),
        averageDailyTasks: Int = 0,
        topTaskCategories: [String] = [],
        streakRecord: Int = 0,
        lastUpdated: Date = Date()
    ) {
        self.weeklyCompletionRates = weeklyCompletionRates
        self.preferredWorkHours = preferredWorkHours
        self.averageDailyTasks = averageDailyTasks
        self.topTaskCategories = topTaskCategories
        self.streakRecord = streakRecord
        self.lastUpdated = lastUpdated
    }
}

// MARK: - Work Hour Range

public struct WorkHourRange: Codable, Sendable {
    public let start: Int
    public let end: Int

    public init(start: Int = 9, end: Int = 18) {
        self.start = start
        self.end = end
    }
}
