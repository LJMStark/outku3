import Foundation
@preconcurrency import KeychainAccess

// MARK: - Keychain Service

/// 安全存储敏感数据（tokens、credentials）
public final class KeychainService: @unchecked Sendable {
    public static let shared = KeychainService()

    private let keychain: Keychain

    private enum Keys {
        static let googleAccessToken = "google_access_token"
        static let googleRefreshToken = "google_refresh_token"
        static let googleTokenExpiry = "google_token_expiry"
        static let googleGrantedScopes = "google_granted_scopes"
        static let appleUserIdentifier = "apple_user_identifier"
        static let supabaseAccessToken = "supabase_access_token"
        static let supabaseRefreshToken = "supabase_refresh_token"
        static let openAIAPIKey = "openai_api_key"
        static let notionAccessToken = "notion_access_token"
        static let notionWorkspaceId = "notion_workspace_id"
        static let taskadeAccessToken = "taskade_access_token"
        static let taskadeRefreshToken = "taskade_refresh_token"
    }

    private init() {
        // 使用 App Bundle ID 作为 Keychain service identifier
        self.keychain = Keychain(service: "com.kirole.app")
            .accessibility(.afterFirstUnlock)
    }

    // MARK: - Google Tokens

    public func saveGoogleTokens(
        accessToken: String,
        refreshToken: String?,
        expiresIn: TimeInterval
    ) throws {
        try keychain.set(accessToken, key: Keys.googleAccessToken)

        if let refreshToken = refreshToken {
            try keychain.set(refreshToken, key: Keys.googleRefreshToken)
        }

        let expiryDate = Date().addingTimeInterval(expiresIn)
        let expiryString = ISO8601DateFormatter().string(from: expiryDate)
        try keychain.set(expiryString, key: Keys.googleTokenExpiry)
    }

    public func getGoogleAccessToken() -> String? {
        do {
            return try keychain.get(Keys.googleAccessToken)
        } catch {
            ErrorReporter.log(
                .persistence(operation: "read", target: "google_access_token", underlying: error.localizedDescription),
                context: "KeychainService.getGoogleAccessToken"
            )
            return nil
        }
    }

    public func getGoogleRefreshToken() -> String? {
        do {
            return try keychain.get(Keys.googleRefreshToken)
        } catch {
            ErrorReporter.log(
                .persistence(operation: "read", target: "google_refresh_token", underlying: error.localizedDescription),
                context: "KeychainService.getGoogleRefreshToken"
            )
            return nil
        }
    }

    public func getGoogleTokenExpiry() -> Date? {
        do {
            guard let expiryString = try keychain.get(Keys.googleTokenExpiry) else {
                return nil
            }
            return ISO8601DateFormatter().date(from: expiryString)
        } catch {
            ErrorReporter.log(
                .persistence(operation: "read", target: "google_token_expiry", underlying: error.localizedDescription),
                context: "KeychainService.getGoogleTokenExpiry"
            )
            return nil
        }
    }

    public func isGoogleTokenExpired() -> Bool {
        guard let expiry = getGoogleTokenExpiry() else {
            return true
        }
        // 提前 5 分钟认为过期，以便有时间刷新
        return Date().addingTimeInterval(300) >= expiry
    }

    public func clearGoogleTokens() {
        do {
            try keychain.remove(Keys.googleAccessToken)
            try keychain.remove(Keys.googleRefreshToken)
            try keychain.remove(Keys.googleTokenExpiry)
            try keychain.remove(Keys.googleGrantedScopes)
        } catch {
            ErrorReporter.log(
                .persistence(operation: "delete", target: "google_tokens", underlying: error.localizedDescription),
                context: "KeychainService.clearGoogleTokens"
            )
        }
    }

    // MARK: - Google Scopes

    /// 保存 Google 授权的 scopes
    public func saveGoogleScopes(_ scopes: [String]) throws {
        let scopesString = scopes.joined(separator: ",")
        try keychain.set(scopesString, key: Keys.googleGrantedScopes)
    }

    /// 获取保存的 Google scopes
    public func getGoogleScopes() -> [String]? {
        do {
            guard let scopesString = try keychain.get(Keys.googleGrantedScopes),
                  !scopesString.isEmpty else {
                return nil
            }
            return scopesString.components(separatedBy: ",")
        } catch {
            ErrorReporter.log(
                .persistence(operation: "read", target: "google_scopes", underlying: error.localizedDescription),
                context: "KeychainService.getGoogleScopes"
            )
            return nil
        }
    }

    /// 清除 Google scopes
    public func clearGoogleScopes() {
        do {
            try keychain.remove(Keys.googleGrantedScopes)
        } catch {
            ErrorReporter.log(
                .persistence(operation: "delete", target: "google_scopes", underlying: error.localizedDescription),
                context: "KeychainService.clearGoogleScopes"
            )
        }
    }

    // MARK: - Apple Sign In

    public func saveAppleUserIdentifier(_ identifier: String) throws {
        try keychain.set(identifier, key: Keys.appleUserIdentifier)
    }

    public func getAppleUserIdentifier() -> String? {
        do {
            guard let storedIdentifier = try keychain.get(Keys.appleUserIdentifier) else {
                return nil
            }
            let identifier = storedIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !identifier.isEmpty else { return nil }
            return identifier
        } catch {
            ErrorReporter.log(
                .persistence(operation: "read", target: "apple_user_identifier", underlying: error.localizedDescription),
                context: "KeychainService.getAppleUserIdentifier"
            )
            return nil
        }
    }

