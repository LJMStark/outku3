import AuthenticationServices
import CryptoKit
import Foundation
@preconcurrency import KeychainAccess
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct TodoistOAuthConfiguration: Sendable, Equatable {
    public let clientID: String
    public let redirectURI: URL
    public let scopes: [String]
    public let authorizationEndpoint: URL
    public let tokenEndpoint: URL

    public init(
        clientID: String,
        redirectURI: URL,
        scopes: [String] = ["data:read_write"],
        authorizationEndpoint: URL = URL(string: "https://app.todoist.com/oauth/authorize")!,
        tokenEndpoint: URL = URL(string: "https://api.todoist.com/oauth/access_token")!
    ) throws {
        guard let clientMetadataURL = URL(string: clientID),
              clientMetadataURL.scheme == "https",
              clientMetadataURL.host != nil,
              redirectURI.scheme == "https",
              redirectURI.host != nil,
              authorizationEndpoint.scheme == "https",
              tokenEndpoint.scheme == "https" else {
            throw TodoistAuthError.invalidConfiguration
        }
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.scopes = scopes
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
    }

    var callbackHostAndPath: (host: String, path: String)? {
        guard let host = redirectURI.host else { return nil }
        return (host, redirectURI.path)
    }
}

public enum TodoistPKCE {
    public static func makeVerifier() -> String {
        (UUID().uuidString + UUID().uuidString)
            .replacingOccurrences(of: "-", with: "")
    }

    public static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum TodoistOAuthRequestBuilder {
    static func authorizationURL(
        configuration: TodoistOAuthConfiguration,
        state: String,
        codeChallenge: String
    ) throws -> URL {
        guard var components = URLComponents(
            url: configuration.authorizationEndpoint,
            resolvingAgainstBaseURL: false
        ) else {
            throw TodoistAuthError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "scope", value: configuration.scopes.joined(separator: ",")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        guard let url = components.url else { throw TodoistAuthError.invalidURL }
        return url
    }

    static func tokenExchangeRequest(
        configuration: TodoistOAuthConfiguration,
        code: String,
        verifier: String
    ) throws -> URLRequest {
        formRequest(
            endpoint: configuration.tokenEndpoint,
            fields: [
                ("client_id", configuration.clientID),
                ("grant_type", "authorization_code"),
                ("code", code),
                ("redirect_uri", configuration.redirectURI.absoluteString),
                ("code_verifier", verifier),
            ]
        )
    }

    static func refreshRequest(
        configuration: TodoistOAuthConfiguration,
        refreshToken: String
    ) throws -> URLRequest {
        formRequest(
            endpoint: configuration.tokenEndpoint,
            fields: [
                ("client_id", configuration.clientID),
                ("grant_type", "refresh_token"),
                ("refresh_token", refreshToken),
            ]
        )
    }

    private static func formRequest(endpoint: URL, fields: [(String, String)]) -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = TodoistAPI.formEncoded(fields)
        return request
    }
}

public struct TodoistTokenSet: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date?
    public let scope: String?

    public init(accessToken: String, refreshToken: String?, expiresAt: Date?, scope: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scope = scope
    }

    public func isExpiring(within interval: TimeInterval = 300, now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return now.addingTimeInterval(interval) >= expiresAt
    }
}

public protocol TodoistTokenStoring: Sendable {
    func load() async throws -> TodoistTokenSet?
    func save(_ tokens: TodoistTokenSet) async throws
    func clear() async throws
}

public actor TodoistKeychainTokenStore: TodoistTokenStoring {
    private let keychain: Keychain
    private let key: String

    public init(service: String = "com.kirole.app", key: String = "todoist_token_set") {
        keychain = Keychain(service: service).accessibility(.afterFirstUnlockThisDeviceOnly)
        self.key = key
    }

    public func load() throws -> TodoistTokenSet? {
        guard let data = try keychain.getData(key) else { return nil }
        return try JSONDecoder().decode(TodoistTokenSet.self, from: data)
    }

    public func save(_ tokens: TodoistTokenSet) throws {
        try keychain.set(JSONEncoder().encode(tokens), key: key)
    }

    public func clear() throws {
        try keychain.remove(key)
    }
}

struct TodoistTokenResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: TimeInterval?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
    }
}

