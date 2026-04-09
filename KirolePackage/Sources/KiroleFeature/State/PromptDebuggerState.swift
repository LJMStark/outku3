import SwiftUI
import Observation

/// A state container for the prompt debugger module.
/// It stores custom prompt overrides for the 6 CompanionStyles.
@Observable
@MainActor
public final class PromptDebuggerState {
    public static let shared = PromptDebuggerState()

    /// Custom prompt overrides mapped by CompanionStyle.
    public var overridePrompts: [CompanionStyle: String] = [:]
    
    /// A completely custom overarching prompt that takes precedence over everything
    public var customGlobalOverride: String? = nil
    
    /// User provided phrase/keywords for the AI companion to learn during tests
    public var testLearnText: String = ""
    
    /// The style currently selected in the debugger UI for editing.
    public var selectedMockStyle: CompanionStyle = .companion
    
    public var lastMockSummary: String = ""
    public var lastGeneratedDialogue: String = ""
    public var lastGeneratedTranslation: String = ""
    
    /// Fetch real AIContext from AppState and tailor it for testing.
    public func createMockContext(
        type: AITextType,
        styleOverride: CompanionStyle? = nil
    ) async -> AIContext {
        let triggerState = await AppState.shared.buildCompanionDialogueTriggerState(at: Date())
        let c = triggerState.context
        
        let newStyle = styleOverride ?? selectedMockStyle
        let newLearnText = testLearnText.trimmingCharacters(in: .whitespaces).isEmpty ? c.userDefinedLearnText : testLearnText
        
        // Actually modify context parameters if needed to SIMULATE the phase cleanly if the user's real schedule doesn't match
        var mockNextAgenda = c.nextAgendaItem
        let mockFocusTime = c.focusTimeToday
        let mockActiveTask = Self.resolveTaskTitleForMock(
            type: type,
            activeTaskTitle: c.activeTaskTitle,
            allTasks: AppState.shared.tasks
        )
        let mockProgress = Self.resolveTaskProgressForMock(
            type: type,
            baseCompleted: c.tasksCompletedToday,
            baseTotal: c.totalTasksToday,
            allTasks: AppState.shared.tasks
        )
        let mockTasksCompleted = mockProgress.completed
        let mockTasksTotal = mockProgress.total
        
        if type == .scheduleReminder && mockNextAgenda == nil {
            mockNextAgenda = "Now · 拔智齿"
        }
        
        let realContext = AIContext(
            companionStyle: newStyle,
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
            energyBlocks: c.energyBlocks,
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
        
        lastMockSummary = """
        【触发时机】: \(type)
        【时间】: \(timeStr) (真实当前时间)
        【任务进度】: \(mockTasksCompleted)/\(mockTasksTotal) 任务
        【日程事件】: 今日 \(c.eventsToday) 个事件 (真实数据)
        【日程活动】: \(mockNextAgenda ?? "无")
        【专注任务】: \(mockActiveTask ?? "没在专注")
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

    nonisolated static func resolveTaskTitleForMock(
        type: AITextType,
        activeTaskTitle: String?,
        allTasks: [TaskItem]
    ) -> String? {
        guard type == .taskEncouragement else {
            return activeTaskTitle
        }

        if let latestTaskTitle = latestIncompleteTaskTitleForMock(allTasks: allTasks) {
            return latestTaskTitle
        }

        return activeTaskTitle ?? "写核心代码"
    }

    nonisolated static func latestIncompleteTaskTitleForMock(allTasks: [TaskItem]) -> String? {
        allTasks
            .filter { !$0.isCompleted }
            .max { lhs, rhs in
                lhs.lastModified < rhs.lastModified
            }?
            .title
    }

    private init() {}
}
