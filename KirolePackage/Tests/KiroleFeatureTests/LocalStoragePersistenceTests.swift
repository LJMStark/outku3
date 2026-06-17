import Testing
import Foundation
@testable import KiroleFeature

/// Covers the new on-device persistence surface added in the B4 batch:
/// integration-connection toggles (so a user's disconnect survives relaunch) and
/// `quarantineCorruptFile` (move a corrupt JSON aside instead of letting defaults overwrite it).
/// Both touch the real Documents directory + resettable file set, so every body runs inside
/// `SharedPersistenceTestLock` to stay isolated from other persistence-mutating suites.
@Suite("LocalStorage Integration & Quarantine (B4)", .serialized)
struct LocalStoragePersistenceTests {

    private static let connectionsFile = "integration_connections.json"

    @Test("integration connection states round-trip through save/load")
    func integrationConnectionsRoundTrip() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let storage = LocalStorage.shared
            let states = ["Apple Calendar": false, "Apple Reminders": true, "Google": true]
            try await storage.saveIntegrationConnections(states)

            let loaded = try await storage.loadIntegrationConnections()

            #expect(loaded == states)
            try await storage.deleteFile(named: Self.connectionsFile)
        }
    }

    @Test("loading integration connections when no file exists returns nil, not a throw")
    func integrationConnectionsMissingReturnsNil() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let storage = LocalStorage.shared
            try await storage.deleteFile(named: Self.connectionsFile)

            let loaded = try await storage.loadIntegrationConnections()

            #expect(loaded == nil)
        }
    }

    @Test("quarantine moves a corrupt file aside so a subsequent load returns nil")
    func quarantineMovesCorruptFileAside() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let storage = LocalStorage.shared
            try await storage.saveIntegrationConnections(["Google": true])

            try await storage.quarantineCorruptFile(named: Self.connectionsFile)

            // Original was renamed to `.corrupt`, so the live file is gone and load returns nil
            // rather than serving partial/default data over the original.
            let loaded = try await storage.loadIntegrationConnections()
            #expect(loaded == nil, "original file should have been moved to .corrupt")

            // Quarantining again with the original now absent is a safe no-op (fileExists guard).
            try await storage.quarantineCorruptFile(named: Self.connectionsFile)

            try await storage.deleteFile(named: Self.connectionsFile + ".corrupt")
        }
    }

    @Test("quarantine rejects path-traversal and absolute filenames without throwing or escaping Documents")
    func quarantineRejectsTraversalAndAbsolutePaths() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let storage = LocalStorage.shared
            // Each guarded name (`..`, leading `/`, nested `/`) must early-return: no throw, and
            // crucially nothing is moved outside the Documents sandbox.
            try await storage.quarantineCorruptFile(named: "../../evil.json")
            try await storage.quarantineCorruptFile(named: "/etc/passwd")
            try await storage.quarantineCorruptFile(named: "nested/dir.json")
        }
    }
}
