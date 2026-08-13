import Foundation
import Testing
@testable import KiroleFeature

@Suite("Auth credential cleanup")
struct AuthCredentialCleanupTests {
    @Test("Disconnect Todoist clears the previous user's project selection")
    @MainActor
    func disconnectTodoistClearsProjectSelection() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let store = ProviderProjectSelectionStore.shared
            await store.save(["project-from-user-a"], for: .todoist)
            let manager = AuthManager(
                keychainService: KeychainService(
                    service: "com.kirole.tests.todoist-disconnect.\(UUID().uuidString)"
                )
            )

            do {
                try await manager.disconnectTodoist()
                #expect(await store.selectedProjectIDs(for: .todoist).isEmpty)
            } catch {
                await store.clear(.todoist)
                throw error
            }
            await store.clear(.todoist)
        }
    }

    @Test("Clear all removes Todoist and every TickTick credential")
    func clearAllIncludesTaskProviderCredentials() async throws {
        let serviceName = "com.kirole.tests.credentials.\(UUID().uuidString)"
        let keychain = KeychainService(service: serviceName)
        let todoistStore = TodoistKeychainTokenStore(service: serviceName)
        let internationalTokenStore = TickTickKeychainTokenStore(
            region: .international,
            service: serviceName
        )
        let internationalPendingStore = TickTickPendingAuthorizationStore(
            region: .international,
            service: serviceName
        )
        let chinaTokenStore = TickTickKeychainTokenStore(
            region: .china,
            service: serviceName
        )
        let chinaPendingStore = TickTickPendingAuthorizationStore(
            region: .china,
            service: serviceName
        )
        try await todoistStore.save(TodoistTokenSet(
            accessToken: "todoist-token",
            refreshToken: nil,
            expiresAt: nil,
            scope: "data:read_write"
        ))
        try await internationalTokenStore.save(TickTickTokenSet(
            accessToken: "ticktick-token",
            expiresAt: nil,
            scope: "tasks:read",
            accountID: "connection-1",
            region: .international,
            ownerUserID: "user-1"
        ))
        try await internationalPendingStore.save(TickTickPendingAuthorization(
            attemptID: "attempt-1",
            claimSecret: "claim-secret",
            region: .international,
            ownerUserID: "user-1",
            expiresAt: Date().addingTimeInterval(600),
            delivery: nil
        ))
        try await chinaTokenStore.save(.fixture(region: .china))
        try await chinaPendingStore.save(TickTickPendingAuthorization(
            attemptID: "attempt-china",
            claimSecret: "claim-secret-china",
            region: .china,
            ownerUserID: "user-1",
            expiresAt: Date().addingTimeInterval(600),
            delivery: nil
        ))

        try keychain.clearAll()

        #expect(try await todoistStore.load() == nil)
        #expect(try await internationalTokenStore.load() == nil)
        #expect(try await internationalPendingStore.load() == nil)
        #expect(try await chinaTokenStore.load() == nil)
        #expect(try await chinaPendingStore.load() == nil)
    }

    @Test("Disabled TickTick cleanup reports deletion failure and still resets every region")
    @MainActor
    func disabledTickTickCleanupIsVerifiedAndResetsSyncState() async {
        let audit = CredentialCleanupAudit()
        let internationalTokenStore = CredentialTokenStoreSpy(
            tokens: .fixture(region: .international),
            clearError: CredentialCleanupTestError.credentialDeletionFailed,
            audit: audit,
            label: "token-international"
        )
        let chinaTokenStore = CredentialTokenStoreSpy(
            tokens: .fixture(region: .china),
            audit: audit,
            label: "token-china"
        )
        let internationalPendingStore = CredentialPendingStoreSpy(
            audit: audit,
            label: "pending-international"
        )
        let chinaPendingStore = CredentialPendingStoreSpy(
            audit: audit,
            label: "pending-china"
        )
        let tokenStores: [TickTickRegion: any TickTickTokenStoring] = [
            .international: internationalTokenStore,
            .china: chinaTokenStore,
        ]
        let pendingStores: [TickTickRegion: any TickTickPendingAuthorizationStoring] = [
            .international: internationalPendingStore,
            .china: chinaPendingStore,
        ]
        let cleaner = TickTickLocalStateCleaner(
            makeTokenStore: { tokenStores[$0]! },
            makePendingStore: { pendingStores[$0]! },
            resetSyncState: { region in
                await audit.append("reset-\(region.rawValue)")
            },
            clearProjectSelection: { region in
                await audit.append("selection-\(region.rawValue)")
            }
        )
        let manager = AuthManager(
            keychainService: KeychainService(
                service: "com.kirole.tests.restore.\(UUID().uuidString)"
            )
        )
        manager.tickTickLocalStateCleaner = cleaner

        await #expect(throws: CredentialCleanupTestError.credentialDeletionFailed) {
            try await manager.restoreTaskProviderConnections(tickTickIsAvailable: false)
        }

        let events = await audit.events()
        #expect(events.contains("reset-international"))
        #expect(events.contains("reset-china"))
        #expect(events.contains("pending-international-clear"))
        #expect(events.contains("pending-china-clear"))
        #expect(events.contains("selection-international"))
        #expect(events.contains("selection-china"))
        #expect(manager.isTickTickConnected == false)
    }

    @Test("Unavailable TickTick tasks are purged after local tasks finish loading")
    @MainActor
    func unavailableTickTickTasksArePurgedAfterLoad() async throws {
        // The process-wide AppState also owns a startup load task that may persist its snapshot.
        // Drain it before this test takes ownership of the shared tasks.json fixture.
        await AppState.shared.ensureInitialLoadComplete()
        try await SharedPersistenceTestLock.shared.withLock {
            let storage = LocalStorage.shared
            let originalTasks = try await storage.loadTasks()
            let tickTickTask = TaskItem(
                id: "ticktick-old",
                externalReference: ProviderItemReference(
                    provider: .tickTick,
                    accountID: "old-account",
                    itemID: "remote-task",
                    region: .international
                ),
                title: "Old TickTick task",
                source: .tickTick
            )
            let localTask = TaskItem(id: "local", title: "Keep me", source: .apple)

            do {
                try await storage.saveTasks([tickTickTask, localTask])
                let state = AppState(loadLocalDataOnInit: true)
                await state.ensureInitialLoadComplete()

                #expect(state.tasks.map(\.id) == ["local"])
                let persisted = try await storage.loadTasks()
                #expect(persisted?.map(\.id) == ["local"])
            } catch {
                try await Self.restoreTasks(originalTasks, storage: storage)
                throw error
            }
            try await Self.restoreTasks(originalTasks, storage: storage)
        }
    }

    private static func restoreTasks(
        _ tasks: [TaskItem]?,
        storage: LocalStorage
    ) async throws {
        if let tasks {
            try await storage.saveTasks(tasks)
        } else {
            try await storage.deleteFile(named: "tasks.json")
        }
    }
}

