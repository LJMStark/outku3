
import Foundation

/// Invalidates asynchronous credential results after sign-out/disconnect. Main-actor isolation
/// serializes memory access, while this generation also protects across actor reentrancy at await.
struct GoogleCredentialOperationGate: Sendable {
    private(set) var generation: UInt64 = 0
    private(set) var blocksNewOperations = false

    func snapshot() -> UInt64? {
        blocksNewOperations ? nil : generation
    }

    func accepts(_ snapshot: UInt64) -> Bool {
        !blocksNewOperations && snapshot == generation
    }

    mutating func invalidate(blockNewOperations: Bool) {
        generation &+= 1
        blocksNewOperations = blockNewOperations
    }

    mutating func unblock() {
        blocksNewOperations = false
    }
}

#if canImport(UIKit)
import GoogleSignIn
import UIKit

// MARK: - Google Sign In Service (iOS)

/// 处理 Google Sign In 认证流程，包含 Calendar 和 Tasks API 权限
@MainActor
public final class GoogleSignInService {
    public static let shared = GoogleSignInService()

    private let keychainService = KeychainService.shared
    private var refreshTask: Task<String, Error>?
    private var refreshTaskID: UUID?
    private var disconnectTask: Task<Void, Never>?
    private var disconnectTaskID: UUID?
    private var credentialGate = GoogleCredentialOperationGate()
    /// signIn / restore / addScopes 互斥。gate 只能事后作废陈旧结果，挡不住同代次
    /// 并发进 SDK（启动 restore 撞上用户点登录 → 双认证 UI / token 互踩），
    /// 同 key 串行队列补上互斥。refresh 有自己的共享任务去重，不走此队列。
    private let credentialOperationQueue = KeyedSerialTaskQueue<String>()
    private static let credentialQueueKey = "google-credential-operation"

    // Google API Scopes
    // calendarReadOnly 是 calendarList 端点（多日历同步）所需——events scope 不覆盖它，
    // 缺失时该调用恒 403、只能同步主日历（2026-07-04 联调定位）。三者同为 sensitive 档，
    // 加它不改变审核等级；Testing 模式下无需审核即可生效。已连接的旧授权没有此 scope，
    // 需断开重连一次升级；未重连的用户走 GoogleCalendarAPI 的 403 降级（主日历，无 warning）。
    private let scopes = [
        GoogleOAuthScope.calendarEvents,
        GoogleOAuthScope.calendarReadOnly,
        GoogleOAuthScope.tasks
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
    public func signIn() async throws -> GoogleSignInResult {
        // 快照在调用点（入队前）取；闭包内用 accepts 复检。排队期间落地的 signOut
        // 只换代不 block——若在队首才取快照会拿到新代次继续登录，违背"signOut 作废
        // 未决凭证操作"；disconnect（block）两种取法都能拒，此取法对两者都正确。
        let generation = try credentialOperationSnapshot()
        return try await credentialOperationQueue.run(for: Self.credentialQueueKey) {
            guard self.credentialGate.accepts(generation) else {
                throw GoogleSignInError.notSignedIn
            }
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene.windows.first?.rootViewController else {
                throw GoogleSignInError.noRootViewController
            }

            // 请求额外的 scopes
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: rootViewController,
                hint: nil,
                additionalScopes: self.scopes
            )

            let user = result.user
            try self.validateCredentialResult(generation, user: user)
            try self.persistTokensIfAvailable(for: user)
            self.persistScopesIfAvailable(user.grantedScopes ?? [])
            return self.makeSignInResult(from: user)
        }
    }

    // MARK: - Restore Previous Sign In

    /// 恢复之前的登录状态
    public func restorePreviousSignIn() async throws -> GoogleSignInResult? {
        let generation = try credentialOperationSnapshot()
        return try await credentialOperationQueue.run(for: Self.credentialQueueKey) { () async throws -> GoogleSignInResult? in
            guard self.credentialGate.accepts(generation) else {
                throw GoogleSignInError.notSignedIn
            }
            do {
                let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
                try self.validateCredentialResult(generation, user: user)
                return self.makeSignInResult(from: user)
            } catch {
                guard Self.isMissingPreviousSignInError(error) else { throw error }
                return nil
            }
        }
    }

    // MARK: - Refresh Token

