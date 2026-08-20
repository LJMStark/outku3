import Foundation
import Testing
@testable import KiroleFeature

@Suite("Auth sign-out isolation", .serialized)
struct AuthSignOutIsolationTests {
    @Test("Global sign out invalidates AppState provider commits before its first await")
    @MainActor
    func signOutInvalidatesAppStateBeforeFirstSuspension() async throws {
        let manager = AuthManager(keychainService: KeychainService(
            service: "com.kirole.tests.signout-generation.\(UUID().uuidString)"
        ))
        let state = AppState.shared
        await state.ensureInitialLoadComplete()
        let oldGoogleGeneration = state.externalSyncGeneration(for: .google)
        let oldAppleGeneration = state.externalSyncGeneration(for: .apple)
        let resetEntered = SignOutSuspensionGate()
        manager.googleSyncStateResetOverride = {
            await resetEntered.suspend()
        }
        manager.customCompanionSignOutCleanup = {}
        manager.providerDataSignOutCleanupOverride = {}
        manager.localCredentialSignOutCleanupOverride = {}
        manager.supabaseSignOutOverride = {}

        let signOut = Task { @MainActor in await manager.signOut() }
        await resetEntered.waitUntilSuspended()

        #expect(!state.canCommitExternalSync(.google, generation: oldGoogleGeneration))
        #expect(!state.canCommitExternalSync(.apple, generation: oldAppleGeneration))
        await resetEntered.resume()
        await signOut.value
    }

    @Test("Sign out removes provider snapshots and persisted connection choices")
    @MainActor
    func signOutClearsProviderDataAndConnections() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let storage = LocalStorage.shared
            let originalTasks = try await storage.loadTasks()
            let originalEvents = try await storage.loadEvents()
            let originalConnections = try await storage.loadIntegrationConnections()
            let originalSyncTimes = try await storage.loadIntegrationSyncTimes()

            do {
                let localTask = TaskItem(id: "local-task", title: "Keep local task")
                let appleReminder = TaskItem(
                    id: "apple-reminder",
                    appleReminderId: "reminder-1",
                    title: "Apple reminder",
                    source: .apple
                )
                let googleTask = TaskItem(id: "google-task", title: "Google task", source: .google)
                let localEvent = CalendarEvent(
                    id: "local-event",
                    title: "Keep local event",
                    startTime: Date(),
                    endTime: Date().addingTimeInterval(60)
                )
                let googleEvent = CalendarEvent(
                    id: "google-event",
                    googleEventId: "event-1",
                    googleCalendarId: "calendar-1",
                    title: "Google event",
                    startTime: Date(),
                    endTime: Date().addingTimeInterval(60),
                    source: .google
                )
                let connectedIntegrations = Integration.defaultIntegrations.map { integration in
                    var connected = integration
                    connected.isConnected = true
                    return connected
                }
                let connectionSnapshot = Dictionary(
                    uniqueKeysWithValues: connectedIntegrations.map { ($0.type.rawValue, true) }
                )

                try await storage.saveTasks([localTask, appleReminder, googleTask])
                try await storage.saveEvents([localEvent, googleEvent])
                try await storage.saveIntegrationConnections(connectionSnapshot)
                try await storage.saveIntegrationSyncTimes(["google": Date()])

                let state = AppState.makeForTesting()
                state.tasks = [localTask, appleReminder, googleTask]
                state.events = [localEvent, googleEvent]
                state.integrations = connectedIntegrations
                state.integrationLastSyncedAt = ["google": Date()]

                try await state.prepareProviderDataForSignOut()

                #expect(state.tasks.map(\.id) == ["local-task"])
                #expect(state.events.map(\.id) == ["local-event"])
                #expect(state.integrations.allSatisfy { !$0.isConnected })
                #expect(state.integrationLastSyncedAt.isEmpty)
                #expect(try await storage.loadTasks()?.map(\.id) == ["local-task"])
                #expect(try await storage.loadEvents()?.map(\.id) == ["local-event"])
                #expect(try await storage.loadIntegrationConnections()?.values.allSatisfy { !$0 } == true)
                #expect(try await storage.loadIntegrationSyncTimes().isEmpty)
            } catch {
                try await Self.restore(
                    tasks: originalTasks,
                    events: originalEvents,
                    connections: originalConnections,
                    syncTimes: originalSyncTimes,
                    storage: storage
                )
                throw error
            }

