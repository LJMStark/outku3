import Foundation
import Testing
@testable import KiroleFeature

@Suite("TickTick OAuth credential races", .serialized)
struct TickTickAuthRaceTests {
    @Test("A stale start response cannot persist a pending authorization")
    func staleStartDoesNotPersistPendingAuthorization() async throws {
        let gate = OAuthCredentialOperationGate()
        let backend = TickTickStartBarrierBackend()
        let pendingStore = TickTickRacePendingStore()
        let manager = makeManager(
            gate: gate,
            backend: backend,
            tokenStore: TickTickRaceTokenStore(),
            pendingStore: pendingStore
        )
        let operation = try #require(gate.beginOperation())
        let authorization = Task {
            defer { gate.endOperation(operation) }
            return try await manager.startAuthorization(operation: operation)
        }

        await backend.waitUntilStartBegins()
        let cleanup = gate.invalidateAndBlock()
        await backend.releaseStart()

        await #expect(throws: TickTickAuthError.credentialOperationInvalidated) {
            _ = try await authorization.value
        }
        #expect(await pendingStore.saveCount() == 0)
        gate.complete(cleanup)
    }

    @Test("A stale claim response cannot persist a delivery or acknowledge it")
    func staleClaimDoesNotAdvanceDelivery() async throws {
        let gate = OAuthCredentialOperationGate()
        let backend = TickTickClaimBarrierBackend()
        let pendingStore = TickTickRacePendingStore(value: .fixture(delivery: nil))
        let tokenStore = TickTickRaceTokenStore()
        let manager = makeManager(
            gate: gate,
            backend: backend,
            tokenStore: tokenStore,
            pendingStore: pendingStore
        )
        let operation = try #require(gate.beginOperation())
        let claim = Task {
            defer { gate.endOperation(operation) }
            return try await manager.claimAndAcknowledge(
                attemptID: "attempt-1",
                operation: operation
            )
        }

        await backend.waitUntilClaimBegins()
        let cleanup = gate.invalidateAndBlock()
        await backend.releaseClaim()

        await #expect(throws: TickTickAuthError.credentialOperationInvalidated) {
            _ = try await claim.value
        }
        #expect(await pendingStore.load()?.delivery == nil)
        #expect(await backend.acknowledgementCount() == 0)
        #expect(await tokenStore.load() == nil)
        gate.complete(cleanup)
    }

    @Test("A stale acknowledgement cannot save a connected token")
    func staleAcknowledgementDoesNotSaveToken() async throws {
        let gate = OAuthCredentialOperationGate()
        let backend = TickTickAcknowledgementBarrierBackend()
        let delivery = TickTickTokenDelivery.fixture
        let pendingStore = TickTickRacePendingStore(value: .fixture(delivery: delivery))
        let tokenStore = TickTickRaceTokenStore()
        let manager = makeManager(
            gate: gate,
            backend: backend,
            tokenStore: tokenStore,
            pendingStore: pendingStore
        )
        let operation = try #require(gate.beginOperation())
        let claim = Task {
            defer { gate.endOperation(operation) }
            return try await manager.claimAndAcknowledge(
                attemptID: "attempt-1",
                operation: operation
            )
        }

        await backend.waitUntilAcknowledgementBegins()
        let cleanup = gate.invalidateAndBlock()
        await backend.releaseAcknowledgement()

        await #expect(throws: TickTickAuthError.credentialOperationInvalidated) {
            _ = try await claim.value
        }
        #expect(await tokenStore.load() == nil)
        #expect(await pendingStore.load()?.delivery == delivery)
        gate.complete(cleanup)
    }

    @Test("Cleanup drains an in-flight token save before clearing Keychain")
    func cleanupDrainsTokenSaveBeforeClear() async throws {
        let gate = OAuthCredentialOperationGate()
        let tokenStore = TickTickRaceTokenStore(blockBeforeSave: true)
        let pendingStore = TickTickRacePendingStore(value: .fixture(delivery: .fixture))
        let manager = makeManager(
            gate: gate,
            backend: TickTickImmediateBackend(),
            tokenStore: tokenStore,
            pendingStore: pendingStore
        )
        let operation = try #require(gate.beginOperation())
        let claim = Task {
            defer { gate.endOperation(operation) }
            return try await manager.claimAndAcknowledge(
                attemptID: "attempt-1",
                operation: operation
            )
        }

        await tokenStore.waitUntilSaveBegins()
        let cleanup = gate.invalidateAndBlock()
        let clearing = Task {
            try await gate.waitForInvalidatedOperations(before: cleanup)
            await tokenStore.clear()
        }
        for _ in 0..<20 { await Task.yield() }
        #expect(await tokenStore.clearCount() == 0)

        await tokenStore.releaseSave()
        await #expect(throws: TickTickAuthError.credentialOperationInvalidated) {
            _ = try await claim.value
        }
        try await clearing.value

        #expect(await tokenStore.load() == nil)
        gate.complete(cleanup)
    }

    @Test("Same-account reconnect rejects the old manager publication")
    @MainActor
    func sameAccountABARejectsOldConnectedPublication() async throws {
        let authManager = AuthManager(
            keychainService: KeychainService(
                service: "com.kirole.tests.ticktick-race.\(UUID().uuidString)"
            )
        )
        let components = try makeComponents(gate: authManager.tickTickCredentialOperationGate)
        let oldOperation = try #require(
            authManager.tickTickCredentialOperationGate.beginOperation()
        )
        let cleanup = authManager.beginTickTickCredentialCleanupForSignOut()

        #expect(throws: TickTickAuthError.credentialOperationInvalidated) {
            try authManager.publishTickTickConnection(
                .fixture,
                region: .international,
                authService: components.auth,
                credentialManager: components.credentials,
                operation: oldOperation
            )
        }
        #expect(!authManager.isTickTickConnected)
        #expect(authManager.tickTickRegion == nil)

        authManager.completeTickTickCredentialCleanupForSignOut(cleanup)
        #expect(authManager.tickTickCredentialOperationGate.beginOperation() == nil)
        authManager.tickTickCredentialOperationGate.endOperation(oldOperation)

        let newOperation = try #require(
            authManager.tickTickCredentialOperationGate.beginOperation()
        )
        try authManager.publishTickTickConnection(
            .fixture,
            region: .international,
            authService: components.auth,
            credentialManager: components.credentials,
            operation: newOperation
        )
        authManager.tickTickCredentialOperationGate.endOperation(newOperation)

        #expect(authManager.isTickTickConnected)
        #expect(authManager.tickTickRegion == .international)
        UserDefaults.standard.removeObject(forKey: AuthManager.tickTickRegionKey)
    }

    @Test("An older sign-out completion cannot unblock a newer cleanup")
    @MainActor
    func staleSignOutCompletionDoesNotUnblockNewCleanup() {
        let authManager = AuthManager(
            keychainService: KeychainService(
                service: "com.kirole.tests.ticktick-cleanup.\(UUID().uuidString)"
            )
        )
        let first = authManager.beginTickTickCredentialCleanupForSignOut()
        let second = authManager.beginTickTickCredentialCleanupForSignOut()

        authManager.completeTickTickCredentialCleanupForSignOut(first)
        #expect(authManager.tickTickCredentialOperationGate.beginOperation() == nil)

        authManager.completeTickTickCredentialCleanupForSignOut(second)
        #expect(authManager.tickTickCredentialOperationGate.beginOperation() != nil)
    }

    @Test("Disconnect cancels a first connection before it is published")
    @MainActor
    func disconnectCancelsStagedFirstConnection() throws {
        let authManager = AuthManager(
            keychainService: KeychainService(
                service: "com.kirole.tests.ticktick-staged.\(UUID().uuidString)"
            )
        )
        let cancellation = TickTickAuthorizationCancellationSpy()
        let components = try makeComponents(
            gate: authManager.tickTickCredentialOperationGate,
            authorizationCancellation: { cancellation.record() }
        )
        authManager.stageTickTickConnection(
            authService: components.auth,
            credentialManager: components.credentials,
            ownerUserID: "user-1"
        )

        let cleanup = authManager.beginTickTickCredentialCleanupForSignOut()

        #expect(cancellation.callCount == 1)
        authManager.completeTickTickCredentialCleanupForSignOut(cleanup)
    }

    @Test("An aborted sign out drains and erases an old token save before reopening")
    @MainActor
    func abortedSignOutClearsOldSaveBeforeReopening() async throws {
        let authManager = AuthManager(
            keychainService: KeychainService(
                service: "com.kirole.tests.ticktick-abort.\(UUID().uuidString)"
            )
        )
        let tokenStore = TickTickRaceTokenStore(blockBeforeSave: true)
        let pendingStore = TickTickRacePendingStore()
        authManager.tickTickLocalStateCleaner = TickTickLocalStateCleaner(
            makeTokenStore: { _ in tokenStore },
            makePendingStore: { _ in pendingStore },
            resetSyncState: { _ in },
            clearProjectSelection: { _ in }
        )
        let operation = try #require(
            authManager.tickTickCredentialOperationGate.beginOperation()
        )
        let oldSave = Task {
            defer { authManager.tickTickCredentialOperationGate.endOperation(operation) }
            await tokenStore.save(.fixture)
            guard authManager.tickTickCredentialOperationGate.accepts(operation) else {
                throw TickTickAuthError.credentialOperationInvalidated
            }
        }

        await tokenStore.waitUntilSaveBegins()
        let cleanup = authManager.beginTickTickCredentialCleanupForSignOut()
        let abort = Task { @MainActor in
            try await authManager.finishAbortedTickTickSignOut(cleanup)
        }
        for _ in 0..<20 { await Task.yield() }
        #expect(await tokenStore.clearCount() == 0)

        await tokenStore.releaseSave()
        await #expect(throws: TickTickAuthError.credentialOperationInvalidated) {
            try await oldSave.value
        }
        try await abort.value

        #expect(await tokenStore.load() == nil)
        #expect(authManager.tickTickCredentialOperationGate.beginOperation() != nil)
    }

    @Test("A staged acknowledgement delivery is disconnected during cleanup")
    @MainActor
    func stagedDeliveryIsDisconnectedDuringCleanup() async throws {
        let authManager = AuthManager(
            keychainService: KeychainService(
                service: "com.kirole.tests.ticktick-delivery-cleanup.\(UUID().uuidString)"
            )
        )
        let backend = TickTickCompletedDeliveryBackend()
        let tokenStore = TickTickRaceTokenStore()
        let pendingStore = TickTickRacePendingStore(value: .fixture(delivery: .fixture))
        let credentials = makeManager(
            gate: authManager.tickTickCredentialOperationGate,
            backend: backend,
            tokenStore: tokenStore,
            pendingStore: pendingStore
        )
        let components = try makeComponents(
            gate: authManager.tickTickCredentialOperationGate,
            credentials: credentials
        )
        authManager.stageTickTickConnection(
            authService: components.auth,
            credentialManager: credentials,
            ownerUserID: "user-1"
        )
        authManager.tickTickLocalStateCleaner = TickTickLocalStateCleaner(
            makeTokenStore: { _ in tokenStore },
            makePendingStore: { _ in pendingStore },
            resetSyncState: { _ in },
            clearProjectSelection: { _ in }
        )

        let cleanup = authManager.beginTickTickCredentialCleanupForSignOut()
        try await authManager.disconnectTickTick(preparedCleanup: cleanup)

        #expect(await backend.disconnectedConnectionIDs() == ["same-account"])
        #expect(await pendingStore.load() == nil)
    }

    @Test("Restore reports a cross-user credential that Keychain cannot erase")
    func crossUserDeletionFailureIsNotSwallowed() async throws {
        let gate = OAuthCredentialOperationGate()
        let tokenStore = TickTickUnclearableTokenStore(value: TickTickTokenSet(
            accessToken: "old-user-token",
            expiresAt: nil,
            scope: "tasks:read",
            accountID: "old-account",
            region: .international,
            ownerUserID: "user-2"
        ))
        let manager = makeManager(
            gate: gate,
            backend: TickTickImmediateBackend(),
            tokenStore: tokenStore,
            pendingStore: TickTickRacePendingStore()
        )
        let operation = try #require(gate.beginOperation())
        defer { gate.endOperation(operation) }

        await #expect(throws: TickTickAuthError.credentialDeletionFailed) {
            _ = try await manager.isConnected(operation: operation)
        }
        #expect(await tokenStore.load() != nil)
    }

    private func makeManager(
        gate: OAuthCredentialOperationGate,
        backend: any TickTickOAuthBackendServing,
        tokenStore: any TickTickTokenStoring,
        pendingStore: any TickTickPendingAuthorizationStoring
    ) -> TickTickCredentialManager {
        TickTickCredentialManager(
            region: .international,
            ownerUserID: "user-1",
            backend: backend,
            tokenStore: tokenStore,
            pendingStore: pendingStore,
            operationGate: gate
        )
    }

    @MainActor
    private func makeComponents(
        gate: OAuthCredentialOperationGate,
        credentials suppliedCredentials: TickTickCredentialManager? = nil,
        authorizationCancellation: @escaping @MainActor () -> Void = {}
    ) throws -> (auth: TickTickAuthService, credentials: TickTickCredentialManager) {
        let configuration = try TickTickOAuthConfiguration(
            backendEndpoint: URL(string: "https://api.kirole.example/ticktick-oauth")!,
            returnURI: URL(string: "https://kirole.example/ticktick-return")!,
            region: .international,
            backendAPIKey: "public-key"
        )
        let credentials = suppliedCredentials ?? makeManager(
                gate: gate,
                backend: TickTickImmediateBackend(),
                tokenStore: TickTickRaceTokenStore(),
                pendingStore: TickTickRacePendingStore()
            )
        return (
            TickTickAuthService(
                configuration: configuration,
                credentialManager: credentials,
                operationGate: gate,
                authorizationCancellation: authorizationCancellation
            ),
            credentials
        )
    }
}

