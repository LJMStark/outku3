import Foundation

extension AppState {
    public func updateUserProfile(_ profile: UserProfile) {
        userProfile = profile
        Task { @MainActor in
            do {
                try await localStorage.saveUserProfile(profile)
            } catch {
                reportPersistenceError(error, operation: "save", target: "user_profile.json")
                ErrorReporter.log(error, context: "AppState.updateUserProfile")
            }
        }
    }

    public func completeOnboarding(with profile: OnboardingProfile) {
        var completedProfile = profile
        completedProfile.onboardingCompletedAt = Date()
        onboardingProfile = completedProfile

        Task { @MainActor in
            do {
                try await localStorage.saveOnboardingProfile(completedProfile)
            } catch {
                reportPersistenceError(error, operation: "save", target: "onboarding_profile.json")
                ErrorReporter.log(error, context: "AppState.completeOnboarding")
            }
        }
    }

    public var isOnboardingCompleted: Bool {
        onboardingProfile?.onboardingCompletedAt != nil || userProfile.onboardingCompletedAt != nil
    }

    public func resetOnboarding() async {
        onboardingProfile = nil
        userProfile.onboardingCompletedAt = nil

        do {
            try await localStorage.deleteFile(named: "onboarding_profile.json")
            try await localStorage.saveUserProfile(userProfile)
        } catch {
            reportPersistenceError(error, operation: "reset", target: "onboarding_profile.json")
            ErrorReporter.log(error, context: "AppState.resetOnboarding")
        }
    }
}