    /// 刷新 access token（去重：并发调用共享同一个刷新任务）
    public func refreshTokenIfNeeded() async throws -> String {
        // 如果已有正在进行的刷新任务，直接等待它
        if let existingTask = refreshTask, !existingTask.isCancelled {
            return try await existingTask.value
        }

        let generation = try credentialOperationSnapshot()
        let taskID = UUID()
        let task = Task<String, Error> { @MainActor in
            defer {
                if self.refreshTaskID == taskID {
                    self.refreshTask = nil
                    self.refreshTaskID = nil
                }
            }

            // SDK 凭证段与 signIn/restore/addScopes 同 key 串行（联审 2026-07-16 F1）：
            // 此前 refresh 内嵌的 restorePreviousSignIn / refreshTokensIfNeeded 绕过队列，
            // 可与交互登录并发进入 Google SDK——a415f19 的互斥被这条侧门架空。
            // refreshTask 去重保留在队列之外；跨账号结果覆盖由 validateCredentialResult
            // 的 currentUser 身份比对拦截（本就存在，队列化后仍保留兜底）。
            return try await self.credentialOperationQueue.run(for: Self.credentialQueueKey) {
                guard self.credentialGate.accepts(generation) else {
                    throw GoogleSignInError.notSignedIn
                }

                if GIDSignIn.sharedInstance.currentUser == nil {
                    do {
                        _ = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
                    } catch {
                        if Self.isMissingPreviousSignInError(error) {
                            throw GoogleSignInError.notSignedIn
                        }
                        throw error
                    }
                }

                guard let currentUser = GIDSignIn.sharedInstance.currentUser else {
                    throw GoogleSignInError.notSignedIn
                }
                try self.validateCredentialResult(generation, user: currentUser)

                if self.keychainService.isGoogleTokenExpired() {
                    try await currentUser.refreshTokensIfNeeded()
                    try self.validateCredentialResult(generation, user: currentUser)
                    try self.persistTokensIfAvailable(for: currentUser)
                }

                try self.validateCredentialResult(generation, user: currentUser)
                return currentUser.accessToken.tokenString
            }
        }

        refreshTaskID = taskID
        refreshTask = task
        return try await task.value
    }

    // MARK: - Get Current Access Token

    /// 获取当前有效的 access token（如需要会自动刷新）
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
    public func requestAdditionalScopes() async throws -> GoogleSignInResult {
        let generation = try credentialOperationSnapshot()
        return try await credentialOperationQueue.run(for: Self.credentialQueueKey) {
            guard self.credentialGate.accepts(generation) else {
                throw GoogleSignInError.notSignedIn
            }
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene.windows.first?.rootViewController,
                  let currentUser = GIDSignIn.sharedInstance.currentUser else {
                throw GoogleSignInError.notSignedIn
            }

            let result = try await currentUser.addScopes(self.scopes, presenting: rootViewController)
            let user = result.user
            try self.validateCredentialResult(generation, user: user)
            try self.persistTokensIfAvailable(for: user)
            self.persistScopesIfAvailable(user.grantedScopes ?? [])
            return self.makeSignInResult(from: user)
        }
    }

    // MARK: - Sign Out

    /// 登出
    public func signOut() {
        invalidateCredentialOperations(blockNewOperations: false)
        GIDSignIn.sharedInstance.signOut()
        keychainService.clearGoogleTokens()
    }

    // MARK: - Disconnect

    /// 断开连接（撤销所有权限）
    public func disconnect() async {
        if let disconnectTask {
            await disconnectTask.value
            return
        }

        invalidateCredentialOperations(blockNewOperations: true)
        keychainService.clearGoogleTokens()

        let taskID = UUID()
        let task = Task { @MainActor in
            defer {
                // Revoke can fail before the SDK clears its local session. The user's local
                // disconnect choice still wins, while the callback error remains observable.
                GIDSignIn.sharedInstance.signOut()
                self.keychainService.clearGoogleTokens()
                if self.disconnectTaskID == taskID {
                    self.disconnectTask = nil
                    self.disconnectTaskID = nil
                    self.credentialGate.unblock()
                }
            }

            let disconnectError: Error? = await withCheckedContinuation { continuation in
                GIDSignIn.sharedInstance.disconnect { error in
                    continuation.resume(returning: error)
                }
            }
            if let disconnectError {
                ErrorReporter.log(
                    disconnectError,
                    context: "GoogleSignInService.disconnect.revoke"
                )
            }
        }

        disconnectTaskID = taskID
        disconnectTask = task
        await task.value
    }

    // MARK: - Handle URL