            try await Self.restore(
                tasks: originalTasks,
                events: originalEvents,
                connections: originalConnections,
                syncTimes: originalSyncTimes,
                storage: storage
            )
        }
    }

    @Test("Credential deletion failure blocks Supabase sign out and preserves identity")
    @MainActor
    func credentialFailureDoesNotClearRemoteSessionFirst() async throws {
        let serviceName = "com.kirole.tests.signout-order.\(UUID().uuidString)"
        let keychain = KeychainService(service: serviceName)
        try keychain.saveAppleUserIdentifier("apple-user-a")
        let manager = AuthManager(keychainService: keychain)
        manager.restoreLocalIdentityFromKeychain()
        manager.googleSyncStateResetOverride = {}
        manager.customCompanionSignOutCleanup = {}
        manager.providerDataSignOutCleanupOverride = {}
        manager.localCredentialSignOutCleanupOverride = {
            throw AuthSignOutIsolationError.credentialDeletionFailed
        }
        let audit = SignOutAudit()
        manager.supabaseSignOutOverride = {
            await audit.recordSupabaseSignOut()
        }

        await manager.signOut()

        #expect(await audit.supabaseSignOutCount() == 0)
        #expect(manager.currentUser?.id == "apple-user-a")
        #expect(manager.authState.isAuthenticated)
        #expect(keychain.getAppleUserIdentifier() == "apple-user-a")
        try keychain.clearAll()
    }

    @Test("Provider snapshot persistence failure preserves identity and credentials")
    @MainActor
    func providerPersistenceFailurePreservesIdentity() async throws {
        let serviceName = "com.kirole.tests.signout-provider-persistence.\(UUID().uuidString)"
        let keychain = KeychainService(service: serviceName)
        try keychain.saveAppleUserIdentifier("apple-user-a")
        let manager = AuthManager(keychainService: keychain)
        manager.restoreLocalIdentityFromKeychain()
        manager.googleSyncStateResetOverride = {}
        manager.customCompanionSignOutCleanup = {}
        manager.providerDataSignOutCleanupOverride = {
            throw AuthSignOutIsolationError.providerPersistenceFailed
        }
        var didAttemptCredentialCleanup = false
        let audit = SignOutAudit()
        manager.localCredentialSignOutCleanupOverride = {
            didAttemptCredentialCleanup = true
        }
        manager.supabaseSignOutOverride = {
            await audit.recordSupabaseSignOut()
        }

        await manager.signOut()

        #expect(!didAttemptCredentialCleanup)
        #expect(await audit.supabaseSignOutCount() == 0)
        #expect(manager.currentUser?.id == "apple-user-a")
        #expect(manager.authState.isAuthenticated)
        #expect(keychain.getAppleUserIdentifier() == "apple-user-a")
        try keychain.clearAll()
    }

    @Test("Supabase sign-out failure still completes verified local sign out")
    @MainActor
    func supabaseFailureDoesNotLeaveAuthenticatedUI() async throws {
        let serviceName = "com.kirole.tests.signout-supabase.\(UUID().uuidString)"
        let keychain = KeychainService(service: serviceName)
        try keychain.saveAppleUserIdentifier("apple-user-a")
        try keychain.saveGoogleTokens(
            accessToken: "google-access",
            refreshToken: "google-refresh",
            expiresIn: 3_600
        )
        try keychain.saveGoogleScopes([GoogleOAuthScope.calendarReadOnly])
        let manager = AuthManager(keychainService: keychain)
        manager.restoreLocalIdentityFromKeychain()
        manager.googleSyncStateResetOverride = {}
        manager.customCompanionSignOutCleanup = {}
        manager.providerDataSignOutCleanupOverride = {}
        manager.supabaseSignOutOverride = {
            throw AuthSignOutIsolationError.supabaseSignOutFailed
        }

        await manager.signOut()

        #expect(manager.currentUser == nil)
        #expect(manager.authState == .unauthenticated)
        #expect(keychain.getAppleUserIdentifier() == nil)
        #expect(keychain.getGoogleAccessToken() == nil)
        #expect(keychain.getGoogleRefreshToken() == nil)
    }

    private static func restore(
        tasks: [TaskItem]?,
        events: [CalendarEvent]?,
        connections: [String: Bool]?,
        syncTimes: [String: Date],
        storage: LocalStorage
    ) async throws {
        if let tasks {
            try await storage.saveTasks(tasks)
        } else {
            try await storage.deleteFile(named: "tasks.json")
        }
        if let events {
            try await storage.saveEvents(events)
        } else {
            try await storage.deleteFile(named: "events.json")
        }
        if let connections {
            try await storage.saveIntegrationConnections(connections)
        } else {
            try await storage.deleteFile(named: "integration_connections.json")
        }
        try await storage.saveIntegrationSyncTimes(syncTimes)
    }
}

private actor SignOutAudit {
    private var supabaseCount = 0

    func recordSupabaseSignOut() {
        supabaseCount += 1
    }

    func supabaseSignOutCount() -> Int {
        supabaseCount
    }

}

private actor SignOutSuspensionGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func suspend() async {
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilSuspended() async {
        if continuation != nil { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private enum AuthSignOutIsolationError: Error {
    case credentialDeletionFailed
    case providerPersistenceFailed
    case supabaseSignOutFailed
}
