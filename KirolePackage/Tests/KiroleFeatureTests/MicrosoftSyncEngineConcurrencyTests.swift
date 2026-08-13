import Foundation
import Testing
@testable import KiroleFeature

extension MicrosoftSyncEngineTests {
    @Test("A suspended sync cannot recreate provider state after reset")
    @MainActor
    func suspendedSyncCannotCommitAfterReset() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MicrosoftSyncStateStore(directoryURL: directory)
        try await store.saveState(MicrosoftSyncState(accountID: "account-a"))
        let graph = SuspendedMicrosoftGraphStub()
        let token = MutableMicrosoftTokenStub(accountID: "account-a")
        let engine = MicrosoftSyncEngine(
            graphClient: graph,
            stateStore: store,
            tokenProvider: token
        )
        let oldEvent = makeOutlookEvent(accountID: "account-a", itemID: "old")
        let replacement = try decodeOutlookEvent(
            """
            {
              "id": "replacement",
              "subject": "Must not appear",
              "start": {"dateTime": "2026-08-13T09:00:00.0000000", "timeZone": "UTC"},
              "end": {"dateTime": "2026-08-13T10:00:00.0000000", "timeZone": "UTC"},
              "isAllDay": false,
              "isCancelled": false
            }
            """
        )
        let appState = AppState.makeForTesting()
        appState.events = [oldEvent]

        let sync = Task {
            try await engine.performSync(
                currentEvents: [oldEvent],
                currentTasks: [],
                includeOutlook: true,
                includeTodo: false
            )
        }
        await graph.waitForCalendarRequest()
        try await engine.clearProviderState()
        await graph.succeedCalendar(with: [replacement])

        do {
            let result = try await sync.value
            appState.applyMicrosoftSyncResult(
                result,
                includeOutlook: true,
                includeTodo: false
            )
            Issue.record("Expected the reset Microsoft operation to become stale")
        } catch MicrosoftSyncError.staleOperation {
            // Expected: AppState never receives a result owned by the cleared account.
        } catch {
            Issue.record("Expected staleOperation, got \(error)")
        }

