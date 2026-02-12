import Testing
import Foundation
@testable import KiroleFeature

// MARK: - AI Context Tests

@Test func testAIContextIncludesAllUserProfileFields() async throws {
    let context = AIContext(
        companionStyle: .playful,
        workType: .freelancer,
        primaryGoals: [.productivity, .focus],
        petName: "TestPet",
        petMood: .excited,
        tasksCompletedToday: 3,
        totalTasksToday: 5,
        eventsToday: 2,
        currentStreak: 7,
        recentCompletionRate: 0.85
    )

    #expect(context.companionStyle == .playful)
    #expect(context.workType == .freelancer)
    #expect(context.primaryGoals.count == 2)
    #expect(context.petName == "TestPet")
    #expect(context.petMood == .excited)
    #expect(context.tasksCompletedToday == 3)
    #expect(context.totalTasksToday == 5)
    #expect(context.eventsToday == 2)
    #expect(context.currentStreak == 7)
    #expect(context.recentCompletionRate == 0.85)
}

@Test func testAIContextDefaultValues() async throws {
    let context = AIContext()

    #expect(context.companionStyle == .encouraging)
    #expect(context.workType == .other)
    #expect(context.primaryGoals.isEmpty)
    #expect(context.petName == "Baby Waffle")
    #expect(context.petMood == .happy)
    #expect(context.tasksCompletedToday == 0)
    #expect(context.totalTasksToday == 0)
    #expect(context.eventsToday == 0)
    #expect(context.currentStreak == 0)
    #expect(context.recentCompletionRate == 0)
    #expect(context.behaviorSummary == nil)
    #expect(context.recentTexts.isEmpty)
}

@Test func testAIContextWithBehaviorSummary() async throws {
    let summary = UserBehaviorSummary(
        weeklyCompletionRates: [0.5, 0.6, 0.7, 0.8],
        preferredWorkHours: WorkHourRange(start: 9, end: 17),
        averageDailyTasks: 5,
        topTaskCategories: ["Review", "Write", "Design"],
        streakRecord: 14
    )

    let context = AIContext(
        companionStyle: .calm,
        behaviorSummary: summary,
        recentTexts: ["Hello!", "Keep going!"]
    )

    #expect(context.behaviorSummary != nil)
    #expect(context.behaviorSummary?.weeklyCompletionRates.count == 4)
    #expect(context.behaviorSummary?.streakRecord == 14)
    #expect(context.recentTexts.count == 2)
}

// MARK: - AI Text Type Tests

@Test func testAITextTypeAllCases() async throws {
    let types: [AITextType] = [
        .morningGreeting, .dailySummary, .companionPhrase,
        .taskEncouragement, .settlementSummary
    ]
    #expect(types.count == 5)
}

// MARK: - Companion Style Tests

@Test func testAllCompanionStylesHaveDistinctDescriptions() async throws {
    let styles = CompanionStyle.allCases
    #expect(styles.count == 4)

    let descriptions = Set(styles.map(\.description))
    #expect(descriptions.count == 4)
}

@Test func testCompanionStyleRawValues() async throws {
    #expect(CompanionStyle.encouraging.rawValue == "Encouraging")
    #expect(CompanionStyle.strict.rawValue == "Strict")
    #expect(CompanionStyle.playful.rawValue == "Playful")
    #expect(CompanionStyle.calm.rawValue == "Calm")
}

// MARK: - Behavior Analyzer Tests

@Test func testBehaviorAnalyzerEmptyData() async throws {
    let analyzer = BehaviorAnalyzer()
    let summary = analyzer.generateSummary(
        tasks: [],
        focusSessions: [],
        streak: Streak(currentStreak: 0)
    )

    #expect(summary.weeklyCompletionRates.count == 4)
    #expect(summary.weeklyCompletionRates.allSatisfy { $0 == 0 })
    #expect(summary.averageDailyTasks == 0)
    #expect(summary.topTaskCategories.isEmpty)
    #expect(summary.streakRecord == 0)
    #expect(summary.preferredWorkHours.start == 9)
    #expect(summary.preferredWorkHours.end == 18)
}

