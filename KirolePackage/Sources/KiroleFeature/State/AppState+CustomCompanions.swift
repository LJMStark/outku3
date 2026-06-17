// NOTE: try? is discouraged in this codebase. Use do-try-catch + ErrorReporter.log instead.
import Foundation

extension AppState {

    // MARK: - Lifecycle

    /// Create a new custom companion, persist its metadata + assets, and make it active.
    /// Throws on persistence failure so the UI can surface the error and the user can retry —
    /// silently swallowing the error here used to leave a customCompanionId pointing at a
    /// companion that had never been written to disk.
    @discardableResult
    public func addCustomCompanion(
        name: String,
        relationship: CompanionRelationship,
        personaVoice: CompanionPersonaVoice,
        customPrompt: String = "",
        curiosityLevel: Double = 0.5,
        humorLevel: Double = 0.5,
        strictnessLevel: Double = 0.3,
        backstory: String = "",
        sensitiveBoundary: String = "",
        previewData: Data,
        pixelData: Data
    ) async throws -> CustomCompanion {
        let id = UUID()
        let companion = CustomCompanion(
            id: id,
            name: name,
            relationship: relationship,
            personaVoice: personaVoice,
            customPrompt: customPrompt,
            curiosityLevel: curiosityLevel,
            humorLevel: humorLevel,
            strictnessLevel: strictnessLevel,
            backstory: backstory,
            sensitiveBoundary: sensitiveBoundary,
            avatarPreviewFileName: LocalStorage.customCompanionPreviewFileName(for: id),
            avatarPixelsFileName: LocalStorage.customCompanionPixelsFileName(for: id)
        )

        // Persist assets first; if this fails we never touch in-memory or selection state.
        try await localStorage.saveCustomCompanionAssets(
            id: id,
            previewData: previewData,
            pixelData: pixelData
        )

        // Build the would-be list and try to persist before mutating shared state. If list
        // persistence fails, roll back the asset write so we don't leak orphan files.
        let updatedList = customCompanions + [companion]
        do {
            try await localStorage.saveCustomCompanions(updatedList)
        } catch {
            try? await localStorage.deleteCustomCompanionAssets(id: id)
            throw error
        }

        customCompanions = updatedList
        selectCustomCompanion(id: id)
        return companion
    }

    /// Replace an existing custom companion's metadata (name / relationship / voice / roast).
    /// Avatar assets are immutable here — re-upload requires deleting and recreating.
    /// Bumps `updatedAt` so downstream caches (e.g. home dialogue fingerprint) invalidate
    /// even if the caller forgot to set it.
    public func updateCustomCompanion(_ updated: CustomCompanion) {
        guard let index = customCompanions.firstIndex(where: { $0.id == updated.id }) else {
            return
        }
        var bumped = updated
        bumped.updatedAt = Date()
        customCompanions[index] = bumped
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

    /// Switching to a new companion identity resets intimacy back to acquaintance —
    /// staying at "close friend" while meeting a brand-new persona would make the AI
    /// open with an unearned tone. Selecting the same companion again is a no-op for intimacy.
    public func selectBuiltInCompanion(_ character: CompanionCharacter) {
        let isDifferentIdentity = userProfile.currentSelection != .builtIn(character)
        var profile = userProfile
        profile.companionCharacter = character
        profile.customCompanionId = nil
        if isDifferentIdentity {
            profile.intimacyStage = .acquaintance
        }
        updateUserProfile(profile)
    }

    public func selectCustomCompanion(id: UUID) {
        guard customCompanions.contains(where: { $0.id == id }) else { return }
        let isDifferentIdentity = userProfile.currentSelection != .custom(id)
        var profile = userProfile
        profile.customCompanionId = id
        if isDifferentIdentity {
            profile.intimacyStage = .acquaintance
        }
        updateUserProfile(profile)
        requestBLESync(reason: "selectCustomCompanion")

        // Re-push the pixel frame so the device shows the newly active avatar.
        Task { @MainActor in
            guard let pixels = await localStorage.loadCustomCompanionPixels(id: id) else { return }
            customAvatarFlushAttempts = 0  // fresh retry budget for the newly selected avatar
            await pushCustomAvatarFrame(pixelData: pixels, companionId: id)
        }
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

    /// Sends the avatar pixel frame via BLE. On failure, queues the companion ID in LocalStorage
    /// so `flushPendingCustomCompanionPushIfNeeded` can retry on the next BLE reconnect.
    private func pushCustomAvatarFrame(pixelData: Data, companionId: UUID) async {
        do {
            try await BLEService.shared.sendCustomAvatarFrame(pixelData: pixelData)
            await localStorage.clearPendingCustomCompanionPush()
            isCustomAvatarPendingBLEPush = false
            customAvatarFlushAttempts = 0
        } catch {
            await localStorage.savePendingCustomCompanionPush(id: companionId)
            isCustomAvatarPendingBLEPush = true
            ErrorReporter.log(
                .sync(component: "BLE CustomAvatarFrame", underlying: error.localizedDescription),
                context: "AppState.pushCustomAvatarFrame id=\(companionId)"
            )
        }
    }

    /// Flush back-off policy. Re-push the 0x15 frame on every sync for the first
    /// `maxImmediateFlushAttempts`, then drop to once every `periodicFlushRetryInterval` syncs.
    /// This stops the frame from being re-sent on every single sync while firmware can't accept
    /// 0x15 yet, WITHOUT ever permanently giving up: a hard cap would strand a pending push
    /// forever once hit — a transient failure streak (hardware briefly unready) would then never
    /// self-heal even after the hardware recovers, leaving the device on the old avatar until the
    /// user manually re-selects a companion. Counter resets on a successful push or new selection.
    private static let maxImmediateFlushAttempts = 5
    private static let periodicFlushRetryInterval = 20

    /// Whether the `attempt`-th consecutive flush should actually re-push. Pure + static so the
    /// back-off schedule is unit-testable without driving real BLE. `attempt` is 1-based.
    static func shouldAttemptCustomAvatarFlush(attempt: Int) -> Bool {
        attempt <= maxImmediateFlushAttempts || attempt % periodicFlushRetryInterval == 0
    }

    /// Called by BLESyncCoordinator after establishing a connection.
    /// Re-sends the avatar frame for the active custom companion when a previous push failed.
    public func flushPendingCustomCompanionPushIfNeeded() async {
        guard isCustomAvatarPendingBLEPush,
              let id = userProfile.customCompanionId,
              let pixels = await localStorage.loadCustomCompanionPixels(id: id) else {
            return
        }
        // Count every flush opportunity (even skipped ones) so the periodic retry keeps advancing.
        customAvatarFlushAttempts += 1
        guard Self.shouldAttemptCustomAvatarFlush(attempt: customAvatarFlushAttempts) else { return }
        await pushCustomAvatarFrame(pixelData: pixels, companionId: id)
    }
}
