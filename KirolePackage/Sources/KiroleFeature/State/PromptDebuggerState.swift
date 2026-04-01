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
    
    /// User provided phrase/keywords for the AI companion to learn during tests
    public var testLearnText: String = ""
    
    /// The style currently selected in the debugger UI for editing.
    public var selectedMockStyle: CompanionStyle = .companion
    
    /// Randomly mock an AIContext for a "worst case" scenario or an interesting setup.
    public func createMockContext() -> AIContext {
        let maxTasks = Int.random(in: 0...8)
        let doneTasks = Int.random(in: 0...maxTasks)
        let rate = maxTasks > 0 ? Double(doneTasks) / Double(maxTasks) : 0
        
        let mockMemories: [[String]] = [
            ["Three days ago, the user completely abandoned all tasks.", "Yesterday, they made a fierce comeback."].shuffled(),
            ["User struggled deeply with 'Writing Code' this morning."].shuffled(),
            ["Last week the user hit a 10-day streak, their highest ever.", "They broke their streak yesterday."].shuffled(),
            []
        ]
        
        let mockEmotions = [
            "deeply amused by the user's struggle but attempting to hide it",
            "exhausted, harboring a deep sense of apathy towards productivity",
            "frantic, treating every single open task as a ticking time bomb",
            "judgmental and smug, feeling infinitely superior to the human user",
            "warm, supportive, but slightly worried about the user's burnout",
            nil
        ]
        
        let mockObjectives = [
            "Use reverse psychology. Act like the task is not worth doing so the user wants to prove you wrong.",
            "De-escalate the user's anxiety by making the current situation feel trivial and manageable.",
            "Mock their ambition gently to lower their defenses, then slip in a genuine piece of advice.",
            nil
        ]
        
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
            hardwareConnected: Bool.random(),
            episodicMemories: mockMemories.randomElement() ?? [],
            dimensionalEmotion: mockEmotions.randomElement() ?? nil,
            psychologicalObjective: mockObjectives.randomElement() ?? nil,
            userDefinedLearnText: testLearnText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : testLearnText
        )
    }

    private init() {}
}

#endif
