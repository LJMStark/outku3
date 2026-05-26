import Foundation

// MARK: - AI Text Type

public enum AITextType: String, Codable, Sendable {
    case morningGreeting
    case dailySummary
    case companionPhrase
    case taskEncouragement
    case scheduleReminder
    case settlementSummary
    case smartReminder
}

// MARK: - AI Context

public struct AIContext: Sendable {
    public var companionStyle: CompanionStyle { companionCharacter.resolvedStyle }
    public let companionCharacter: CompanionCharacter
    public let intimacyStage: IntimacyStage
    public let workType: WorkType
    public let primaryGoals: [UserGoal]
    public let petName: String
    public let petMood: PetMood
    public let currentTime: Date
    public let tasksCompletedToday: Int
    public let totalTasksToday: Int
    public let eventsToday: Int
    public let recentCompletionRate: Double
    public let behaviorSummary: UserBehaviorSummary?
    public let recentTexts: [String]
    public let focusTimeToday: Int
    public let energyBottles: Int
    public let currentSceneName: String?
    public let hardwareConnected: Bool
    public let nextAgendaItem: String?
    public let activeTaskTitle: String?
    public let topTaskTitles: [String]
    
    // MARK: - Advanced Persona Engineering Subsystems
    public let episodicMemories: [String]
    public let dimensionalEmotion: String?
    public let psychologicalObjective: String?
    public let userDefinedLearnText: String?

    /// When set, the active companion is user-created. Prompt assembly should use this
    /// in place of the built-in `companionCharacter` style description.
    public let customCompanion: CustomCompanion?

    public init(
        companionCharacter: CompanionCharacter = .joy,
        intimacyStage: IntimacyStage = .acquaintance,
        workType: WorkType = .other,
        primaryGoals: [UserGoal] = [],
        petName: String = "Baby Waffle",
        petMood: PetMood = .happy,
        currentTime: Date = Date(),
        tasksCompletedToday: Int = 0,
        totalTasksToday: Int = 0,
        eventsToday: Int = 0,
        recentCompletionRate: Double = 0,
        behaviorSummary: UserBehaviorSummary? = nil,
        recentTexts: [String] = [],
        focusTimeToday: Int = 0,
        energyBottles: Int = 0,
        currentSceneName: String? = nil,
        hardwareConnected: Bool = false,
        nextAgendaItem: String? = nil,
        activeTaskTitle: String? = nil,
        topTaskTitles: [String] = [],
        episodicMemories: [String] = [],
        dimensionalEmotion: String? = nil,
        psychologicalObjective: String? = nil,
        userDefinedLearnText: String? = nil,
        customCompanion: CustomCompanion? = nil
    ) {
        self.companionCharacter = companionCharacter
        self.intimacyStage = intimacyStage
        self.workType = workType
        self.primaryGoals = primaryGoals
        self.petName = petName
        self.petMood = petMood
        self.currentTime = currentTime
        self.tasksCompletedToday = tasksCompletedToday
        self.totalTasksToday = totalTasksToday
        self.eventsToday = eventsToday
        self.recentCompletionRate = recentCompletionRate
        self.behaviorSummary = behaviorSummary
        self.recentTexts = recentTexts
        self.focusTimeToday = focusTimeToday
        self.energyBottles = energyBottles
        self.currentSceneName = currentSceneName
        self.hardwareConnected = hardwareConnected
        self.nextAgendaItem = nextAgendaItem
        self.activeTaskTitle = activeTaskTitle
        self.topTaskTitles = topTaskTitles
        
        self.episodicMemories = episodicMemories
        self.dimensionalEmotion = dimensionalEmotion
        self.psychologicalObjective = psychologicalObjective
        self.userDefinedLearnText = userDefinedLearnText
        self.customCompanion = customCompanion
    }

    func replacing(recentTexts: [String]) -> AIContext {
        replacing(
            recentCompletionRate: recentCompletionRate,
            behaviorSummary: behaviorSummary,
            recentTexts: recentTexts
        )
    }

    func replacing(
        recentCompletionRate: Double,
        behaviorSummary: UserBehaviorSummary?,
        recentTexts: [String]
    ) -> AIContext {
        AIContext(
            companionCharacter: companionCharacter,
            intimacyStage: intimacyStage,
            workType: workType,
            primaryGoals: primaryGoals,
            petName: petName,
            petMood: petMood,
            currentTime: currentTime,
            tasksCompletedToday: tasksCompletedToday,
            totalTasksToday: totalTasksToday,
            eventsToday: eventsToday,
            recentCompletionRate: recentCompletionRate,
            behaviorSummary: behaviorSummary,
            recentTexts: recentTexts,
            focusTimeToday: focusTimeToday,
            energyBottles: energyBottles,
            currentSceneName: currentSceneName,
            hardwareConnected: hardwareConnected,
            nextAgendaItem: nextAgendaItem,
            activeTaskTitle: activeTaskTitle,
            topTaskTitles: topTaskTitles,
            episodicMemories: episodicMemories,
            dimensionalEmotion: dimensionalEmotion,
            psychologicalObjective: psychologicalObjective,
            userDefinedLearnText: userDefinedLearnText,
            customCompanion: customCompanion
        )
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
    public let lastUpdated: Date

    public init(
        weeklyCompletionRates: [Double] = [],
        preferredWorkHours: WorkHourRange = WorkHourRange(),
        averageDailyTasks: Int = 0,
        topTaskCategories: [String] = [],
        lastUpdated: Date = Date()
    ) {
        self.weeklyCompletionRates = weeklyCompletionRates
        self.preferredWorkHours = preferredWorkHours
        self.averageDailyTasks = averageDailyTasks
        self.topTaskCategories = topTaskCategories
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
