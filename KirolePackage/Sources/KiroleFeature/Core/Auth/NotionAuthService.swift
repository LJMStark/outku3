import Foundation
import AuthenticationServices
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Notion Auth Service

/// Handles Notion OAuth 2.0 flow using ASWebAuthenticationSession.
/// Token exchange is proxied through a Supabase Edge Function so that
/// client_secret never ships in the binary.
@MainActor
public final class NotionAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
    public static let shared = NotionAuthService()

    typealias WebAuthorization = @MainActor (URL, String) async throws -> URL
    typealias TokenExchange = @MainActor (String, String) async throws -> NotionTokenResponse

    private let keychainService: KeychainService
    private let configuredClientID: String?
    private let webAuthorization: WebAuthorization?
    private let tokenExchange: TokenExchange?
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
        tokenExchange: TokenExchange? = nil
    ) {
        self.keychainService = keychainService
        configuredClientID = clientID
        self.credentialGate = credentialGate
        self.webAuthorization = webAuthorization
        self.tokenExchange = tokenExchange
        super.init()
    }

    // MARK: - OAuth Flow

    public func authorize() async throws -> String {
        let operation = try beginCredentialOperation()
        defer { endCredentialOperation(operation) }

        guard let clientId = configuredClientID ?? AppSecrets.notionClientId else {
            throw NotionAuthError.missingCredentials
        }

        let redirectURI = "kirole://notion-callback"
        let state = UUID().uuidString
        guard var components = URLComponents(string: "https://api.notion.com/v1/oauth/authorize") else {
            throw NotionAuthError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "owner", value: "user"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "state", value: state),
        ]
        guard let url = components.url else {
            throw NotionAuthError.invalidURL
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
            throw NotionAuthError.noAuthorizationCode
        }

        let tokenResponse: NotionTokenResponse
        if let tokenExchange {
            tokenResponse = try await tokenExchange(code, redirectURI)
        } else {
            tokenResponse = try await exchangeCodeViaEdgeFunction(code: code, redirectURI: redirectURI)
        }

        try validateCredentialOperation(operation)
        try keychainService.saveNotionAccessToken(tokenResponse.accessToken)
        if let workspaceId = tokenResponse.workspaceId {
            try validateCredentialOperation(operation)
            try keychainService.saveNotionWorkspaceId(workspaceId)
        }

        try validateCredentialOperation(operation)
        return tokenResponse.accessToken
    }

    // MARK: - Token Exchange (via Edge Function)

    private func exchangeCodeViaEdgeFunction(code: String, redirectURI: String) async throws -> NotionTokenResponse {
        guard let supabase = AppSecrets.supabaseConfig,
              let url = URL(string: "\(supabase.url)/functions/v1/notion-oauth") else {
            throw NotionAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(supabase.anonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "code": code,
            "redirect_uri": redirectURI,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NotionAuthError.tokenExchangeFailed
        }

        return try JSONDecoder().decode(NotionTokenResponse.self, from: data)
    }

    // MARK: - Token Access

    public func getAccessToken() -> String? {
        keychainService.getNotionAccessToken()
    }

    public var isConnected: Bool {
        keychainService.getNotionAccessToken() != nil
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
            try keychainService.clearNotionTokens()
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
            throw NotionAuthError.operationInvalidated
        }
        return operation
    }

    func validateCredentialOperation(_ operation: OAuthCredentialOperationTicket) throws {
        guard !Task.isCancelled, credentialGate.accepts(operation) else {
            if Task.isCancelled { throw CancellationError() }
            throw NotionAuthError.operationInvalidated
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
        keychainService.getNotionAccessToken() == nil
            && keychainService.getNotionWorkspaceId() == nil
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
                        continuation.resume(throwing: NotionAuthError.noCallbackURL)
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
                continuation.resume(throwing: NotionAuthError.invalidURL)
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
            throw NotionAuthError.invalidState
        }
    }
}

// MARK: - Token Response

struct NotionTokenResponse: Decodable, Sendable {
    let accessToken: String
    let workspaceId: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case workspaceId = "workspace_id"
    }
}

// MARK: - Notion Auth Error

public enum NotionAuthError: LocalizedError, Sendable {
    case missingCredentials
    case invalidURL
    case noAuthorizationCode
    case tokenExchangeFailed
    case noCallbackURL
    case invalidState
    case operationInvalidated

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Notion OAuth client ID not configured. Fill NOTION_OAUTH_CLIENT_ID in Config/Secrets.xcconfig, then rebuild the app."
        case .invalidURL:
            return "Invalid Notion OAuth URL"
        case .noAuthorizationCode:
            return "No authorization code received from Notion"
        case .tokenExchangeFailed:
            return "Failed to exchange authorization code for Notion token"
        case .noCallbackURL:
            return "No callback URL received from Notion"
        case .invalidState:
            return "Notion OAuth state validation failed"
        case .operationInvalidated:
            return "Notion authorization was cancelled by disconnect or sign out"
        }
    }
}
