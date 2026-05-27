import Testing
import Foundation
@testable import KiroleFeature

// MARK: - AI Context Tests

@Test func testAIContextIncludesAllUserProfileFields() async throws {
    let context = AIContext(
        companionCharacter: .nova,
        workType: .freelancer,
        primaryGoals: [.productivity, .focus],
        petName: "TestPet",
        petMood: .excited,
        tasksCompletedToday: 3,
        totalTasksToday: 5,
        eventsToday: 2,
        recentCompletionRate: 0.85
    )

    #expect(context.companionStyle == .nova)
    #expect(context.companionCharacter == .nova)
    #expect(context.workType == .freelancer)
    #expect(context.primaryGoals.count == 2)
    #expect(context.petName == "TestPet")
    #expect(context.petMood == .excited)
    #expect(context.tasksCompletedToday == 3)
    #expect(context.totalTasksToday == 5)
    #expect(context.eventsToday == 2)
    #expect(context.recentCompletionRate == 0.85)
}

@Test func testAIContextDefaultValues() async throws {
    let context = AIContext()

    #expect(context.companionStyle == .joy)
    #expect(context.companionCharacter == .joy)
    #expect(context.workType == .other)
    #expect(context.primaryGoals.isEmpty)
    #expect(context.petName == "Baby Waffle")
    #expect(context.petMood == .happy)
    #expect(context.tasksCompletedToday == 0)
    #expect(context.totalTasksToday == 0)
    #expect(context.eventsToday == 0)
    #expect(context.recentCompletionRate == 0)
    #expect(context.behaviorSummary == nil)
    #expect(context.recentTexts.isEmpty)
}

@Test func testAIContextWithBehaviorSummary() async throws {
    let summary = UserBehaviorSummary(
        weeklyCompletionRates: [0.5, 0.6, 0.7, 0.8],
        preferredWorkHours: WorkHourRange(start: 9, end: 17),
        averageDailyTasks: 5,
        topTaskCategories: ["Review", "Write", "Design"]
    )

    let context = AIContext(
        companionCharacter: .silas,
        behaviorSummary: summary,
        recentTexts: ["Hello!", "Keep going!"]
    )

    #expect(context.companionStyle == .silas)
    #expect(context.companionCharacter == .silas)
    #expect(context.behaviorSummary != nil)
    #expect(context.behaviorSummary?.weeklyCompletionRates.count == 4)
    #expect(context.recentTexts.count == 2)
}

@Test func testAIContextReplacingOnlyUpdatesRequestedFields() async throws {
    let originalSummary = UserBehaviorSummary(
        weeklyCompletionRates: [0.3],
        preferredWorkHours: WorkHourRange(start: 8, end: 16),
        averageDailyTasks: 4,
        topTaskCategories: ["Write"]
    )
    let updatedSummary = UserBehaviorSummary(
        weeklyCompletionRates: [0.9],
        preferredWorkHours: WorkHourRange(start: 10, end: 18),
        averageDailyTasks: 7,
        topTaskCategories: ["Review"]
    )
    let original = AIContext(
        companionCharacter: .nova,
        intimacyStage: .closeFriend,
        workType: .freelancer,
        primaryGoals: [.focus, .productivity],
        petName: "Nova",
        petMood: .focused,
        currentTime: Date(timeIntervalSince1970: 1_000),
        tasksCompletedToday: 2,
        totalTasksToday: 5,
        eventsToday: 3,
        recentCompletionRate: 0.4,
        behaviorSummary: originalSummary,
        recentTexts: ["old"],
        focusTimeToday: 45,
        energyBottles: 8,
        currentSceneName: "forest",
        hardwareConnected: true,
        nextAgendaItem: "10:00 · Planning",
        activeTaskTitle: "Draft",
        topTaskTitles: ["Draft", "Review"],
        episodicMemories: ["Entered focus"],
        dimensionalEmotion: "steady",
        psychologicalObjective: "protect attention",
        userDefinedLearnText: "custom tone"
    )

    let updated = original.replacing(
        recentCompletionRate: 0.8,
        behaviorSummary: updatedSummary,
        recentTexts: ["new", "latest"]
    )

    #expect(updated.companionCharacter == original.companionCharacter)
    #expect(updated.intimacyStage == original.intimacyStage)
    #expect(updated.workType == original.workType)
    #expect(updated.primaryGoals == original.primaryGoals)
    #expect(updated.petName == original.petName)
    #expect(updated.petMood == original.petMood)
    #expect(updated.currentTime == original.currentTime)
    #expect(updated.tasksCompletedToday == original.tasksCompletedToday)
    #expect(updated.totalTasksToday == original.totalTasksToday)
    #expect(updated.eventsToday == original.eventsToday)
    #expect(updated.focusTimeToday == original.focusTimeToday)
    #expect(updated.energyBottles == original.energyBottles)
    #expect(updated.currentSceneName == original.currentSceneName)
    #expect(updated.hardwareConnected == original.hardwareConnected)
    #expect(updated.nextAgendaItem == original.nextAgendaItem)
    #expect(updated.activeTaskTitle == original.activeTaskTitle)
    #expect(updated.topTaskTitles == original.topTaskTitles)
    #expect(updated.episodicMemories == original.episodicMemories)
    #expect(updated.dimensionalEmotion == original.dimensionalEmotion)
    #expect(updated.psychologicalObjective == original.psychologicalObjective)
    #expect(updated.userDefinedLearnText == original.userDefinedLearnText)
    #expect(updated.recentCompletionRate == 0.8)
    #expect(updated.behaviorSummary?.weeklyCompletionRates == [0.9])
    #expect(updated.recentTexts == ["new", "latest"])
}

