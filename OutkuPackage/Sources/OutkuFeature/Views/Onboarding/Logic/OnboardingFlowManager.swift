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
        
        // Sequence the reveal
        // Sequence the reveal
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            // 1. Brief pause
            try? await Task.sleep(for: .seconds(0.5))
            
            // 2. Flash
            withAnimation(.easeIn(duration: 0.1)) {
                self.showFlash = true
            }
            
            // 3. Switch to revealed state behind the flash
            try? await Task.sleep(for: .seconds(0.1))
            self.isShadowMode = false
            self.isRevealed = true
            self.appState?.pet.name = self.petName
            self.appState?.pet.currentForm = self.selectedForm
            self.appState?.pet.pronouns = self.selectedPronouns
            
            // 4. Fade out flash
            withAnimation(.easeOut(duration: 1.0)) {
                self.showFlash = false
            }
            
            // 5. Success Dialog
            try? await Task.sleep(for: .seconds(1.0))
            self.startDialog(text: "I am \(self.petName)! I'm so happy to meet you!")
            
            // 6. Transition to Sanctuary after delay
            try? await Task.sleep(for: .seconds(3.0))
            withAnimation {
                self.currentStep = .sanctuary
            }
        }
    }
    
    func completeOnboarding() {
        withAnimation {
            currentStep = .complete
        }
    }
    
    // Helper to simulate typing
    public func startDialog(text: String) {
        dialogText = ""
        isTyping = true
        showChoices = false
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            for char in text {
                self.dialogText.append(char)
                // Haptic feedback could go here
                try? await Task.sleep(for: .seconds(0.03))
            }
            
            self.isTyping = false
            self.showChoices = true
        }
    }
}
