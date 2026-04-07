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
    
    /// Fetch real AIContext from AppState and tailor it for testing.
    public func createMockContext(type: AITextType) async -> AIContext {
        let triggerState = await AppState.shared.buildCompanionDialogueTriggerState(at: Date())
        let c = triggerState.context
        
        let newStyle = selectedMockStyle
        let newLearnText = testLearnText.trimmingCharacters(in: .whitespaces).isEmpty ? c.userDefinedLearnText : testLearnText
        
        // Actually modify context parameters if needed to SIMULATE the phase cleanly if the user's real schedule doesn't match
        var mockNextAgenda = c.nextAgendaItem
        var mockFocusTime = c.focusTimeToday
        var mockActiveTask = c.activeTaskTitle
        
        if type == .taskEncouragement && mockActiveTask == nil {
            mockActiveTask = "写核心代码"
        }
        
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
            tasksCompletedToday: c.tasksCompletedToday,
            totalTasksToday: c.totalTasksToday,
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
        【今日进度】: \(c.tasksCompletedToday)/\(c.totalTasksToday) 任务 (真实数据)
        【日程事件】: 今日 \(c.eventsToday) 个事件 (真实数据)
        【日程活动】: \(mockNextAgenda ?? "无")
        【专注任务】: \(mockActiveTask ?? "没在专注")
        【近期表现】: \(Int(c.recentCompletionRate * 100))% 完成率, \(c.currentStreak)天连读
        【宠物心情】: \(c.petMood.rawValue)
        """
        
        return realContext
    }

    private init() {}
}
