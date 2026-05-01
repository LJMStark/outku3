import SwiftUI
import Observation

/// A state container for the prompt debugger module.
/// It stores custom prompt overrides for the 3 product companion styles.
@Observable
@MainActor
public final class PromptDebuggerState {
    public static let shared = PromptDebuggerState()

    /// Custom prompt overrides keyed by CompanionStyle (derived from CompanionCharacter.resolvedStyle).
    public var overridePrompts: [CompanionCharacter: String] = [:]
    
    /// A completely custom overarching prompt that takes precedence over everything
    public var customGlobalOverride: String? = nil
    
    /// User provided phrase/keywords for the AI companion to learn during tests
    public var testLearnText: String = ""

    /// Selected OpenRouter model id for companion dialogue generation.
    public var selectedCompanionModelID: String = OpenAIService.defaultChatModelID
    
    /// The character currently selected in the debugger UI for editing.
    public var selectedMockCharacter: CompanionCharacter = .joy
    
    public var lastMockSummary: String = ""
    public var lastGeneratedDialogue: String = ""
    public var lastGeneratedTranslation: String = ""
    
    /// Fetch real AIContext from AppState and tailor it for testing.
    public func createMockContext(
        type: AITextType,
        characterOverride: CompanionCharacter? = nil
    ) async -> AIContext {
        let triggerState = await AppState.shared.buildCompanionDialogueTriggerState(at: Date())
        let c = triggerState.context
        let currentTasks = AppState.shared.tasks
        let activeSession = FocusSessionService.shared.activeSession
        let resolvedActiveTask = AppState.resolveActiveTask(
            activeSession: activeSession,
            tasks: currentTasks
        )
        let latestResolvedTask = activeSession.flatMap { AppState.resolveLatestTask(taskId: $0.taskId, in: currentTasks) }
        let latestIncompleteTaskItem = AppState.latestIncompleteTask(in: currentTasks)
        let latestIncompleteTask = latestIncompleteTaskItem?.title
        
        let newCharacter = characterOverride ?? selectedMockCharacter
        let newLearnText = testLearnText.trimmingCharacters(in: .whitespaces).isEmpty ? c.userDefinedLearnText : testLearnText
        
        // Actually modify context parameters if needed to SIMULATE the phase cleanly if the user's real schedule doesn't match
        var mockNextAgenda = c.nextAgendaItem
        let mockFocusTime = c.focusTimeToday
        let mockTaskDetails = Self.resolveTaskDetailsForMock(
            type: type,
            activeTaskTitle: c.activeTaskTitle,
            topTaskTitles: c.topTaskTitles,
            allTasks: currentTasks
        )
        let mockActiveTask = mockTaskDetails.taskTitle
        let mockProgress = Self.resolveTaskProgressForMock(
            type: type,
            baseCompleted: c.tasksCompletedToday,
            baseTotal: c.totalTasksToday,
            allTasks: currentTasks
        )
        let mockTasksCompleted = mockProgress.completed
        let mockTasksTotal = mockProgress.total
        
        if type == .scheduleReminder && mockNextAgenda == nil {
            mockNextAgenda = "Now · 拔智齿"
        }
        
        let realContext = AIContext(
            companionCharacter: newCharacter,
            intimacyStage: c.intimacyStage,
            workType: c.workType,
            primaryGoals: c.primaryGoals,
            petName: c.petName,
            petMood: c.petMood,
            currentTime: c.currentTime,
            tasksCompletedToday: mockTasksCompleted,
            totalTasksToday: mockTasksTotal,
            eventsToday: c.eventsToday,
            currentStreak: c.currentStreak,
            recentCompletionRate: c.recentCompletionRate,
            behaviorSummary: c.behaviorSummary,
            recentTexts: c.recentTexts,
            focusTimeToday: mockFocusTime,
            energyBottles: c.energyBottles,
            currentSceneName: c.currentSceneName,
            hardwareConnected: c.hardwareConnected,
            nextAgendaItem: mockNextAgenda,
            activeTaskTitle: mockActiveTask,
            topTaskTitles: c.topTaskTitles,
            episodicMemories: c.episodicMemories,
            dimensionalEmotion: c.dimensionalEmotion,
            psychologicalObjective: c.psychologicalObjective,
            userDefinedLearnText: newLearnText
        )
        
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let timeStr = formatter.string(from: c.currentTime)
        
        let isLocal = latestIncompleteTaskItem.map { AppState.isLocallyModified($0) ? "LOCAL" : "SYNC" } ?? "N/A"
        lastMockSummary = """
        【触发时机】: \(type)
        【时间】: \(timeStr) (真实当前时间)
        【任务详情】: 传参任务=\(mockActiveTask ?? "无") | 命中来源=\(mockTaskDetails.source)
        【真实链路】: taskId=\(resolvedActiveTask.taskId ?? "无") | 会话快照=\(activeSession?.taskTitle ?? "无") | 最新解析=\(resolvedActiveTask.taskTitle ?? "无") | 来源=\(latestResolvedTask == nil ? "focus session snapshot" : "tasks(taskId -> latest snapshot)")
        【候选任务】: Top1=\(c.topTaskTitles.first ?? "无") | 最新未完成=\(latestIncompleteTask ?? "无") (\(isLocal)) | 完成进度=\(mockTasksCompleted)/\(mockTasksTotal)
        【日程事件】: 今日 \(c.eventsToday) 个事件 (真实数据)
        【日程活动】: \(mockNextAgenda ?? "无")
        【近期表现】: \(Int(c.recentCompletionRate * 100))% 完成率, \(c.currentStreak)天连读
        【宠物心情】: \(c.petMood.rawValue)
        """
        
        return realContext
    }

    nonisolated static func resolveTaskProgressForMock(
        type: AITextType,
        baseCompleted: Int,
        baseTotal: Int,
        allTasks: [TaskItem]
    ) -> (completed: Int, total: Int) {
        guard type == .taskEncouragement, baseTotal == 0, !allTasks.isEmpty else {
            return (baseCompleted, baseTotal)
        }

        let completed = allTasks.filter(\.isCompleted).count
        return (completed, allTasks.count)
    }

    nonisolated static func resolveTaskDetailsForMock(
        type: AITextType,
        activeTaskTitle: String?,
        topTaskTitles: [String] = [],
        allTasks: [TaskItem]
    ) -> (taskTitle: String?, source: String) {
        guard type == .taskEncouragement else {
            return (activeTaskTitle, "current-context")
        }

        if let latestTaskTitle = latestIncompleteTaskTitleForMock(allTasks: allTasks) {
            return (latestTaskTitle, "latest-incomplete")
        }

        if let activeTaskTitle = nonEmptyTitle(activeTaskTitle) {
            return (activeTaskTitle, "active-task")
        }

        if let topTaskTitle = topTaskTitles.compactMap(nonEmptyTitle).first {
            return (topTaskTitle, "top-task")
        }

        return (activeTaskTitle ?? "写核心代码", "fallback")
    }

    nonisolated static func latestIncompleteTaskTitleForMock(allTasks: [TaskItem]) -> String? {
        AppState.latestIncompleteTask(in: allTasks)?.title
    }

    nonisolated private static func nonEmptyTitle(_ title: String?) -> String? {
        guard let title else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private init() {}
}