private actor CredentialCleanupAudit {
    private var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }

    func events() -> [String] {
        values
    }
}

private enum CredentialCleanupTestError: Error, Equatable {
    case credentialDeletionFailed
}

private actor CredentialTokenStoreSpy: TickTickTokenStoring {
    private var tokens: TickTickTokenSet?
    private let clearError: Error?
    private let audit: CredentialCleanupAudit
    private let label: String

    init(
        tokens: TickTickTokenSet?,
        clearError: Error? = nil,
        audit: CredentialCleanupAudit,
        label: String
    ) {
        self.tokens = tokens
        self.clearError = clearError
        self.audit = audit
        self.label = label
    }

    func load() throws -> TickTickTokenSet? {
        tokens
    }

    func save(_ tokens: TickTickTokenSet) {
        self.tokens = tokens
    }

    func clear() async throws {
        await audit.append("\(label)-clear")
        if let clearError { throw clearError }
        tokens = nil
    }
}

private actor CredentialPendingStoreSpy: TickTickPendingAuthorizationStoring {
    private var pending: TickTickPendingAuthorization?
    private let audit: CredentialCleanupAudit
    private let label: String

    init(audit: CredentialCleanupAudit, label: String) {
        self.audit = audit
        self.label = label
    }

    func load() throws -> TickTickPendingAuthorization? {
        pending
    }

    func save(_ pending: TickTickPendingAuthorization) {
        self.pending = pending
    }

    func clear() async {
        await audit.append("\(label)-clear")
        pending = nil
    }
}

private extension TickTickTokenSet {
    static func fixture(region: TickTickRegion) -> TickTickTokenSet {
        TickTickTokenSet(
            accessToken: "token-\(region.rawValue)",
            expiresAt: nil,
            scope: "tasks:read",
            accountID: "connection-\(region.rawValue)",
            region: region,
            ownerUserID: "user-1"
        )
    }
}
