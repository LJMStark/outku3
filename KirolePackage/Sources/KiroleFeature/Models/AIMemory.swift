import Foundation

// MARK: - AI Text Type

public enum AITextType: String, Codable, Sendable {
    case morningGreeting
    /// Retained for Codable back-compat; box② now generates via the neutral
    /// OpenAIService.generateDaySummaryText (not the persona pipeline).
    case dailySummary
    case companionPhrase
    case taskEncouragement
    case scheduleReminder
    case settlementSummary
    case smartReminder
    /// 硬件"页面四 每日总结"金句：全部完成 → IP 风格庆祝收尾。
    case settlementQuoteCelebration
    /// 硬件"页面四 每日总结"金句：未完成但日程+专注 > 4h → IP 风格"努力了，只是任务太满"。
    case settlementQuoteOverloaded

    /// 是否为「值得纪念的时刻」——决定 Mode B（signatureQuote / 生成式金句）是否可能触发。
    ///
    /// 客户 2026-07-28 规范对三个角色都写了 Mode B «reserved for completions, milestones, or
    /// moments worth marking»，且明确 «chosen externally by the system, not guessed by you»——
    /// 即**由 App 决定何时进 Mode B**，不是每次回复都掷骰子。此前实现对所有场景一律 20%
    /// 随机，早安语也可能冒出一句 Marcus Aurelius，与规范冲突。
    ///
    /// 收束到「一天结算」这一组：`settlementSummary` 是日终结算（`resolveCompanionPhase` 在
    /// 全部完成且傍晚/夜间时才给出 `.daySettled`），两个 `settlementQuote*` 本就是硬件每日
    /// 总结页的金句槽。日常场景（早安 / 陪伴 / 任务鼓励 / 日程提醒 / 空闲）恒走 Mode A。
    public var allowsSecondaryMode: Bool {
        switch self {
        case .settlementSummary, .settlementQuoteCelebration, .settlementQuoteOverloaded:
            return true
        case .morningGreeting, .companionPhrase, .taskEncouragement,
             .scheduleReminder, .smartReminder, .dailySummary:
            return false
        }
    }
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