// MARK: - AI Text Type Tests

@Test func testAITextTypeAllCases() async throws {
    let types: [AITextType] = [
        .morningGreeting, .dailySummary, .companionPhrase,
        .taskEncouragement, .settlementSummary
    ]
    #expect(types.count == 5)
}

// MARK: - Companion Dialogue Display Policy Tests

@Test func testCompanionDialogueDisplayPolicyRejectsIncompleteSentence() async throws {
    let text = "I am right here beside you as you face this"
    #expect(!CompanionDialogueDisplayPolicy.isValidForDisplay(text))
}

@Test func testCompanionDialogueDisplayPolicyAcceptsCompleteSentence() async throws {
    let text = "I am right here beside you as you face this, steady and quiet with you every moment."
    #expect(CompanionDialogueDisplayPolicy.isValidForDisplay(text))
}

@Test func testSharedDialogueRetryPolicyRetriesTimeouts() async throws {
    #expect(CompanionTextService.shouldRetrySharedDialogue(after: URLError(.timedOut)))
    #expect(CompanionTextService.shouldRetrySharedDialogue(after: NetworkError.rateLimited))
    #expect(CompanionTextService.shouldRetrySharedDialogue(after: NetworkError.serverError(503)))
    #expect(CompanionTextService.shouldRetrySharedDialogue(after: NetworkError.invalidResponse))
    #expect(CompanionTextService.shouldRetrySharedDialogue(after: OpenAIError.emptyResponse))
}

@Test func testSharedDialogueRetryPolicyRejectsHardFailures() async throws {
    #expect(!CompanionTextService.shouldRetrySharedDialogue(after: OpenAIError.notConfigured))
    #expect(!CompanionTextService.shouldRetrySharedDialogue(after: NetworkError.forbidden))
}

// MARK: - Companion Style Tests

@Test func testAllCompanionStylesHaveDistinctDescriptions() async throws {
    let styles = CompanionStyle.allCases
    #expect(styles.count == 3)
    #expect(Set(styles) == Set([CompanionStyle.joy, .silas, .nova]))

    let descriptions = Set(styles.map(\.description))
    #expect(descriptions.count == 3)
}

@Test func testCompanionStyleRawValues() async throws {
    #expect(CompanionStyle.joy.rawValue == "Joy")
    #expect(CompanionStyle.silas.rawValue == "Silas")
    #expect(CompanionStyle.nova.rawValue == "Nova")
}

@Test func testCompanionModelOptionsUseExpectedOpenRouterIDs() async throws {
    let modelIDs = OpenAIService.companionModelOptions.map(\.id)
    #expect(modelIDs == ["openai/gpt-oss-120b:free"])
    #expect(OpenAIService.defaultChatModelID == "openai/gpt-oss-120b:free")
}

@MainActor
@Test func testCompanionModelPreferenceCanSwitchModelID() async throws {
    let preference = CompanionModelPreference.shared
    let original = preference.modelID
    defer { preference.modelID = original }

    preference.modelID = "openai/gpt-oss-120b:free"
    #expect(preference.modelID == "openai/gpt-oss-120b:free")
}

