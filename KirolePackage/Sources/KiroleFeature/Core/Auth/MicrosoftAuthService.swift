import Foundation
@preconcurrency import MSAL
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Cloud support

public enum MicrosoftCloudEnvironment: String, Sendable, Codable {
    case global
    case china21Vianet

    public var isSupported: Bool { self == .global }
}

public struct MicrosoftAccount: Sendable, Equatable {
    public let id: String
    public let cloud: MicrosoftCloudEnvironment
}

public enum MicrosoftIntegrationCapability: Sendable, CaseIterable, Hashable {
    case outlookCalendar
    case todo

    var delegatedScope: String {
        switch self {
        case .outlookCalendar: "Calendars.Read"
        case .todo: "Tasks.ReadWrite"
        }
    }
}

// MARK: - Public service

/// Microsoft public-client authentication backed by the official MSAL SDK.
///
/// MSAL owns authorization-code PKCE, token refresh, and token persistence. Kirole stores only
/// the selected MSAL account identifier and the minimal Graph scopes granted to that account.
@MainActor
public final class MicrosoftAuthService {
    public static let shared = MicrosoftAuthService()

    private let tokenProvider: MicrosoftTokenProvider

    init(tokenProvider: MicrosoftTokenProvider = .shared) {
        self.tokenProvider = tokenProvider
    }

    public func authorize(
        cloud: MicrosoftCloudEnvironment = .global,
        capabilities: Set<MicrosoftIntegrationCapability>
    ) async throws -> MicrosoftAccount {
        guard cloud.isSupported else {
            throw MicrosoftAuthError.unsupportedCloud
        }
        guard !capabilities.isEmpty else {
            throw MicrosoftAuthError.missingRequiredScope
        }
        return try await tokenProvider.authorize(capabilities: capabilities)
    }

    public func isConnected() async -> Bool {
        await tokenProvider.isConnected()
    }

    public func hasAccess(to capability: MicrosoftIntegrationCapability) async -> Bool {
        await tokenProvider.hasScope(capability.delegatedScope)
    }

    public func account() async -> MicrosoftAccount? {
        guard let accountID = await tokenProvider.accountID() else { return nil }
        return MicrosoftAccount(id: accountID, cloud: .global)
    }

    public func disconnect() async throws {
        try await tokenProvider.disconnect()
    }

    /// Routes the registered `msauth.<bundle-id>://auth` callback back into MSAL.
    /// The App shell calls this from its UIApplicationDelegate URL handler.
    @discardableResult
    public static func handleRedirectURL(
        _ url: URL,
        sourceApplication: String? = nil
    ) -> Bool {
        #if os(iOS)
        MSALPublicClientApplication.handleMSALResponse(
            url,
            sourceApplication: sourceApplication
        )
        #else
        false
        #endif
    }
}

// MARK: - Testable MSAL boundary

struct MicrosoftMSALToken: Sendable, Equatable {
    let accessToken: String
    let accountID: String
    let grantedScopes: [String]
}

@MainActor
protocol MicrosoftMSALClientProtocol: AnyObject {
    func accountIdentifiers() throws -> [String]
    func acquireTokenInteractively(scopes: [String]) async throws -> MicrosoftMSALToken
    func acquireTokenSilently(
        accountID: String,
        scopes: [String],
        forceRefresh: Bool
    ) async throws -> MicrosoftMSALToken
    func removeAccount(identifier: String) throws
}

/// Thin wrapper around MSAL Objective-C APIs. It deliberately returns value types so no MSAL
/// account or result object crosses the main-actor boundary.
@MainActor
final class MicrosoftMSALClient: MicrosoftMSALClientProtocol {
    static let shared = MicrosoftMSALClient()

    private static let redirectURI = "msauth.com.kirole.app://auth"
    private var cachedApplication: MSALPublicClientApplication?
    private var cachedClientID: String?

    func accountIdentifiers() throws -> [String] {
        try application().allAccounts().compactMap(\.identifier).sorted()
    }

