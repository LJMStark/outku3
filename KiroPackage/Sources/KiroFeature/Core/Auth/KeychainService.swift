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
    }

    private init() {
        // 使用 App Bundle ID 作为 Keychain service identifier
        self.keychain = Keychain(service: "com.kiro.app")
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
        try? keychain.get(Keys.googleAccessToken)
    }

    public func getGoogleRefreshToken() -> String? {
        try? keychain.get(Keys.googleRefreshToken)
    }

    public func getGoogleTokenExpiry() -> Date? {
        guard let expiryString = try? keychain.get(Keys.googleTokenExpiry) else {
            return nil
        }
        return ISO8601DateFormatter().date(from: expiryString)
    }

    public func isGoogleTokenExpired() -> Bool {
        guard let expiry = getGoogleTokenExpiry() else {
            return true
        }
        // 提前 5 分钟认为过期，以便有时间刷新
        return Date().addingTimeInterval(300) >= expiry
    }

    public func clearGoogleTokens() {
        try? keychain.remove(Keys.googleAccessToken)
        try? keychain.remove(Keys.googleRefreshToken)
        try? keychain.remove(Keys.googleTokenExpiry)
        try? keychain.remove(Keys.googleGrantedScopes)
    }

    // MARK: - Google Scopes

    /// 保存 Google 授权的 scopes
    public func saveGoogleScopes(_ scopes: [String]) throws {
        let scopesString = scopes.joined(separator: ",")
        try keychain.set(scopesString, key: Keys.googleGrantedScopes)
    }

    /// 获取保存的 Google scopes
    public func getGoogleScopes() -> [String]? {
        guard let scopesString = try? keychain.get(Keys.googleGrantedScopes),
              !scopesString.isEmpty else {
            return nil
        }
        return scopesString.components(separatedBy: ",")
    }

    /// 清除 Google scopes
    public func clearGoogleScopes() {
        try? keychain.remove(Keys.googleGrantedScopes)
    }

    // MARK: - Apple Sign In

    public func saveAppleUserIdentifier(_ identifier: String) throws {
        try keychain.set(identifier, key: Keys.appleUserIdentifier)
    }

    public func getAppleUserIdentifier() -> String? {
        try? keychain.get(Keys.appleUserIdentifier)
    }

    public func clearAppleUserIdentifier() {
        try? keychain.remove(Keys.appleUserIdentifier)
    }

    // MARK: - Supabase Tokens

    public func saveSupabaseTokens(accessToken: String, refreshToken: String) throws {
        try keychain.set(accessToken, key: Keys.supabaseAccessToken)
        try keychain.set(refreshToken, key: Keys.supabaseRefreshToken)
    }

    public func getSupabaseAccessToken() -> String? {
        try? keychain.get(Keys.supabaseAccessToken)
    }

    public func getSupabaseRefreshToken() -> String? {
        try? keychain.get(Keys.supabaseRefreshToken)
    }

    public func clearSupabaseTokens() {
        try? keychain.remove(Keys.supabaseAccessToken)
        try? keychain.remove(Keys.supabaseRefreshToken)
    }

    // MARK: - OpenAI API Key

    public func saveOpenAIAPIKey(_ apiKey: String) throws {
        try keychain.set(apiKey, key: Keys.openAIAPIKey)
    }

    public func getOpenAIAPIKey() -> String? {
        try? keychain.get(Keys.openAIAPIKey)
    }

    public func clearOpenAIAPIKey() {
        try? keychain.remove(Keys.openAIAPIKey)
    }

    public func hasOpenAIAPIKey() -> Bool {
        getOpenAIAPIKey() != nil
    }

    // MARK: - Clear All

    public func clearAll() {
        clearGoogleTokens()
        clearAppleUserIdentifier()
        clearSupabaseTokens()
        clearOpenAIAPIKey()
    }
}