public actor TodoistCredentialManager {
    typealias TokenResponseLoader = @Sendable (URLRequest) async throws -> TodoistTokenResponse

    private let configuration: TodoistOAuthConfiguration
    private let store: any TodoistTokenStoring
    private let session: URLSession
    private let tokenResponseLoader: TokenResponseLoader?
    nonisolated let credentialGate: OAuthCredentialOperationGate

    public init(
        configuration: TodoistOAuthConfiguration,
        store: any TodoistTokenStoring = TodoistKeychainTokenStore(),
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.store = store
        self.session = session
        credentialGate = OAuthCredentialOperationGate()
        tokenResponseLoader = nil
    }

    init(
        configuration: TodoistOAuthConfiguration,
        store: any TodoistTokenStoring = TodoistKeychainTokenStore(),
        session: URLSession = .shared,
        credentialGate: OAuthCredentialOperationGate,
        tokenResponseLoader: TokenResponseLoader? = nil
    ) {
        self.configuration = configuration
        self.store = store
        self.session = session
        self.credentialGate = credentialGate
        self.tokenResponseLoader = tokenResponseLoader
    }

    public func exchangeAuthorizationCode(_ code: String, verifier: String) async throws -> TodoistTokenSet {
        let operation = try beginCredentialOperation()
        defer { endCredentialOperation(operation) }

        let request = try TodoistOAuthRequestBuilder.tokenExchangeRequest(
            configuration: configuration,
            code: code,
            verifier: verifier
        )
        let response = try await tokenResponse(for: request)
        try validateCredentialOperation(operation)
        let tokens = Self.tokenSet(response, previousRefreshToken: nil)
        try await store.save(tokens)
        try validateCredentialOperation(operation)
        return tokens
    }

    public func accessToken(forceRefresh: Bool = false, now: Date = Date()) async throws -> String {
        let operation = try beginCredentialOperation()
        defer { endCredentialOperation(operation) }

        guard let tokens = try await store.load() else { throw TodoistAuthError.notAuthenticated }
        try validateCredentialOperation(operation)
        guard forceRefresh || tokens.isExpiring(now: now) else {
            try validateCredentialOperation(operation)
            return tokens.accessToken
        }
        guard let refreshToken = tokens.refreshToken else {
            if tokens.expiresAt == nil {
                try validateCredentialOperation(operation)
                return tokens.accessToken
            }
            throw TodoistAuthError.reauthorizationRequired
        }

        let request = try TodoistOAuthRequestBuilder.refreshRequest(
            configuration: configuration,
            refreshToken: refreshToken
        )
        let response = try await tokenResponse(for: request)
        try validateCredentialOperation(operation)
        // Todoist rotates refresh tokens. A grace-window replay can omit the replacement,
        // so keep the already persisted value instead of accidentally deleting it.
        let refreshed = Self.tokenSet(response, previousRefreshToken: refreshToken)
        try await store.save(refreshed)
        try validateCredentialOperation(operation)
        return refreshed.accessToken
    }

    public func isConnected() async -> Bool {
        (try? await store.load()) != nil
    }

    func clearCredentials(after cleanup: OAuthCredentialCleanupTicket) async throws {
        guard credentialGate.accepts(cleanup) else {
            throw TodoistAuthError.operationInvalidated
        }
        try await credentialGate.waitForInvalidatedOperations(before: cleanup)
        guard credentialGate.accepts(cleanup) else {
            throw TodoistAuthError.operationInvalidated
        }
        try await store.clear()
        guard try await store.load() == nil else {
            throw TodoistAuthError.credentialDeletionFailed
        }
    }

    private func tokenResponse(for request: URLRequest) async throws -> TodoistTokenResponse {
        if let tokenResponseLoader {
            return try await tokenResponseLoader(request)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TodoistAuthError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw TodoistAuthError.tokenExchangeFailed(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(TodoistTokenResponse.self, from: data)
        } catch {
            throw TodoistAuthError.invalidResponse
        }
    }

    private static func tokenSet(
        _ response: TodoistTokenResponse,
        previousRefreshToken: String?
    ) -> TodoistTokenSet {
        TodoistTokenSet(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? previousRefreshToken,
            expiresAt: response.expiresIn.map { Date().addingTimeInterval($0) },
            scope: response.scope
        )
    }

    private func beginCredentialOperation() throws -> OAuthCredentialOperationTicket {
        guard let operation = credentialGate.beginOperation() else {
            throw TodoistAuthError.operationInvalidated
        }
        return operation
    }

    private func validateCredentialOperation(_ operation: OAuthCredentialOperationTicket) throws {
        guard !Task.isCancelled, credentialGate.accepts(operation) else {
            if Task.isCancelled { throw CancellationError() }
            throw TodoistAuthError.operationInvalidated
        }
    }

    private func endCredentialOperation(_ operation: OAuthCredentialOperationTicket) {
        credentialGate.endOperation(operation)
    }
}

@MainActor
public final class TodoistAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
    typealias WebAuthorization = @MainActor (URL) async throws -> URL

    private let configuration: TodoistOAuthConfiguration
    private let credentialManager: TodoistCredentialManager
    private let webAuthorization: WebAuthorization?
    let credentialGate: OAuthCredentialOperationGate
    private var currentSession: ASWebAuthenticationSession?

    public init(
        configuration: TodoistOAuthConfiguration,
        credentialManager: TodoistCredentialManager? = nil
    ) {
        self.configuration = configuration
        let resolvedGate = credentialManager?.credentialGate ?? OAuthCredentialOperationGate()
        self.credentialGate = resolvedGate
        self.credentialManager = credentialManager ?? TodoistCredentialManager(
            configuration: configuration,
            store: TodoistKeychainTokenStore(),
            credentialGate: resolvedGate
        )
        webAuthorization = nil
        super.init()
    }

    init(
        configuration: TodoistOAuthConfiguration,
        credentialManager: TodoistCredentialManager? = nil,
        credentialGate: OAuthCredentialOperationGate,
        webAuthorization: WebAuthorization? = nil
    ) {
        self.configuration = configuration
        let resolvedGate = credentialManager?.credentialGate ?? credentialGate
        self.credentialGate = resolvedGate
        self.credentialManager = credentialManager ?? TodoistCredentialManager(
            configuration: configuration,
            store: TodoistKeychainTokenStore(),
            credentialGate: resolvedGate
        )
        self.webAuthorization = webAuthorization
        super.init()
    }

    public func authorize() async throws -> TodoistTokenSet {
        let operation = try beginCredentialOperation()
        defer { endCredentialOperation(operation) }

        let state = UUID().uuidString
        let verifier = TodoistPKCE.makeVerifier()
        let url = try TodoistOAuthRequestBuilder.authorizationURL(
            configuration: configuration,
            state: state,
            codeChallenge: TodoistPKCE.challenge(for: verifier)
        )
        let callback: URL
        if let webAuthorization {
            callback = try await webAuthorization(url)
        } else {
            callback = try await performWebAuth(url: url)
        }
        try validateCredentialOperation(operation)
        guard OAuthCallbackValidator.matches(
            callback,
            registeredRedirectURI: configuration.redirectURI
        ) else {
            throw TodoistAuthError.invalidCallback
        }
        let components = URLComponents(url: callback, resolvingAgainstBaseURL: false)
        if let error = components?.queryItems?.first(where: { $0.name == "error" })?.value {
            throw TodoistAuthError.providerRejected(error)
        }
        guard components?.queryItems?.first(where: { $0.name == "state" })?.value == state else {
            throw TodoistAuthError.invalidState
        }
        guard let code = components?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw TodoistAuthError.missingAuthorizationCode
        }
        let tokens = try await credentialManager.exchangeAuthorizationCode(code, verifier: verifier)
        try validateCredentialOperation(operation)
        return tokens
    }

    func beginCredentialOperation() throws -> OAuthCredentialOperationTicket {
        guard let operation = credentialGate.beginOperation() else {
            throw TodoistAuthError.operationInvalidated
        }
        return operation
    }

    func validateCredentialOperation(_ operation: OAuthCredentialOperationTicket) throws {
        guard !Task.isCancelled, credentialGate.accepts(operation) else {
            if Task.isCancelled { throw CancellationError() }
            throw TodoistAuthError.operationInvalidated
        }
    }

    func endCredentialOperation(_ operation: OAuthCredentialOperationTicket) {
        credentialGate.endOperation(operation)
    }

    func invalidateAndBlockCredentialOperations() -> OAuthCredentialCleanupTicket {
        let cleanup = credentialGate.invalidateAndBlock()
        currentSession?.cancel()
        currentSession = nil
        return cleanup
    }

    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? UIWindow()
        #elseif canImport(AppKit)
        NSApplication.shared.windows.first ?? ASPresentationAnchor()
        #else
        ASPresentationAnchor()
        #endif
    }

    private func performWebAuth(url: URL) async throws -> URL {
        guard #available(iOS 17.4, macOS 14.4, *),
              let callback = configuration.callbackHostAndPath else {
            throw TodoistAuthError.unsupportedSystemVersion
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: url,
                callback: .https(host: callback.host, path: callback.path)
            ) { callbackURL, error in
                Task { @MainActor in
                    self.currentSession = nil
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let callbackURL {
                        continuation.resume(returning: callbackURL)
                    } else {
                        continuation.resume(throwing: TodoistAuthError.missingCallback)
                    }
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            currentSession = session
            guard session.start() else {
                currentSession = nil
                continuation.resume(throwing: TodoistAuthError.invalidURL)
                return
            }
        }
    }
}