@MainActor
@Test func testPromptDebuggerMockContextHonorsVisibleCharacterSelection() async throws {
    let debuggerState = PromptDebuggerState.shared
    let appState = AppState.shared
    let originalProfile = appState.userProfile
    let originalCharacter = debuggerState.selectedMockCharacter
    let originalOverrides = debuggerState.overridePrompts
    defer { appState.updateUserProfile(originalProfile) }
    defer { debuggerState.selectedMockCharacter = originalCharacter }
    defer { debuggerState.overridePrompts = originalOverrides }

    appState.updateUserProfile(
        UserProfile(
            workType: originalProfile.workType,
            primaryGoals: originalProfile.primaryGoals,
            companionCharacter: .silas,
            intimacyStage: .familiar,
            onboardingCompletedAt: originalProfile.onboardingCompletedAt
        )
    )
    debuggerState.selectedMockCharacter = .joy

    let context = await debuggerState.createMockContext(
        type: .smartReminder,
        characterOverride: .nova
    )

    #expect(context.companionStyle == .nova)
    #expect(context.companionCharacter == .nova)
    #expect(context.intimacyStage == .familiar)
    #expect(debuggerState.selectedMockCharacter == .joy)
}

@MainActor
@Test func testCompanionTriggerStateUsesFreshTaskSnapshot() async throws {
    let progress = AppState.companionTaskProgressSnapshot(from: [
        TaskItem(title: "Today Pending", isCompleted: false, dueDate: Date()),
        TaskItem(title: "Today Done", isCompleted: true, dueDate: Date())
    ])

    #expect(progress.completed == 1)
    #expect(progress.total == 2)
    #expect(progress.rate == 0.5)
}

@Test func testResolveActiveTaskPrefersLatestTaskSnapshot() async throws {
    let activeSession = FocusSession(
        taskId: "focus-task",
        taskTitle: "Old Session Title"
    )
    let resolved = AppState.resolveActiveTask(
        activeSession: activeSession,
        tasks: [
            TaskItem(
                id: "focus-task",
                title: "Old Task Snapshot",
                lastModified: Date(timeIntervalSince1970: 100),
                remoteUpdatedAt: Date(timeIntervalSince1970: 100)
            ),
            TaskItem(
                id: "focus-task",
                title: "Latest Synced Task",
                lastModified: Date(timeIntervalSince1970: 120),
                remoteUpdatedAt: Date(timeIntervalSince1970: 200)
            )
        ]
    )

    #expect(resolved.taskId == "focus-task")
    #expect(resolved.taskTitle == "Latest Synced Task")
}

@Test func testResolveActiveTaskFallsBackToSessionSnapshot() async throws {
    let activeSession = FocusSession(
        taskId: "missing-task",
        taskTitle: "Session Snapshot Title"
    )
    let resolved = AppState.resolveActiveTask(
        activeSession: activeSession,
        tasks: []
    )

    #expect(resolved.taskId == "missing-task")
    #expect(resolved.taskTitle == "Session Snapshot Title")
}

@Test func testResolveActiveTaskFallsBackToLatestIncompleteTaskWhenSessionTaskMissing() async throws {
    let activeSession = FocusSession(
        taskId: "missing-task",
        taskTitle: "Session Snapshot Title"
    )
    let resolved = AppState.resolveActiveTask(
        activeSession: activeSession,
        tasks: [
            TaskItem(
                id: "old-completed",
                title: "Old Completed Task",
                isCompleted: true,
                lastModified: Date(timeIntervalSince1970: 100)
            ),
            TaskItem(
                id: "latest-incomplete",
                title: "Latest Incomplete Task",
                isCompleted: false,
                lastModified: Date(timeIntervalSince1970: 200)
            )
        ]
    )

    #expect(resolved.taskId == "latest-incomplete")
    #expect(resolved.taskTitle == "Latest Incomplete Task")
}

@MainActor
@Test func testPromptDebuggerTaskEncouragementBackfillsTaskCounts() async throws {
    let resolved = PromptDebuggerState.resolveTaskProgressForMock(
        type: .taskEncouragement,
        baseCompleted: 0,
        baseTotal: 0,
        allTasks: [
            TaskItem(title: "Backlog Pending", isCompleted: false, dueDate: nil),
            TaskItem(title: "Backlog Done", isCompleted: true, dueDate: nil)
        ]
    )

    #expect(resolved.completed == 1)
    #expect(resolved.total == 2)
}

