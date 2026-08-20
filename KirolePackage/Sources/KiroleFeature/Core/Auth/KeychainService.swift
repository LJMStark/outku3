import Foundation
@preconcurrency import KeychainAccess
import Security

// MARK: - Keychain Service

/// 安全存储敏感数据（tokens、credentials）。KeychainAccess 的配置在初始化后不再修改，
/// 每次调用只创建局部 Security 查询，因此可跨 actor 使用；多字段业务操作的一致性由调用方保证。
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
        static let microsoftAccountMetadata = "microsoft_account_metadata_v1"
        static let todoistTokenSet = "todoist_token_set"
        static let tickTickTokenSets = [
            "ticktick_token_set_international",
            "ticktick_token_set_china",
        ]
        static let tickTickPendingAuthorizations = [
            "ticktick_pending_oauth_international",
            "ticktick_pending_oauth_china",
        ]

        static let all = [
            googleAccessToken,
            googleRefreshToken,
            googleTokenExpiry,
            googleGrantedScopes,
            appleUserIdentifier,
            supabaseAccessToken,
            supabaseRefreshToken,
            openAIAPIKey,
            notionAccessToken,
            notionWorkspaceId,
            taskadeAccessToken,
            taskadeRefreshToken,
            microsoftAccountMetadata,
            todoistTokenSet,
        ] + tickTickTokenSets + tickTickPendingAuthorizations

        static let retiredProviderCredentials = [
            notionAccessToken,
            notionWorkspaceId,
            taskadeAccessToken,
            taskadeRefreshToken,
            microsoftAccountMetadata,
            todoistTokenSet,
        ] + tickTickTokenSets + tickTickPendingAuthorizations
    }

    init(service: String = "com.kirole.app") {
        // 使用 App Bundle ID 作为 Keychain service identifier
        // .afterFirstUnlockThisDeviceOnly: allows BLE BGAppRefreshTask to read tokens
        // while device is locked (after first unlock), and prevents iCloud Keychain backup.
        self.keychain = Keychain(service: service)
            .accessibility(.afterFirstUnlockThisDeviceOnly)
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

    // Removed providers keep their old key names only for upgrade cleanup. This is idempotent and
    // runs before any current provider is restored, so a retired OAuth token cannot linger just
    // because its old Settings row no longer exists.
    func clearRetiredProviderCredentials(
        microsoftAccessGroup: String? = "93SL23NPNG.com.microsoft.adalcache"
    ) throws {
        var firstError: Error?
        for key in Keys.retiredProviderCredentials {
            do {
                guard try keychain.getData(key) != nil else { continue }
                try keychain.remove(key)
                guard try keychain.getData(key) == nil else {
                    throw KeychainCleanupError.credentialDeletionFailed
                }
            } catch {
                firstError = firstError ?? error
                ErrorReporter.log(
                    .persistence(operation: "delete", target: "retired_provider_credentials", underlying: error.localizedDescription),
                    context: "KeychainService.clearRetiredProviderCredentials"
                )
            }
        }

        if let microsoftAccessGroup {
            let status = SecItemDelete([
                kSecClass: kSecClassGenericPassword,
                kSecAttrAccessGroup: microsoftAccessGroup,
            ] as CFDictionary)
            if status != errSecSuccess, status != errSecItemNotFound {
                firstError = firstError ?? KeychainCleanupError.credentialDeletionFailed
                ErrorReporter.log(
                    .persistence(
                        operation: "delete",
                        target: "retired_microsoft_credentials",
                        underlying: "OSStatus \(status)"
                    ),
                    context: "KeychainService.clearRetiredProviderCredentials"
                )
            }
        }

        if firstError != nil {
            throw KeychainCleanupError.credentialDeletionFailed
        }
    }

    // MARK: - Clear All

    public func clearAll() throws {
        var firstError: Error?
        for key in Keys.all {
            do {
                guard try keychain.getData(key) != nil else { continue }
                try keychain.remove(key)
                guard try keychain.getData(key) == nil else {
                    throw KeychainCleanupError.credentialDeletionFailed
                }
            } catch {
                firstError = firstError ?? error
                ErrorReporter.log(
                    .persistence(operation: "delete", target: "all_credentials", underlying: error.localizedDescription),
                    context: "KeychainService.clearAll"
                )
            }
        }
        if firstError != nil {
            throw KeychainCleanupError.credentialDeletionFailed
        }
    }
}

enum KeychainCleanupError: LocalizedError, Sendable {
    case credentialDeletionFailed

    var errorDescription: String? {
        "Local credentials could not be removed"
    }
}
