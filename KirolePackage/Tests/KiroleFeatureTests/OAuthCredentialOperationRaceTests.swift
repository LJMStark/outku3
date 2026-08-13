import Foundation
import Testing
@testable import KiroleFeature

@Suite("OAuth credential operation races", .serialized)
struct OAuthCredentialOperationRaceTests {
    @Test("Disconnect invalidates old work and blocks new credential operations")
    func disconnectInvalidatesAndBlocks() throws {
        let gate = OAuthCredentialOperationGate()
        let oldOperation = try #require(gate.beginOperation())

        let disconnect = gate.invalidateAndBlock()

        #expect(!gate.accepts(oldOperation))
        #expect(gate.beginOperation() == nil)

        gate.endOperation(oldOperation)
        gate.complete(disconnect)

        let newOperation = try #require(gate.beginOperation())
        #expect(gate.accepts(newOperation))
        #expect(newOperation != oldOperation)
        gate.endOperation(newOperation)
    }

    @Test("A same-account disconnect and reconnect still rejects the pre-disconnect result")
    func sameAccountABAStillInvalidatesOldResult() throws {
        let gate = OAuthCredentialOperationGate()
        let accountAFirstAuthorization = try #require(gate.beginOperation())

        let disconnect = gate.invalidateAndBlock()
        gate.complete(disconnect)

        #expect(!gate.accepts(accountAFirstAuthorization))
        #expect(gate.beginOperation() == nil)
        gate.endOperation(accountAFirstAuthorization)
        let accountASecondAuthorization = try #require(gate.beginOperation())
        #expect(gate.accepts(accountASecondAuthorization))
        #expect(accountAFirstAuthorization != accountASecondAuthorization)

        gate.endOperation(accountASecondAuthorization)
    }

    @Test("Only the matching cleanup generation may unblock a provider")
    func staleCleanupCannotUnblockNewerDisconnect() {
        let gate = OAuthCredentialOperationGate()
        let firstDisconnect = gate.invalidateAndBlock()
        let retryingDisconnect = gate.invalidateAndBlock()

        gate.complete(firstDisconnect)
        #expect(gate.beginOperation() == nil)

        gate.complete(retryingDisconnect)
        #expect(gate.beginOperation() != nil)
    }

    @Test("A sign-out aborted before credential cleanup reopens only the new generation")
    func abortedSignOutReopensNewGeneration() throws {
        let gate = OAuthCredentialOperationGate()
        let authorizationWaitingBeforeSignOut = try #require(gate.beginOperation())

        let signOut = gate.invalidateAndBlock()
        gate.complete(signOut)

        #expect(!gate.accepts(authorizationWaitingBeforeSignOut))
        #expect(gate.beginOperation() == nil)
        gate.endOperation(authorizationWaitingBeforeSignOut)
        let retryAfterAbortedSignOut = try #require(gate.beginOperation())
        #expect(gate.accepts(retryAfterAbortedSignOut))

        gate.endOperation(retryAfterAbortedSignOut)
    }

    @Test("Duplicate operation completion cannot drain another operation")
    func duplicateOperationCompletionIsIdempotent() throws {
        let gate = OAuthCredentialOperationGate()
        let first = try #require(gate.beginOperation())
        let second = try #require(gate.beginOperation())
        let cleanup = gate.invalidateAndBlock()
        gate.complete(cleanup)

        gate.endOperation(first)
        gate.endOperation(first)
        #expect(gate.beginOperation() == nil)

        gate.endOperation(second)
        #expect(gate.beginOperation() != nil)
    }

    @Test("Concurrent cleanup claims and old operations must all finish before unblocking")
    func concurrentCleanupClaimsWaitForEachOtherAndOldWork() throws {
        let gate = OAuthCredentialOperationGate()
        let oldOperation = try #require(gate.beginOperation())
        let firstCleanup = gate.invalidateAndBlock()
        let secondCleanup = gate.invalidateAndBlock()

        gate.complete(firstCleanup)
        gate.complete(secondCleanup)
        #expect(gate.beginOperation() == nil)

        gate.endOperation(oldOperation)
        #expect(gate.beginOperation() != nil)
    }

