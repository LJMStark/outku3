import Foundation

struct TickTickLocalStateCleaner: Sendable {
    private let makeTokenStore: @Sendable (TickTickRegion) -> any TickTickTokenStoring
    private let makePendingStore: @Sendable (TickTickRegion) -> any TickTickPendingAuthorizationStoring
    private let resetSyncState: @Sendable (TickTickRegion) async throws -> Void
    private let clearProjectSelection: @Sendable (TickTickRegion) async throws -> Void

    static let live = TickTickLocalStateCleaner(
        makeTokenStore: { TickTickKeychainTokenStore(region: $0) },
        makePendingStore: { TickTickPendingAuthorizationStore(region: $0) },
        resetSyncState: { try await TickTickSyncEngine(region: $0).reset() },
        clearProjectSelection: { region in
            let store = ProviderProjectSelectionStore.shared
            let key = ProviderProjectSelectionKey.tickTick(region)
            await store.clear(key)
            guard await store.selectedProjectIDs(for: key).isEmpty else {
                throw TickTickAuthError.credentialDeletionFailed
            }
        }
    )

    init(
        makeTokenStore: @escaping @Sendable (TickTickRegion) -> any TickTickTokenStoring,
        makePendingStore: @escaping @Sendable (TickTickRegion) -> any TickTickPendingAuthorizationStoring,
        resetSyncState: @escaping @Sendable (TickTickRegion) async throws -> Void,
        clearProjectSelection: @escaping @Sendable (TickTickRegion) async throws -> Void
    ) {
        self.makeTokenStore = makeTokenStore
        self.makePendingStore = makePendingStore
        self.resetSyncState = resetSyncState
        self.clearProjectSelection = clearProjectSelection
    }

    func clearAll(regions: [TickTickRegion] = TickTickRegion.allCases) async throws {
        var firstError: Error?
        for region in regions {
            let tokenStore = makeTokenStore(region)
            do {
                try await tokenStore.clear()
                guard try await tokenStore.load() == nil else {
                    throw TickTickAuthError.credentialDeletionFailed
                }
            } catch {
                firstError = firstError ?? error
            }

            let pendingStore = makePendingStore(region)
            do {
                try await pendingStore.clear()
                guard try await pendingStore.load() == nil else {
                    throw TickTickAuthError.credentialDeletionFailed
                }
            } catch {
                firstError = firstError ?? error
            }

            do {
                try await resetSyncState(region)
            } catch {
                firstError = firstError ?? error
            }

            do {
                try await clearProjectSelection(region)
            } catch {
                firstError = firstError ?? error
            }
        }
        if let firstError { throw firstError }
    }
}

@MainActor
extension AuthManager {
    public func connectTickTick(region: TickTickRegion) async throws -> TickTickTokenSet {
        guard IntegrationType.tickTick.isAvailable else {
            throw TickTickAuthError.secureBackendRequired
        }
        guard cloudWritableUserId != nil else {
            throw TickTickAuthError.kiroleSignInRequired
        }
        guard region == .international else {
            throw TickTickAuthError.unsupportedRegion
        }
        let operation = try beginTickTickCredentialOperation()
        defer { tickTickCredentialOperationGate.endOperation(operation) }
        let components = try makeTickTickComponents(region: region)
        stageTickTickConnection(
            authService: components.auth,
            credentialManager: components.credentials,
            ownerUserID: cloudWritableUserId
        )
        let credentials: TickTickTokenSet
        do {
            credentials = try await components.auth.authorize(operation: operation)
        } catch {
            if tickTickCredentialOperationGate.accepts(operation) {
                discardStagedTickTickConnection(authService: components.auth)
            }
            throw error
        }
        try publishTickTickConnection(
            credentials,
            region: region,
            authService: components.auth,
            credentialManager: components.credentials,
            operation: operation
        )
        return credentials
    }

    public func getTickTickCredentials() async throws -> TickTickTokenSet {
        guard let region = tickTickRegion else {
            throw TickTickAuthError.notAuthenticated
        }
        let operation = try beginTickTickCredentialOperation()
        defer { tickTickCredentialOperationGate.endOperation(operation) }
        let components = try makeTickTickComponents(region: region)
        let credentials = try await components.credentials.credentials(operation: operation)
        try validateTickTickCredentialOperation(operation)
        tickTickAuthService = components.auth
        tickTickCredentialManager = components.credentials
        tickTickCredentialOwnerUserID = credentials.ownerUserID
        return credentials
    }