@MainActor
private final class TickTickAuthorizationCancellationSpy {
    private(set) var callCount = 0
    func record() { callCount += 1 }
}

private actor TickTickRacePendingStore: TickTickPendingAuthorizationStoring {
    private var value: TickTickPendingAuthorization?
    private var saves = 0

    init(value: TickTickPendingAuthorization? = nil) {
        self.value = value
    }

    func load() -> TickTickPendingAuthorization? { value }

    func save(_ pending: TickTickPendingAuthorization) {
        value = pending
        saves += 1
    }

    func clear() { value = nil }
    func saveCount() -> Int { saves }
}

private actor TickTickRaceTokenStore: TickTickTokenStoring {
    private var value: TickTickTokenSet?
    private var saveStarted = false
    private var saveStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var saveRelease: CheckedContinuation<Void, Never>?
    private var clears = 0
    private let blockBeforeSave: Bool

    init(blockBeforeSave: Bool = false) {
        self.blockBeforeSave = blockBeforeSave
    }

    func load() -> TickTickTokenSet? { value }

    func save(_ tokens: TickTickTokenSet) async {
        if blockBeforeSave {
            saveStarted = true
            let waiters = saveStartWaiters
            saveStartWaiters.removeAll(keepingCapacity: true)
            waiters.forEach { $0.resume() }
            await withCheckedContinuation { saveRelease = $0 }
        }
        value = tokens
    }

    func clear() {
        value = nil
        clears += 1
    }

    func waitUntilSaveBegins() async {
        guard !saveStarted else { return }
        await withCheckedContinuation { saveStartWaiters.append($0) }
    }

    func releaseSave() {
        let continuation = saveRelease
        saveRelease = nil
        continuation?.resume()
    }

    func clearCount() -> Int { clears }
}

