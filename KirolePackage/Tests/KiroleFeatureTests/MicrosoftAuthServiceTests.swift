import Foundation
import Testing
@testable import KiroleFeature

@Suite("Microsoft MSAL authentication")
@MainActor
struct MicrosoftAuthServiceTests {
    @Test("Microsoft authorization entry point honors the release gate")
    func releaseGateBlocksAuthorizationEntryPoint() async {
        let manager = AuthManager(
            keychainService: KeychainService(
                service: "com.kirole.tests.microsoft-release-gate.\(UUID().uuidString)"
            ),
            microsoftAvailability: { _ in false }
        )

        await #expect(throws: MicrosoftAuthError.secureConfigurationRequired) {
            try await manager.ensureMicrosoftAccess(for: .outlookCalendar)
        }
    }

    @Test("Microsoft account metadata is stored outside UserDefaults and cleared with Keychain")
    func metadataUsesKeychainAndParticipatesInClearAll() async throws {
        let serviceName = "com.kirole.tests.microsoft-metadata.\(UUID().uuidString)"
        let metadataStore = MicrosoftAccountMetadataStore(service: serviceName)
        let defaults = try #require(UserDefaults(suiteName: serviceName))
        let keychain = KeychainService(service: serviceName)
        defer {
            defaults.removePersistentDomain(forName: serviceName)
            try? keychain.clearAll()
        }

        try await metadataStore.save(MicrosoftAccountMetadata(
            accountID: "home-account-id",
            grantedScopes: ["Tasks.ReadWrite"]
        ))

        #expect(defaults.object(forKey: "microsoft_msal_account_id_v1") == nil)
        #expect(defaults.object(forKey: "microsoft_msal_scopes_v1") == nil)
        #expect(await metadataStore.load()?.accountID == "home-account-id")

        try keychain.clearAll()

        #expect(await metadataStore.load() == nil)
    }

    @Test("MSAL account identifier remains the provider namespace across silent refresh")
    func stableAccountIdentifier() async throws {
        let (metadataStore, keychain) = makeMetadataStore()
        defer { try? keychain.clearAll() }
        let client = MicrosoftMSALClientStub()
        client.interactiveToken = MicrosoftMSALToken(
            accessToken: "interactive-token",
            accountID: "home-account-id",
            grantedScopes: ["Calendars.Read"]
        )
        client.silentToken = MicrosoftMSALToken(
            accessToken: "silent-token",
            accountID: "home-account-id",
            grantedScopes: ["Calendars.Read"]
        )
        let provider = MicrosoftTokenProvider(client: client, metadataStore: metadataStore)

        let account = try await provider.authorize(capabilities: [.outlookCalendar])
        let accessToken = try await provider.accessToken()

        #expect(account.id == "home-account-id")
        #expect(await provider.accountID() == "home-account-id")
        #expect(accessToken == "silent-token")
        #expect(client.lastSilentAccountID == "home-account-id")
        #expect(client.lastSilentScopes == ["Calendars.Read"])
    }

    @Test("Failed MSAL cache removal keeps the selected account metadata")
    func failedDisconnectKeepsMetadata() async throws {
        let (metadataStore, keychain) = makeMetadataStore()
        defer { try? keychain.clearAll() }
        let client = MicrosoftMSALClientStub()
        client.interactiveToken = MicrosoftMSALToken(
            accessToken: "token",
            accountID: "home-account-id",
            grantedScopes: ["Tasks.ReadWrite"]
        )
        client.removeError = MicrosoftAuthTestError.removeFailed
        let provider = MicrosoftTokenProvider(client: client, metadataStore: metadataStore)
        _ = try await provider.authorize(capabilities: [.todo])

        do {
            try await provider.disconnect()
            Issue.record("Expected MSAL removal failure")
        } catch MicrosoftAuthTestError.removeFailed {
            // Expected: metadata must remain so the app does not claim it disconnected.
        }

        #expect(await provider.accountID() == "home-account-id")
    }

    @Test("MSAL disconnect verifies the account actually left the token cache")
    func silentRemovalFailureKeepsMetadata() async throws {
        let (metadataStore, keychain) = makeMetadataStore()
        defer { try? keychain.clearAll() }
        let client = MicrosoftMSALClientStub()
        client.interactiveToken = MicrosoftMSALToken(
            accessToken: "token",
            accountID: "home-account-id",
            grantedScopes: ["Tasks.ReadWrite"]
        )
        client.keepIdentifierAfterRemove = true
        let provider = MicrosoftTokenProvider(client: client, metadataStore: metadataStore)
        _ = try await provider.authorize(capabilities: [.todo])

        await #expect(throws: MicrosoftAuthError.self) {
            try await provider.disconnect()
        }
        #expect(await provider.accountID() == "home-account-id")
    }

    @Test("MSAL disconnect propagates token-cache enumeration failure and keeps metadata")
    func enumerationFailureKeepsMetadata() async throws {
        let (metadataStore, keychain) = makeMetadataStore()
        defer { try? keychain.clearAll() }
        let client = MicrosoftMSALClientStub()
        client.interactiveToken = MicrosoftMSALToken(
            accessToken: "token",
            accountID: "home-account-id",
            grantedScopes: ["Tasks.ReadWrite"]
        )
        let provider = MicrosoftTokenProvider(client: client, metadataStore: metadataStore)
        _ = try await provider.authorize(capabilities: [.todo])
        client.accountIdentifiersError = MicrosoftAuthTestError.enumerationFailed

        await #expect(throws: MicrosoftAuthTestError.self) {
            try await provider.disconnect()
        }

        #expect(await metadataStore.load()?.accountID == "home-account-id")
    }

    @Test("MSAL disconnect removes an orphaned cached account without selected metadata")
    func missingSelectionRemovesOrphanedCachedAccount() async throws {
        let (metadataStore, keychain) = makeMetadataStore()
        defer { try? keychain.clearAll() }
        let client = MicrosoftMSALClientStub()
        client.interactiveToken = MicrosoftMSALToken(
            accessToken: "token",
            accountID: "home-account-id",
            grantedScopes: ["Tasks.ReadWrite"]
        )
        let provider = MicrosoftTokenProvider(client: client, metadataStore: metadataStore)
        _ = try await provider.authorize(capabilities: [.todo])
        try await metadataStore.clear()

        try await provider.disconnect()

        #expect(try client.accountIdentifiers().isEmpty)
        #expect(client.removedIdentifiers == ["home-account-id"])
    }

    @Test("MSAL disconnect removes the selected account first and every historical account")
    func disconnectRemovesAllCachedAccounts() async throws {
        let (metadataStore, keychain) = makeMetadataStore()
        defer { try? keychain.clearAll() }
        let client = MicrosoftMSALClientStub()
        client.interactiveToken = MicrosoftMSALToken(
            accessToken: "token",
            accountID: "selected-account",
            grantedScopes: ["Calendars.Read"]
        )
        let provider = MicrosoftTokenProvider(client: client, metadataStore: metadataStore)
        _ = try await provider.authorize(capabilities: [.outlookCalendar])
        client.addCachedIdentifiers(["historical-b", "historical-a"])

        try await provider.disconnect()

        #expect(try client.accountIdentifiers().isEmpty)
        #expect(client.removedIdentifiers == [
            "selected-account",
            "historical-b",
            "historical-a"
        ])
        #expect(await metadataStore.load() == nil)
    }

    private func makeMetadataStore() -> (MicrosoftAccountMetadataStore, KeychainService) {
        let keychain = KeychainService(
            service: "com.kirole.tests.microsoft-metadata.\(UUID().uuidString)"
        )
        return (MicrosoftAccountMetadataStore(keychain: keychain), keychain)
    }
}

