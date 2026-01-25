import SwiftUI
import Observation

enum OnboardingStep: Equatable {
    case awakening      // Initial dark state
    case conversation   // Chatting with shadow
    case naming         // Input name
    case reveal         // Explosion of light
    case sanctuary      // Setup permissions/calendar
    case complete       // Done
}

@Observable
@MainActor
class OnboardingFlowManager {
    // Core State
    var currentStep: OnboardingStep = .awakening
    var petName: String = ""
    var selectedForm: PetForm = .cat
    var selectedPronouns: PetPronouns = .theyThem

    // Animation State
    var isShadowMode: Bool = true
    var isRevealed: Bool = false
    var showFlash: Bool = false

    // Dialog State
    var dialogText: String = ""
    var isTyping: Bool = false
    var showChoices: Bool = false

    // Task Management
    private var revealTask: Task<Void, Never>?
    private var dialogTask: Task<Void, Never>?

    // Dependencies
    private var appState: AppState?
    
    func setAppState(_ state: AppState) {
        self.appState = state
        // Pre-select defaults
        self.selectedForm = state.pet.currentForm
    }
    
    // Actions
    func wakeUp() {
        withAnimation(.easeInOut(duration: 2.0)) {
            currentStep = .conversation
        }
        startDialog(text: "Where am I? ... Oh, hello.")
    }
    
    func selectForm(_ form: PetForm) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            selectedForm = form
        }
    }
    
    func confirmName() {
        guard !petName.isEmpty else { return }

        withAnimation(.easeInOut(duration: 0.5)) {
            currentStep = .reveal
        }

        revealTask?.cancel()
        revealTask = Task { @MainActor in
            try? await performRevealSequence()
        }
    }

    private func performRevealSequence() async throws {
        try await delay(0.5)

        withAnimation(.easeIn(duration: 0.1)) {
            showFlash = true
        }

        try await delay(0.1)
        isShadowMode = false
        isRevealed = true
        appState?.pet.name = petName
        appState?.pet.currentForm = selectedForm
        appState?.pet.pronouns = selectedPronouns

        withAnimation(.easeOut(duration: 1.0)) {
            showFlash = false
        }

        try await delay(1.0)
        startDialog(text: "I am \(petName)! I'm so happy to meet you!")

        try await delay(3.0)
        withAnimation {
            currentStep = .sanctuary
        }
    }

    private func delay(_ seconds: Double) async throws {
        try Task.checkCancellation()
        try await Task.sleep(for: .seconds(seconds))
    }
    
    func completeOnboarding() {
        withAnimation {
            currentStep = .complete
        }
    }
    
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

    /// Cancel all running tasks
    func cancelAllTasks() {
        revealTask?.cancel()
        dialogTask?.cancel()
    }
}
