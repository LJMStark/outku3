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
}

enum GoogleProviderCleanupError: LocalizedError, Sendable {
    case credentialsRemain

    var errorDescription: String? {
        "Google credentials could not be removed"
    }
}