private enum MicrosoftAuthTestError: Error {
    case removeFailed
    case enumerationFailed
}

@MainActor
private final class MicrosoftMSALClientStub: MicrosoftMSALClientProtocol {
    var interactiveToken: MicrosoftMSALToken?
    var silentToken: MicrosoftMSALToken?
    var removeError: Error?
    var accountIdentifiersError: Error?
    var keepIdentifierAfterRemove = false
    private var identifiers: [String] = []
    private(set) var lastSilentAccountID: String?
    private(set) var lastSilentScopes: [String] = []
    private(set) var removedIdentifiers: [String] = []

    func addCachedIdentifiers(_ accountIDs: [String]) {
        identifiers.append(contentsOf: accountIDs)
    }

    func accountIdentifiers() throws -> [String] {
        if let accountIdentifiersError { throw accountIdentifiersError }
        return identifiers
    }

    func acquireTokenInteractively(scopes: [String]) async throws -> MicrosoftMSALToken {
        guard let interactiveToken else { throw MicrosoftAuthError.invalidTokenResponse }
        identifiers = [interactiveToken.accountID]
        return interactiveToken
    }

    func acquireTokenSilently(
        accountID: String,
        scopes: [String],
        forceRefresh: Bool
    ) async throws -> MicrosoftMSALToken {
        lastSilentAccountID = accountID
        lastSilentScopes = scopes
        guard let silentToken else { throw MicrosoftAuthError.invalidTokenResponse }
        return silentToken
    }

    func removeAccount(identifier: String) throws {
        if let removeError { throw removeError }
        removedIdentifiers.append(identifier)
        guard !keepIdentifierAfterRemove else { return }
        identifiers.removeAll { $0 == identifier }
    }
}
