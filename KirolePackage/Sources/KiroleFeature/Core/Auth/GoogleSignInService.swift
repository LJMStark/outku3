
#if canImport(UIKit)
import Foundation
import GoogleSignIn
import UIKit

// MARK: - Google Sign In Service (iOS)

/// 处理 Google Sign In 认证流程，包含 Calendar 和 Tasks API 权限
public final class GoogleSignInService: @unchecked Sendable {
    public static let shared = GoogleSignInService()

    private let keychainService = KeychainService.shared
    private var refreshTask: Task<String, Error>?

    // Google API Scopes
    private let scopes = [
        "https://www.googleapis.com/auth/calendar.readonly",
        "https://www.googleapis.com/auth/tasks"
    ]

    private init() {}

    // MARK: - Configuration

    /// 配置 Google Sign In（在 App 启动时调用）
    public func configure() {
        // Google Sign In 会自动从 Info.plist 读取 Client ID
        // 确保 Info.plist 包含 GIDClientID 和 URL Schemes
    }

    // MARK: - Sign In

    /// 执行 Google Sign In
    @MainActor
    public func signIn() async throws -> GoogleSignInResult {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            throw GoogleSignInError.noRootViewController
        }

        // 请求额外的 scopes
        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: rootViewController,
            hint: nil,
            additionalScopes: scopes
        )

        let user = result.user
        try persistTokensIfAvailable(for: user)
        persistScopesIfAvailable(user.grantedScopes ?? [])
        return makeSignInResult(from: user)
    }

    // MARK: - Restore Previous Sign In

    /// 恢复之前的登录状态
    @MainActor
    public func restorePreviousSignIn() async throws -> GoogleSignInResult? {
        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            return makeSignInResult(from: user)
        } catch {
            // 没有之前的登录状态
            return nil
        }
    }

    // MARK: - Refresh Token

    /// 刷新 access token（去重：并发调用共享同一个刷新任务）
    @MainActor
    public func refreshTokenIfNeeded() async throws -> String {
        // 如果已有正在进行的刷新任务，直接等待它
        if let existingTask = refreshTask, !existingTask.isCancelled {
            return try await existingTask.value
        }

        let task = Task<String, Error> { @MainActor in
            defer { self.refreshTask = nil }

            if GIDSignIn.sharedInstance.currentUser == nil {
                _ = try? await GIDSignIn.sharedInstance.restorePreviousSignIn()
            }

            guard let currentUser = GIDSignIn.sharedInstance.currentUser else {
                throw GoogleSignInError.notSignedIn
            }

            if keychainService.isGoogleTokenExpired() {
                try await currentUser.refreshTokensIfNeeded()
                try persistTokensIfAvailable(for: currentUser)
            }

            return currentUser.accessToken.tokenString
        }

        refreshTask = task
        return try await task.value
    }

    // MARK: - Get Current Access Token

    /// 获取当前有效的 access token（如需要会自动刷新）
    @MainActor
    public func getValidAccessToken() async throws -> String {
        try await refreshTokenIfNeeded()
    }

    // MARK: - Check Scopes

    /// 检查是否已授权所需的 scopes
    public func hasRequiredScopes() -> Bool {
        guard let currentUser = GIDSignIn.sharedInstance.currentUser,
              let grantedScopes = currentUser.grantedScopes else {
            return false
        }

        return scopes.allSatisfy { grantedScopes.contains($0) }
    }

    // MARK: - Request Additional Scopes

    /// 请求额外的权限
    @MainActor
    public func requestAdditionalScopes() async throws {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController,
              let currentUser = GIDSignIn.sharedInstance.currentUser else {
            throw GoogleSignInError.notSignedIn
        }

        _ = try await currentUser.addScopes(scopes, presenting: rootViewController)
    }

    // MARK: - Sign Out

    /// 登出
    public func signOut() {
        GIDSignIn.sharedInstance.signOut()
        keychainService.clearGoogleTokens()
    }

    // MARK: - Disconnect

    /// 断开连接（撤销所有权限）
    public func disconnect() async {
        await withCheckedContinuation { continuation in
            GIDSignIn.sharedInstance.disconnect { _ in
                continuation.resume()
            }
        }
        keychainService.clearGoogleTokens()
    }

    // MARK: - Handle URL

    /// 处理 OAuth 回调 URL
    public func handle(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    private func makeSignInResult(from user: GIDGoogleUser) -> GoogleSignInResult {
        GoogleSignInResult(
            userID: user.userID ?? "",
            email: user.profile?.email,
            displayName: user.profile?.name,
            avatarURL: user.profile?.imageURL(withDimension: 200),
            accessToken: user.accessToken.tokenString,
            refreshToken: user.refreshToken.tokenString,
            grantedScopes: user.grantedScopes ?? []
        )
    }

    private func persistTokensIfAvailable(for user: GIDGoogleUser) throws {
        guard let accessToken = user.accessToken.tokenString as String?,
              let refreshToken = user.refreshToken.tokenString as String? else {
            return
        }

        let expiresIn = user.accessToken.expirationDate?.timeIntervalSinceNow ?? 3600
        try keychainService.saveGoogleTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresIn: expiresIn
        )
    }

    private func persistScopesIfAvailable(_ grantedScopes: [String]) {
        guard !grantedScopes.isEmpty else { return }
        try? keychainService.saveGoogleScopes(grantedScopes)
    }
}

