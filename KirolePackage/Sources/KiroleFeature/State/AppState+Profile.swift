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

        UserDefaults.standard.set(true, forKey: "isOnboardingCompleted")

        // Map AI-relevant fields into UserProfile
        let mappedProfile = UserProfile.from(onboarding: completedProfile, merging: userProfile)
        userProfile = mappedProfile

        Task { @MainActor in
            do {
                try await localStorage.saveOnboardingProfile(completedProfile)
                try await localStorage.saveUserProfile(mappedProfile)
            } catch {
                reportPersistenceError(error, operation: "save", target: "onboarding_profile.json")
                ErrorReporter.log(error, context: "AppState.completeOnboarding")
            }

            // If the user finished the upload form on PersonalizationPage, materialize it
            // into a real CustomCompanion now. addCustomCompanion handles persistence and
            // calls selectCustomCompanion, which re-saves userProfile with the new id.
            if completedProfile.hasCustomCompanionDraft {
                await createCustomCompanionFromOnboarding(completedProfile)
            }
        }
    }

    private func createCustomCompanionFromOnboarding(_ profile: OnboardingProfile) async {
        guard let rawName = profile.customCompanionName,
              let preview = profile.customAvatarPreviewData,
              let pixels = profile.customAvatarPixelData else {
            return
        }
        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let relationship = profile.customCompanionRelationship ?? .pet
        let voice = profile.customCompanionVoice ?? .companion

        do {
            _ = try await addCustomCompanion(
                name: trimmedName,
                relationship: relationship,
                personaVoice: voice,
                roastModeEnabled: profile.customCompanionRoast,
                previewData: preview,
                pixelData: pixels
            )
        } catch {
            reportPersistenceError(error, operation: "create", target: "custom_companion_from_onboarding")
            ErrorReporter.log(error, context: "AppState.createCustomCompanionFromOnboarding")
        }
    }

    /// UserProfile is the authoritative source for onboarding completion
    public var isOnboardingCompleted: Bool {
        userProfile.onboardingCompletedAt != nil
    }

    public func resetOnboarding() async {
        onboardingProfile = nil
        userProfile.onboardingCompletedAt = nil
        UserDefaults.standard.set(false, forKey: "isOnboardingCompleted")

        do {
            try await localStorage.deleteFile(named: "onboarding_profile.json")
            try await localStorage.saveUserProfile(userProfile)
        } catch {
            reportPersistenceError(error, operation: "reset", target: "onboarding_profile.json")
            ErrorReporter.log(error, context: "AppState.resetOnboarding")
        }
    }
}
