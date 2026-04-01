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
        let maxTasks = Int.random(in: 0...8)
        let doneTasks = Int.random(in: 0...maxTasks)
        let rate = maxTasks > 0 ? Double(doneTasks) / Double(maxTasks) : 0
        
        return AIContext(
            companionStyle: selectedMockStyle,
            workType: .officeWorker,
            primaryGoals: [.productivity, .procrastination],
            petName: "Demon",
            petMood: .missing,
            currentTime: Date().addingTimeInterval(TimeInterval.random(in: -43200...43200)),
            tasksCompletedToday: doneTasks,
            totalTasksToday: maxTasks,
            eventsToday: Int.random(in: 0...5),
            currentStreak: Int.random(in: 0...15),
            recentCompletionRate: rate,
            behaviorSummary: nil,
            recentTexts: [],
            focusTimeToday: Int.random(in: 0...180),
            energyBlocks: Int.random(in: 0...5),
            currentSceneName: ["Messy Room", "Clean Desk", "Zen Garden", "Night City"].randomElement()!,
            hardwareConnected: Bool.random()
        )
    }

    private init() {}
}

#endif
