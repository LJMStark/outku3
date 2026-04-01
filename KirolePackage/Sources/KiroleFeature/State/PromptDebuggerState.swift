import SwiftUI
import Observation

#if DEBUG

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
    
    /// The style currently selected in the debugger UI for editing.
    public var selectedMockStyle: CompanionStyle = .companion
    
    /// Randomly mock an AIContext for a "worst case" scenario or an interesting setup.
    public func createMockContext() -> AIContext {
        return AIContext(
            companionStyle: selectedMockStyle,
            workType: .officeWorker,
            primaryGoals: [.productivity, .procrastination],
            petName: "Demon",
            petMood: .missing, // Make it missing to trigger emotional dramatic
            currentTime: Date(),
            tasksCompletedToday: 1,
            totalTasksToday: 15, // Huge backlog
            eventsToday: 3,
            currentStreak: 0, // Broken streak
            recentCompletionRate: 0.1, // Bad rate
            behaviorSummary: nil,
            recentTexts: [],
            focusTimeToday: 5, // Barely focused
            energyBlocks: 1, // Low energy
            currentSceneName: "Messy Room",
            hardwareConnected: false
        )
    }

    private init() {}
}

#endif