    /// 处理 OAuth 回调 URL
    public func handle(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    private func credentialOperationSnapshot() throws -> UInt64 {
        guard let generation = credentialGate.snapshot() else {
            throw GoogleSignInError.notSignedIn
        }
        return generation
    }

    private func validateCredentialResult(_ generation: UInt64, user: GIDGoogleUser) throws {
        let currentUserMatches = GIDSignIn.sharedInstance.currentUser === user
        let isAccepted = credentialGate.accepts(generation) && currentUserMatches
        guard !Task.isCancelled, isAccepted else {
            // Google writes currentUser and its own Keychain before returning. If an operation
            // finishes after sign-out/disconnect, reject its result and remove that late SDK
            // session so a later refresh cannot revive it.
            if currentUserMatches {
                GIDSignIn.sharedInstance.signOut()
                keychainService.clearGoogleTokens()
            }
            if Task.isCancelled {
                throw CancellationError()
            }
            throw GoogleSignInError.notSignedIn
        }
    }

    private func invalidateCredentialOperations(blockNewOperations: Bool) {
        let shouldBlock = blockNewOperations
            || disconnectTask != nil
            || credentialGate.blocksNewOperations
        credentialGate.invalidate(blockNewOperations: shouldBlock)
        refreshTask?.cancel()
        refreshTask = nil
        refreshTaskID = nil
    }

    private nonisolated static func isMissingPreviousSignInError(_ error: Error) -> Bool {
        let error = error as NSError
        // GoogleSignIn's kGIDSignInErrorDomain / kGIDSignInErrorCodeHasNoAuthInKeychain.
        return error.domain == "com.google.GIDSignIn" && error.code == -4
    }

    private func makeSignInResult(from user: GIDGoogleUser) -> GoogleSignInResult {
        GoogleSignInResult(
            userID: user.userID ?? "",
            email: user.profile?.email,
            displayName: user.profile?.name,
            avatarURL: user.profile?.imageURL(withDimension: 200),
            idToken: user.idToken?.tokenString,
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
        do {
            try keychainService.saveGoogleScopes(grantedScopes)
        } catch {
            ErrorReporter.log(
                .persistence(operation: "save", target: "google_scopes", underlying: error.localizedDescription),
                context: "GoogleSignInService.persistScopesIfAvailable"
            )
        }
    }
}

// MARK: - Google Sign In Result (iOS)

public struct GoogleSignInResult: Sendable {
    public let userID: String
    public let email: String?
    public let displayName: String?
    public let avatarURL: URL?
    public let idToken: String?
    public let accessToken: String
    public let refreshToken: String
    public let grantedScopes: [String]

    public var calendarAccessLevel: GoogleCalendarAccessLevel {
        GoogleCalendarAccessLevel.from(grantedScopes: grantedScopes)
    }

    public var hasCalendarAccess: Bool {
        calendarAccessLevel.canRead
    }

    public var hasCalendarWriteAccess: Bool {
        calendarAccessLevel.canWrite
    }

    public var hasTasksAccess: Bool {
        grantedScopes.contains(GoogleOAuthScope.tasks)
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

// MARK: - Google Sign In Service (macOS Stub)

@MainActor
public final class GoogleSignInService {
    public static let shared = GoogleSignInService()
    private init() {}
    public func configure() {}
    
    public func signIn() async throws -> GoogleSignInResult { throw GoogleSignInError.notSupported }
    
    public func restorePreviousSignIn() async throws -> GoogleSignInResult? { return nil }
    
    public func signOut() {}
    public func disconnect() async {}
    
    public func refreshTokenIfNeeded() async throws -> String { throw GoogleSignInError.notSupported }
    
    public func getValidAccessToken() async throws -> String { throw GoogleSignInError.notSupported }
    
    public func requestAdditionalScopes() async throws -> GoogleSignInResult { throw GoogleSignInError.notSupported }
    
    public func handle(_ url: URL) -> Bool { return false }
}

public struct GoogleSignInResult: Sendable {
    public let userID: String = ""
    public let email: String? = nil
    public let displayName: String? = nil
    public let avatarURL: URL? = nil
    public let idToken: String? = nil
    public let accessToken: String = ""
    public let refreshToken: String = ""
    public let grantedScopes: [String] = []
    public var calendarAccessLevel: GoogleCalendarAccessLevel = .none
    public var hasCalendarAccess: Bool = false
    public var hasCalendarWriteAccess: Bool = false
    public var hasTasksAccess: Bool = false
}

public enum GoogleSignInError: LocalizedError, Sendable {
    case notSupported
    case canceled
    case failed(String)
    public var errorDescription: String? {
        switch self {
        case .notSupported:
            return "Google Sign In not supported on macOS"
        case .canceled:
            return "Sign in was canceled"
        case .failed(let message):
            return "Sign in failed: \(message)"
        }
    }
}

#endif