@Test func testPromptDebuggerTaskEncouragementUsesLatestIncompleteTaskTitle() async throws {
    let olderIncompleteTask = TaskItem(
        title: "Older Incomplete Task",
        lastModified: Date(timeIntervalSince1970: 100)
    )
    let latestIncompleteTask = TaskItem(
        title: "Latest Incomplete Task",
        isCompleted: false,
        lastModified: Date(timeIntervalSince1970: 150)
    )
    let latestCompletedTask = TaskItem(
        title: "Latest Completed Task",
        isCompleted: true,
        lastModified: Date(timeIntervalSince1970: 200)
    )

    let resolvedTitle = PromptDebuggerState.resolveTaskDetailsForMock(
        type: .taskEncouragement,
        activeTaskTitle: nil,
        allTasks: [olderIncompleteTask, latestIncompleteTask, latestCompletedTask]
    ).taskTitle

    #expect(resolvedTitle == "Latest Incomplete Task")
}

@Test func testPromptDebuggerTaskDetailsExposeResolutionSource() async throws {
    let resolved = PromptDebuggerState.resolveTaskDetailsForMock(
        type: .taskEncouragement,
        activeTaskTitle: nil,
        topTaskTitles: ["Top Task A"],
        allTasks: []
    )

    #expect(resolved.taskTitle == "Top Task A")
    #expect(resolved.source == "top-task")
}

@Test func testPromptDebuggerTaskEncouragementPrefersLatestIncompleteOverActiveSnapshot() async throws {
    let resolvedTitle = PromptDebuggerState.resolveTaskDetailsForMock(
        type: .taskEncouragement,
        activeTaskTitle: "Current Focus Task",
        topTaskTitles: ["Top Task A", "Top Task B"],
        allTasks: [
            TaskItem(title: "Latest Incomplete Task", isCompleted: false, lastModified: Date(timeIntervalSince1970: 200))
        ]
    ).taskTitle

    #expect(resolvedTitle == "Latest Incomplete Task")
}

@Test func testPromptDebuggerTaskEncouragementFallsBackToTopTaskTitle() async throws {
    let resolvedTitle = PromptDebuggerState.resolveTaskDetailsForMock(
        type: .taskEncouragement,
        activeTaskTitle: nil,
        topTaskTitles: ["Top Task A", "Top Task B"],
        allTasks: [
            TaskItem(title: "Completed Task", isCompleted: true, lastModified: Date(timeIntervalSince1970: 200))
        ]
    ).taskTitle

    #expect(resolvedTitle == "Top Task A")
}

@Test func testPromptDebuggerTaskRecencyPrefersLocallyModifiedTask() async throws {
    // Task A: locally modified (lastModified diverges from remoteUpdatedAt by >1s)
    let locallyModifiedTask = TaskItem(
        title: "Local Timestamp Newer",
        isCompleted: false,
        lastModified: Date(timeIntervalSince1970: 300),
        remoteUpdatedAt: Date(timeIntervalSince1970: 100)
    )
    // Task B: sync-only updated (lastModified == remoteUpdatedAt, set by sync engine)
    let syncOnlyTask = TaskItem(
        title: "Remote Timestamp Newer",
        isCompleted: false,
        lastModified: Date(timeIntervalSince1970: 400),
        remoteUpdatedAt: Date(timeIntervalSince1970: 400)
    )

    let resolvedTitle = PromptDebuggerState.latestIncompleteTaskTitleForMock(
        allTasks: [locallyModifiedTask, syncOnlyTask]
    )

    // Locally-modified task should always win over sync-only task
    #expect(resolvedTitle == "Local Timestamp Newer")
}

@Test func testLatestIncompleteTaskFiltersPendingDeletion() async throws {
    let normalTask = TaskItem(
        title: "Normal Task",
        isCompleted: false,
        lastModified: Date(timeIntervalSince1970: 100)
    )
    let deletingTask = TaskItem(
        title: "Deleting Task",
        isCompleted: false,
        pendingDeletion: true,
        lastModified: Date(timeIntervalSince1970: 200)
    )

    let result = AppState.latestIncompleteTask(in: [normalTask, deletingTask])
    #expect(result?.title == "Normal Task")
}