public enum TodoistAuthError: LocalizedError, Sendable, Equatable {
    case invalidConfiguration
    case unsupportedSystemVersion
    case invalidURL
    case invalidCallback
    case invalidState
    case missingAuthorizationCode
    case missingCallback
    case notAuthenticated
    case credentialDeletionFailed
    case reauthorizationRequired
    case invalidResponse
    case tokenExchangeFailed(Int)
    case providerRejected(String)
    case operationInvalidated

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Todoist OAuth configuration is incomplete"
        case .unsupportedSystemVersion: "Todoist sign-in requires iOS 17.4 or later"
        case .invalidURL: "Todoist OAuth URL is invalid"
        case .invalidCallback: "Todoist returned an unexpected OAuth callback"
        case .invalidState: "Todoist OAuth state validation failed"
        case .missingAuthorizationCode: "Todoist did not return an authorization code"
        case .missingCallback: "Todoist did not return an OAuth callback"
        case .notAuthenticated: "Todoist is not connected"
        case .credentialDeletionFailed: "Todoist credentials could not be removed"
        case .reauthorizationRequired: "Todoist authorization expired; reconnect the account"
        case .invalidResponse: "Todoist returned an invalid token response"
        case .tokenExchangeFailed(let status): "Todoist token exchange failed (HTTP \(status))"
        case .providerRejected(let detail): "Todoist rejected authorization: \(detail)"
        case .operationInvalidated: "Todoist authorization was cancelled by disconnect or sign out"
        }
    }
}