        #expect(appState.events.map(\.id) == [oldEvent.id])
        #expect(!FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("microsoft_sync_state.json").path
        ))
    }

    @Test("A suspended sync cannot commit after authorization switches to B")
    @MainActor
    func suspendedSyncCannotCommitAfterAccountSwitch() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MicrosoftSyncStateStore(directoryURL: directory)
        let originalState = MicrosoftSyncState(accountID: "account-a")
        try await store.saveState(originalState)
        let graph = SuspendedMicrosoftGraphStub()
        let token = MutableMicrosoftTokenStub(accountID: "account-a")
        let engine = MicrosoftSyncEngine(
            graphClient: graph,
            stateStore: store,
            tokenProvider: token
        )
        let oldEvent = makeOutlookEvent(accountID: "account-a", itemID: "old")
        let replacement = try decodeOutlookEvent(
            """
            {
              "id": "replacement",
              "subject": "Must not appear",
              "start": {"dateTime": "2026-08-13T09:00:00.0000000", "timeZone": "UTC"},
              "end": {"dateTime": "2026-08-13T10:00:00.0000000", "timeZone": "UTC"},
              "isAllDay": false,
              "isCancelled": false
            }
            """
        )
        let appState = AppState.makeForTesting()
        appState.events = [oldEvent]

        let sync = Task {
            try await engine.performSync(
                currentEvents: [oldEvent],
                currentTasks: [],
                includeOutlook: true,
                includeTodo: false
            )
        }
        await graph.waitForCalendarRequest()
        await token.setAccountID("account-b")
        await graph.succeedCalendar(with: [replacement])

        do {
            let result = try await sync.value
            appState.applyMicrosoftSyncResult(
                result,
                includeOutlook: true,
                includeTodo: false
            )
            Issue.record("Expected the previous-account Microsoft operation to become stale")
        } catch MicrosoftSyncError.staleOperation {
            // Expected.
        } catch {
            Issue.record("Expected staleOperation, got \(error)")
        }

        #expect(appState.events.map(\.id) == [oldEvent.id])
        #expect(try await store.loadState() == originalState)
    }

    @Test("A successful suspended writeback cannot recreate its outbox after reset")
    func successfulWritebackCannotCommitAfterReset() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MicrosoftSyncStateStore(directoryURL: directory)
        let entry = MicrosoftTodoOutboxEntry(
            accountID: "account-a",
            listID: "list",
            taskID: "task",
            targetStatus: .completed
        )
        try await store.saveOutbox([entry])
        let graph = SuspendedMicrosoftGraphStub()
        let token = MutableMicrosoftTokenStub(accountID: "account-a")
        let engine = MicrosoftSyncEngine(
            graphClient: graph,
            stateStore: store,
            tokenProvider: token
        )
        let task = makeTodoTask(
            accountID: "account-a",
            listID: "list",
            itemID: "task",
            isCompleted: true
        )

        let write = Task { try await engine.pushTodoCompletion(task) }
        await graph.waitForStatusUpdate()
        try await engine.clearProviderState()
        await graph.succeedStatusUpdate()

        await expectStaleOperation(from: write)
        #expect(!FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("microsoft_todo_outbox.json").path
        ))
    }

    @Test("A failed suspended writeback cannot enqueue itself after reset")
    func failedWritebackCannotCommitAfterReset() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MicrosoftSyncStateStore(directoryURL: directory)
        let graph = SuspendedMicrosoftGraphStub()
        let token = MutableMicrosoftTokenStub(accountID: "account-a")
        let engine = MicrosoftSyncEngine(
            graphClient: graph,
            stateStore: store,
            tokenProvider: token
        )
        let task = makeTodoTask(
            accountID: "account-a",
            listID: "list",
            itemID: "task",
            isCompleted: true
        )

        let write = Task { try await engine.pushTodoCompletion(task) }
        await graph.waitForStatusUpdate()
        try await engine.clearProviderState()
        await graph.failStatusUpdate()

        await expectStaleOperation(from: write)
        #expect(!FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("microsoft_todo_outbox.json").path
        ))
    }

    @Test("A successful suspended writeback cannot remove A intent after switching to B")
    func successfulWritebackCannotCommitAfterAccountSwitch() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MicrosoftSyncStateStore(directoryURL: directory)
        let old = MicrosoftTodoOutboxEntry(
            accountID: "account-a",
            listID: "list",
            taskID: "task",
            targetStatus: .completed
        )
        let current = MicrosoftTodoOutboxEntry(
            accountID: "account-b",
            listID: "new-list",
            taskID: "new-task",
            targetStatus: .inProgress
        )
        try await store.saveOutbox([old, current])
        let graph = SuspendedMicrosoftGraphStub()
        let token = MutableMicrosoftTokenStub(accountID: "account-a")
        let engine = MicrosoftSyncEngine(
            graphClient: graph,
            stateStore: store,
            tokenProvider: token
        )
        let task = makeTodoTask(
            accountID: "account-a",
            listID: "list",
            itemID: "task",
            isCompleted: true
        )

        let write = Task { try await engine.pushTodoCompletion(task) }
        await graph.waitForStatusUpdate()
        await token.setAccountID("account-b")
        await graph.succeedStatusUpdate()

        await expectStaleOperation(from: write)
        #expect(try await store.loadOutbox() == [old, current])
    }

    @Test("A failed suspended writeback cannot enqueue A intent after switching to B")
    func failedWritebackCannotCommitAfterAccountSwitch() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MicrosoftSyncStateStore(directoryURL: directory)
        let current = MicrosoftTodoOutboxEntry(
            accountID: "account-b",
            listID: "new-list",
            taskID: "new-task",
            targetStatus: .inProgress
        )
        try await store.saveOutbox([current])
        let graph = SuspendedMicrosoftGraphStub()
        let token = MutableMicrosoftTokenStub(accountID: "account-a")
        let engine = MicrosoftSyncEngine(
            graphClient: graph,
            stateStore: store,
            tokenProvider: token
        )
        let task = makeTodoTask(
            accountID: "account-a",
            listID: "list",
            itemID: "task",
            isCompleted: true
        )

        let write = Task { try await engine.pushTodoCompletion(task) }
        await graph.waitForStatusUpdate()
        await token.setAccountID("account-b")
        await graph.failStatusUpdate()

        await expectStaleOperation(from: write)
        #expect(try await store.loadOutbox() == [current])
    }

    @Test("An account transition blocks new work and invalidates same-account ABA")
    func accountTransitionBlocksWorkAndInvalidatesABA() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MicrosoftSyncStateStore(directoryURL: directory)
        try await store.saveState(MicrosoftSyncState(accountID: "account-a"))
        let graph = SuspendedMicrosoftGraphStub()
        let token = MutableMicrosoftTokenStub(accountID: "account-a")
        let engine = MicrosoftSyncEngine(
            graphClient: graph,
            stateStore: store,
            tokenProvider: token
        )

        let oldSync = Task {
            try await engine.performSync(
                currentEvents: [],
                currentTasks: [],
                includeOutlook: true,
                includeTodo: false
            )
        }
        await graph.waitForCalendarRequest()
        let transition = try await engine.beginAccountTransition(
            clearingProviderState: false
        )

        await #expect(throws: MicrosoftSyncError.self) {
            _ = try await engine.performSync(
                currentEvents: [],
                currentTasks: [],
                includeOutlook: false,
                includeTodo: false
            )
        }

        // The visible account is A both before and after this transition. Generation, rather than
        // account equality, must still invalidate the suspended pre-transition operation.
        await engine.finishAccountTransition(transition)
        await graph.succeedCalendar(with: [])
        do {
            _ = try await oldSync.value
            Issue.record("Expected a same-account ABA transition to invalidate old work")
        } catch MicrosoftSyncError.staleOperation {
            // Expected.
        } catch {
            Issue.record("Expected staleOperation, got \(error)")
        }
    }

    @Test("A result cannot pass the MainActor commit gate after an identity transition")
    @MainActor
    func resultLeaseCannotCommitAfterIdentityTransition() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MicrosoftSyncStateStore(directoryURL: directory)
        try await store.saveState(MicrosoftSyncState(accountID: "account-a"))
        let engine = MicrosoftSyncEngine(
            graphClient: MicrosoftGraphStub(listSnapshot: []),
            stateStore: store,
            tokenProvider: MicrosoftTokenStub(accountID: "account-a")
        )
        let result = try await engine.performSync(
            currentEvents: [],
            currentTasks: [],
            includeOutlook: false,
            includeTodo: false
        )
        #expect(result.isCurrentForAppStateCommit)

        let commitBoundary = try MicrosoftSyncCommitGate.beginTransition()
        #expect(!result.isCurrentForAppStateCommit)
        MicrosoftSyncCommitGate.finishTransition(commitBoundary)
        #expect(!result.isCurrentForAppStateCommit)
    }
}
