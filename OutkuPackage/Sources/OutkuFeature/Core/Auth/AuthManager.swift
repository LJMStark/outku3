import Foundation
import SwiftUI

// MARK: - Auth Manager

/// 统一管理认证状态，协调 Apple Sign In 和 Google Sign In
@Observable
@MainActor
public final class AuthManager: @unchecked Sendable {
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

        // 检查 Apple Sign In 状态
        let appleCredentialState = await appleSignInService.checkCredentialState()

        if appleCredentialState == .authorized {
            // 尝试恢复 Apple 用户
            if let userIdentifier = keychainService.getAppleUserIdentifier() {
                let user = User(
                    id: userIdentifier,
                    authProvider: .apple
                )
                currentUser = user
                authState = .authenticated(user)
            }
        }

        // 检查 Google 连接状态
        if let googleResult = try? await googleSignInService.restorePreviousSignIn() {
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
        }
    }

    // MARK: - Apple Sign In

    /// 使用 Apple 登录
    public func signInWithApple() async throws {
        authState = .authenticating

        do {
            let result = try await appleSignInService.signIn()

            // 保存用户标识符
            try appleSignInService.saveUserIdentifier(result.userIdentifier)

            let user = User(
                id: result.userIdentifier,
                email: result.email,
                displayName: result.displayName,
                authProvider: .apple
            )

            currentUser = user
            authState = .authenticated(user)

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
}