@Test func testBehaviorAnalyzerStreakRecord() async throws {
    let analyzer = BehaviorAnalyzer()
    let streak = Streak(currentStreak: 5, longestStreak: 20)

    let summary = analyzer.generateSummary(
        tasks: [],
        focusSessions: [],
        streak: streak
    )

    #expect(summary.streakRecord == 20)
}

@Test func testBehaviorAnalyzerTopCategories() async throws {
    let analyzer = BehaviorAnalyzer()
    let tasks = [
        TaskItem(title: "Review PR #123"),
        TaskItem(title: "Review docs"),
        TaskItem(title: "Write tests"),
        TaskItem(title: "Write proposal"),
        TaskItem(title: "Write email"),
        TaskItem(title: "Design mockup"),
    ]

    let summary = analyzer.generateSummary(
        tasks: tasks,
        focusSessions: [],
        streak: Streak()
    )

    #expect(summary.topTaskCategories.count == 3)
    #expect(summary.topTaskCategories.first == "Write")
}

@Test func testBehaviorAnalyzerAverageDailyTasks() async throws {
    let analyzer = BehaviorAnalyzer()
    let calendar = Calendar.current

    // Create 60 tasks spread over last 30 days -> average should be 2
    var tasks: [TaskItem] = []
    for i in 0..<60 {
        let dueDate = calendar.date(byAdding: .day, value: -(i % 30), to: Date())
        tasks.append(TaskItem(title: "Task \(i)", dueDate: dueDate))
    }

    let summary = analyzer.generateSummary(
        tasks: tasks,
        focusSessions: [],
        streak: Streak()
    )

    #expect(summary.averageDailyTasks == 2)
}

@Test func testBehaviorAnalyzerPreferredWorkHoursWithCompletedTasks() async throws {
    let analyzer = BehaviorAnalyzer()
    let calendar = Calendar.current
    let today = Date()

    // Create completed tasks with lastModified at 10am, 11am, 2pm
    let tasks = [10, 11, 14, 10, 11, 10].map { hour -> TaskItem in
        let modified = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: today)!
        return TaskItem(
            title: "Task at \(hour)",
            isCompleted: true,
            lastModified: modified
        )
    }

    let summary = analyzer.generateSummary(
        tasks: tasks,
        focusSessions: [],
        streak: Streak()
    )

    #expect(summary.preferredWorkHours.start <= 10)
    #expect(summary.preferredWorkHours.end >= 11)
}

// MARK: - AI Interaction Model Tests

