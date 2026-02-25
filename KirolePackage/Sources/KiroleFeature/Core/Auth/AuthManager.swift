import Foundation
import AuthenticationServices
import SwiftUI

// MARK: - Auth Manager

/// 统一管理认证状态，协调 Apple Sign In 和 Google Sign In
@Observable
@MainActor
public final class AuthManager {
    public static let shared = AuthManager()

    // MARK: - State

    public private(set) var authState: AuthState = .unauthenticated
    public private(set) var currentUser: User?
    public private(set) var isGoogleConnected: Bool = false
    public private(set) var hasCalendarAccess: Bool = false
    public private(set) var hasTasksAccess: Bool = false

    // MARK: - Services

    private let appleSignInService = AppleSignInService.shared
    private let googleSignInService = GoogleSignInService.shared
    private let keychainService = KeychainService.shared

    private init() {}

    // MARK: - Initialization

    /// 在 App 启动时调用，恢复之前的登录状态
    public func initialize() async {
        // 配置 Google Sign In
        googleSignInService.configure()

        // 仅从 Keychain 恢复 Apple 登录态，避免启动时额外认证调用导致不稳定
        restoreAppleStateFromKeychain()

        // 检查 Google 连接状态
        if let googleResult = try? await googleSignInService.restorePreviousSignIn() {
            // Google SDK 恢复成功
            isGoogleConnected = true
            hasCalendarAccess = googleResult.hasCalendarAccess
            hasTasksAccess = googleResult.hasTasksAccess

            // 如果没有 Apple 登录，使用 Google 作为主要认证
            if currentUser == nil {
                let user = User(
                    id: googleResult.userID,
                    email: googleResult.email,
                    displayName: googleResult.displayName,
                    avatarURL: googleResult.avatarURL,
                    authProvider: .google
                )
                currentUser = user
                authState = .authenticated(user)
            }
        } else {
            // Google SDK 恢复失败，尝试从 Keychain 恢复状态
            restoreGoogleStateFromKeychain()
        }
    }

    /// 从 Keychain 恢复 Apple 登录状态
    private func restoreAppleStateFromKeychain() {
        guard let userIdentifier = keychainService.getAppleUserIdentifier() else {
            return
        }

        let user = User(
            id: userIdentifier,
            authProvider: .apple
        )
        currentUser = user
        authState = .authenticated(user)
    }

    /// 从 Keychain 恢复 Google 连接状态
    private func restoreGoogleStateFromKeychain() {
        // 检查是否有有效的 tokens 和 scopes
        guard keychainService.getGoogleAccessToken() != nil,
              keychainService.getGoogleRefreshToken() != nil,
              let savedScopes = keychainService.getGoogleScopes() else {
            return
        }

        // 从保存的 scopes 恢复权限状态
        isGoogleConnected = true
        hasCalendarAccess = savedScopes.contains("https://www.googleapis.com/auth/calendar.readonly")
        hasTasksAccess = savedScopes.contains("https://www.googleapis.com/auth/tasks")
    }

    // MARK: - Apple Sign In

    /// 使用 Apple 登录
    public func signInWithApple() async throws {
        authState = .authenticating

        do {
            let result = try await appleSignInService.signIn()
            try completeAppleSignIn(
                userIdentifier: result.userIdentifier,
                email: result.email,
                displayName: result.displayName
            )
        } catch {
            if let appleError = error as? AppleSignInError, case .canceled = appleError {
                authState = .unauthenticated
            } else {
                authState = .error(error.localizedDescription)
            }
            throw error
        }
    }

    /// 使用 SignInWithAppleButton 返回的授权结果完成登录（避免重复发起 Apple 登录流程）
    public func signInWithAppleAuthorization(_ authorization: ASAuthorization) async throws {
        authState = .authenticating

        do {
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                throw AppleSignInError.invalidCredential
            }

            var nameParts: [String] = []
            if let givenName = credential.fullName?.givenName {
                nameParts.append(givenName)
            }
            if let familyName = credential.fullName?.familyName {
                nameParts.append(familyName)
            }
            let displayName = nameParts.isEmpty ? nil : nameParts.joined(separator: " ")

            try completeAppleSignIn(
                userIdentifier: credential.user,
                email: credential.email,
                displayName: displayName
            )
        } catch {
            authState = .error(error.localizedDescription)
            throw error
        }
    }

    // MARK: - Google Sign In

    /// 使用 Google 登录（或连接 Google 账户）
    public func signInWithGoogle() async throws {
        // 如果已经有 Apple 登录，这是连接 Google 账户
        let isConnecting = currentUser != nil

        if !isConnecting {
            authState = .authenticating
        }

        do {
            let result = try await googleSignInService.signIn()

            isGoogleConnected = true
            hasCalendarAccess = result.hasCalendarAccess
            hasTasksAccess = result.hasTasksAccess

            // 如果是首次登录（不是连接），设置用户
            if !isConnecting {
                let user = User(
                    id: result.userID,
                    email: result.email,
                    displayName: result.displayName,
                    avatarURL: result.avatarURL,
                    authProvider: .google
                )
                currentUser = user
                authState = .authenticated(user)
            }

        } catch {
            if !isConnecting {
                authState = .error(error.localizedDescription)
            }
            throw error
        }
    }

    // MARK: - Refresh Google Token

    /// 刷新 Google access token（如果需要）
    public func refreshGoogleTokenIfNeeded() async throws -> String {
        try await googleSignInService.refreshTokenIfNeeded()
    }

    /// 获取有效的 Google access token
    public func getGoogleAccessToken() async throws -> String {
        try await googleSignInService.getValidAccessToken()
    }

    // MARK: - Disconnect Google

    /// 断开 Google 账户连接
    public func disconnectGoogle() async {
        await googleSignInService.disconnect()
        isGoogleConnected = false
        hasCalendarAccess = false
        hasTasksAccess = false

        // 如果主要认证是 Google，则登出
        if currentUser?.authProvider == .google {
            await signOut()
        }
    }

    // MARK: - Sign Out

    /// 完全登出
    public func signOut() async {
        // 清除 Google
        googleSignInService.signOut()
        isGoogleConnected = false
        hasCalendarAccess = false
        hasTasksAccess = false

        // 清除 Apple
        appleSignInService.clearCredentials()

        // 清除所有 keychain 数据
        keychainService.clearAll()

        // 重置状态
        currentUser = nil
        authState = .unauthenticated
    }

    // MARK: - Handle URL

    /// 处理 OAuth 回调 URL
    public func handleURL(_ url: URL) -> Bool {
        googleSignInService.handle(url)
    }

    private func completeAppleSignIn(
        userIdentifier: String,
        email: String?,
        displayName: String?
    ) throws {
        try appleSignInService.saveUserIdentifier(userIdentifier)

        let user = User(
            id: userIdentifier,
            email: email,
            displayName: displayName,
            authProvider: .apple
        )

        currentUser = user
        authState = .authenticated(user)
    }
}
