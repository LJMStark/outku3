import Foundation
import AuthenticationServices
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Taskade Auth Service

/// Handles Taskade OAuth 2.0 flow using ASWebAuthenticationSession
@MainActor
public final class TaskadeAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
    public static let shared = TaskadeAuthService()

    private let keychainService = KeychainService.shared
    private var currentSession: ASWebAuthenticationSession?

    private override init() {
        super.init()
    }

    // MARK: - OAuth Flow

    /// Initiates Taskade OAuth authorization flow
    public func authorize() async throws -> String {
        guard let clientId = AppSecrets.taskadeClientId,
              let clientSecret = AppSecrets.taskadeClientSecret else {
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
            URLQueryItem(name: "state", value: state)
        ]
        guard let url = components.url else {
            throw TaskadeAuthError.invalidURL
        }

        let callbackURL = try await performWebAuth(url: url, callbackScheme: "kirole")
        try validateState(expected: state, callbackURL: callbackURL)

        guard let code = extractCode(from: callbackURL) else {
            throw TaskadeAuthError.noAuthorizationCode
        }

        let tokenResponse = try await exchangeCode(
            code: code,
            clientId: clientId,
            clientSecret: clientSecret,
            redirectURI: redirectURI
        )

        try keychainService.saveTaskadeTokens(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken
        )

        return tokenResponse.accessToken
    }

    // MARK: - Token Exchange

    private func exchangeCode(
        code: String,
        clientId: String,
        clientSecret: String,
        redirectURI: String
    ) async throws -> TaskadeTokenResponse {
        guard let url = URL(string: "https://www.taskade.com/oauth2/token") else {
            throw TaskadeAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "redirect_uri", value: redirectURI)
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw TaskadeAuthError.tokenExchangeFailed
        }

        return try JSONDecoder().decode(TaskadeTokenResponse.self, from: data)
    }

    // MARK: - Token Refresh

    public func refreshTokenIfNeeded() async throws -> String {
        if let accessToken = keychainService.getTaskadeAccessToken() {
            return accessToken
        }

        guard let refreshToken = keychainService.getTaskadeRefreshToken(),
              let clientId = AppSecrets.taskadeClientId,
              let clientSecret = AppSecrets.taskadeClientSecret else {
            throw TaskadeAuthError.tokenExpired
        }

        return try await refreshAccessToken(
            refreshToken: refreshToken,
            clientId: clientId,
            clientSecret: clientSecret
        )
    }

    public func forceRefreshAccessToken() async throws -> String {
        guard let refreshToken = keychainService.getTaskadeRefreshToken(),
              let clientId = AppSecrets.taskadeClientId,
              let clientSecret = AppSecrets.taskadeClientSecret else {
            throw TaskadeAuthError.tokenExpired
        }

        return try await refreshAccessToken(
            refreshToken: refreshToken,
            clientId: clientId,
            clientSecret: clientSecret
        )
    }

    private func refreshAccessToken(
        refreshToken: String,
        clientId: String,
        clientSecret: String
    ) async throws -> String {
        guard let url = URL(string: "https://www.taskade.com/oauth2/token") else {
            throw TaskadeAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "client_secret", value: clientSecret)
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw TaskadeAuthError.tokenRefreshFailed
        }

        let tokenResponse = try JSONDecoder().decode(TaskadeTokenResponse.self, from: data)

        try keychainService.saveTaskadeTokens(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken
        )

        return tokenResponse.accessToken
    }

    // MARK: - Token Access

    public func getAccessToken() async throws -> String {
        try await refreshTokenIfNeeded()
    }

    public var isConnected: Bool {
        keychainService.getTaskadeAccessToken() != nil
    }

    public func disconnect() {
        keychainService.clearTaskadeTokens()
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

private struct TaskadeTokenResponse: Decodable {
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

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Taskade OAuth credentials not configured. Fill TASKADE_OAUTH_CLIENT_ID and TASKADE_OAUTH_CLIENT_SECRET in Config/Secrets.xcconfig, then rebuild the app."
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
        }
    }
}