@Test func testAIInteractionCodable() async throws {
    let interaction = AIInteraction(
        type: .morningGreeting,
        completionRate: 0.75,
        petMood: "Happy",
        timeOfDay: "morning",
        generatedText: "Good morning!",
        petName: "Waffle"
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(interaction)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(AIInteraction.self, from: data)

    #expect(decoded.id == interaction.id)
    #expect(decoded.type == .morningGreeting)
    #expect(decoded.completionRate == 0.75)
    #expect(decoded.petMood == "Happy")
    #expect(decoded.timeOfDay == "morning")
    #expect(decoded.generatedText == "Good morning!")
    #expect(decoded.petName == "Waffle")
}

@Test func testAIInteractionDefaultValues() async throws {
    let interaction = AIInteraction(
        type: .taskEncouragement,
        generatedText: "You can do it!",
        petName: "Buddy"
    )

    #expect(interaction.completionRate == 0)
    #expect(interaction.petMood == "")
    #expect(interaction.timeOfDay == "")
}

// MARK: - User Behavior Summary Tests

@Test func testUserBehaviorSummaryCodable() async throws {
    let summary = UserBehaviorSummary(
        weeklyCompletionRates: [0.5, 0.6, 0.7, 0.8],
        preferredWorkHours: WorkHourRange(start: 8, end: 17),
        averageDailyTasks: 5,
        topTaskCategories: ["Review", "Write"],
        streakRecord: 14
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(summary)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(UserBehaviorSummary.self, from: data)

    #expect(decoded.weeklyCompletionRates == [0.5, 0.6, 0.7, 0.8])
    #expect(decoded.preferredWorkHours.start == 8)
    #expect(decoded.preferredWorkHours.end == 17)
    #expect(decoded.averageDailyTasks == 5)
    #expect(decoded.topTaskCategories == ["Review", "Write"])
    #expect(decoded.streakRecord == 14)
}

@Test func testUserBehaviorSummaryDefaults() async throws {
    let summary = UserBehaviorSummary()

    #expect(summary.weeklyCompletionRates.isEmpty)
    #expect(summary.preferredWorkHours.start == 9)
    #expect(summary.preferredWorkHours.end == 18)
    #expect(summary.averageDailyTasks == 0)
    #expect(summary.topTaskCategories.isEmpty)
    #expect(summary.streakRecord == 0)
}

// MARK: - CompanionTextService Fallback Tests

@Test @MainActor func testMorningGreetingFallbackWithoutAPIKey() async throws {
    let service = CompanionTextService.shared
    let result = await service.generateMorningGreeting(
        petName: "Waffle", petMood: .happy, weather: Weather()
    )
    #expect(!result.isEmpty)
}

@Test @MainActor func testDailySummaryFallbackWithoutAPIKey() async throws {
    let service = CompanionTextService.shared
    let result = await service.generateDailySummary(
        tasksCount: 3, eventsCount: 2, petName: "Waffle"
    )
    #expect(!result.isEmpty)
    #expect(result.contains("3"))
}

@Test @MainActor func testCompanionPhraseFallbackWithoutAPIKey() async throws {
    let service = CompanionTextService.shared
    let result = await service.generateCompanionPhrase(
        petMood: .focused, timeOfDay: .morning
    )
    #expect(!result.isEmpty)
}

@Test @MainActor func testTaskEncouragementFallbackWithoutAPIKey() async throws {
    let service = CompanionTextService.shared
    let result = await service.generateTaskEncouragement(
        taskTitle: "Review PR", petName: "Waffle", petMood: .happy
    )
    #expect(!result.isEmpty)
}

@Test @MainActor func testSettlementMessageFallbackWithoutAPIKey() async throws {
    let service = CompanionTextService.shared
    let result = await service.generateSettlementMessage(
        tasksCompleted: 5, tasksTotal: 5, streakDays: 3, petName: "Waffle"
    )
    #expect(!result.isEmpty)
    #expect(result.contains("Perfect"))
}

@Test @MainActor func testSettlementMessagePartialCompletion() async throws {
    let service = CompanionTextService.shared
    let result = await service.generateSettlementMessage(
        tasksCompleted: 4, tasksTotal: 5, streakDays: 3, petName: "Waffle"
    )
    #expect(!result.isEmpty)
    #expect(result.contains("4/5"))
}

@Test @MainActor func testSettlementMessageNoTasks() async throws {
    let service = CompanionTextService.shared
    let result = await service.generateSettlementMessage(
        tasksCompleted: 0, tasksTotal: 0, streakDays: 0, petName: "Waffle"
    )
    #expect(!result.isEmpty)
    #expect(result.contains("Tomorrow"))
}

@Test @MainActor func testDailySummaryNoTasksNoEvents() async throws {
    let service = CompanionTextService.shared
    let result = await service.generateDailySummary(
        tasksCount: 0, eventsCount: 0, petName: "Waffle"
    )
    #expect(result == "A free day! Time to relax.")
}

@Test @MainActor func testVerbalizeTaskPassthrough() async throws {
    let service = CompanionTextService.shared
    let result = await service.verbalizeTask(taskTitle: "Review PR #42")
    #expect(result == "Review PR #42")
}

// MARK: - Work Hour Range Tests

@Test func testWorkHourRangeDefaults() async throws {
    let range = WorkHourRange()
    #expect(range.start == 9)
    #expect(range.end == 18)
}

@Test func testWorkHourRangeCustom() async throws {
    let range = WorkHourRange(start: 7, end: 22)
    #expect(range.start == 7)
    #expect(range.end == 22)
}
