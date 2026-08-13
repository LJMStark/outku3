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
    public private(set) var googleCalendarAccessLevel: GoogleCalendarAccessLevel = .none
    public private(set) var hasTasksAccess: Bool = false
    public private(set) var isNotionConnected: Bool = false
    public private(set) var isTaskadeConnected: Bool = false
    public internal(set) var isMicrosoftConnected: Bool = false
    public internal(set) var hasMicrosoftCalendarAccess: Bool = false
    public internal(set) var hasMicrosoftTodoAccess: Bool = false
    public internal(set) var isTodoistConnected: Bool = false
    public internal(set) var isTickTickConnected: Bool = false
    public internal(set) var tickTickRegion: TickTickRegion?

    public var hasCalendarAccess: Bool {
        googleCalendarAccessLevel.canRead
    }

    public var hasCalendarWriteAccess: Bool {
        googleCalendarAccessLevel.canWrite
    }

    /// User id safe to use as a cloud (Supabase) write target. Returns `nil`
    /// while the local identity is still pending Supabase confirmation, so
    /// callers can skip writes that would otherwise be rejected by RLS or
    /// land under a transient placeholder id.
    public var cloudWritableUserId: String? {
        guard let user = currentUser, !user.isPendingRemoteIdentity else {
            return nil
        }
        return user.id
    }

    // MARK: - Services

    private let appleSignInService = AppleSignInService.shared
    private let googleSignInService = GoogleSignInService.shared
    private let notionAuthService: NotionAuthService
    private let taskadeAuthService: TaskadeAuthService
    let microsoftAuthService = MicrosoftAuthService.shared
    @ObservationIgnored let microsoftAvailability: @MainActor (IntegrationType) -> Bool
    private let keychainService: KeychainService
    private let supabaseService = SupabaseService.shared
    @ObservationIgnored var todoistAuthService: TodoistAuthService?
    @ObservationIgnored var todoistCredentialManager: TodoistCredentialManager?
    @ObservationIgnored let todoistCredentialOperationGate = OAuthCredentialOperationGate()
    @ObservationIgnored var tickTickAuthService: TickTickAuthService?
    @ObservationIgnored var tickTickCredentialManager: TickTickCredentialManager?
    @ObservationIgnored var tickTickCredentialOwnerUserID: String?
    @ObservationIgnored let tickTickCredentialOperationGate = OAuthCredentialOperationGate()
    @ObservationIgnored var tickTickLocalStateCleaner = TickTickLocalStateCleaner.live
    @ObservationIgnored var taskProviderSignOutCleanupOverride: (@MainActor () async throws -> Void)?
    @ObservationIgnored var providerDataSignOutCleanupOverride: (@MainActor () async throws -> Void)?
    @ObservationIgnored var localCredentialSignOutCleanupOverride: (@MainActor () throws -> Void)?
    @ObservationIgnored var supabaseSignOutOverride: (@Sendable () async throws -> Void)?
    @ObservationIgnored var googleSyncStateResetOverride: (@MainActor () async throws -> Void)?
    @ObservationIgnored var googleSyncActivationOverride: (@MainActor () async throws -> Void)?
    @ObservationIgnored var googleDisconnectOverride: (@MainActor () async -> Void)?
    @ObservationIgnored var todoistDisconnectSyncResetOverride: (@MainActor () async throws -> Void)?
    @ObservationIgnored var todoistDisconnectProjectCleanupOverride: (@MainActor () async throws -> Void)?
    @ObservationIgnored var todoistComponentFactoryOverride: (@MainActor () throws -> (
        auth: TodoistAuthService,
        credentials: TodoistCredentialManager
    ))?
    @ObservationIgnored var todoistPreparedSignOutCleanup: OAuthCredentialCleanupTicket?
    @ObservationIgnored var todoistPreparedSignOutCleanupCompleted = false
    @ObservationIgnored var customCompanionSignOutCleanup: @MainActor () async throws -> Void = {
        try await AppState.shared.prepareCustomCompanionDataForSignOut()
    }

    static let tickTickRegionKey = "integrations.ticktick.region"

    init(
        keychainService: KeychainService = .shared,
        notionAuthService: NotionAuthService? = nil,
        taskadeAuthService: TaskadeAuthService? = nil,
        microsoftAvailability: @escaping @MainActor (IntegrationType) -> Bool = { $0.isAvailable }
    ) {
        self.keychainService = keychainService
        self.microsoftAvailability = microsoftAvailability
        self.notionAuthService = notionAuthService
            ?? (keychainService === KeychainService.shared
                ? .shared
                : NotionAuthService(keychainService: keychainService))
        self.taskadeAuthService = taskadeAuthService
            ?? (keychainService === KeychainService.shared
                ? .shared
                : TaskadeAuthService(keychainService: keychainService))
    }

    // MARK: - Initialization

    /// 在 App 启动时调用，恢复之前的登录状态。
    ///
    /// 流程拆三步：
    ///   - Step A: 从 Keychain 同步恢复本地身份。即使飞行模式 / Supabase 不可达，
    ///     也能让 currentUser 立刻就位，避免冷启动直接掉登录。
    ///   - Step B: 尝试 Google SDK 本地恢复（不依赖网络），补全 email / 头像等信息。
    ///   - Step C: 异步尝试 Supabase session 恢复，把 pending user 升级到 canonical id。
    ///     失败时静默——currentUser 维持 pending 状态，下一次有网时自然会再升级。
    public func initialize() async {
        googleSignInService.configure()

        // Step A: synchronous Keychain restore — works offline.
        restoreLocalIdentityFromKeychain()

        // Step B: Google SDK local restore (typically offline-safe via cached creds).
        let restoredGoogleResult: GoogleSignInResult?
        do {
            restoredGoogleResult = try await googleSignInService.restorePreviousSignIn()
        } catch {
            restoredGoogleResult = nil
            ErrorReporter.log(error, context: "AuthManager.initialize.restoreGoogleSignIn")
        }
        if let googleResult = restoredGoogleResult {
            applyGoogleSignInResult(googleResult, isRestore: true, restoredSupabaseUser: nil)
        }

        // Step C: best-effort Supabase session restore + canonical id upgrade.
        let restoredSupabaseUser = await restoredSupabaseUser(from: restoredGoogleResult)
        if let supabaseUser = restoredSupabaseUser {
            promoteCurrentUser(with: supabaseUser, googleResult: restoredGoogleResult)
        }

        isNotionConnected = notionAuthService.isConnected
        isTaskadeConnected = taskadeAuthService.isConnected
        isMicrosoftConnected = await microsoftAuthService.isConnected()
        hasMicrosoftCalendarAccess = await microsoftAuthService.hasAccess(to: .outlookCalendar)
        hasMicrosoftTodoAccess = await microsoftAuthService.hasAccess(to: .todo)
        do {
            try await restoreTaskProviderConnections()
        } catch {
            AppState.shared.lastError = error.localizedDescription
            ErrorReporter.log(error, context: "AuthManager.initialize.restoreTaskProviderConnections")
        }
    }

    /// Step A: hydrate `currentUser` from Keychain so the UI can show an
    /// authenticated state without a Supabase round-trip. The user is marked
    /// `isPendingRemoteIdentity` until Supabase confirms its canonical id.
    func restoreLocalIdentityFromKeychain() {
        // Apple takes precedence: identifier is the source of truth for Apple users.
        if let appleIdentifier = keychainService.getAppleUserIdentifier() {
            let user = User(
                id: appleIdentifier,
                authProvider: .apple,
                isPendingRemoteIdentity: true
            )
            currentUser = user
            authState = .authenticated(user)
            return
        }

        // Google: presence of access + refresh tokens implies the user previously
        // signed in. We can't read sub/email from Keychain alone, so the id is a
        // placeholder that Step B (Google SDK) or Step C (Supabase) will replace.
        guard keychainService.getGoogleAccessToken() != nil,
              keychainService.getGoogleRefreshToken() != nil,
              let savedScopes = keychainService.getGoogleScopes() else {
            return
        }

        isGoogleConnected = true
        googleCalendarAccessLevel = GoogleCalendarAccessLevel.from(grantedScopes: savedScopes)
        hasTasksAccess = savedScopes.contains(GoogleOAuthScope.tasks)

        let user = User(
            id: Self.pendingGoogleUserID,
            authProvider: .google,
            isPendingRemoteIdentity: true
        )
        currentUser = user
        authState = .authenticated(user)
    }

    /// Step C helper: replace `currentUser`'s id with the Supabase canonical id
    /// and clear the `isPendingRemoteIdentity` flag. Preserves any locally-known
    /// display info (email, displayName, avatar) gathered during Steps A/B.
    private func promoteCurrentUser(
        with supabaseUser: SupabaseUser,
        googleResult: GoogleSignInResult?
    ) {
        let existing = currentUser
        let provider: AuthProvider = existing?.authProvider
            ?? (keychainService.getAppleUserIdentifier() != nil ? .apple : .google)

        let promoted = User(
            id: supabaseUser.id,
            email: supabaseUser.email ?? existing?.email ?? googleResult?.email,
            displayName: existing?.displayName ?? googleResult?.displayName,
            avatarURL: existing?.avatarURL ?? googleResult?.avatarURL,
            authProvider: provider,
            createdAt: supabaseUser.createdAt,
            lastLoginAt: Date(),
            isPendingRemoteIdentity: false
        )
        currentUser = promoted
        authState = .authenticated(promoted)
    }

    /// Sentinel id used while a Google-only user has tokens in Keychain but
    /// no canonical Supabase id yet. Always paired with `isPendingRemoteIdentity`.
    private static let pendingGoogleUserID = "pending-google-identity"

    private func restoredSupabaseUser(from googleResult: GoogleSignInResult?) async -> SupabaseUser? {
        if let currentUser = await supabaseService.getCurrentUser() {
            return currentUser
        }

        guard let googleResult else {
            return nil
        }

        do {
            return try await signInToSupabase(withGoogleResult: googleResult)
        } catch {
            ErrorReporter.log(error, context: "AuthManager.initialize.restoreSupabaseUser")
            return nil
        }
    }

    private func applyGoogleSignInResult(
        _ result: GoogleSignInResult,
        isRestore: Bool,
        restoredSupabaseUser: SupabaseUser? = nil
    ) {
        isGoogleConnected = true
        googleCalendarAccessLevel = result.calendarAccessLevel
        hasTasksAccess = result.hasTasksAccess

        guard isRestore else { return }

        // No user yet → create one (canonical if Supabase available, else pending).
        if currentUser == nil {
            var user = Self.makeCanonicalUser(
                providerUserID: result.userID,
                email: result.email,
                displayName: result.displayName,
                avatarURL: result.avatarURL,
                authProvider: .google,
                supabaseUser: restoredSupabaseUser
            )
            user.isPendingRemoteIdentity = (restoredSupabaseUser == nil)
            currentUser = user
            authState = .authenticated(user)
            return
        }

        // Step A left us a Google placeholder; fill in real id/email/displayName.
        if let existing = currentUser,
           existing.authProvider == .google,
           existing.isPendingRemoteIdentity,
           existing.id == Self.pendingGoogleUserID {
            let updated = User(
                id: result.userID,
                email: result.email ?? existing.email,
                displayName: result.displayName ?? existing.displayName,
                avatarURL: result.avatarURL ?? existing.avatarURL,
                authProvider: .google,
                createdAt: existing.createdAt,
                lastLoginAt: Date(),
                isPendingRemoteIdentity: true
            )
            currentUser = updated
            authState = .authenticated(updated)
        }
    }

    // MARK: - Apple Sign In

    /// 使用 Apple 登录
    public func signInWithApple() async throws {
        authState = .authenticating

        do {
            let result = try await appleSignInService.signIn()
            let supabaseUser = try await signInToSupabase(withAppleIDToken: result.identityTokenString)
            try completeAppleSignIn(
                userIdentifier: result.userIdentifier,
                email: result.email,
                displayName: result.displayName,
                supabaseUser: supabaseUser
            )
        } catch {
            handleAuthenticationError(error)
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

            let displayName = buildDisplayName(from: credential.fullName)
            let supabaseUser = try await signInToSupabase(
                withAppleIDToken: String(data: credential.identityToken ?? Data(), encoding: .utf8)
            )
            try completeAppleSignIn(
                userIdentifier: credential.user,
                email: credential.email,
                displayName: displayName,
                supabaseUser: supabaseUser
            )
        } catch {
            authState = .error(error.localizedDescription)
            throw error
        }
    }

    private func buildDisplayName(from fullName: PersonNameComponents?) -> String? {
        guard let fullName else { return nil }
        var nameParts: [String] = []
        if let givenName = fullName.givenName {
            nameParts.append(givenName)
        }
        if let familyName = fullName.familyName {
            nameParts.append(familyName)
        }
        return nameParts.isEmpty ? nil : nameParts.joined(separator: " ")
    }

    private func handleAuthenticationError(_ error: Error) {
        if let appleError = error as? AppleSignInError, case .canceled = appleError {
            authState = .unauthenticated
        } else {
            authState = .error(error.localizedDescription)
        }
    }

    // MARK: - Google Sign In

    /// 使用 Google 登录（或连接 Google 账户）
    public func signInWithGoogle() async throws {
        // 如果已经有 Apple 登录，这是连接 Google 账户
        let isConnecting = currentUser != nil
        var didResetGoogleSyncState = false

        if !isConnecting {
            authState = .authenticating
        }

        do {
            // The legacy Google outbox has no account owner. Clear it and invalidate every
            // suspended sync before opening Google's authorization UI; the engine stays blocked
            // until the new identity and its Supabase session are fully committed below.
            try await resetGoogleSyncStateForAccountTransition()
            didResetGoogleSyncState = true
            let result = try await googleSignInService.signIn()
            let supabaseUser = isConnecting
                ? nil
                : try await signInToSupabase(withGoogleResult: result)
            try await activateGoogleSyncAfterAuthorization()

            isGoogleConnected = true
            googleCalendarAccessLevel = result.calendarAccessLevel
            hasTasksAccess = result.hasTasksAccess

            // 如果是首次登录（不是连接），设置用户
            if !isConnecting {
                let user = Self.makeCanonicalUser(
                    providerUserID: result.userID,
                    email: result.email,
                    displayName: result.displayName,
                    avatarURL: result.avatarURL,
                    authProvider: .google,
                    supabaseUser: supabaseUser
                )
                currentUser = user
                authState = .authenticated(user)
            }

        } catch {
            // Authorization may already have written an SDK/Keychain session before a later
            // Supabase or engine commit failed. Remove that partial identity and leave sync
            // disabled so old and new account generations cannot coexist. If reset itself failed,
            // preserve the existing visible connection and credentials: cleanup failure must not
            // be presented as a successful disconnect.
            if didResetGoogleSyncState {
                googleSignInService.signOut()
                isGoogleConnected = false
                googleCalendarAccessLevel = .none
                hasTasksAccess = false
            }
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

    /// 断开 Google 账户连接（仅清除 Google 相关状态，保留主帐号和其他 integration）
    @discardableResult
    public func disconnectGoogle() async -> Bool {
        do {
            // resetAndDisable changes generation before its first storage await. A suspended
            // pull/flush therefore cannot commit while Google revocation is in progress.
            try await resetGoogleSyncStateForAccountTransition()
            if let googleDisconnectOverride {
                await googleDisconnectOverride()
            } else {
                await googleSignInService.disconnect()
            }
            keychainService.clearGoogleTokens()
            guard keychainService.getGoogleAccessToken() == nil,
                  keychainService.getGoogleRefreshToken() == nil,
                  keychainService.getGoogleScopes() == nil else {
                throw GoogleProviderCleanupError.credentialsRemain
            }
        } catch {
            // Keep the visible connection state unchanged when any local cleanup could not be
            // verified. The engine remains disabled, so retrying disconnect is safe.
            AppState.shared.lastError = error.localizedDescription
            ErrorReporter.log(error, context: "AuthManager.disconnectGoogle")
            return false
        }

        isGoogleConnected = false
        googleCalendarAccessLevel = .none
        hasTasksAccess = false
        return true
    }

    public func ensureGoogleAccess(for type: IntegrationType) async throws {
        if !isGoogleConnected {
            try await signInWithGoogle()
            return
        }

        let needsScopeUpgrade: Bool
        switch type {
        case .googleCalendar:
            needsScopeUpgrade = !hasCalendarWriteAccess
        case .googleTasks:
            needsScopeUpgrade = !hasTasksAccess
        default:
            needsScopeUpgrade = false
        }

        guard needsScopeUpgrade else { return }

        let result = try await googleSignInService.requestAdditionalScopes()
        applyGoogleSignInResult(result, isRestore: false)
    }

    // MARK: - Notion Sign In

    /// 使用 Notion 连接
    public func signInWithNotion() async throws {
        let operation = try notionAuthService.beginCredentialOperation()
        defer { notionAuthService.endCredentialOperation(operation) }
        _ = try await notionAuthService.authorize()
        try notionAuthService.validateCredentialOperation(operation)
        isNotionConnected = true
    }

    /// 获取 Notion access token
    public func getNotionAccessToken() -> String? {
        notionAuthService.getAccessToken()
    }

    /// 断开 Notion 连接
    @discardableResult
    public func disconnectNotion() -> Bool {
        guard notionAuthService.disconnect() else { return false }
        isNotionConnected = false
        return true
    }

    // MARK: - Taskade Sign In

    /// 使用 Taskade 连接
    public func signInWithTaskade() async throws {
        let operation = try taskadeAuthService.beginCredentialOperation()
        defer { taskadeAuthService.endCredentialOperation(operation) }
        _ = try await taskadeAuthService.authorize()
        try taskadeAuthService.validateCredentialOperation(operation)
        isTaskadeConnected = true
    }

    /// 获取 Taskade access token
    public func getTaskadeAccessToken() async throws -> String {
        try await taskadeAuthService.getAccessToken()
    }

    /// 断开 Taskade 连接
    @discardableResult
    public func disconnectTaskade() -> Bool {
        guard taskadeAuthService.disconnect() else { return false }
        isTaskadeConnected = false
        return true
    }

    // MARK: - Sign Out

    /// 完全登出
    public func signOut() async {
        AppState.shared.invalidateAllExternalSyncResults()
        let notionCleanup = notionAuthService.invalidateAndBlockCredentialOperations()
        let taskadeCleanup = taskadeAuthService.invalidateAndBlockCredentialOperations()
        let todoistCredentialGate: OAuthCredentialOperationGate
        let todoistCleanup: OAuthCredentialCleanupTicket
        if let todoistAuthService {
            todoistCredentialGate = todoistAuthService.credentialGate
            todoistCleanup = todoistAuthService.invalidateAndBlockCredentialOperations()
        } else {
            todoistCredentialGate = todoistCredentialOperationGate
            todoistCleanup = todoistCredentialGate.invalidateAndBlock()
        }
        let tickTickSignOutHold = beginTickTickCredentialCleanupForSignOut()
        todoistPreparedSignOutCleanup = todoistCleanup
        todoistPreparedSignOutCleanupCompleted = false
        var shouldCompleteNotionCleanup = true
        var shouldCompleteTaskadeCleanup = true
        var shouldReopenTodoist = true
        defer {
            if shouldCompleteNotionCleanup {
                notionAuthService.credentialGate.complete(notionCleanup)
            }
            if shouldCompleteTaskadeCleanup {
                taskadeAuthService.credentialGate.complete(taskadeCleanup)
            }
            let didClearTodoist = todoistPreparedSignOutCleanupCompleted
            if shouldReopenTodoist || todoistPreparedSignOutCleanupCompleted {
                todoistCredentialGate.complete(todoistCleanup)
            }
            if didClearTodoist {
                todoistAuthService = nil
                todoistCredentialManager = nil
            }
            if todoistPreparedSignOutCleanup == todoistCleanup {
                todoistPreparedSignOutCleanup = nil
                todoistPreparedSignOutCleanupCompleted = false
            }
            completeTickTickCredentialCleanupForSignOut(tickTickSignOutHold)
        }

        func finishCredentialCleanupAfterEarlyAbort() async {
            do {
                try await finishAbortedTodoistSignOut(
                    todoistCleanup,
                    credentialGate: todoistCredentialGate
                )
            } catch {
                ErrorReporter.log(
                    error,
                    context: "AuthManager.signOut.finishAbortedTodoistCleanup"
                )
            }
            do {
                try await finishAbortedTickTickSignOut(tickTickSignOutHold)
            } catch {
                ErrorReporter.log(
                    error,
                    context: "AuthManager.signOut.finishAbortedTickTickCleanup"
                )
            }
        }

        // This is deliberately the first suspension in global sign-out. The engine invalidates
        // its generation before awaiting storage deletion, so provider cleanup later in this
        // method cannot race an old Google sync or outbox flush.
        do {
            try await resetGoogleSyncStateForAccountTransition()
        } catch {
            await finishCredentialCleanupAfterEarlyAbort()
            AppState.shared.lastError = error.localizedDescription
            ErrorReporter.log(error, context: "AuthManager.signOut.resetGoogleSyncState")
            return
        }

        // Custom photos are user data. Online we wait for firmware erase confirmation; offline
        // AppState removes local bytes immediately and keeps only an eraseAll marker.
        do {
            try await customCompanionSignOutCleanup()
        } catch {
            await finishCredentialCleanupAfterEarlyAbort()
            AppState.shared.lastError = error.localizedDescription
            ErrorReporter.log(error, context: "AuthManager.signOut.eraseCustomAvatar")
            return
        }

        do {
            if taskProviderSignOutCleanupOverride == nil {
                shouldReopenTodoist = false
            }
            try await cleanupTaskProvidersForSignOut()
        } catch {
            AppState.shared.lastError = error.localizedDescription
            ErrorReporter.log(error, context: "AuthManager.signOut.cleanupTaskProviders")
            return
        }

        do {
            if let providerDataSignOutCleanupOverride {
                try await providerDataSignOutCleanupOverride()
            } else {
                try await AppState.shared.prepareProviderDataForSignOut()
            }
        } catch {
            AppState.shared.lastError = error.localizedDescription
            ErrorReporter.log(error, context: "AuthManager.signOut.cleanupProviderData")
            return
        }

        // Credential deletion is the local security boundary. It must finish before the remote
        // Supabase session is revoked; otherwise a Keychain failure would leave authenticated UI
        // backed by credentials that no longer have a usable cloud session.
        do {
            guard notionAuthService.disconnect(
                after: notionCleanup,
                completeCleanup: false
            ) else {
                shouldCompleteNotionCleanup = false
                throw KeychainCleanupError.credentialDeletionFailed
            }
            isNotionConnected = false
            guard taskadeAuthService.disconnect(
                after: taskadeCleanup,
                completeCleanup: false
            ) else {
                shouldCompleteTaskadeCleanup = false
                throw KeychainCleanupError.credentialDeletionFailed
            }
            isTaskadeConnected = false
            if let localCredentialSignOutCleanupOverride {
                try localCredentialSignOutCleanupOverride()
            } else {
                try keychainService.clearAll()
            }
        } catch {
            AppState.shared.lastError = error.localizedDescription
            ErrorReporter.log(error, context: "AuthManager.signOut.clearLocalCredentials")
            return
        }

        // These services keep SDK or in-memory auth state outside KeychainService. Clear them
        // before the network await below so a process exit cannot let launch restore the old
        // provider after its Keychain credentials were already deleted.
        clearLocalProviderSessionState()

        do {
            if let supabaseSignOutOverride {
                try await supabaseSignOutOverride()
            } else {
                try await supabaseService.signOut()
            }
        } catch {
            // Local credentials are already verified absent. Do not restore authenticated UI for
            // a remote revocation failure; Supabase's local session cannot survive relaunch.
            ErrorReporter.log(error, context: "AuthManager.signOut.supabase")
        }

        // 重置状态
        currentUser = nil
        authState = .unauthenticated
    }

    private func clearLocalProviderSessionState() {
        googleSignInService.signOut()
        isGoogleConnected = false
        googleCalendarAccessLevel = .none
        hasTasksAccess = false
        appleSignInService.clearCredentials()
        isNotionConnected = false
        isTaskadeConnected = false
    }

    /// Reserved for a future account-deletion surface. No backend deletion is introduced here;
    /// this only guarantees that companion photos follow the same device/local cleanup contract.
    public func prepareCustomCompanionDataForAccountDeletion() async throws {
        try await AppState.shared.prepareCustomCompanionDataForAccountRemoval()
    }

    // MARK: - Handle URL

    /// 处理 OAuth 回调 URL
    public func handleURL(_ url: URL) -> Bool {
        googleSignInService.handle(url)
    }

    private func completeAppleSignIn(
        userIdentifier: String,
        email: String?,
        displayName: String?,
        supabaseUser: SupabaseUser
    ) throws {
        try appleSignInService.saveUserIdentifier(userIdentifier)

        let user = Self.makeCanonicalUser(
            providerUserID: userIdentifier,
            email: email,
            displayName: displayName,
            avatarURL: nil,
            authProvider: .apple,
            supabaseUser: supabaseUser
        )

        currentUser = user
        authState = .authenticated(user)
    }

    private func signInToSupabase(withAppleIDToken idToken: String?) async throws -> SupabaseUser {
        guard let idToken, !idToken.isEmpty else {
            throw AppleSignInError.invalidCredential
        }
        return try await supabaseService.signInWithApple(idToken: idToken)
    }

    private func signInToSupabase(withGoogleResult result: GoogleSignInResult) async throws -> SupabaseUser {
        guard let idToken = result.idToken, !idToken.isEmpty else {
            throw GoogleSignInError.failed("Missing Google ID token")
        }
        return try await supabaseService.signInWithGoogle(
            idToken: idToken,
            accessToken: result.accessToken
        )
    }

    nonisolated static func makeCanonicalUser(
        providerUserID: String,
        email: String?,
        displayName: String?,
        avatarURL: URL?,
        authProvider: AuthProvider,
        supabaseUser: SupabaseUser?
    ) -> User {
        User(
            id: supabaseUser?.id ?? providerUserID,
            email: supabaseUser?.email ?? email,
            displayName: displayName,
            avatarURL: avatarURL,
            authProvider: authProvider,
            createdAt: supabaseUser?.createdAt ?? Date(),
            lastLoginAt: Date()
        )
    }
}