    func acquireTokenInteractively(scopes: [String]) async throws -> MicrosoftMSALToken {
        let webParameters = MSALWebviewParameters(
            authPresentationViewController: try presentationViewController()
        )
        webParameters.prefersEphemeralWebBrowserSession = false
        let parameters = MSALInteractiveTokenParameters(
            scopes: scopes,
            webviewParameters: webParameters
        )
        parameters.promptType = .selectAccount

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try application().acquireToken(with: parameters) { result, error in
                    Self.resume(continuation, result: result, error: error)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func acquireTokenSilently(
        accountID: String,
        scopes: [String],
        forceRefresh: Bool
    ) async throws -> MicrosoftMSALToken {
        let application = try application()
        let account = try application.account(forIdentifier: accountID)
        let parameters = MSALSilentTokenParameters(scopes: scopes, account: account)
        parameters.forceRefresh = forceRefresh

        return try await withCheckedThrowingContinuation { continuation in
            application.acquireTokenSilent(with: parameters) { result, error in
                Self.resume(continuation, result: result, error: error)
            }
        }
    }

    func removeAccount(identifier: String) throws {
        let application = try application()
        let account = try application.account(forIdentifier: identifier)
        try application.remove(account)
    }

    private func application() throws -> MSALPublicClientApplication {
        guard let clientID = AppSecrets.microsoftClientId else {
            throw MicrosoftAuthError.missingCredentials
        }
        if cachedClientID == clientID, let cachedApplication {
            return cachedApplication
        }
        let configuration = MSALPublicClientApplicationConfig(
            clientId: clientID,
            redirectUri: Self.redirectURI,
            authority: nil
        )
        let application = try MSALPublicClientApplication(configuration: configuration)
        cachedClientID = clientID
        cachedApplication = application
        return application
    }

    private nonisolated static func resume(
        _ continuation: CheckedContinuation<MicrosoftMSALToken, Error>,
        result: MSALResult?,
        error: Error?
    ) {
        if let error {
            let nsError = error as NSError
            if nsError.domain == MSALErrorDomain, nsError.code == -50005 {
                continuation.resume(throwing: CancellationError())
            } else {
                continuation.resume(throwing: error)
            }
            return
        }
        guard let result,
              let accountID = result.account.identifier,
              !accountID.isEmpty,
              !result.accessToken.isEmpty else {
            continuation.resume(throwing: MicrosoftAuthError.invalidTokenResponse)
            return
        }
        continuation.resume(returning: MicrosoftMSALToken(
            accessToken: result.accessToken,
            accountID: accountID,
            grantedScopes: result.scopes
        ))
    }

    #if canImport(UIKit)
    private func presentationViewController() throws -> UIViewController {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        guard let root else { throw MicrosoftAuthError.missingPresentationContext }
        return Self.topViewController(from: root)
    }

    private static func topViewController(from root: UIViewController) -> UIViewController {
        if let presented = root.presentedViewController {
            return topViewController(from: presented)
        }
        if let navigation = root as? UINavigationController,
           let visible = navigation.visibleViewController {
            return topViewController(from: visible)
        }
        if let tabs = root as? UITabBarController,
           let selected = tabs.selectedViewController {
            return topViewController(from: selected)
        }
        return root
    }
    #elseif canImport(AppKit)
    private func presentationViewController() throws -> NSViewController {
        guard let controller = NSApplication.shared.keyWindow?.contentViewController
            ?? NSApplication.shared.mainWindow?.contentViewController else {
            throw MicrosoftAuthError.missingPresentationContext
        }
        return controller
    }
    #endif
}

// MARK: - Account metadata

struct MicrosoftAccountMetadata: Codable, Sendable, Equatable {
    let accountID: String
    let grantedScopes: [String]
}

actor MicrosoftAccountMetadataStore {
    static let shared = MicrosoftAccountMetadataStore()

    private let keychain: KeychainService

    init(service: String? = nil) {
        keychain = service.map(KeychainService.init(service:)) ?? .shared
    }

    init(keychain: KeychainService) {
        self.keychain = keychain
    }

    func load() -> MicrosoftAccountMetadata? {
        do {
            guard let data = try keychain.getMicrosoftAccountMetadata() else { return nil }
            return try JSONDecoder().decode(MicrosoftAccountMetadata.self, from: data)
        } catch {
            ErrorReporter.log(
                .persistence(
                    operation: "read",
                    target: "microsoft_account_metadata",
                    underlying: error.localizedDescription
                ),
                context: "MicrosoftAccountMetadataStore.load"
            )
            return nil
        }
    }

    func save(_ metadata: MicrosoftAccountMetadata) throws {
        let normalized = MicrosoftAccountMetadata(
            accountID: metadata.accountID,
            grantedScopes: metadata.grantedScopes.sorted()
        )
        try keychain.saveMicrosoftAccountMetadata(JSONEncoder().encode(normalized))
    }

    func clear() throws {
        try keychain.clearMicrosoftAccountMetadata()
    }
}

// MARK: - Token provider

protocol MicrosoftTokenProviding: Sendable {
    func accessToken() async throws -> String
    func forceRefresh() async throws -> String
    func accountID() async -> String?
}

@MainActor
final class MicrosoftTokenProvider {
    static let shared = MicrosoftTokenProvider()

    private let client: any MicrosoftMSALClientProtocol
    private let metadataStore: MicrosoftAccountMetadataStore

    init(
        client: any MicrosoftMSALClientProtocol = MicrosoftMSALClient.shared,
        metadataStore: MicrosoftAccountMetadataStore = .shared
    ) {
        self.client = client
        self.metadataStore = metadataStore
    }

    func authorize(
        capabilities: Set<MicrosoftIntegrationCapability>
    ) async throws -> MicrosoftAccount {
        let existing = try await resolvedMetadata()
        let requested = Set(existing?.grantedScopes ?? [])
            .union(capabilities.map(\.delegatedScope))
        let token = try await client.acquireTokenInteractively(scopes: requested.sorted())
        let granted = Self.minimalGrantedScopes(
            returned: token.grantedScopes,
            requested: requested
        )
        let scopes = existing?.accountID == token.accountID
            ? Set(existing?.grantedScopes ?? []).union(granted).sorted()
            : granted.sorted()
        try await metadataStore.save(MicrosoftAccountMetadata(
            accountID: token.accountID,
            grantedScopes: scopes
        ))
        return MicrosoftAccount(id: token.accountID, cloud: .global)
    }

    func accessToken() async throws -> String {
        try await acquireToken(forceRefresh: false)
    }

    func forceRefresh() async throws -> String {
        try await acquireToken(forceRefresh: true)
    }

    func isConnected() async -> Bool {
        (try? await resolvedMetadata()) != nil
    }

    func accountID() async -> String? {
        (try? await resolvedMetadata())?.accountID
    }

    func hasScope(_ scope: String) async -> Bool {
        do {
            guard let metadata = try await resolvedMetadata() else { return false }
            if Self.contains(scope, in: metadata.grantedScopes) {
                return true
            }
            let token = try await client.acquireTokenSilently(
                accountID: metadata.accountID,
                scopes: [scope],
                forceRefresh: false
            )
            let granted = Self.minimalGrantedScopes(
                returned: token.grantedScopes,
                requested: [scope]
            )
            guard Self.contains(scope, in: Array(granted)) else { return false }
            try await metadataStore.save(MicrosoftAccountMetadata(
                accountID: metadata.accountID,
                grantedScopes: Set(metadata.grantedScopes).union(granted).sorted()
            ))
            return true
        } catch {
            return false
        }
    }

    func disconnect() async throws {
        // Microsoft integrations share one MSAL public-client cache. Treat disconnect as a
        // client-wide privacy boundary: enumerate first, remove every cached account, then prove
        // the cache is empty. Any read/removal failure leaves metadata intact so the user can
        // retry instead of the app falsely claiming success.
        var accountIDs = try client.accountIdentifiers()
        if let selectedID = await metadataStore.load()?.accountID,
           let selectedIndex = accountIDs.firstIndex(of: selectedID),
           selectedIndex != accountIDs.startIndex {
            accountIDs.remove(at: selectedIndex)
            accountIDs.insert(selectedID, at: accountIDs.startIndex)
        }

        for accountID in accountIDs {
            try client.removeAccount(identifier: accountID)
        }
        let remainingAccountIDs = try client.accountIdentifiers()
        guard remainingAccountIDs.isEmpty else {
            throw MicrosoftAuthError.credentialDeletionFailed
        }
        try await metadataStore.clear()
    }

    private func acquireToken(forceRefresh: Bool) async throws -> String {
        guard let metadata = try await resolvedMetadata() else {
            throw MicrosoftAuthError.notAuthenticated
        }
        guard !metadata.grantedScopes.isEmpty else {
            throw MicrosoftAuthError.missingRequiredScope
        }
        let token = try await client.acquireTokenSilently(
            accountID: metadata.accountID,
            scopes: metadata.grantedScopes,
            forceRefresh: forceRefresh
        )
        guard token.accountID == metadata.accountID else {
            try await metadataStore.clear()
            throw MicrosoftAuthError.accountChanged
        }
        return token.accessToken
    }

    private func resolvedMetadata() async throws -> MicrosoftAccountMetadata? {
        let identifiers: [String]
        do {
            identifiers = try client.accountIdentifiers()
        } catch {
            return nil
        }
        if let stored = await metadataStore.load(), identifiers.contains(stored.accountID) {
            return stored
        }
        guard identifiers.count == 1, let identifier = identifiers.first else {
            try await metadataStore.clear()
            return nil
        }
        let recovered = MicrosoftAccountMetadata(accountID: identifier, grantedScopes: [])
        try await metadataStore.save(recovered)
        return recovered
    }

    private nonisolated static func minimalGrantedScopes(
        returned: [String],
        requested: Set<String>
    ) -> Set<String> {
        Set(requested.filter { requestedScope in
            contains(requestedScope, in: returned)
        })
    }

    private nonisolated static func contains(_ scope: String, in scopes: [String]) -> Bool {
        scopes.contains { $0.caseInsensitiveCompare(scope) == .orderedSame }
    }
}

struct MicrosoftTokenProviderBridge: MicrosoftTokenProviding {
    func accessToken() async throws -> String {
        try await MicrosoftTokenProvider.shared.accessToken()
    }

    func forceRefresh() async throws -> String {
        try await MicrosoftTokenProvider.shared.forceRefresh()
    }

    func accountID() async -> String? {
        await MicrosoftTokenProvider.shared.accountID()
    }
}

// MARK: - Error

public enum MicrosoftAuthError: LocalizedError, Sendable, Equatable {
    case missingCredentials
    case secureConfigurationRequired
    case missingRequiredScope
    case unsupportedCloud
    case missingPresentationContext
    case invalidTokenResponse
    case notAuthenticated
    case accountChanged
    case credentialDeletionFailed
    case sdkFailure(String)

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Microsoft OAuth client ID is not configured"
        case .secureConfigurationRequired:
            return "Microsoft connection is unavailable until OAuth setup is verified"
        case .missingRequiredScope:
            return "Choose at least one Microsoft integration to connect"
        case .unsupportedCloud:
            return "Microsoft 21Vianet is not supported in this version"
        case .missingPresentationContext:
            return "Microsoft sign-in needs an active app window"
        case .invalidTokenResponse:
            return "Microsoft sign-in returned an invalid token response"
        case .notAuthenticated:
            return "Microsoft account is not connected"
        case .accountChanged:
            return "Microsoft account changed during token refresh"
        case .credentialDeletionFailed:
            return "Microsoft credentials could not be removed"
        case .sdkFailure(let detail):
            return "Microsoft authentication failed: \(detail)"
        }
    }
}
