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
        static let appleUserIdentifier = "apple_user_identifier"
        static let supabaseAccessToken = "supabase_access_token"
        static let supabaseRefreshToken = "supabase_refresh_token"
    }

    private init() {
        // 使用 App Bundle ID 作为 Keychain service identifier
        self.keychain = Keychain(service: "com.outku.app")
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

    // MARK: - Clear All

    public func clearAll() {
        clearGoogleTokens()
        clearAppleUserIdentifier()
        clearSupabaseTokens()
    }
}
