import Foundation
import AuthenticationServices

// MARK: - Taskade Auth Service

/// Handles Taskade OAuth 2.0 flow using ASWebAuthenticationSession
@MainActor
public final class TaskadeAuthService {
    public static let shared = TaskadeAuthService()

    private let keychainService = KeychainService.shared

    private init() {}

    // MARK: - OAuth Flow

    /// Initiates Taskade OAuth authorization flow
    public func authorize() async throws -> String {
        guard let clientId = AppSecrets.taskadeClientId,
              let clientSecret = AppSecrets.taskadeClientSecret else {
            throw TaskadeAuthError.missingCredentials
        }

        let redirectURI = "kirole://taskade-callback"
        let authURL = "https://www.taskade.com/oauth/authorize?client_id=\(clientId)&response_type=code&redirect_uri=\(redirectURI)&scope=read,write"

        guard let url = URL(string: authURL) else {
            throw TaskadeAuthError.invalidURL
        }

        let callbackURL = try await performWebAuth(url: url, callbackScheme: "kirole")

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
        guard let url = URL(string: "https://www.taskade.com/oauth/token") else {
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

    private func refreshAccessToken(
        refreshToken: String,
        clientId: String,
        clientSecret: String
    ) async throws -> String {
        guard let url = URL(string: "https://www.taskade.com/oauth/token") else {
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

    private func performWebAuth(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
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
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    private func extractCode(from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "code" })?
            .value
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

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Taskade OAuth credentials not configured"
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
        }
    }
}
