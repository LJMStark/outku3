import Foundation
import AuthenticationServices
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Notion Auth Service

/// Handles Notion OAuth 2.0 flow using ASWebAuthenticationSession
@MainActor
public final class NotionAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
    public static let shared = NotionAuthService()

    private let keychainService = KeychainService.shared
    private var currentSession: ASWebAuthenticationSession?

    private override init() {
        super.init()
    }

    // MARK: - OAuth Flow

    /// Initiates Notion OAuth authorization flow
    /// Returns the access token on success
    public func authorize() async throws -> String {
        guard let clientId = AppSecrets.notionClientId,
              let clientSecret = AppSecrets.notionClientSecret else {
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
            URLQueryItem(name: "state", value: state)
        ]
        guard let url = components.url else {
            throw NotionAuthError.invalidURL
        }

        let callbackURL = try await performWebAuth(url: url, callbackScheme: "kirole")
        try validateState(expected: state, callbackURL: callbackURL)

        guard let code = extractCode(from: callbackURL) else {
            throw NotionAuthError.noAuthorizationCode
        }

        let tokenResponse = try await exchangeCode(
            code: code,
            clientId: clientId,
            clientSecret: clientSecret,
            redirectURI: redirectURI
        )

        try keychainService.saveNotionAccessToken(tokenResponse.accessToken)
        if let workspaceId = tokenResponse.workspaceId {
            try keychainService.saveNotionWorkspaceId(workspaceId)
        }

        return tokenResponse.accessToken
    }

    // MARK: - Token Exchange

    private func exchangeCode(
        code: String,
        clientId: String,
        clientSecret: String,
        redirectURI: String
    ) async throws -> NotionTokenResponse {
        guard let url = URL(string: "https://api.notion.com/v1/oauth/token") else {
            throw NotionAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Notion uses Basic Auth for token exchange
        let credentials = "\(clientId):\(clientSecret)"
        let base64Credentials = Data(credentials.utf8).base64EncodedString()
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")

        let body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

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

    public func disconnect() {
        keychainService.clearNotionTokens()
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

private struct NotionTokenResponse: Decodable {
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

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Notion OAuth credentials not configured. Fill NOTION_OAUTH_CLIENT_ID and NOTION_OAUTH_CLIENT_SECRET in Config/Secrets.xcconfig, then rebuild the app."
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
        }
    }
}
