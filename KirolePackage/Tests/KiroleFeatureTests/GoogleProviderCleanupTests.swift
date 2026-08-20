import Foundation
import KeychainAccess
import Testing
@testable import KiroleFeature

@Suite("Google provider cleanup")
struct GoogleProviderCleanupTests {
    @Test("launch cleanup removes retired credentials without touching Google")
    func retiredCredentialCleanupPreservesGoogle() throws {
        let serviceName = "com.kirole.tests.retired-credentials.\(UUID().uuidString)"
        let rawKeychain = Keychain(service: serviceName)
        let keychain = KeychainService(service: serviceName)
        try keychain.saveGoogleTokens(accessToken: "google", refreshToken: "refresh", expiresIn: 3_600)
        try rawKeychain.set("retired", key: "notion_access_token")
        try rawKeychain.set("retired", key: "todoist_token_set")

        try keychain.clearRetiredProviderCredentials(microsoftAccessGroup: nil)

        #expect(keychain.getGoogleAccessToken() == "google")
        #expect(try rawKeychain.get("notion_access_token") == nil)
        #expect(try rawKeychain.get("todoist_token_set") == nil)
        try keychain.clearAll()
    }

    @Test("A failed pre-authorization reset preserves the existing Google connection")
    @MainActor
    func authorizationResetFailurePreservesExistingConnection() async throws {
        let serviceName = "com.kirole.tests.google-auth-reset-failure.\(UUID().uuidString)"
        let keychain = KeychainService(service: serviceName)
        try keychain.saveGoogleTokens(
            accessToken: "access",
            refreshToken: "refresh",
            expiresIn: 3_600
        )
        try keychain.saveGoogleScopes([GoogleOAuthScope.tasks])
        let manager = AuthManager(keychainService: keychain)
        manager.restoreLocalIdentityFromKeychain()
        manager.googleSyncStateResetOverride = {
            throw GoogleProviderCleanupTestError.resetFailed
        }

        await #expect(throws: GoogleProviderCleanupTestError.resetFailed) {
            try await manager.signInWithGoogle()
        }

        #expect(manager.isGoogleConnected)
        #expect(manager.hasTasksAccess)
        #expect(keychain.getGoogleAccessToken() == "access")
        #expect(keychain.getGoogleRefreshToken() == "refresh")
        try keychain.clearAll()
    }

    @Test("Disconnect keeps the connection visible when sync-state reset fails")
    @MainActor
    func disconnectDoesNotPretendAfterResetFailure() async throws {
        let serviceName = "com.kirole.tests.google-reset-failure.\(UUID().uuidString)"
        let keychain = KeychainService(service: serviceName)
        try keychain.saveGoogleTokens(
            accessToken: "access",
            refreshToken: "refresh",
            expiresIn: 3_600
        )
        try keychain.saveGoogleScopes([GoogleOAuthScope.tasks])
        let manager = AuthManager(keychainService: keychain)
        manager.restoreLocalIdentityFromKeychain()
        let audit = GoogleCleanupAudit()
        manager.googleSyncStateResetOverride = {
            throw GoogleProviderCleanupTestError.resetFailed
        }
        manager.googleDisconnectOverride = {
            await audit.recordDisconnect()
        }

        let disconnected = await manager.disconnectGoogle()

        #expect(!disconnected)
        #expect(manager.isGoogleConnected)
        #expect(keychain.getGoogleAccessToken() == "access")
        #expect(keychain.getGoogleRefreshToken() == "refresh")
        #expect(await audit.disconnectCount() == 0)
        try keychain.clearAll()
    }

    @Test("Disconnect clears credentials only after sync-state reset succeeds")
    @MainActor
    func disconnectCommitsAfterVerifiedCleanup() async throws {
        let serviceName = "com.kirole.tests.google-reset-success.\(UUID().uuidString)"
        let keychain = KeychainService(service: serviceName)
        try keychain.saveGoogleTokens(
            accessToken: "access",
            refreshToken: "refresh",
            expiresIn: 3_600
        )
        try keychain.saveGoogleScopes([GoogleOAuthScope.tasks])
        let manager = AuthManager(keychainService: keychain)
        manager.restoreLocalIdentityFromKeychain()
        let audit = GoogleCleanupAudit()
        manager.googleSyncStateResetOverride = {
            await audit.recordReset()
        }
        manager.googleDisconnectOverride = {
            await audit.recordDisconnect()
        }

        let disconnected = await manager.disconnectGoogle()

        #expect(disconnected)
        #expect(!manager.isGoogleConnected)
        #expect(manager.googleCalendarAccessLevel == .none)
        #expect(!manager.hasTasksAccess)
        #expect(keychain.getGoogleAccessToken() == nil)
        #expect(keychain.getGoogleRefreshToken() == nil)
        #expect(keychain.getGoogleScopes() == nil)
        #expect(await audit.events() == ["reset", "disconnect"])
    }

    @Test("Global sign-out stops before any other cleanup when Google reset fails")
    @MainActor
    func globalSignOutPreservesIdentityAfterGoogleResetFailure() async throws {
        let serviceName = "com.kirole.tests.google-global-reset.\(UUID().uuidString)"
        let keychain = KeychainService(service: serviceName)
        try keychain.saveAppleUserIdentifier("apple-user")
        let manager = AuthManager(keychainService: keychain)
        manager.restoreLocalIdentityFromKeychain()
        let audit = GoogleCleanupAudit()
        manager.googleSyncStateResetOverride = {
            throw GoogleProviderCleanupTestError.resetFailed
        }
        manager.customCompanionSignOutCleanup = {
            await audit.recordLaterCleanup()
        }
        manager.providerDataSignOutCleanupOverride = {}
        manager.supabaseSignOutOverride = {
            await audit.recordSupabaseSignOut()
        }

        await manager.signOut()

        #expect(manager.currentUser?.id == "apple-user")
        #expect(manager.authState.isAuthenticated)
        #expect(keychain.getAppleUserIdentifier() == "apple-user")
        #expect(await audit.laterCleanupCount() == 0)
        #expect(await audit.supabaseSignOutCount() == 0)
        try keychain.clearAll()
    }
}

private actor GoogleCleanupAudit {
    private var orderedEvents: [String] = []
    private var laterCleanups = 0
    private var supabaseSignOuts = 0

    func recordReset() {
        orderedEvents.append("reset")
    }

    func recordDisconnect() {
        orderedEvents.append("disconnect")
    }

    func recordLaterCleanup() {
        laterCleanups += 1
    }

    func recordSupabaseSignOut() {
        supabaseSignOuts += 1
    }

    func events() -> [String] { orderedEvents }
    func disconnectCount() -> Int { orderedEvents.filter { $0 == "disconnect" }.count }
    func laterCleanupCount() -> Int { laterCleanups }
    func supabaseSignOutCount() -> Int { supabaseSignOuts }
}

private enum GoogleProviderCleanupTestError: Error {
    case resetFailed
}
