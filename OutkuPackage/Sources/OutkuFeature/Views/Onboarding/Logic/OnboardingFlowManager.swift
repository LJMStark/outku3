import SwiftUI
import Observation

// MARK: - Onboarding Step

public enum OnboardingStep: Int, CaseIterable, Equatable {
    case welcome = 0
    case identity = 1
    case goals = 2
    case companionStyle = 3
    case awakening = 4
    case naming = 5
    case connect = 6
    case complete = 7

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    var previous: OnboardingStep? {
        OnboardingStep(rawValue: rawValue - 1)
    }
}

// MARK: - Onboarding Flow Manager

@Observable
@MainActor
public class OnboardingFlowManager {
    // Core State
    public var currentStep: OnboardingStep = .welcome
    public var petName: String = ""

    // User Profile Data
    public var selectedWorkType: WorkType?
    public var selectedGoals: Set<UserGoal> = []
    public var selectedCompanionStyle: CompanionStyle?

    // Animation State
    public var isShadowMode: Bool = true
    public var isRevealed: Bool = false
    public var showFlash: Bool = false

    // Dialog State
    public var dialogText: String = ""
    public var isTyping: Bool = false
    public var showChoices: Bool = false
    public var currentDialogIndex: Int = 0

    // Task Management
    private var revealTask: Task<Void, Never>?
    private var dialogTask: Task<Void, Never>?

    // Dependencies
    private var appState: AppState?

    // Suggested pet names
    public let suggestedNames = ["Tiko", "Pixel", "Mochi", "Bean"]

    // Awakening dialog sequence
    private let awakeningDialogs = [
        "I've been waiting for you...",
        "I'm Tiko, and I'll be with you on this journey.",
        "I might look different each day, but I'm always here."
    ]

    public init() {}

    public func setAppState(_ state: AppState) {
        self.appState = state
    }

    // MARK: - Navigation

    public func goToNextStep() {
        guard let next = currentStep.next else { return }
        withAnimation(.easeInOut(duration: 0.5)) {
            currentStep = next
        }

        if next == .awakening {
            startAwakeningSequence()
        } else if next == .naming {
            startDialog(text: "What would you like to call me?")
        }
    }

    public func goToPreviousStep() {
        guard let previous = currentStep.previous else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = previous
        }
    }

    // MARK: - Step Actions

    public func selectWorkType(_ type: WorkType) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            selectedWorkType = type
        }
        // Auto-advance after selection
        Task { @MainActor in
            try? await delay(0.3)
            goToNextStep()
        }
    }

    public func toggleGoal(_ goal: UserGoal) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if selectedGoals.contains(goal) {
                selectedGoals.remove(goal)
            } else if selectedGoals.count < 3 {
                selectedGoals.insert(goal)
            }
        }
    }

    public func selectCompanionStyle(_ style: CompanionStyle) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            selectedCompanionStyle = style
        }
        // Auto-advance after selection
        Task { @MainActor in
            try? await delay(0.3)
            goToNextStep()
        }
    }

    public func selectSuggestedName(_ name: String) {
        petName = name
    }

    // MARK: - Awakening Sequence

    private func startAwakeningSequence() {
        currentDialogIndex = 0
        showNextAwakeningDialog()
    }

    private func showNextAwakeningDialog() {
        guard currentDialogIndex < awakeningDialogs.count else {
            // Finished all dialogs, move to naming
            Task { @MainActor in
                try? await delay(1.0)
                goToNextStep()
            }
            return
        }

        startDialog(text: awakeningDialogs[currentDialogIndex])
    }

    public func advanceAwakeningDialog() {
        currentDialogIndex += 1
        showNextAwakeningDialog()
    }

    // MARK: - Naming & Reveal

    public func confirmName() {
        guard !petName.isEmpty else { return }

        revealTask?.cancel()
        revealTask = Task { @MainActor in
            try? await performRevealSequence()
        }
    }

    private func performRevealSequence() async throws {
        try await delay(0.3)

        withAnimation(.easeIn(duration: 0.1)) {
            showFlash = true
        }

        try await delay(0.1)
        isShadowMode = false
        isRevealed = true

        // Update pet name
        appState?.pet.name = petName

        withAnimation(.easeOut(duration: 1.0)) {
            showFlash = false
        }

        try await delay(1.0)
        startDialog(text: "I am \(petName)! I'm so happy to meet you!")

        try await delay(2.5)
        withAnimation {
            currentStep = .connect
        }
    }

    // MARK: - Complete Onboarding

    public func completeOnboarding() {
        // Save user profile to AppState
        guard let appState = appState else { return }

        let profile = UserProfile(
            workType: selectedWorkType ?? .other,
            primaryGoals: Array(selectedGoals),
            companionStyle: selectedCompanionStyle ?? .encouraging,
            onboardingCompletedAt: Date()
        )

        appState.updateUserProfile(profile)

        withAnimation {
            currentStep = .complete
        }
    }

    public func skipConnect() {
        completeOnboarding()
    }

    // MARK: - Dialog

    public func startDialog(text: String) {
        dialogText = ""
        isTyping = true
        showChoices = false

        dialogTask?.cancel()
        dialogTask = Task { @MainActor in
            for char in text {
                try? await delay(0.03)
                dialogText.append(char)
            }
            isTyping = false
            showChoices = true
        }
    }

    private func delay(_ seconds: Double) async throws {
        try Task.checkCancellation()
        try await Task.sleep(for: .seconds(seconds))
    }

    // MARK: - Cleanup

    public func cancelAllTasks() {
        revealTask?.cancel()
        dialogTask?.cancel()
    }

    // MARK: - Validation

    public var canProceedFromNaming: Bool {
        !petName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
