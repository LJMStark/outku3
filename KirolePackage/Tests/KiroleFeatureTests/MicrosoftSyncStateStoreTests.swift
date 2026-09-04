import Foundation
import Testing
@testable import KiroleFeature

@Suite("Microsoft sync persistence")
struct MicrosoftSyncStateStoreTests {
    @Test("State and outbox survive a new actor instance")
    func persistsAcrossInstances() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = MicrosoftSyncStateStore(directoryURL: directory)
        let state = MicrosoftSyncState(
            accountID: "account",
            outlookDeltaLink: "https://graph.microsoft.com/v1.0/me/calendarView/delta?$deltatoken=x",
            todoListIDs: ["list"]
        )
        try await first.saveState(state)
        try await first.enqueue(MicrosoftTodoOutboxEntry(
            accountID: "account",
            listID: "list",
            taskID: "task",
            targetStatus: .completed
        ))

        let second = MicrosoftSyncStateStore(directoryURL: directory)
        #expect(try await second.loadState() == state)
        #expect(try await second.loadOutbox().count == 1)
    }

    @Test("Newest target state replaces stale queued state for one task")
    func coalescesTargetState() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MicrosoftSyncStateStore(directoryURL: directory)

        try await store.enqueue(MicrosoftTodoOutboxEntry(
            accountID: "account",
            listID: "list",
            taskID: "task",
            targetStatus: .completed
        ))
        try await store.enqueue(MicrosoftTodoOutboxEntry(
            accountID: "account",
            listID: "list",
            taskID: "task",
            targetStatus: .inProgress
        ))

        let outbox = try await store.loadOutbox()
        #expect(outbox.count == 1)
        #expect(outbox.first?.targetStatus == .inProgress)
    }

    @Test("Outbox attempt commit preserves an intent enqueued during the network wait")
    func attemptCommitPreservesNewerIntent() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MicrosoftSyncStateStore(directoryURL: directory)
        let attempted = MicrosoftTodoOutboxEntry(
            accountID: "account",
            listID: "list",
            taskID: "task",
            targetStatus: .completed
        )
        try await store.saveOutbox([attempted])

        let newer = MicrosoftTodoOutboxEntry(
            accountID: "account",
            listID: "list",
            taskID: "task",
            targetStatus: .inProgress
        )
        try await store.enqueue(newer)
        var retry = attempted
        retry.retryCount = 1
        try await store.commitOutboxAttempt(
            attempted: [attempted],
            retrying: [retry]
        )

        let outbox = try await store.loadOutbox()
        #expect(outbox == [newer])
    }

    @Test("Account boundary removes only the previous account outbox")
    func accountBoundaryKeepsCurrentAccountIntent() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MicrosoftSyncStateStore(directoryURL: directory)
        let old = MicrosoftTodoOutboxEntry(
            accountID: "account-a",
            listID: "list-a",
            taskID: "old",
            targetStatus: .completed
        )
        let current = MicrosoftTodoOutboxEntry(
            accountID: "account-b",
            listID: "list-b",
            taskID: "current",
            targetStatus: .inProgress
        )
        try await store.saveOutbox([old, current])

        try await store.retainOutbox(forAccountID: "account-b")

        #expect(try await store.loadOutbox() == [current])
    }

    @Test("A pre-reset epoch cannot recreate Microsoft state or outbox files")
    func staleEpochCannotWriteAfterReset() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MicrosoftSyncStateStore(directoryURL: directory)
        let staleEpoch = await store.currentOperationEpoch()

        try await store.reset()

        await #expect(throws: MicrosoftSyncStoreEpochMismatch.self) {
            try await store.saveState(
                MicrosoftSyncState(accountID: "account-a"),
                expectedEpoch: staleEpoch
            )
        }
        await #expect(throws: MicrosoftSyncStoreEpochMismatch.self) {
            try await store.enqueue(
                MicrosoftTodoOutboxEntry(
                    accountID: "account-a",
                    listID: "list",
                    taskID: "task",
                    targetStatus: .completed
                ),
                expectedEpoch: staleEpoch
            )
        }

        #expect(!FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("microsoft_sync_state.json").path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("microsoft_todo_outbox.json").path
        ))
    }
}
