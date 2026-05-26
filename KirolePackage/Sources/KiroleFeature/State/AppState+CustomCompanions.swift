// NOTE: try? is discouraged in this codebase. Use do-try-catch + ErrorReporter.log instead.
import Foundation

extension AppState {

    // MARK: - Lifecycle

    /// Create a new custom companion, persist its metadata + assets, and make it active.
    /// Returns the created companion so the UI can immediately reflect it.
    @discardableResult
    public func addCustomCompanion(
        name: String,
        relationship: CompanionRelationship,
        personaVoice: CompanionPersonaVoice,
        roastModeEnabled: Bool,
        previewData: Data,
        pixelData: Data
    ) async -> CustomCompanion {
        let id = UUID()
        let companion = CustomCompanion(
            id: id,
            name: name,
            relationship: relationship,
            personaVoice: personaVoice,
            roastModeEnabled: roastModeEnabled,
            avatarPreviewFileName: LocalStorage.customCompanionPreviewFileName(for: id),
            avatarPixelsFileName: LocalStorage.customCompanionPixelsFileName(for: id)
        )

        customCompanions.append(companion)

        do {
            try await localStorage.saveCustomCompanionAssets(
                id: id,
                previewData: previewData,
                pixelData: pixelData
            )
        } catch {
            reportPersistenceError(error, operation: "save", target: "custom_companion_assets")
        }

        do {
            try await localStorage.saveCustomCompanions(customCompanions)
        } catch {
            reportPersistenceError(error, operation: "save", target: "custom_companions.json")
        }

        selectCustomCompanion(id: id)
        return companion
    }

    /// Replace an existing custom companion's metadata (name / relationship / voice / roast).
    /// Avatar assets are immutable here — re-upload requires deleting and recreating.
    public func updateCustomCompanion(_ updated: CustomCompanion) {
        guard let index = customCompanions.firstIndex(where: { $0.id == updated.id }) else {
            return
        }
        customCompanions[index] = updated
        persistCustomCompanionsList()
    }

    /// Delete a custom companion (its metadata + assets) and snap back to the built-in
    /// character if it was active.
    public func deleteCustomCompanion(id: UUID) {
        customCompanions.removeAll { $0.id == id }

        if userProfile.customCompanionId == id {
            var profile = userProfile
            profile.customCompanionId = nil
            updateUserProfile(profile)
        }

        Task { @MainActor in
            do {
                try await localStorage.deleteCustomCompanionAssets(id: id)
            } catch {
                reportPersistenceError(error, operation: "delete", target: "custom_companion_assets")
            }
        }
        persistCustomCompanionsList()
    }

    // MARK: - Selection

    public func selectBuiltInCompanion(_ character: CompanionCharacter) {
        var profile = userProfile
        profile.companionCharacter = character
        profile.customCompanionId = nil
        updateUserProfile(profile)
    }

    public func selectCustomCompanion(id: UUID) {
        guard customCompanions.contains(where: { $0.id == id }) else { return }
        var profile = userProfile
        profile.customCompanionId = id
        updateUserProfile(profile)
    }

    // MARK: - Helpers

    public var activeCustomCompanion: CustomCompanion? {
        guard let id = userProfile.customCompanionId else { return nil }
        return customCompanions.first { $0.id == id }
    }

    private func persistCustomCompanionsList() {
        let snapshot = customCompanions
        Task { @MainActor in
            do {
                try await localStorage.saveCustomCompanions(snapshot)
            } catch {
                reportPersistenceError(error, operation: "save", target: "custom_companions.json")
            }
        }
    }
}
