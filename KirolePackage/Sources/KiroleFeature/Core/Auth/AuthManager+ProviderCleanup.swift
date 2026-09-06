import Foundation

@MainActor
extension AuthManager {
    func resetGoogleSyncStateForAccountTransition() async throws {
        if let googleSyncStateResetOverride {
            try await googleSyncStateResetOverride()
        } else {
            try await GoogleSyncEngine.shared.resetAndDisable()
        }
    }

    /// Sign-out counterpart to `resetGoogleSyncStateForAccountTransition`. Deleting the state files
    /// via `clearAll()` is not enough on its own: `MicrosoftSyncStateStore` is an actor holding
    /// `stateCache` / `outboxCache` in memory, so a later sync in the same process would keep using
    /// the previous identity's delta cursor and merge the new account's delta onto an emptied
    /// snapshot — unchanged events would simply disappear.
    func resetMicrosoftSyncStateForAccountTransition() async throws {
        if let microsoftSyncStateResetOverride {
            try await microsoftSyncStateResetOverride()
            return
        }
        // Skip entirely when Outlook was never connected. `clearProviderState()` opens a
        // `MicrosoftSyncCommitGate` transition, and that gate's generation is process-wide static
        // state — running it unconditionally would invalidate unrelated in-flight Microsoft work
        // for no reason. Persistent state is covered regardless: `clearAll()` removes the account
        // metadata and `Files.persisted` now includes both sync-state files. Only the engine's
        // in-memory caches need this call, and those are empty unless this process connected.
        guard isMicrosoftConnected else { return }
        try await MicrosoftSyncEngine.shared.clearProviderState()
    }

    func activateGoogleSyncAfterAuthorization() async throws {
        if let googleSyncActivationOverride {
            try await googleSyncActivationOverride()
        } else {
            try await GoogleSyncEngine.shared.activateAfterAuthorization()
        }
    }
}

enum GoogleProviderCleanupError: LocalizedError, Sendable {
    case credentialsRemain

    var errorDescription: String? {
        "Google credentials could not be removed"
    }
}
