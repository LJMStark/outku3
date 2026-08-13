import Foundation
import Testing
@testable import KiroleFeature

extension MicrosoftSyncEngineTests {
    @Test("To Do keeps all cursors when one list snapshot fails")
    func todoCursorCommitIsTransactional() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MicrosoftSyncStateStore(directoryURL: directory)
        let original = MicrosoftSyncState(
            accountID: "account",
            todoListsDeltaLink: "old-lists-delta",
            todoListIDs: ["old-list"],
            todoTaskDeltaLinks: ["old-list": "old-task-delta"]
        )
        try await store.saveState(original)
        let newList = try decodeTodoList(
            """
            {"id":"new-list","displayName":"New"}
            """
        )
        let graph = MicrosoftGraphStub(listSnapshot: [newList], failTaskListID: "new-list")
        let engine = MicrosoftSyncEngine(
            graphClient: graph,
            stateStore: store,
            tokenProvider: MicrosoftTokenStub(accountID: "account")
        )

        await #expect(throws: MicrosoftSyncError.self) {
            _ = try await engine.performSync(
                currentEvents: [],
                currentTasks: [],
                includeOutlook: false,
                includeTodo: true
            )
        }

        #expect(try await store.loadState() == original)
    }

    @Test("Fresh list snapshot removes tasks from lists no longer returned")
    func freshListSnapshotRemovesMissingLists() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MicrosoftSyncStateStore(directoryURL: directory)
        try await store.saveState(MicrosoftSyncState(
            accountID: "account",
            todoListsDeltaLink: "expired-lists-delta",
            todoListIDs: ["missing-list"],
            todoTaskDeltaLinks: ["missing-list": "old-task-delta"]
        ))
        let newList = try decodeTodoList(
            """
            {"id":"new-list","displayName":"New"}
            """
        )
        let graph = MicrosoftGraphStub(listSnapshot: [newList])
        let engine = MicrosoftSyncEngine(
            graphClient: graph,
            stateStore: store,
            tokenProvider: MicrosoftTokenStub(accountID: "account")
        )
        let missingReference = ProviderItemReference(
            provider: .microsoftToDo,
            accountID: "account",
            containerID: "missing-list",
            itemID: "task",
            region: .global
        )
        let missingTask = TaskItem(
            id: missingReference.stableLocalID,
            externalReference: missingReference,
            title: "Removed with list",
            source: .microsoftToDo
        )

        let result = try await engine.performSync(
            currentEvents: [],
            currentTasks: [missingTask],
            includeOutlook: false,
            includeTodo: true
        )
        let state = try await store.loadState()

        #expect(result.tasks.isEmpty)
        #expect(state.todoListIDs == ["new-list"])
        #expect(state.todoTaskDeltaLinks["missing-list"] == nil)
    }

    @Test("To Do outbox keeps an intent after more than five transient failures")
    func outboxNeverDropsTransientFailure() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MicrosoftSyncStateStore(directoryURL: directory)
        try await store.saveState(MicrosoftSyncState(accountID: "account"))
        try await store.enqueue(MicrosoftTodoOutboxEntry(
            accountID: "account",
            listID: "list",
            taskID: "task",
            targetStatus: .completed,
            retryCount: 5
        ))
        let graph = MicrosoftGraphStub(listSnapshot: [], failStatusUpdates: true)
        let engine = MicrosoftSyncEngine(
            graphClient: graph,
            stateStore: store,
            tokenProvider: MicrosoftTokenStub(accountID: "account")
        )

        let result = try await engine.performSync(
            currentEvents: [],
            currentTasks: [],
            includeOutlook: false,
            includeTodo: true
        )

        let outbox = try await store.loadOutbox()
        #expect(outbox.count == 1)
        #expect(outbox.first?.retryCount == 6)
        #expect(result.warnings.contains { $0.contains("queued") })
    }

    @Test("To Do outbox drops only explicit permanent 403 and 404 failures", arguments: [403, 404])
    func outboxDropsPermanentHTTPFailure(statusCode: Int) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MicrosoftSyncStateStore(directoryURL: directory)
        try await store.saveState(MicrosoftSyncState(accountID: "account"))
        try await store.enqueue(MicrosoftTodoOutboxEntry(
            accountID: "account",
            listID: "list",
            taskID: "deleted-task",
            targetStatus: .completed,
            retryCount: 2
        ))
        let graph = MicrosoftGraphStub(
            listSnapshot: [],
            statusUpdateError: MicrosoftGraphError.httpError(statusCode, "permanent")
        )
        let engine = MicrosoftSyncEngine(
            graphClient: graph,
            stateStore: store,
            tokenProvider: MicrosoftTokenStub(accountID: "account")
        )

        let result = try await engine.performSync(
            currentEvents: [],
            currentTasks: [],
            includeOutlook: false,
            includeTodo: true
        )

        #expect(try await store.loadOutbox().isEmpty)
        #expect(result.warnings.contains { $0.contains("discarded") })
    }

    @Test("A first 404 write failure is not inserted into the To Do outbox")
    func directPermanentFailureIsNotQueued() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MicrosoftSyncStateStore(directoryURL: directory)
        let graph = MicrosoftGraphStub(
            listSnapshot: [],
            statusUpdateError: MicrosoftGraphError.httpError(404, "deleted")
        )
        let engine = MicrosoftSyncEngine(
            graphClient: graph,
            stateStore: store,
            tokenProvider: MicrosoftTokenStub(accountID: "account")
        )
        let task = makeTodoTask(
            accountID: "account",
            listID: "list",
            itemID: "deleted-task",
            isCompleted: true
        )

        await #expect(throws: MicrosoftGraphError.self) {
            try await engine.pushTodoCompletion(task)
        }

        #expect(try await store.loadOutbox().isEmpty)
    }


    @Test("To Do refuses to write a task from a different Microsoft account")
    func completionRejectsAccountMismatch() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MicrosoftSyncStateStore(directoryURL: directory)
        let graph = MicrosoftGraphStub(listSnapshot: [])
        let engine = MicrosoftSyncEngine(
            graphClient: graph,
            stateStore: store,
            tokenProvider: MicrosoftTokenStub(accountID: "new-account")
        )
        let reference = ProviderItemReference(
            provider: .microsoftToDo,
            accountID: "old-account",
            containerID: "list",
            itemID: "task",
            region: .global,
            allowsContentModifications: true
        )
        let task = TaskItem(
            id: reference.stableLocalID,
            externalReference: reference,
            title: "Old account task",
            isCompleted: true,
            source: .microsoftToDo
        )

        await #expect(throws: MicrosoftSyncError.self) {
            try await engine.pushTodoCompletion(task)
        }

        #expect(await graph.statusUpdateCallCount() == 0)
        #expect(try await store.loadOutbox().isEmpty)
    }

    @Test("Outlook delta updates and removes by provider-scoped stable ID")
    func outlookDeltaMerge() throws {
        let initial = try decodeOutlookEvent("""
        {
          "id": "keep",
          "subject": "New title",
          "start": {"dateTime": "2026-08-12T09:00:00.0000000", "timeZone": "UTC"},
          "end": {"dateTime": "2026-08-12T10:00:00.0000000", "timeZone": "UTC"},
          "isAllDay": false,
          "isCancelled": false
        }
        """)
        let removed = try decodeOutlookEvent("""
        {"id": "remove", "@removed": {"reason": "deleted"}}
        """)
        let removeReference = ProviderItemReference(
            provider: .outlook,
            accountID: "account",
            containerID: "default",
            itemID: "remove",
            region: .global,
            allowsContentModifications: false
        )
        let current = CalendarEvent(
            id: removeReference.stableLocalID,
            externalReference: removeReference,
            title: "Old",
            startTime: Date(timeIntervalSince1970: 1),
            endTime: Date(timeIntervalSince1970: 2),
            source: .outlook
        )

        let merged = MicrosoftSyncEngine.applyOutlookDelta(
            [initial, removed],
            to: [current],
            accountID: "account"
        )

        #expect(merged.count == 1)
        #expect(merged.first?.title == "New title")
        #expect(merged.first?.externalReference?.allowsContentModifications == false)
    }

    @Test("To Do completion remembers the last non-completed status for undo")
    func todoPreservesPreviousStatus() throws {
        let inProgress = try decodeTodoTask("""
        {"id":"task","title":"Task","status":"inProgress","importance":"normal"}
        """)
        let completed = try decodeTodoTask("""
        {"id":"task","title":"Task","status":"completed","importance":"normal"}
        """)

        let first = MicrosoftSyncEngine.applyTodoDelta(
            [inProgress],
            listID: "list",
            to: [],
            accountID: "account"
        )
        let second = MicrosoftSyncEngine.applyTodoDelta(
            [completed],
            listID: "list",
            to: first,
            accountID: "account"
        )

        let task = try #require(second.first)
        #expect(task.isCompleted)
        #expect(task.externalReference?.remoteStatus == "completed")
        #expect(task.externalReference?.previousRemoteStatus == "inProgress")
    }

    @Test("To Do identity is namespaced by account and list")
    func todoIdentityNamespace() throws {
        let task = try decodeTodoTask("""
        {"id":"same-id","title":"Task","status":"notStarted","importance":"normal"}
        """)
        let first = try #require(MicrosoftSyncEngine.applyTodoDelta(
            [task], listID: "list-a", to: [], accountID: "account"
        ).first)
        let second = try #require(MicrosoftSyncEngine.applyTodoDelta(
            [task], listID: "list-b", to: [], accountID: "account"
        ).first)

        #expect(first.id != second.id)
    }
}
