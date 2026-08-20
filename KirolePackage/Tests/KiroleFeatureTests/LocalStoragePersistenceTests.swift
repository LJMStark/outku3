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

    @Test("retired provider artifacts are removed from every old storage location")
    func retiredProviderArtifactsAreRemoved() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        let support = root.appendingPathComponent("Application Support", isDirectory: true)
        let providerDirectory = support
            .appendingPathComponent("com.kirole.app", isDirectory: true)
            .appendingPathComponent("ProviderSync", isDirectory: true)
        let defaultsName = "com.kirole.tests.retired-provider-artifacts.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer {
            defaults.removePersistentDomain(forName: defaultsName)
            try? fileManager.removeItem(at: root)
        }
        try fileManager.createDirectory(at: documents, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: providerDirectory, withIntermediateDirectories: true)
        for filename in ["microsoft_sync_state.json", "microsoft_todo_outbox.json"] {
            try Data("retired".utf8).write(to: documents.appendingPathComponent(filename))
        }
        for filename in [
            "todoist-sync-state.json",
            "ticktick-international-sync-state.json",
            "ticktick-china-sync-state.json",
        ] {
            try Data("retired".utf8).write(to: providerDirectory.appendingPathComponent(filename))
        }
        defaults.set(["project"], forKey: "integrations.selectedProjects.todoist")
        defaults.set("china", forKey: "integrations.ticktick.region")

        try LocalStorage.removeRetiredProviderArtifacts(
            fileManager: fileManager,
            documentsDirectory: documents,
            applicationSupportDirectory: support,
            userDefaults: defaults
        )

        #expect(!fileManager.fileExists(atPath: documents.appendingPathComponent("microsoft_sync_state.json").path))
        #expect(!fileManager.fileExists(atPath: providerDirectory.path))
        #expect(defaults.object(forKey: "integrations.selectedProjects.todoist") == nil)
        #expect(defaults.object(forKey: "integrations.ticktick.region") == nil)
    }

    @Test("retired provider records are removed without dropping Apple and Google data")
    func retiredProviderRecordsAreRemovedSelectively() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let appleTask = TaskItem(id: "apple", title: "Apple", source: .apple)
        let googleTask = TaskItem(id: "google", title: "Google", source: .google)
        let currentData = try encoder.encode([appleTask, googleTask])
        var records = try #require(JSONSerialization.jsonObject(with: currentData) as? [[String: Any]])

        var retiredSource = records[0]
        retiredSource["id"] = "todoist"
        retiredSource["source"] = "Todoist"
        records.append(retiredSource)

        var retiredReference = records[0]
        retiredReference["id"] = "notion"
        retiredReference["externalReference"] = [
            "provider": "notion",
            "accountID": "old-account",
            "itemID": "old-item",
            "allowsContentModifications": false,
        ]
        records.append(retiredReference)

        let oldData = try JSONSerialization.data(withJSONObject: records)
        let filtered = try LocalStorage.removingRetiredProviderRecords(from: oldData)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = try decoder.decode([TaskItem].self, from: filtered.data)

        #expect(filtered.removedCount == 2)
        #expect(loaded.map(\.id) == ["apple", "google"])
    }

    @Test("malformed current-provider records are not silently discarded")
    func malformedCurrentProviderRecordsStillFailDecode() throws {
        let malformed = try JSONSerialization.data(withJSONObject: [[
            "id": "broken",
            "source": "Apple Calendar",
        ]])
        let filtered = try LocalStorage.removingRetiredProviderRecords(from: malformed)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        #expect(filtered.removedCount == 0)
        #expect(throws: DecodingError.self) {
            _ = try decoder.decode([TaskItem].self, from: filtered.data)
        }
    }

    @Test("focus history date keys use the timezone supplied at call time")
    func focusHistoryDateKeyUsesCurrentTimeZone() throws {
        let utc = try #require(TimeZone(secondsFromGMT: 0))
        let pacific = try #require(TimeZone(secondsFromGMT: -8 * 60 * 60))
        let epoch = Date(timeIntervalSince1970: 0)

        #expect(LocalStorage.dateKey(from: epoch, timeZone: utc) == "1970-01-01")
        #expect(LocalStorage.dateKey(from: epoch, timeZone: pacific) == "1969-12-31")
    }

    @Test("integration connection states round-trip through save/load")
    func integrationConnectionsRoundTrip() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let storage = LocalStorage.shared
            let states = ["Apple Calendar": false, "Apple Reminders": true, "Google Calendar": true]
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

    @Test("last committed structural hash round-trips through save/load")
    func lastCommittedStructuralHashRoundTrip() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let storage = LocalStorage.shared
            let original = await storage.loadLastCommittedStructuralHash()

            await storage.saveLastCommittedStructuralHash("structural-a")
            #expect(await storage.loadLastCommittedStructuralHash() == "structural-a")
            await storage.saveLastCommittedStructuralHash("structural-b")
            #expect(await storage.loadLastCommittedStructuralHash() == "structural-b")

            // The key is deliberately outside resettableUserDefaultKeys — restore by hand so
            // this test cannot leak state into a later relaunch-simulation suite.
            if let original {
                await storage.saveLastCommittedStructuralHash(original)
            } else {
                UserDefaults.standard.removeObject(forKey: "lastCommittedStructuralHash")
            }
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

    @Test("delete rejects nested, traversal, and absolute filenames without escaping Documents")
    func deleteRejectsUnsafePaths() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let storage = LocalStorage.shared
            let fileManager = FileManager.default
            let documentsDirectory = try #require(
                fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            )
            let nestedDirectory = documentsDirectory
                .appendingPathComponent("local-storage-delete-\(UUID().uuidString)")
            let sentinel = nestedDirectory.appendingPathComponent("sentinel.json")
            defer { try? fileManager.removeItem(at: nestedDirectory) }

            try fileManager.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
            try Data("keep".utf8).write(to: sentinel)

            try await storage.deleteFile(
                named: "\(nestedDirectory.lastPathComponent)/sentinel.json"
            )
            try await storage.deleteFile(named: "../../sentinel.json")
            try await storage.deleteFile(named: sentinel.path)

            #expect(fileManager.fileExists(atPath: sentinel.path))
        }
    }

    @Test("orphan custom companion assets are swept without deleting pending candidates")
    func orphanCustomCompanionAssetsAreSweptByPrefix() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("custom-avatar-sweep-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: directory) }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let orphanPreview = directory.appendingPathComponent("custom_companion_orphan_preview.png")
        let orphanImage = directory.appendingPathComponent("custom_companion_orphan_pixels.dat")
        let pendingCandidate = directory.appendingPathComponent("pending_custom_avatar_image.dat")
        let unrelated = directory.appendingPathComponent("user_profile.json")
        for url in [orphanPreview, orphanImage, pendingCandidate, unrelated] {
            try Data("fixture".utf8).write(to: url)
        }

        try LocalStorage.deleteAllCustomCompanionAssets(
            fileManager: fileManager,
            documentsDirectory: directory
        )

        #expect(!fileManager.fileExists(atPath: orphanPreview.path))
        #expect(!fileManager.fileExists(atPath: orphanImage.path))
        #expect(fileManager.fileExists(atPath: pendingCandidate.path))
        #expect(fileManager.fileExists(atPath: unrelated.path))
    }
}