private actor TickTickUnclearableTokenStore: TickTickTokenStoring {
    private var value: TickTickTokenSet?

    init(value: TickTickTokenSet?) { self.value = value }
    func load() -> TickTickTokenSet? { value }
    func save(_ tokens: TickTickTokenSet) { value = tokens }
    func clear() {}
}

private actor TickTickStartBarrierBackend: TickTickOAuthBackendServing {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var release: CheckedContinuation<Void, Never>?

    func start(region: TickTickRegion) async throws -> TickTickAuthorizationStart {
        started = true
        let waiters = startWaiters
        startWaiters.removeAll(keepingCapacity: true)
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { release = $0 }
        return .fixture
    }

    func waitUntilStartBegins() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func releaseStart() {
        let continuation = release
        release = nil
        continuation?.resume()
    }

    func claim(attemptID: String, claimSecret: String) async throws -> TickTickTokenDelivery { .fixture }
    func acknowledge(attemptID: String, claimSecret: String, deliveryID: String) async throws {}
    func cancel(attemptID: String, claimSecret: String) async throws {}
    func disconnect(connectionID: String) async throws {}
}

private actor TickTickClaimBarrierBackend: TickTickOAuthBackendServing {
    private var started = false
    private var claimWaiters: [CheckedContinuation<Void, Never>] = []
    private var release: CheckedContinuation<Void, Never>?
    private var acknowledgements = 0

    func start(region: TickTickRegion) async throws -> TickTickAuthorizationStart { .fixture }

    func claim(attemptID: String, claimSecret: String) async throws -> TickTickTokenDelivery {
        started = true
        let waiters = claimWaiters
        claimWaiters.removeAll(keepingCapacity: true)
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { release = $0 }
        return .fixture
    }

    func acknowledge(attemptID: String, claimSecret: String, deliveryID: String) async throws {
        acknowledgements += 1
    }

    func waitUntilClaimBegins() async {
        guard !started else { return }
        await withCheckedContinuation { claimWaiters.append($0) }
    }

    func releaseClaim() {
        let continuation = release
        release = nil
        continuation?.resume()
    }

    func acknowledgementCount() -> Int { acknowledgements }
    func cancel(attemptID: String, claimSecret: String) async throws {}
    func disconnect(connectionID: String) async throws {}
}