    public func disconnectTickTick() async throws {
        let cleanup = beginTickTickCredentialCleanupForSignOut()
        try await disconnectTickTick(preparedCleanup: cleanup)
    }

    func beginTickTickCredentialCleanupForSignOut() -> OAuthCredentialCleanupTicket {
        let cleanup = tickTickCredentialOperationGate.invalidateAndBlock()
        tickTickAuthService?.cancelCurrentAuthorization()
        return cleanup
    }

    func completeTickTickCredentialCleanupForSignOut(
        _ cleanup: OAuthCredentialCleanupTicket
    ) {
        tickTickCredentialOperationGate.complete(cleanup)
    }

    func finishAbortedTickTickSignOut(
        _ cleanup: OAuthCredentialCleanupTicket
    ) async throws {
        try await disconnectTickTick(preparedCleanup: cleanup)
    }

    func disconnectTickTick(
        preparedCleanup cleanup: OAuthCredentialCleanupTicket
    ) async throws {
        var cleanupFinished = false
        defer {
            if !cleanupFinished { tickTickCredentialOperationGate.fail(cleanup) }
        }
        try await tickTickCredentialOperationGate.waitForInvalidatedOperations(before: cleanup)
        try validateTickTickCleanup(cleanup)

        var serverCleanupError: Error?
        if let credentials = tickTickCredentialManager {
            do {
                try await credentials.disconnect()
            } catch {
                serverCleanupError = error
            }
        } else if let region = tickTickRegion {
            do {
                let components = try makeTickTickComponents(region: region)
                try await components.credentials.disconnect()
            } catch {
                serverCleanupError = error
            }
        }
        try validateTickTickCleanup(cleanup)

        try await tickTickLocalStateCleaner.clearAll()
        try validateTickTickCleanup(cleanup)

        UserDefaults.standard.removeObject(forKey: Self.tickTickRegionKey)
        tickTickAuthService = nil
        tickTickCredentialManager = nil
        tickTickCredentialOwnerUserID = nil
        tickTickRegion = nil
        isTickTickConnected = false

        cleanupFinished = true
        tickTickCredentialOperationGate.complete(cleanup)
        if serverCleanupError != nil { throw TickTickAuthError.serverCleanupPending }
    }

    func restoreTaskProviderConnections(
        tickTickIsAvailable: Bool = IntegrationType.tickTick.isAvailable
    ) async throws {
        if let components = try? makeTodoistComponents() {
            todoistAuthService = components.auth
            todoistCredentialManager = components.credentials
            isTodoistConnected = await components.credentials.isConnected()
        }

        let preferredRegion = UserDefaults.standard.string(forKey: Self.tickTickRegionKey)
            .flatMap(TickTickRegion.init(rawValue:))
        let orderedRegions = preferredRegion.map { preferred in
            [preferred] + TickTickRegion.allCases.filter { $0 != preferred }
        } ?? TickTickRegion.allCases

        guard tickTickIsAvailable else {
            let cleanup = beginTickTickCredentialCleanupForSignOut()
            var cleanupFinished = false
            defer {
                if !cleanupFinished { tickTickCredentialOperationGate.fail(cleanup) }
            }
            try await tickTickCredentialOperationGate.waitForInvalidatedOperations(before: cleanup)
            try validateTickTickCleanup(cleanup)
            try await tickTickLocalStateCleaner.clearAll(regions: orderedRegions)
            try validateTickTickCleanup(cleanup)
            clearTickTickConnectionPublication()
            cleanupFinished = true
            tickTickCredentialOperationGate.complete(cleanup)
            return
        }

        let operation = try beginTickTickCredentialOperation()
        defer { tickTickCredentialOperationGate.endOperation(operation) }
        for region in orderedRegions {
            guard let components = try? makeTickTickComponents(region: region) else { continue }
            let connected = try await components.credentials.isConnected(operation: operation)
            guard connected else { continue }
            try validateTickTickCredentialOperation(operation)
            tickTickAuthService = components.auth
            tickTickCredentialManager = components.credentials
            tickTickCredentialOwnerUserID = cloudWritableUserId
            tickTickRegion = region
            isTickTickConnected = true
            break
        }
    }