    public func clearAppleUserIdentifier() {
        do {
            try keychain.remove(Keys.appleUserIdentifier)
        } catch {
            ErrorReporter.log(
                .persistence(operation: "delete", target: "apple_user_identifier", underlying: error.localizedDescription),
                context: "KeychainService.clearAppleUserIdentifier"
            )
        }
    }

    // MARK: - Supabase Tokens

    public func saveSupabaseTokens(accessToken: String, refreshToken: String) throws {
        try keychain.set(accessToken, key: Keys.supabaseAccessToken)
        try keychain.set(refreshToken, key: Keys.supabaseRefreshToken)
    }

    public func getSupabaseAccessToken() -> String? {
        do {
            return try keychain.get(Keys.supabaseAccessToken)
        } catch {
            ErrorReporter.log(
                .persistence(operation: "read", target: "supabase_access_token", underlying: error.localizedDescription),
                context: "KeychainService.getSupabaseAccessToken"
            )
            return nil
        }
    }

    public func getSupabaseRefreshToken() -> String? {
        do {
            return try keychain.get(Keys.supabaseRefreshToken)
        } catch {
            ErrorReporter.log(
                .persistence(operation: "read", target: "supabase_refresh_token", underlying: error.localizedDescription),
                context: "KeychainService.getSupabaseRefreshToken"
            )
            return nil
        }
    }

    public func clearSupabaseTokens() {
        do {
            try keychain.remove(Keys.supabaseAccessToken)
            try keychain.remove(Keys.supabaseRefreshToken)
        } catch {
            ErrorReporter.log(
                .persistence(operation: "delete", target: "supabase_tokens", underlying: error.localizedDescription),
                context: "KeychainService.clearSupabaseTokens"
            )
        }
    }

    // MARK: - OpenAI API Key

    public func saveOpenAIAPIKey(_ apiKey: String) throws {
        try keychain.set(apiKey, key: Keys.openAIAPIKey)
    }

    public func getOpenAIAPIKey() -> String? {
        do {
            return try keychain.get(Keys.openAIAPIKey)
        } catch {
            ErrorReporter.log(
                .persistence(operation: "read", target: "openai_api_key", underlying: error.localizedDescription),
                context: "KeychainService.getOpenAIAPIKey"
            )
            return nil
        }
    }

    public func clearOpenAIAPIKey() {
        do {
            try keychain.remove(Keys.openAIAPIKey)
        } catch {
            ErrorReporter.log(
                .persistence(operation: "delete", target: "openai_api_key", underlying: error.localizedDescription),
                context: "KeychainService.clearOpenAIAPIKey"
            )
        }
    }

    public func hasOpenAIAPIKey() -> Bool {
        getOpenAIAPIKey() != nil
    }

    // MARK: - Notion Tokens

    public func saveNotionAccessToken(_ token: String) throws {
        try keychain.set(token, key: Keys.notionAccessToken)
    }

    public func saveNotionWorkspaceId(_ id: String) throws {
        try keychain.set(id, key: Keys.notionWorkspaceId)
    }

    public func getNotionAccessToken() -> String? {
        do {
            return try keychain.get(Keys.notionAccessToken)
        } catch {
            ErrorReporter.log(
                .persistence(operation: "read", target: "notion_access_token", underlying: error.localizedDescription),
                context: "KeychainService.getNotionAccessToken"
            )
            return nil
        }
    }

    public func getNotionWorkspaceId() -> String? {
        do {
            return try keychain.get(Keys.notionWorkspaceId)
        } catch {
            return nil
        }
    }

    public func clearNotionTokens() {
        do {
            try keychain.remove(Keys.notionAccessToken)
            try keychain.remove(Keys.notionWorkspaceId)
        } catch {
            ErrorReporter.log(
                .persistence(operation: "delete", target: "notion_tokens", underlying: error.localizedDescription),
                context: "KeychainService.clearNotionTokens"
            )
        }
    }

    // MARK: - Taskade Tokens

    public func saveTaskadeTokens(accessToken: String, refreshToken: String?) throws {
        try keychain.set(accessToken, key: Keys.taskadeAccessToken)
        if let refreshToken {
            try keychain.set(refreshToken, key: Keys.taskadeRefreshToken)
        }
    }

    public func getTaskadeAccessToken() -> String? {
        do {
            return try keychain.get(Keys.taskadeAccessToken)
        } catch {
            ErrorReporter.log(
                .persistence(operation: "read", target: "taskade_access_token", underlying: error.localizedDescription),
                context: "KeychainService.getTaskadeAccessToken"
            )
            return nil
        }
    }

    public func getTaskadeRefreshToken() -> String? {
        do {
            return try keychain.get(Keys.taskadeRefreshToken)
        } catch {
            return nil
        }
    }

    public func clearTaskadeTokens() {
        do {
            try keychain.remove(Keys.taskadeAccessToken)
            try keychain.remove(Keys.taskadeRefreshToken)
        } catch {
            ErrorReporter.log(
                .persistence(operation: "delete", target: "taskade_tokens", underlying: error.localizedDescription),
                context: "KeychainService.clearTaskadeTokens"
            )
        }
    }

    // MARK: - Clear All

    public func clearAll() {
        clearGoogleTokens()
        clearAppleUserIdentifier()
        clearSupabaseTokens()
        clearOpenAIAPIKey()
        clearNotionTokens()
        clearTaskadeTokens()
    }
}