private actor TickTickAcknowledgementBarrierBackend: TickTickOAuthBackendServing {
    private var started = false
    private var acknowledgementWaiters: [CheckedContinuation<Void, Never>] = []
    private var release: CheckedContinuation<Void, Never>?

    func start(region: TickTickRegion) async throws -> TickTickAuthorizationStart { .fixture }
    func claim(attemptID: String, claimSecret: String) async throws -> TickTickTokenDelivery { .fixture }

    func acknowledge(attemptID: String, claimSecret: String, deliveryID: String) async throws {
        started = true
        let waiters = acknowledgementWaiters
        acknowledgementWaiters.removeAll(keepingCapacity: true)
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { release = $0 }
    }

    func waitUntilAcknowledgementBegins() async {
        guard !started else { return }
        await withCheckedContinuation { acknowledgementWaiters.append($0) }
    }

    func releaseAcknowledgement() {
        let continuation = release
        release = nil
        continuation?.resume()
    }

    func cancel(attemptID: String, claimSecret: String) async throws {}
    func disconnect(connectionID: String) async throws {}
}

private actor TickTickImmediateBackend: TickTickOAuthBackendServing {
    func start(region: TickTickRegion) async throws -> TickTickAuthorizationStart { .fixture }
    func claim(attemptID: String, claimSecret: String) async throws -> TickTickTokenDelivery { .fixture }
    func acknowledge(attemptID: String, claimSecret: String, deliveryID: String) async throws {}
    func cancel(attemptID: String, claimSecret: String) async throws {}
    func disconnect(connectionID: String) async throws {}
}

