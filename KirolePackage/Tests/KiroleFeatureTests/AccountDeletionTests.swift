import Foundation
import Testing
@testable import KiroleFeature

@Suite("Account deletion remote policy")
struct AccountDeletionRemotePolicyTests {
    @Test("Missing or unconfigured cloud sessions can finish locally")
    func missingCloudSessionCanFinishLocally() {
        #expect(AccountDeletionRemotePolicy.canFinishLocallyAfterRemoteError(SupabaseError.notConfigured))
        #expect(AccountDeletionRemotePolicy.canFinishLocallyAfterRemoteError(SupabaseError.noSession))
        #expect(!AccountDeletionRemotePolicy.canFinishLocallyAfterRemoteError(SupabaseError.sessionUserMismatch))
        #expect(!AccountDeletionRemotePolicy.canFinishLocallyAfterRemoteError(AccountDeletionError.remoteDeletionFailed))
        #expect(!AccountDeletionRemotePolicy.canFinishLocallyAfterRemoteError(URLError(.notConnectedToInternet)))
    }

    @Test("HTTP 401 after delete is treated as the cloud account already being gone")
    func http401IsDeletedCloudSession() {
        #expect(AccountDeletionRemotePolicy.isDeletedCloudStatus(401))
        #expect(!AccountDeletionRemotePolicy.isDeletedCloudStatus(403))
        #expect(!AccountDeletionRemotePolicy.isDeletedCloudStatus(500))
        #expect(
            AccountDeletionRemotePolicy.canFinishLocallyAfterRemoteError(
                AccountDeletionRemotePolicy.httpError(statusCode: 401)
            )
        )
        #expect(
            !AccountDeletionRemotePolicy.canFinishLocallyAfterRemoteError(
                AccountDeletionRemotePolicy.httpError(statusCode: 500)
            )
        )
    }
}

@Suite("Account deletion")
struct AccountDeletionTests {
    @Test("Delete account requires an authenticated session")
    @MainActor
    func deleteAccountRequiresAuthentication() async {
        let serviceName = "com.kirole.tests.account-deletion.\(UUID().uuidString)"
        let manager = AuthManager(keychainService: KeychainService(service: serviceName))

        await #expect(throws: AccountDeletionError.notAuthenticated) {
            try await manager.deleteAccount()
        }
    }

    @Test("Pending local identity without a cloud session still wipes locally")
    @MainActor
    func deleteAccountSkipsRemoteWhenPendingAndHasNoSession() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let serviceName = "com.kirole.tests.account-deletion-pending.\(UUID().uuidString)"
            let keychain = KeychainService(service: serviceName)
            try keychain.saveAppleUserIdentifier("apple-user-delete-pending")
            let manager = AuthManager(keychainService: keychain)
            manager.restoreLocalIdentityFromKeychain()
            #expect(manager.currentUser?.isPendingRemoteIdentity == true)
            #expect(!manager.hasLocalSupabaseAccessToken)
            stubSuccessfulLocalSignOut(on: manager)
            var didResetLocalData = false
            manager.accountDeletionLocalResetOverride = {
                didResetLocalData = true
            }

            try await manager.deleteAccount()

            #expect(didResetLocalData)
            #expect(manager.authState == .unauthenticated)
            try keychain.clearAll()
        }
    }

    @Test("Retryable remote deletion failure keeps the session")
    @MainActor
    func deleteAccountKeepsSessionWhenRemoteFails() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let serviceName = "com.kirole.tests.account-deletion-fail.\(UUID().uuidString)"
            let keychain = KeychainService(service: serviceName)
            try keychain.saveAppleUserIdentifier("apple-user-delete-fail")
            let manager = AuthManager(keychainService: keychain)
            manager.restoreLocalIdentityFromKeychain()
            manager.accountDeletionRemoteOverride = {
                throw URLError(.notConnectedToInternet)
            }
            manager.accountDeletionLocalResetOverride = {}

            await #expect(throws: AccountDeletionError.remoteDeletionFailed) {
                try await manager.deleteAccount()
            }
            #expect(manager.authState.isAuthenticated)
            #expect(keychain.getAppleUserIdentifier() == "apple-user-delete-fail")
            try keychain.clearAll()
        }
    }

    @Test("HTTP 401 from the delete RPC still signs out")
    @MainActor
    func deleteAccountTreatsUnauthorizedAsRemoteSuccess() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let serviceName = "com.kirole.tests.account-deletion-401.\(UUID().uuidString)"
            let keychain = KeychainService(service: serviceName)
            try keychain.saveAppleUserIdentifier("apple-user-delete-401")
            let manager = AuthManager(keychainService: keychain)
            manager.restoreLocalIdentityFromKeychain()
            stubSuccessfulLocalSignOut(on: manager)
            manager.accountDeletionRemoteOverride = {
                throw AccountDeletionRemotePolicy.httpError(statusCode: 401)
            }
            var didResetLocalData = false
            manager.accountDeletionLocalResetOverride = {
                didResetLocalData = true
            }

            try await manager.deleteAccount()

            #expect(didResetLocalData)
            #expect(manager.authState == .unauthenticated)
            try keychain.clearAll()
        }
    }

    @Test("Successful deletion signs out without wiping shared app state in tests")
    @MainActor
    func deleteAccountSignsOutAfterRemoteSuccess() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let serviceName = "com.kirole.tests.account-deletion-ok.\(UUID().uuidString)"
            let keychain = KeychainService(service: serviceName)
            try keychain.saveAppleUserIdentifier("apple-user-delete-ok")
            let manager = AuthManager(keychainService: keychain)
            manager.restoreLocalIdentityFromKeychain()
            stubSuccessfulLocalSignOut(on: manager)
            manager.accountDeletionRemoteOverride = {}
            var didResetLocalData = false
            manager.accountDeletionLocalResetOverride = {
                didResetLocalData = true
            }

            try await manager.deleteAccount()

            #expect(didResetLocalData)
            #expect(manager.authState == .unauthenticated)
            try keychain.clearAll()
        }
    }

    @Test("Successful remote deletion still drops the session if sign-out aborts")
    @MainActor
    func deleteAccountDropsSessionWhenSignOutAborts() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let serviceName = "com.kirole.tests.account-deletion-force.\(UUID().uuidString)"
            let keychain = KeychainService(service: serviceName)
            try keychain.saveAppleUserIdentifier("apple-user-delete-force")
            let manager = AuthManager(keychainService: keychain)
            manager.restoreLocalIdentityFromKeychain()
            manager.googleSyncStateResetOverride = {}
            manager.customCompanionSignOutCleanup = {
                throw AccountDeletionTestError.signOutAborted
            }
            manager.accountDeletionRemoteOverride = {}
            manager.accountDeletionLocalResetOverride = {}

            try await manager.deleteAccount()

            #expect(manager.authState == .unauthenticated)
            #expect(keychain.getAppleUserIdentifier() == nil)
        }
    }

    @Test("Keychain cleanup failure keeps the session after a remote delete")
    @MainActor
    func deleteAccountKeepsSessionWhenKeychainClearFails() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let serviceName = "com.kirole.tests.account-deletion-keychain.\(UUID().uuidString)"
            let keychain = KeychainService(service: serviceName)
            try keychain.saveAppleUserIdentifier("apple-user-delete-keychain")
            let manager = AuthManager(keychainService: keychain)
            manager.restoreLocalIdentityFromKeychain()
            manager.googleSyncStateResetOverride = {}
            manager.customCompanionSignOutCleanup = {
                throw AccountDeletionTestError.signOutAborted
            }
            manager.localCredentialSignOutCleanupOverride = {
                throw KeychainCleanupError.credentialDeletionFailed
            }
            manager.accountDeletionRemoteOverride = {}
            var didResetLocalData = false
            manager.accountDeletionLocalResetOverride = {
                didResetLocalData = true
            }

            await #expect(throws: AccountDeletionError.localCredentialsRemain) {
                try await manager.deleteAccount()
            }
            #expect(!didResetLocalData)
            #expect(manager.authState.isAuthenticated)
            #expect(keychain.getAppleUserIdentifier() == "apple-user-delete-keychain")
            try keychain.clearAll()
        }
    }

    @MainActor
    private func stubSuccessfulLocalSignOut(on manager: AuthManager) {
        manager.googleSyncStateResetOverride = {}
        manager.customCompanionSignOutCleanup = {}
        manager.taskProviderSignOutCleanupOverride = {}
        manager.providerDataSignOutCleanupOverride = {}
        manager.localCredentialSignOutCleanupOverride = {}
        manager.supabaseSignOutOverride = {}
    }
}