    @Test("Failed cleanup stays blocked until a verified retry completes")
    func failedCleanupRequiresVerifiedRetry() {
        let gate = OAuthCredentialOperationGate()
        let failedCleanup = gate.invalidateAndBlock()

        gate.fail(failedCleanup)
        #expect(gate.beginOperation() == nil)

        let retry = gate.invalidateAndBlock()
        gate.complete(retry)
        #expect(gate.beginOperation() != nil)
    }

    @Test("Credential cleanup times out instead of waiting forever for a network operation")
    func cleanupWaitHasTimeout() async throws {
        let gate = OAuthCredentialOperationGate()
        let hungOperation = try #require(gate.beginOperation())
        let cleanup = gate.invalidateAndBlock()

        await #expect(throws: OAuthCredentialOperationGateError.drainTimedOut) {
            try await gate.waitForInvalidatedOperations(
                before: cleanup,
                timeout: .milliseconds(10)
            )
        }

        #expect(gate.accepts(cleanup))
        #expect(gate.beginOperation() == nil)
        gate.fail(cleanup)
        gate.endOperation(hungOperation)
    }

    @Test("Cancelling credential cleanup stops its wait and keeps the provider blocked")
    func cancellingCleanupStopsWait() async throws {
        let gate = OAuthCredentialOperationGate()
        let hungOperation = try #require(gate.beginOperation())
        let cleanup = gate.invalidateAndBlock()
        let waiting = Task {
            try await gate.waitForInvalidatedOperations(
                before: cleanup,
                timeout: .seconds(30)
            )
        }

        await Task.yield()
        waiting.cancel()
        await #expect(throws: CancellationError.self) {
            try await waiting.value
        }

        #expect(gate.accepts(cleanup))
        #expect(gate.beginOperation() == nil)
        gate.fail(cleanup)
        gate.endOperation(hungOperation)
    }

    @Test("A manager with a test Keychain builds isolated Notion and Taskade services")
    @MainActor
    func customKeychainBuildsIsolatedProviderServices() throws {
        let keychain = KeychainService(service: "com.kirole.tests.provider-isolation.\(UUID().uuidString)")
        try keychain.saveNotionAccessToken("isolated-notion")
        try keychain.saveTaskadeTokens(accessToken: "isolated-taskade", refreshToken: "refresh")
        let manager = AuthManager(keychainService: keychain)

        #expect(manager.disconnectNotion())
        #expect(manager.disconnectTaskade())

        #expect(keychain.getNotionAccessToken() == nil)
        #expect(keychain.getTaskadeAccessToken() == nil)
        #expect(keychain.getTaskadeRefreshToken() == nil)
    }

    @Test("A failed first sign-out cleanup reopens a new authorization but rejects the old response")
    @MainActor
    func failedInitialSignOutCleanupReopensOnlyNewGeneration() async throws {
        let keychain = KeychainService(service: "com.kirole.tests.aborted-signout.\(UUID().uuidString)")
        let exchange = OAuthTokenRequestGate<NotionTokenResponse>()
        let service = NotionAuthService(
            keychainService: keychain,
            clientID: "notion-client",
            webAuthorization: { url, _ in
                try Self.callback(for: url, scheme: "kirole", host: "notion-callback")
            },
            tokenExchange: { _, _ in try await exchange.wait() }
        )
        let manager = AuthManager(keychainService: keychain, notionAuthService: service)
        manager.googleSyncStateResetOverride = {
            throw OAuthCredentialRaceTestError.firstSignOutCleanupFailed
        }

        let staleConnect = Task { @MainActor in try await manager.signInWithNotion() }
        await exchange.waitUntilStarted()
        await manager.signOut()

        #expect(service.credentialGate.beginOperation() == nil)

        exchange.resume(returning: NotionTokenResponse(
            accessToken: "late-notion-token",
            workspaceId: "workspace"
        ))
        await #expect(throws: NotionAuthError.operationInvalidated) {
            try await staleConnect.value
        }
        #expect(keychain.getNotionAccessToken() == nil)
        #expect(!manager.isNotionConnected)
        let retry = try service.beginCredentialOperation()
        #expect(service.credentialGate.accepts(retry))
        service.endCredentialOperation(retry)
    }

    @Test("Notion authorization returning after disconnect cannot restore credentials or manager state")
    @MainActor
    func notionAuthorizationCannotReturnAfterDisconnect() async throws {
        let keychain = KeychainService(service: "com.kirole.tests.notion-race.\(UUID().uuidString)")
        let exchange = OAuthTokenRequestGate<NotionTokenResponse>()
        let service = NotionAuthService(
            keychainService: keychain,
            clientID: "notion-client",
            webAuthorization: { url, _ in
                try Self.callback(for: url, scheme: "kirole", host: "notion-callback")
            },
            tokenExchange: { _, _ in try await exchange.wait() }
        )
        let manager = AuthManager(keychainService: keychain, notionAuthService: service)

        let connect = Task { @MainActor in try await manager.signInWithNotion() }
        await exchange.waitUntilStarted()
        #expect(manager.disconnectNotion())
        exchange.resume(returning: NotionTokenResponse(
            accessToken: "late-notion-token",
            workspaceId: "workspace"
        ))

        await #expect(throws: NotionAuthError.operationInvalidated) {
            try await connect.value
        }
        #expect(keychain.getNotionAccessToken() == nil)
        #expect(keychain.getNotionWorkspaceId() == nil)
        #expect(!manager.isNotionConnected)
    }

    @Test("Notion authorization failure returning after disconnect keeps credentials absent")
    @MainActor
    func notionAuthorizationFailureCannotReturnAfterDisconnect() async throws {
        let keychain = KeychainService(service: "com.kirole.tests.notion-failure-race.\(UUID().uuidString)")
        let exchange = OAuthTokenRequestGate<NotionTokenResponse>()
        let service = NotionAuthService(
            keychainService: keychain,
            clientID: "notion-client",
            webAuthorization: { url, _ in
                try Self.callback(for: url, scheme: "kirole", host: "notion-callback")
            },
            tokenExchange: { _, _ in try await exchange.wait() }
        )
        let manager = AuthManager(keychainService: keychain, notionAuthService: service)

        let connect = Task { @MainActor in try await manager.signInWithNotion() }
        await exchange.waitUntilStarted()
        #expect(manager.disconnectNotion())
        exchange.resume(throwing: OAuthCredentialRaceTestError.remoteFailure)

        await #expect(throws: OAuthCredentialRaceTestError.remoteFailure) {
            try await connect.value
        }
        #expect(keychain.getNotionAccessToken() == nil)
        #expect(!manager.isNotionConnected)
    }

    @Test("Taskade refresh returning after disconnect cannot recreate tokens")
    @MainActor
    func taskadeRefreshCannotReturnAfterDisconnect() async throws {
        let keychain = KeychainService(service: "com.kirole.tests.taskade-refresh-race.\(UUID().uuidString)")
        try keychain.saveTaskadeTokens(accessToken: "", refreshToken: "refresh-a")
        try keychain.clearTaskadeTokens()
        try keychain.saveTaskadeTokens(accessToken: "seed", refreshToken: "refresh-a")
        let refresh = OAuthTokenRequestGate<TaskadeTokenResponse>()
        let service = TaskadeAuthService(
            keychainService: keychain,
            clientID: "taskade-client",
            tokenRequest: { body in
                #expect(body["action"] == "refresh")
                return try await refresh.wait()
            }
        )

        let refreshTask = Task { @MainActor in
            try await service.forceRefreshAccessToken()
        }
        await refresh.waitUntilStarted()
        #expect(service.disconnect())
        refresh.resume(returning: TaskadeTokenResponse(
            accessToken: "late-taskade-token",
            refreshToken: "late-refresh-token"
        ))

        await #expect(throws: TaskadeAuthError.operationInvalidated) {
            try await refreshTask.value
        }
        #expect(keychain.getTaskadeAccessToken() == nil)
        #expect(keychain.getTaskadeRefreshToken() == nil)
    }

    @Test("Taskade connect returning after disconnect cannot publish connected")
    @MainActor
    func taskadeConnectCannotPublishAfterDisconnect() async throws {
        let keychain = KeychainService(service: "com.kirole.tests.taskade-connect-race.\(UUID().uuidString)")
        let exchange = OAuthTokenRequestGate<TaskadeTokenResponse>()
        let service = TaskadeAuthService(
            keychainService: keychain,
            clientID: "taskade-client",
            webAuthorization: { url, _ in
                try Self.callback(for: url, scheme: "kirole", host: "taskade-callback")
            },
            tokenRequest: { _ in try await exchange.wait() }
        )
        let manager = AuthManager(keychainService: keychain, taskadeAuthService: service)

        let connect = Task { @MainActor in try await manager.signInWithTaskade() }
        await exchange.waitUntilStarted()
        #expect(manager.disconnectTaskade())
        exchange.resume(returning: TaskadeTokenResponse(
            accessToken: "late-taskade-token",
            refreshToken: "late-refresh-token"
        ))

        await #expect(throws: TaskadeAuthError.operationInvalidated) {
            try await connect.value
        }
        #expect(keychain.getTaskadeAccessToken() == nil)
        #expect(keychain.getTaskadeRefreshToken() == nil)
        #expect(!manager.isTaskadeConnected)
    }

    @Test("Taskade authorization failure returning after disconnect cannot publish connected")
    @MainActor
    func taskadeAuthorizationFailureCannotPublishAfterDisconnect() async throws {
        let keychain = KeychainService(service: "com.kirole.tests.taskade-failure-race.\(UUID().uuidString)")
        let exchange = OAuthTokenRequestGate<TaskadeTokenResponse>()
        let service = TaskadeAuthService(
            keychainService: keychain,
            clientID: "taskade-client",
            webAuthorization: { url, _ in
                try Self.callback(for: url, scheme: "kirole", host: "taskade-callback")
            },
            tokenRequest: { _ in try await exchange.wait() }
        )
        let manager = AuthManager(keychainService: keychain, taskadeAuthService: service)

        let connect = Task { @MainActor in try await manager.signInWithTaskade() }
        await exchange.waitUntilStarted()
        #expect(manager.disconnectTaskade())
        exchange.resume(throwing: OAuthCredentialRaceTestError.remoteFailure)

        await #expect(throws: OAuthCredentialRaceTestError.remoteFailure) {
            try await connect.value
        }
        #expect(keychain.getTaskadeAccessToken() == nil)
        #expect(!manager.isTaskadeConnected)
    }

    @Test("Taskade refresh returning after sign out cannot recreate tokens")
    @MainActor
    func taskadeRefreshCannotReturnAfterSignOut() async throws {
        let keychain = KeychainService(service: "com.kirole.tests.taskade-signout-race.\(UUID().uuidString)")
        try keychain.saveTaskadeTokens(accessToken: "old-access", refreshToken: "old-refresh")
        let refresh = OAuthTokenRequestGate<TaskadeTokenResponse>()
        let service = TaskadeAuthService(
            keychainService: keychain,
            clientID: "taskade-client",
            tokenRequest: { _ in try await refresh.wait() }
        )
        let manager = AuthManager(keychainService: keychain, taskadeAuthService: service)
        Self.stubSignOutDependencies(on: manager)

        let refreshTask = Task { @MainActor in try await service.forceRefreshAccessToken() }
        await refresh.waitUntilStarted()
        let signOut = Task { @MainActor in await manager.signOut() }
        await Self.waitUntilBlocked(service.credentialGate)
        refresh.resume(returning: TaskadeTokenResponse(
            accessToken: "late-access",
            refreshToken: "late-refresh"
        ))

        await #expect(throws: TaskadeAuthError.operationInvalidated) {
            try await refreshTask.value
        }
        await signOut.value
        #expect(keychain.getTaskadeAccessToken() == nil)
        #expect(keychain.getTaskadeRefreshToken() == nil)
    }

    @Test("Provider gates stay blocked until global sign out has fully returned")
    @MainActor
    func providerGatesStayBlockedForEntireSignOut() async throws {
        let keychain = KeychainService(
            service: "com.kirole.tests.full-signout-window.\(UUID().uuidString)"
        )
        try keychain.saveNotionAccessToken("old-notion")
        try keychain.saveTaskadeTokens(accessToken: "old-taskade", refreshToken: "old-refresh")
        let notion = NotionAuthService(
            keychainService: keychain,
            clientID: "notion-client",
            webAuthorization: { url, _ in
                try Self.callback(for: url, scheme: "kirole", host: "notion-callback")
            },
            tokenExchange: { _, _ in
                NotionTokenResponse(accessToken: "new-notion", workspaceId: "workspace")
            }
        )
        let taskade = TaskadeAuthService(
            keychainService: keychain,
            clientID: "taskade-client",
            webAuthorization: { url, _ in
                try Self.callback(for: url, scheme: "kirole", host: "taskade-callback")
            },
            tokenRequest: { _ in
                TaskadeTokenResponse(accessToken: "new-taskade", refreshToken: "new-refresh")
            }
        )
        let manager = AuthManager(
            keychainService: keychain,
            notionAuthService: notion,
            taskadeAuthService: taskade
        )
        Self.stubSignOutDependencies(on: manager)
        let supabaseSignOut = OAuthTokenRequestGate<Void>()
        manager.supabaseSignOutOverride = { try await supabaseSignOut.wait() }

        let signOut = Task { @MainActor in await manager.signOut() }
        await supabaseSignOut.waitUntilStarted()

        await #expect(throws: NotionAuthError.operationInvalidated) {
            try await manager.signInWithNotion()
        }
        await #expect(throws: TaskadeAuthError.operationInvalidated) {
            try await manager.signInWithTaskade()
        }
        #expect(keychain.getNotionAccessToken() == nil)
        #expect(keychain.getTaskadeAccessToken() == nil)
        #expect(!manager.isNotionConnected)
        #expect(!manager.isTaskadeConnected)

        supabaseSignOut.resume(returning: ())
        await signOut.value
    }

    @Test("Todoist refresh returning after disconnect cannot recreate the token set")
    @MainActor
    func todoistRefreshCannotReturnAfterDisconnect() async throws {
        let configuration = try Self.todoistConfiguration()
        let store = TodoistMemoryTokenStore(tokens: TodoistTokenSet(
            accessToken: "old-access",
            refreshToken: "old-refresh",
            expiresAt: Date.distantPast,
            scope: "data:read_write"
        ))
        let response = OAuthTokenRequestGate<TodoistTokenResponse>()
        let gate = OAuthCredentialOperationGate()
        let credentials = TodoistCredentialManager(
            configuration: configuration,
            store: store,
            credentialGate: gate,
            tokenResponseLoader: { _ in try await response.wait() }
        )
        let auth = TodoistAuthService(
            configuration: configuration,
            credentialManager: credentials,
            credentialGate: gate
        )
        let manager = AuthManager(
            keychainService: KeychainService(
                service: "com.kirole.tests.todoist-refresh-race.\(UUID().uuidString)"
            )
        )
        manager.todoistComponentFactoryOverride = { (auth, credentials) }
        manager.todoistDisconnectSyncResetOverride = {}
        manager.todoistDisconnectProjectCleanupOverride = {}

        let refreshTask = Task {
            try await credentials.accessToken(forceRefresh: true)
        }
        await response.waitUntilStarted()
        let disconnectTask = Task { @MainActor in try await manager.disconnectTodoist() }
        await Self.waitUntilBlocked(gate)
        response.resume(returning: TodoistTokenResponse(
            accessToken: "late-access",
            refreshToken: "late-refresh",
            expiresIn: 3_600,
            scope: "data:read_write"
        ))

        await #expect(throws: TodoistAuthError.operationInvalidated) {
            try await refreshTask.value
        }
        try await disconnectTask.value
        #expect(await store.load() == nil)
        #expect(!manager.isTodoistConnected)
    }

    @Test("Todoist exchange returning after disconnect cannot save or publish connected")
    @MainActor
    func todoistExchangeCannotReturnAfterDisconnect() async throws {
        let fixture = try Self.todoistFixture()
        let manager = fixture.manager

        let connect = Task { @MainActor in try await manager.connectTodoist() }
        await fixture.response.waitUntilStarted()
        let disconnect = Task { @MainActor in try await manager.disconnectTodoist() }
        await Self.waitUntilBlocked(fixture.gate)
        fixture.response.resume(returning: TodoistTokenResponse(
            accessToken: "late-access",
            refreshToken: "late-refresh",
            expiresIn: 3_600,
            scope: "data:read_write"
        ))

        await #expect(throws: TodoistAuthError.operationInvalidated) {
            try await connect.value
        }
        try await disconnect.value
        #expect(await fixture.store.load() == nil)
        #expect(!manager.isTodoistConnected)
    }

    @Test("Todoist exchange failure returning after disconnect cannot publish connected")
    @MainActor
    func todoistExchangeFailureCannotPublishAfterDisconnect() async throws {
        let fixture = try Self.todoistFixture()
        let manager = fixture.manager

        let connect = Task { @MainActor in try await manager.connectTodoist() }
        await fixture.response.waitUntilStarted()
        let disconnect = Task { @MainActor in try await manager.disconnectTodoist() }
        await Self.waitUntilBlocked(fixture.gate)
        fixture.response.resume(throwing: OAuthCredentialRaceTestError.remoteFailure)

        await #expect(throws: OAuthCredentialRaceTestError.remoteFailure) {
            try await connect.value
        }
        try await disconnect.value
        #expect(await fixture.store.load() == nil)
        #expect(!manager.isTodoistConnected)
    }

    @Test("Todoist refresh returning after sign out cannot recreate the token set")
    @MainActor
    func todoistRefreshCannotReturnAfterSignOut() async throws {
        let configuration = try Self.todoistConfiguration()
        let store = TodoistMemoryTokenStore(tokens: TodoistTokenSet(
            accessToken: "old-access",
            refreshToken: "old-refresh",
            expiresAt: Date.distantPast,
            scope: "data:read_write"
        ))
        let response = OAuthTokenRequestGate<TodoistTokenResponse>()
        let gate = OAuthCredentialOperationGate()
        let credentials = TodoistCredentialManager(
            configuration: configuration,
            store: store,
            credentialGate: gate,
            tokenResponseLoader: { _ in try await response.wait() }
        )
        let auth = TodoistAuthService(
            configuration: configuration,
            credentialManager: credentials,
            credentialGate: gate
        )
        let manager = AuthManager(
            keychainService: KeychainService(
                service: "com.kirole.tests.todoist-signout-race.\(UUID().uuidString)"
            )
        )
        manager.todoistComponentFactoryOverride = { (auth, credentials) }
        manager.todoistDisconnectSyncResetOverride = {}
        manager.todoistDisconnectProjectCleanupOverride = {}
        Self.stubSignOutDependencies(on: manager)
        manager.taskProviderSignOutCleanupOverride = {
            try await manager.disconnectTodoist()
        }

        let refreshTask = Task { @MainActor in try await manager.getTodoistAccessToken() }
        await response.waitUntilStarted()
        let signOut = Task { @MainActor in await manager.signOut() }
        await Self.waitUntilBlocked(gate)
        response.resume(returning: TodoistTokenResponse(
            accessToken: "late-access",
            refreshToken: "late-refresh",
            expiresIn: 3_600,
            scope: "data:read_write"
        ))

        await #expect(throws: TodoistAuthError.operationInvalidated) {
            try await refreshTask.value
        }
        await signOut.value
        #expect(await store.load() == nil)
        #expect(!manager.isTodoistConnected)
    }

    @Test("Todoist keeps its blocked component alive until global sign out returns")
    @MainActor
    func todoistGateStaysStableForEntireSignOut() async throws {
        let fixture = try Self.todoistFixture()
        let manager = fixture.manager
        manager.todoistAuthService = try #require(manager.todoistComponentFactoryOverride?().auth)
        manager.todoistCredentialManager = try #require(
            manager.todoistComponentFactoryOverride?().credentials
        )
        manager.isTodoistConnected = true
        Self.stubSignOutDependencies(on: manager)
        manager.taskProviderSignOutCleanupOverride = {
            try await manager.disconnectTodoist()
        }
        let supabaseSignOut = OAuthTokenRequestGate<Void>()
        manager.supabaseSignOutOverride = { try await supabaseSignOut.wait() }

        let signOut = Task { @MainActor in await manager.signOut() }
        await supabaseSignOut.waitUntilStarted()

        #expect(manager.todoistAuthService != nil)
        await #expect(throws: TodoistAuthError.operationInvalidated) {
            try await manager.connectTodoist()
        }
        #expect(await fixture.store.load() == nil)
        #expect(!manager.isTodoistConnected)

        supabaseSignOut.resume(returning: ())
        await signOut.value
    }

    @Test("Todoist publishes disconnected as soon as credential deletion is verified")
    @MainActor
    func todoistPublishesDisconnectedBeforeLaterCleanupFailure() async throws {
        let fixture = try Self.todoistFixture(tokens: TodoistTokenSet(
            accessToken: "old-access",
            refreshToken: "old-refresh",
            expiresAt: Date.distantFuture,
            scope: "data:read_write"
        ))
        let manager = fixture.manager
        manager.isTodoistConnected = true
        manager.todoistDisconnectSyncResetOverride = {
            throw OAuthCredentialRaceTestError.remoteFailure
        }

        await #expect(throws: OAuthCredentialRaceTestError.remoteFailure) {
            try await manager.disconnectTodoist()
        }

        #expect(await fixture.store.load() == nil)
        #expect(!manager.isTodoistConnected)
    }

    private static func callback(for authorizationURL: URL, scheme: String, host: String) throws -> URL {
        let state = try #require(
            URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "state" })?
                .value
        )
        return try #require(URL(string: "\(scheme)://\(host)?code=test-code&state=\(state)"))
    }

    private static func todoistConfiguration() throws -> TodoistOAuthConfiguration {
        try TodoistOAuthConfiguration(
            clientID: "https://kirole.example/oauth/todoist-client.json",
            redirectURI: URL(string: "https://kirole.example/oauth/todoist-callback")!
        )
    }

    @MainActor
    private static func todoistFixture(
        tokens: TodoistTokenSet? = nil
    ) throws -> (
        manager: AuthManager,
        store: TodoistMemoryTokenStore,
        response: OAuthTokenRequestGate<TodoistTokenResponse>,
        gate: OAuthCredentialOperationGate
    ) {
        let configuration = try todoistConfiguration()
        let store = TodoistMemoryTokenStore(tokens: tokens)
        let response = OAuthTokenRequestGate<TodoistTokenResponse>()
        let gate = OAuthCredentialOperationGate()
        let credentials = TodoistCredentialManager(
            configuration: configuration,
            store: store,
            credentialGate: gate,
            tokenResponseLoader: { _ in try await response.wait() }
        )
        let auth = TodoistAuthService(
            configuration: configuration,
            credentialManager: credentials,
            credentialGate: gate,
            webAuthorization: { url in
                try callback(
                    for: url,
                    scheme: "https",
                    host: "kirole.example/oauth/todoist-callback"
                )
            }
        )
        let manager = AuthManager(
            keychainService: KeychainService(
                service: "com.kirole.tests.todoist-exchange-race.\(UUID().uuidString)"
            )
        )
        manager.todoistComponentFactoryOverride = { (auth, credentials) }
        manager.todoistDisconnectSyncResetOverride = {}
        manager.todoistDisconnectProjectCleanupOverride = {}
        return (manager, store, response, gate)
    }

    @MainActor
    private static func stubSignOutDependencies(on manager: AuthManager) {
        manager.googleSyncStateResetOverride = {}
        manager.customCompanionSignOutCleanup = {}
        manager.taskProviderSignOutCleanupOverride = {}
        manager.providerDataSignOutCleanupOverride = {}
        manager.localCredentialSignOutCleanupOverride = {}
        manager.supabaseSignOutOverride = {}
    }

    private static func waitUntilBlocked(_ gate: OAuthCredentialOperationGate) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while clock.now < deadline, let observation = gate.beginOperation() {
            gate.endOperation(observation)
            try? await Task.sleep(for: .milliseconds(1))
        }
        if let observation = gate.beginOperation() {
            gate.endOperation(observation)
            Issue.record("Credential gate did not block within five seconds")
        }
    }
}

