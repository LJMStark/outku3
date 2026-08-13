import Foundation
import AuthenticationServices
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Taskade Auth Service

/// Handles Taskade OAuth 2.0 flow using ASWebAuthenticationSession.
/// Token exchange and refresh are proxied through a Supabase Edge Function
/// so that client_secret never ships in the binary.
@MainActor
public final class TaskadeAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
    public static let shared = TaskadeAuthService()

    typealias WebAuthorization = @MainActor (URL, String) async throws -> URL
    typealias TokenRequest = @MainActor ([String: String]) async throws -> TaskadeTokenResponse

    private let keychainService: KeychainService
    private let configuredClientID: String?
    private let webAuthorization: WebAuthorization?
    private let tokenRequest: TokenRequest?
    let credentialGate: OAuthCredentialOperationGate
    private var currentSession: ASWebAuthenticationSession?

    private override convenience init() {
        self.init(keychainService: .shared)
    }

    init(
        keychainService: KeychainService,
        clientID: String? = nil,
        credentialGate: OAuthCredentialOperationGate = OAuthCredentialOperationGate(),
        webAuthorization: WebAuthorization? = nil,
        tokenRequest: TokenRequest? = nil
    ) {
        self.keychainService = keychainService
        configuredClientID = clientID
        self.credentialGate = credentialGate
        self.webAuthorization = webAuthorization
        self.tokenRequest = tokenRequest
        super.init()
    }

    // MARK: - OAuth Flow

    public func authorize() async throws -> String {
        let operation = try beginCredentialOperation()
        defer { endCredentialOperation(operation) }

        guard let clientId = configuredClientID ?? AppSecrets.taskadeClientId else {
            throw TaskadeAuthError.missingCredentials
        }

        let redirectURI = "kirole://taskade-callback"
        let state = UUID().uuidString
        guard var components = URLComponents(string: "https://www.taskade.com/oauth2/authorize") else {
            throw TaskadeAuthError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "read,write"),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = components.url else {
            throw TaskadeAuthError.invalidURL
        }

        let callbackURL: URL
        if let webAuthorization {
            callbackURL = try await webAuthorization(url, "kirole")
        } else {
            callbackURL = try await performWebAuth(url: url, callbackScheme: "kirole")
        }
        try validateCredentialOperation(operation)
        try validateState(expected: state, callbackURL: callbackURL)

        guard let code = extractCode(from: callbackURL) else {
            throw TaskadeAuthError.noAuthorizationCode
        }

        let exchangeBody = [
            "action": "exchange",
            "code": code,
            "redirect_uri": redirectURI,
        ]
        let tokenResponse = try await requestToken(body: exchangeBody)

        try validateCredentialOperation(operation)
        try keychainService.saveTaskadeTokens(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken
        )

        try validateCredentialOperation(operation)
        return tokenResponse.accessToken
    }

    // MARK: - Token Refresh

    public func refreshTokenIfNeeded() async throws -> String {
        let operation = try beginCredentialOperation()
        defer { endCredentialOperation(operation) }

        if let accessToken = keychainService.getTaskadeAccessToken() {
            try validateCredentialOperation(operation)
            return accessToken
        }
        guard let refreshToken = keychainService.getTaskadeRefreshToken() else {
            throw TaskadeAuthError.tokenExpired
        }
        return try await refreshAccessToken(refreshToken: refreshToken, operation: operation)
    }

    public func forceRefreshAccessToken() async throws -> String {
        let operation = try beginCredentialOperation()
        defer { endCredentialOperation(operation) }

        guard let refreshToken = keychainService.getTaskadeRefreshToken() else {
            throw TaskadeAuthError.tokenExpired
        }
        return try await refreshAccessToken(refreshToken: refreshToken, operation: operation)
    }

    private func refreshAccessToken(
        refreshToken: String,
        operation: OAuthCredentialOperationTicket
    ) async throws -> String {
        let tokenResponse = try await requestToken(body: [
            "action": "refresh",
            "refresh_token": refreshToken,
        ])
        try validateCredentialOperation(operation)
        try keychainService.saveTaskadeTokens(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken
        )
        try validateCredentialOperation(operation)
        return tokenResponse.accessToken
    }

    // MARK: - Edge Function

    private func callEdgeFunction(body: [String: String]) async throws -> TaskadeTokenResponse {
        guard let supabase = AppSecrets.supabaseConfig,
              let url = URL(string: "\(supabase.url)/functions/v1/taskade-oauth") else {
            throw TaskadeAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(supabase.anonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw TaskadeAuthError.tokenExchangeFailed
        }

        return try JSONDecoder().decode(TaskadeTokenResponse.self, from: data)
    }

    private func requestToken(body: [String: String]) async throws -> TaskadeTokenResponse {
        if let tokenRequest {
            return try await tokenRequest(body)
        }
        return try await callEdgeFunction(body: body)
    }

    // MARK: - Token Access

    public func getAccessToken() async throws -> String {
        try await refreshTokenIfNeeded()
    }

    public var isConnected: Bool {
        keychainService.getTaskadeAccessToken() != nil
    }

    @discardableResult
    public func disconnect() -> Bool {
        let cleanup = invalidateAndBlockCredentialOperations()
        return disconnect(after: cleanup, completeCleanup: true)
    }

    @discardableResult
    func disconnect(
        after cleanup: OAuthCredentialCleanupTicket,
        completeCleanup: Bool
    ) -> Bool {
        guard credentialGate.accepts(cleanup) else { return false }
        do {
            try keychainService.clearTaskadeTokens()
        } catch {
            credentialGate.fail(cleanup)
            return false
        }
        guard credentialsAreCleared else {
            credentialGate.fail(cleanup)
            return false
        }
        if completeCleanup {
            credentialGate.complete(cleanup)
        }
        return true
    }

    func beginCredentialOperation() throws -> OAuthCredentialOperationTicket {
        guard let operation = credentialGate.beginOperation() else {
            throw TaskadeAuthError.operationInvalidated
        }
        return operation
    }

    func validateCredentialOperation(_ operation: OAuthCredentialOperationTicket) throws {
        guard !Task.isCancelled, credentialGate.accepts(operation) else {
            if Task.isCancelled { throw CancellationError() }
            throw TaskadeAuthError.operationInvalidated
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

    var credentialsAreCleared: Bool {
        keychainService.getTaskadeAccessToken() == nil
            && keychainService.getTaskadeRefreshToken() == nil
    }

    // MARK: - Helpers

    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? UIWindow()
        #elseif canImport(AppKit)
        NSApplication.shared.windows.first ?? ASPresentationAnchor()
        #else
        ASPresentationAnchor()
        #endif
    }

    private func performWebAuth(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                Task { @MainActor in
                    self.currentSession = nil
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let callbackURL else {
                        continuation.resume(throwing: TaskadeAuthError.noCallbackURL)
                        return
                    }
                    continuation.resume(returning: callbackURL)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.currentSession = session
            if !session.start() {
                self.currentSession = nil
                continuation.resume(throwing: TaskadeAuthError.invalidURL)
            }
        }
    }

    private func extractCode(from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "code" })?
            .value
    }

    private func validateState(expected: String, callbackURL: URL) throws {
        let returnedState = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "state" })?
            .value
        guard returnedState == expected else {
            throw TaskadeAuthError.invalidState
        }
    }
}

// MARK: - Token Response

struct TaskadeTokenResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

// MARK: - Taskade Auth Error

public enum TaskadeAuthError: LocalizedError, Sendable {
    case missingCredentials
    case invalidURL
    case noAuthorizationCode
    case tokenExchangeFailed
    case tokenExpired
    case tokenRefreshFailed
    case noCallbackURL
    case invalidState
    case operationInvalidated

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Taskade OAuth client ID not configured. Fill TASKADE_OAUTH_CLIENT_ID in Config/Secrets.xcconfig, then rebuild the app."
        case .invalidURL:
            return "Invalid Taskade OAuth URL"
        case .noAuthorizationCode:
            return "No authorization code received from Taskade"
        case .tokenExchangeFailed:
            return "Failed to exchange authorization code for Taskade token"
        case .tokenExpired:
            return "Taskade token expired, please reconnect"
        case .tokenRefreshFailed:
            return "Failed to refresh Taskade token"
        case .noCallbackURL:
            return "No callback URL received from Taskade"
        case .invalidState:
            return "Taskade OAuth state validation failed"
        case .operationInvalidated:
            return "Taskade authorization was cancelled by disconnect or sign out"
        }
    }
}