// MARK: - Google Sign In Result (iOS)

public struct GoogleSignInResult: Sendable {
    public let userID: String
    public let email: String?
    public let displayName: String?
    public let avatarURL: URL?
    public let accessToken: String
    public let refreshToken: String
    public let grantedScopes: [String]

    public var hasCalendarAccess: Bool {
        grantedScopes.contains("https://www.googleapis.com/auth/calendar.readonly")
    }

    public var hasTasksAccess: Bool {
        grantedScopes.contains("https://www.googleapis.com/auth/tasks")
    }
}

// MARK: - Google Sign In Error (iOS)

public enum GoogleSignInError: LocalizedError, Sendable {
    case noRootViewController
    case notSignedIn
    case scopesDenied
    case canceled
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .noRootViewController:
            return "Unable to find root view controller"
        case .notSignedIn:
            return "Not signed in to Google"
        case .scopesDenied:
            return "Required permissions were denied"
        case .canceled:
            return "Sign in was canceled"
        case .failed(let message):
            return "Sign in failed: \(message)"
        }
    }
}

#else
import Foundation

// MARK: - Google Sign In Service (macOS Stub)

public final class GoogleSignInService: @unchecked Sendable {
    public static let shared = GoogleSignInService()
    private init() {}
    public func configure() {}
    
    @MainActor
    public func signIn() async throws -> GoogleSignInResult { throw GoogleSignInError.notSupported }
    
    @MainActor
    public func restorePreviousSignIn() async throws -> GoogleSignInResult? { return nil }
    
    public func signOut() {}
    public func disconnect() async {}
    
    @MainActor
    public func refreshTokenIfNeeded() async throws -> String { throw GoogleSignInError.notSupported }
    
    @MainActor
    public func getValidAccessToken() async throws -> String { throw GoogleSignInError.notSupported }
    
    public func handle(_ url: URL) -> Bool { return false }
}

public struct GoogleSignInResult: Sendable {
    public let userID: String = ""
    public let email: String? = nil
    public let displayName: String? = nil
    public let avatarURL: URL? = nil
    public var hasCalendarAccess: Bool = false
    public var hasTasksAccess: Bool = false
}

public enum GoogleSignInError: LocalizedError, Sendable {
    case notSupported
    case canceled
    public var errorDescription: String? {
        switch self {
        case .notSupported:
            return "Google Sign In not supported on macOS"
        case .canceled:
            return "Sign in was canceled"
        }
    }
}

#endif
