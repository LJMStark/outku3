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

    func activateGoogleSyncAfterAuthorization() async throws {
        if let googleSyncActivationOverride {
            try await googleSyncActivationOverride()
        } else {
            try await GoogleSyncEngine.shared.activateAfterAuthorization()
        }
    }

    func cleanupTaskProvidersForSignOut() async throws {
        if let taskProviderSignOutCleanupOverride {
            try await taskProviderSignOutCleanupOverride()
            return
        }

        var firstBlockingError: Error?
        let hasSavedMicrosoftAccount = await MicrosoftAccountMetadataStore.shared.load() != nil
        if AppSecrets.microsoftClientId != nil || isMicrosoftConnected || hasSavedMicrosoftAccount {
            do {
                try await disconnectMicrosoft()
            } catch {
                firstBlockingError = error
                ErrorReporter.log(error, context: "AuthManager.signOut.disconnectMicrosoft")
            }
        }

        do {
            try await disconnectTodoist()
        } catch {
            firstBlockingError = firstBlockingError ?? error
            ErrorReporter.log(error, context: "AuthManager.signOut.disconnectTodoist")
        }

        do {
            try await disconnectTickTick()
        } catch TickTickAuthError.serverCleanupPending {
            // Local credentials and sync state were verified absent. The server metadata can be
            // retried by its own expiry/cleanup process and must not trap the user in this account.
            AppState.shared.lastError = TickTickAuthError.serverCleanupPending.localizedDescription
            ErrorReporter.log(
                TickTickAuthError.serverCleanupPending,
                context: "AuthManager.signOut.disconnectTickTick.serverCleanupPending"
            )
        } catch {
            firstBlockingError = firstBlockingError ?? error
            ErrorReporter.log(error, context: "AuthManager.signOut.disconnectTickTick")
        }

        if let firstBlockingError { throw firstBlockingError }
    }
}

enum GoogleProviderCleanupError: LocalizedError, Sendable {
    case credentialsRemain

    var errorDescription: String? {
        "Google credentials could not be removed"
    }
}