private actor TickTickCompletedDeliveryBackend: TickTickOAuthBackendServing {
    private var disconnectedIDs: [String] = []

    func start(region: TickTickRegion) async throws -> TickTickAuthorizationStart { .fixture }
    func claim(attemptID: String, claimSecret: String) async throws -> TickTickTokenDelivery { .fixture }
    func acknowledge(attemptID: String, claimSecret: String, deliveryID: String) async throws {}
    func cancel(attemptID: String, claimSecret: String) async throws {
        throw TickTickAuthError.authorizationConflict
    }
    func disconnect(connectionID: String) async throws {
        disconnectedIDs.append(connectionID)
    }
    func disconnectedConnectionIDs() -> [String] { disconnectedIDs }
}

private extension TickTickPendingAuthorization {
    static func fixture(delivery: TickTickTokenDelivery?) -> Self {
        TickTickPendingAuthorization(
            attemptID: "attempt-1",
            claimSecret: "claim-secret",
            region: .international,
            ownerUserID: "user-1",
            expiresAt: Date().addingTimeInterval(600),
            delivery: delivery
        )
    }
}

private extension TickTickAuthorizationStart {
    static let fixture = TickTickAuthorizationStart(
        authorizationURL: URL(string: "https://ticktick.com/oauth/authorize")!,
        pending: .fixture(delivery: nil)
    )
}

private extension TickTickTokenDelivery {
    static let fixture = TickTickTokenDelivery(
        deliveryID: "delivery-1",
        tokens: .fixture
    )
}

private extension TickTickTokenSet {
    static let fixture = TickTickTokenSet(
        accessToken: "token",
        expiresAt: nil,
        scope: "tasks:read",
        accountID: "same-account",
        region: .international,
        ownerUserID: "user-1"
    )
}