@Suite("Customer settings account policy")
struct CustomerSettingsAccountPolicyTests {
    @Test("Settings expose privacy policy, sign out, and delete account")
    func settingsExposeAccountAndPrivacyControls() throws {
        let settings = try sourceFile(
            path: "KirolePackage/Sources/KiroleFeature/Views/Settings/SettingsView.swift"
        )
        let session = try sourceFile(
            path: "KirolePackage/Sources/KiroleFeature/Views/Settings/SettingsSessionSection.swift"
        )
        let header = try sourceFile(
            path: "KirolePackage/Sources/KiroleFeature/Views/Components/AppHeaderView.swift"
        )

        #expect(settings.contains("Settings_PrivacyPolicy"))
        #expect(settings.contains("https://kirole.681023.xyz/privacy.html"))
        #expect(settings.contains("SettingsSessionSection()"))
        #expect(session.contains("Settings_SignOut"))
        #expect(session.contains("Settings_DeleteAccount"))
        #expect(session.contains("Delete Account"))
        #expect(header.contains("Home_WeatherAttribution"))
        #expect(header.contains("\\u{F8FF} Weather"))
    }

    @Test("Gated integrations stay out of the customer picker")
    func availableDisplayOrderHidesGatedProviders() {
        let available = IntegrationType.availableDisplayOrder
        #expect(available == IntegrationType.displayOrder.filter(\.isAvailable))
        #expect(available.contains(.googleCalendar))
        #expect(available.contains(.appleCalendar))
        #expect(available.contains(.appleReminders))
        #expect(available.contains(.googleTasks))
        for gated in [
            IntegrationType.notion,
            .taskade,
            .todoist,
            .tickTick,
            .outlookCalendar,
            .microsoftToDo
        ] where !gated.isAvailable {
            #expect(!available.contains(gated))
        }
    }

    private func sourceFile(path: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appending(path: path),
            encoding: .utf8
        )
    }
}

private enum AccountDeletionTestError: Error {
    case signOutAborted
}