@Test func testIsLocallyModifiedDetectsUserEdits() async throws {
    let localOnlyTask = TaskItem(
        title: "Local Only",
        isCompleted: false,
        lastModified: Date(timeIntervalSince1970: 300)
    )
    // remoteUpdatedAt is nil -> locally created
    #expect(AppState.isLocallyModified(localOnlyTask) == true)

    let syncedTask = TaskItem(
        title: "Synced",
        isCompleted: false,
        lastModified: Date(timeIntervalSince1970: 400),
        remoteUpdatedAt: Date(timeIntervalSince1970: 400)
    )
    // lastModified == remoteUpdatedAt -> set by sync, not local edit
    #expect(AppState.isLocallyModified(syncedTask) == false)

    let editedAfterSync = TaskItem(
        title: "Edited After Sync",
        isCompleted: false,
        lastModified: Date(timeIntervalSince1970: 500),
        remoteUpdatedAt: Date(timeIntervalSince1970: 300)
    )
    // lastModified diverges from remoteUpdatedAt -> local edit
    #expect(AppState.isLocallyModified(editedAfterSync) == true)
}

@Test func testPromptDebuggerTaskEncouragementFallsBackWhenNoTaskExists() async throws {
    let resolvedTitle = PromptDebuggerState.resolveTaskDetailsForMock(
        type: .taskEncouragement,
        activeTaskTitle: nil,
        allTasks: []
    ).taskTitle

    #expect(resolvedTitle == "写核心代码")
}

@Test func testTaskEncouragementPayloadPreservesActiveTaskTitle() async throws {
    let payload = CompanionTextService.taskEncouragementPromptPayload(taskTitle: "Review PR #42")

    #expect(payload.activeTaskTitle == "Review PR #42")
    #expect(payload.nextAgendaItem == "Review PR #42")
    #expect(payload.memory.contains("Review PR #42"))
}

// MARK: - Behavior Analyzer Tests

@Test func testBehaviorAnalyzerEmptyData() async throws {
    let analyzer = BehaviorAnalyzer()
    let summary = analyzer.generateSummary(
        tasks: [],
        focusSessions: []
    )

    #expect(summary.weeklyCompletionRates.count == 4)
    #expect(summary.weeklyCompletionRates.allSatisfy { $0 == 0 })
    #expect(summary.averageDailyTasks == 0)
    #expect(summary.topTaskCategories.isEmpty)
    #expect(summary.preferredWorkHours.start == 9)
    #expect(summary.preferredWorkHours.end == 18)
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
        focusSessions: []
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
        focusSessions: []
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
        focusSessions: []
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
        topTaskCategories: ["Review", "Write"]
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
}

@Test func testUserBehaviorSummaryDefaults() async throws {
    let summary = UserBehaviorSummary()

    #expect(summary.weeklyCompletionRates.isEmpty)
    #expect(summary.preferredWorkHours.start == 9)
    #expect(summary.preferredWorkHours.end == 18)
    #expect(summary.averageDailyTasks == 0)
    #expect(summary.topTaskCategories.isEmpty)
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
        tasksCompleted: 5, tasksTotal: 5, petName: "Waffle"
    )
    #expect(!result.isEmpty)
    #expect(result.contains("Perfect"))
}

@Test @MainActor func testSettlementMessagePartialCompletion() async throws {
    let service = CompanionTextService.shared
    let result = await service.generateSettlementMessage(
        tasksCompleted: 4, tasksTotal: 5, petName: "Waffle"
    )
    #expect(!result.isEmpty)
    #expect(result.contains("4/5"))
}

@Test @MainActor func testSettlementMessageNoTasks() async throws {
    let service = CompanionTextService.shared
    let result = await service.generateSettlementMessage(
        tasksCompleted: 0, tasksTotal: 0, petName: "Waffle"
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

@Test @MainActor func testSharedPetDialogueFallbackIsDisplaySafe() async throws {
    let longTitle = String(repeating: "planning work ", count: 10)
    let result = await CompanionTextService.shared.generateSharedPetDialogue(
        baseContext: AIContext(
            tasksCompletedToday: 0,
            totalTasksToday: 3,
            eventsToday: 1,
            nextAgendaItem: "Task · \(longTitle)",
            topTaskTitles: [longTitle]
        )
    )

    #expect(CompanionDialogueDisplayPolicy.isValidForDisplay(result))
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
