import Foundation

extension AppState {
    /// Clears on-device identity after the cloud account is already gone.
    public func resetLocalDataAfterAccountDeletion() async {
        do {
            try await localStorage.clearAll()
        } catch {
            ErrorReporter.log(error, context: "AppState.resetLocalDataAfterAccountDeletion")
        }

        tasks = []
        events = []
        pet = Pet()
        userProfile = .default
        customCompanions = []
        onboardingProfile = nil
        integrations = Integration.defaultIntegrations
        hasExplicitIntegrationConnectionPreferences = false
        integrationLastSyncedAt = [:]
        remoteSyncErrors = [:]
        remoteSyncWarnings = [:]
        currentHaiku = .placeholder
        currentPetDialogue = ""
        weather = Weather()
        lastError = nil
        updateStatistics()
        await resetOnboarding()
    }
}
