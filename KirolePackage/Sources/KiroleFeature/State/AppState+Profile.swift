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

        // Map AI-relevant fields into UserProfile
        let mappedProfile = UserProfile.from(onboarding: completedProfile, merging: userProfile)
        userProfile = mappedProfile

        Task { @MainActor in
            // Order matters: create + select the custom companion FIRST, then persist
            // both profiles, and only then set the "isOnboardingCompleted" gate flag
            // that ContentView's @AppStorage reads. If the process dies or a save throws
            // anywhere along the way, the flag stays false and the user redoes
            // onboarding on next launch (anything already persisted survives on disk).
            // The old order set the gate flag synchronously up front, so a death or
            // save failure before the writes stranded the user in the main app with a
            // default profile and no way back into onboarding.
            if completedProfile.hasCustomCompanionDraft {
                await createCustomCompanionFromOnboarding(completedProfile)
                // addCustomCompanion → selectCustomCompanion → updateUserProfile already
                // saved user_profile.json with customCompanionId set.
            }

            do {
                try await localStorage.saveOnboardingProfile(completedProfile)
                // Use current userProfile (not the captured mappedProfile) so any
                // customCompanionId / intimacyStage updates from selectCustomCompanion
                // above are included in this redundant-but-idempotent write.
                try await localStorage.saveUserProfile(userProfile)
                // Gate flag LAST — only a fully persisted onboarding may flip the UI gate.
                UserDefaults.standard.set(true, forKey: "isOnboardingCompleted")
            } catch {
                reportPersistenceError(error, operation: "save", target: "onboarding_profile.json")
                ErrorReporter.log(error, context: "AppState.completeOnboarding")
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
        let customPrompt = voice == .customPrompt ? profile.customCompanionPrompt ?? "" : ""

        do {
            _ = try await addCustomCompanion(
                name: trimmedName,
                relationship: relationship,
                personaVoice: voice,
                customPrompt: customPrompt,
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
