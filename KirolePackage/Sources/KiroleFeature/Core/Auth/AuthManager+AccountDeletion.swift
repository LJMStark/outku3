import Foundation

public enum AccountDeletionError: Error, LocalizedError, Equatable, Sendable {
    case notAuthenticated
    case remoteDeletionFailed
    case localCredentialsRemain

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Sign in before deleting your account."
        case .remoteDeletionFailed:
            return "Couldn't delete the account. Check your connection and try again."
        case .localCredentialsRemain:
            return "Your Kirole account was deleted, but this iPhone could not remove local sign-in data. Try Delete Account again."
        }
    }
}

extension AuthManager {
    /// Deletes the cloud account when a session exists, then signs out and wipes local data.
    /// Missing/unconfigured cloud sessions skip the RPC. Retryable remote failures keep the session.
    public func deleteAccount() async throws {
        guard authState.isAuthenticated else {
            throw AccountDeletionError.notAuthenticated
        }

        do {
            try await attemptRemoteAccountDeletion()
        } catch {
            guard AccountDeletionRemotePolicy.canFinishLocallyAfterRemoteError(error) else {
                ErrorReporter.log(error, context: "AuthManager.deleteAccount.remote")
                throw AccountDeletionError.remoteDeletionFailed
            }
            ErrorReporter.log(error, context: "AuthManager.deleteAccount.remoteSkippedOrAlreadyGone")
        }

        await signOut()
        if authState.isAuthenticated {
            do {
                try abandonLocalSessionAfterRemoteAccountDeletion()
            } catch {
                ErrorReporter.log(error, context: "AuthManager.deleteAccount.localCredentials")
                throw AccountDeletionError.localCredentialsRemain
            }
        }

        if let accountDeletionLocalResetOverride {
            await accountDeletionLocalResetOverride()
        } else {
            await AppState.shared.resetLocalDataAfterAccountDeletion()
        }
    }

    func attemptRemoteAccountDeletion() async throws {
        if let accountDeletionRemoteOverride {
            try await accountDeletionRemoteOverride()
            return
        }

        // Pending local identity with no JWT: there is nothing to delete on the server
        // from this device. Do not call the shared Supabase client (it reads the
        // process-wide keychain, not this manager's isolated keychain).
        if currentUser?.isPendingRemoteIdentity == true,
           !hasLocalSupabaseAccessToken {
            return
        }

        try await supabaseService.deleteOwnAccount()
    }
}