private actor OAuthTokenRequestGate<Value: Sendable> {
    private var started = false
    private var responseContinuation: CheckedContinuation<Value, Error>?

    func wait() async throws -> Value {
        started = true
        return try await withCheckedThrowingContinuation { continuation in
            responseContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while !started, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        if !started {
            Issue.record("Injected OAuth request did not start within five seconds")
        }
    }

    nonisolated func resume(returning value: Value) {
        Task { await resumeOnActor(returning: value) }
    }

    nonisolated func resume(throwing error: any Error & Sendable) {
        Task { await resumeOnActor(throwing: error) }
    }

    private func resumeOnActor(returning value: Value) {
        responseContinuation?.resume(returning: value)
        responseContinuation = nil
    }

    private func resumeOnActor(throwing error: any Error & Sendable) {
        responseContinuation?.resume(throwing: error)
        responseContinuation = nil
    }
}

private actor TodoistMemoryTokenStore: TodoistTokenStoring {
    private var tokens: TodoistTokenSet?

    init(tokens: TodoistTokenSet?) {
        self.tokens = tokens
    }

    func load() -> TodoistTokenSet? { tokens }
    func save(_ tokens: TodoistTokenSet) { self.tokens = tokens }
    func clear() { tokens = nil }
}

private enum OAuthCredentialRaceTestError: Error, Equatable {
    case remoteFailure
    case firstSignOutCleanupFailed
}