    private func makeTickTickComponents(region: TickTickRegion) throws -> (
        auth: TickTickAuthService,
        credentials: TickTickCredentialManager
    ) {
        guard let ownerUserID = cloudWritableUserId else {
            throw TickTickAuthError.kiroleSignInRequired
        }
        if let auth = tickTickAuthService,
           let credentials = tickTickCredentialManager,
           tickTickCredentialOwnerUserID == ownerUserID,
           tickTickRegion == region {
            return (auth, credentials)
        }
        guard region == .international else { throw TickTickAuthError.unsupportedRegion }
        guard let supabase = AppSecrets.supabaseConfig,
              let baseURL = URL(string: supabase.url),
              let returnURI = URL(string: "https://kirole.681023.xyz/oauth/ticktick-return") else {
            throw TickTickAuthError.invalidConfiguration
        }
        let configuration = try TickTickOAuthConfiguration(
            backendEndpoint: baseURL
                .appending(path: "functions")
                .appending(path: "v1")
                .appending(path: "ticktick-oauth"),
            returnURI: returnURI,
            region: region,
            backendAPIKey: supabase.anonKey
        )
        let credentials = TickTickCredentialManager(
            configuration: configuration,
            ownerUserID: ownerUserID,
            operationGate: tickTickCredentialOperationGate
        ) {
            try await SupabaseService.shared.authenticatedAccessToken(expectedUserID: ownerUserID)
        }
        return (
            TickTickAuthService(
                configuration: configuration,
                credentialManager: credentials,
                operationGate: tickTickCredentialOperationGate
            ),
            credentials
        )
    }

    func publishTickTickConnection(
        _ credentials: TickTickTokenSet,
        region: TickTickRegion,
        authService: TickTickAuthService,
        credentialManager: TickTickCredentialManager,
        operation: OAuthCredentialOperationTicket
    ) throws {
        try validateTickTickCredentialOperation(operation)
        stageTickTickConnection(
            authService: authService,
            credentialManager: credentialManager,
            ownerUserID: credentials.ownerUserID
        )
        tickTickRegion = region
        isTickTickConnected = true
        UserDefaults.standard.set(region.rawValue, forKey: Self.tickTickRegionKey)
    }

    func stageTickTickConnection(
        authService: TickTickAuthService,
        credentialManager: TickTickCredentialManager,
        ownerUserID: String?
    ) {
        tickTickAuthService = authService
        tickTickCredentialManager = credentialManager
        tickTickCredentialOwnerUserID = ownerUserID
    }

    private func beginTickTickCredentialOperation() throws -> OAuthCredentialOperationTicket {
        guard let operation = tickTickCredentialOperationGate.beginOperation() else {
            throw TickTickAuthError.credentialOperationInvalidated
        }
        return operation
    }

    private func validateTickTickCredentialOperation(
        _ operation: OAuthCredentialOperationTicket
    ) throws {
        if Task.isCancelled { throw CancellationError() }
        guard tickTickCredentialOperationGate.accepts(operation) else {
            throw TickTickAuthError.credentialOperationInvalidated
        }
    }

    private func validateTickTickCleanup(_ cleanup: OAuthCredentialCleanupTicket) throws {
        if Task.isCancelled { throw CancellationError() }
        guard tickTickCredentialOperationGate.accepts(cleanup) else {
            throw TickTickAuthError.credentialOperationInvalidated
        }
    }

    private func clearTickTickConnectionPublication() {
        UserDefaults.standard.removeObject(forKey: Self.tickTickRegionKey)
        tickTickAuthService = nil
        tickTickCredentialManager = nil
        tickTickCredentialOwnerUserID = nil
        tickTickRegion = nil
        isTickTickConnected = false
    }

    private func discardStagedTickTickConnection(authService: TickTickAuthService) {
        guard tickTickAuthService === authService, !isTickTickConnected else { return }
        tickTickAuthService = nil
        tickTickCredentialManager = nil
        tickTickCredentialOwnerUserID = nil
    }
}
