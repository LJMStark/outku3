import Foundation
import Testing
@testable import KiroleFeature

extension MicrosoftSyncEngineTests {
    @Test("Account switch state-save failure still replaces the previous account snapshot")
    @MainActor
    func accountSwitchStateSaveFailureCarriesReplacementSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MicrosoftSyncStateStore(directoryURL: directory)
        try await store.saveState(MicrosoftSyncState(accountID: "account-a"))
        try await store.enqueue(MicrosoftTodoOutboxEntry(
            accountID: "account-a",
            listID: "old-list",
            taskID: "old-task",
            targetStatus: .completed
        ))
        try await store.enqueue(MicrosoftTodoOutboxEntry(
            accountID: "account-b",
            listID: "account-b-list",
            taskID: "new-task",
            targetStatus: .completed
        ))

        let newEvent = try decodeOutlookEvent(
            """
            {
              "id": "account-b-event",
              "subject": "New account event",
              "start": {"dateTime": "2026-08-13T09:00:00.0000000", "timeZone": "UTC"},
              "end": {"dateTime": "2026-08-13T10:00:00.0000000", "timeZone": "UTC"},
              "isAllDay": false,
              "isCancelled": false
            }
            """
        )
        let graph = MicrosoftGraphStub(
            listSnapshot: [],
            failStatusUpdates: true,
            outlookSnapshot: [newEvent]
        )
        let engine = MicrosoftSyncEngine(
            graphClient: graph,
            stateStore: store,
            stateSaver: { _, _ in throw InjectedMicrosoftStateSaveError() },
            tokenProvider: MicrosoftTokenStub(accountID: "account-b")
        )
        let oldEvent = makeOutlookEvent(accountID: "account-a", itemID: "old-event")
        let oldTask = makeTodoTask(accountID: "account-a", listID: "old-list", itemID: "old-task")
        let localEvent = CalendarEvent(
            id: "local-event",
            title: "Keep event",
            startTime: Date(timeIntervalSince1970: 10),
            endTime: Date(timeIntervalSince1970: 20),
            source: .apple
        )
        let localTask = TaskItem(id: "local-task", title: "Keep task", source: .apple)
        let appState = AppState.makeForTesting()
        appState.events = [localEvent, oldEvent]
        appState.tasks = [localTask, oldTask]

        do {
            _ = try await engine.performSync(
                currentEvents: [oldEvent],
                currentTasks: [oldTask],
                includeOutlook: true,
                includeTodo: true
            )
            Issue.record("Expected Microsoft state persistence to fail")
        } catch MicrosoftSyncError.stateIOFailed(let failure) {
            #expect(failure.operation == .saveState)
            #expect(failure.result.didChangeAccount)
            #expect(failure.underlyingDescription.contains("injected state save failure"))
            #expect(appState.applyMicrosoftFailedSyncResult(
                failure.result,
                includeOutlook: true,
                includeTodo: true
            ))
        }

        #expect(appState.events.count == 2)
        #expect(appState.events.contains { $0.id == localEvent.id })
        #expect(appState.events.contains { $0.title == "New account event" })
        #expect(!appState.events.contains { $0.id == oldEvent.id })
        #expect(appState.tasks.map(\.id) == [localTask.id])
        #expect(try await store.loadState().accountID == "account-a")
        let outbox = try await store.loadOutbox()
        #expect(outbox.count == 1)
        #expect(outbox.first?.accountID == "account-b")
        #expect(outbox.first?.retryCount == 1)
    }

    @Test("Same-account state-save failure never overwrites a live local edit")
    @MainActor
    func sameAccountStateSaveFailureKeepsLiveSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MicrosoftSyncStateStore(directoryURL: directory)
        try await store.saveState(MicrosoftSyncState(accountID: "account-a"))
        let graph = MicrosoftGraphStub(listSnapshot: [], outlookSnapshot: [])
        let engine = MicrosoftSyncEngine(
            graphClient: graph,
            stateStore: store,
            stateSaver: { _, _ in throw InjectedMicrosoftStateSaveError() },
            tokenProvider: MicrosoftTokenStub(accountID: "account-a")
        )
        let event = makeOutlookEvent(accountID: "account-a", itemID: "event")
        let task = makeTodoTask(accountID: "account-a", listID: "list", itemID: "task")
        let appState = AppState.makeForTesting()
        appState.events = [event]
        appState.tasks = [task]

        do {
            _ = try await engine.performSync(
                currentEvents: [event],
                currentTasks: [task],
                includeOutlook: true,
                includeTodo: true
            )
            Issue.record("Expected Microsoft state persistence to fail")
        } catch MicrosoftSyncError.stateIOFailed(let failure) {
            #expect(failure.operation == .saveState)
            #expect(!failure.result.didChangeAccount)
            appState.tasks[0].isCompleted = true
            #expect(!appState.applyMicrosoftFailedSyncResult(
                failure.result,
                includeOutlook: true,
                includeTodo: true
            ))
        }

        #expect(appState.events.map(\.id) == [event.id])
        #expect(appState.tasks.map(\.id) == [task.id])
        #expect(appState.tasks.first?.isCompleted == true)
    }

    @Test("Account switch outbox-save failure still removes the previous account snapshot")
    @MainActor
    func accountSwitchOutboxSaveFailureCarriesScopedSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MicrosoftSyncStateStore(directoryURL: directory)
        try await store.saveState(MicrosoftSyncState(accountID: "account-a"))
        try await store.enqueue(MicrosoftTodoOutboxEntry(
            accountID: "account-a",
            listID: "old-list",
            taskID: "old-task",
            targetStatus: .completed
        ))
        let engine = MicrosoftSyncEngine(
            graphClient: MicrosoftGraphStub(listSnapshot: []),
            stateStore: store,
            accountBoundaryOutboxReconciler: { _, _ in
                throw MicrosoftSyncStoreIOFailure(
                    operation: .saveOutbox,
                    underlyingDescription: InjectedMicrosoftOutboxSaveError()
                        .localizedDescription
                )
            },
            tokenProvider: MicrosoftTokenStub(accountID: "account-b")
        )
        let oldEvent = makeOutlookEvent(accountID: "account-a", itemID: "old-event")
        let oldTask = makeTodoTask(accountID: "account-a", listID: "old-list", itemID: "old-task")
        let localTask = TaskItem(id: "local-task", title: "Keep task", source: .apple)
        let appState = AppState.makeForTesting()
        appState.events = [oldEvent]
        appState.tasks = [localTask, oldTask]

        do {
            _ = try await engine.performSync(
                currentEvents: [oldEvent],
                currentTasks: [oldTask],
                includeOutlook: true,
                includeTodo: true
            )
            Issue.record("Expected Microsoft outbox persistence to fail")
        } catch MicrosoftSyncError.stateIOFailed(let failure) {
            #expect(failure.operation == .saveOutbox)
            #expect(failure.result.didChangeAccount)
            #expect(appState.applyMicrosoftFailedSyncResult(
                failure.result,
                includeOutlook: true,
                includeTodo: true
            ))
        }

        #expect(appState.events.isEmpty)
        #expect(appState.tasks.map(\.id) == [localTask.id])
        #expect(try await store.loadState().accountID == "account-a")
        #expect(try await store.loadOutbox().first?.accountID == "account-a")
    }

    @Test("Corrupt state load still scopes an account switch before reporting the error")
    @MainActor
    func corruptStateLoadCarriesScopedAccountBoundary() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(
            to: directory.appendingPathComponent("microsoft_sync_state.json")
        )
        let store = MicrosoftSyncStateStore(directoryURL: directory)
        let engine = MicrosoftSyncEngine(
            graphClient: MicrosoftGraphStub(listSnapshot: []),
            stateStore: store,
            tokenProvider: MicrosoftTokenStub(accountID: "account-b")
        )
        let oldEvent = makeOutlookEvent(accountID: "account-a", itemID: "old-event")
        let oldTask = makeTodoTask(accountID: "account-a", listID: "old-list", itemID: "old-task")
        let localEvent = CalendarEvent(
            id: "local-event",
            title: "Keep event",
            startTime: Date(timeIntervalSince1970: 10),
            endTime: Date(timeIntervalSince1970: 20),
            source: .apple
        )
        let appState = AppState.makeForTesting()
        appState.events = [localEvent, oldEvent]
        appState.tasks = [oldTask]

        do {
            _ = try await engine.performSync(
                currentEvents: [oldEvent],
                currentTasks: [oldTask],
                includeOutlook: true,
                includeTodo: true
            )
            Issue.record("Expected corrupt Microsoft state to fail loading")
        } catch MicrosoftSyncError.stateIOFailed(let failure) {
            #expect(failure.operation == .loadState)
            #expect(failure.result.didChangeAccount)
            #expect(appState.applyMicrosoftFailedSyncResult(
                failure.result,
                includeOutlook: true,
                includeTodo: true
            ))
        }

        #expect(appState.events.map(\.id) == [localEvent.id])
        #expect(appState.tasks.isEmpty)
    }

    @Test("Account switch full failure removes the previous account from AppState")
    @MainActor
    func accountSwitchFullFailurePurgesPreviousAccountSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MicrosoftSyncStateStore(directoryURL: directory)
        try await store.saveState(MicrosoftSyncState(accountID: "account-a"))

        let newList = try decodeTodoList(
            """
            {"id":"account-b-list","displayName":"New"}
            """
        )
        let graph = MicrosoftGraphStub(
            listSnapshot: [newList],
            failTaskListID: "account-b-list"
        )
        let engine = MicrosoftSyncEngine(
            graphClient: graph,
            stateStore: store,
            tokenProvider: MicrosoftTokenStub(accountID: "account-b")
        )
        let oldEvent = makeOutlookEvent(accountID: "account-a", itemID: "old-event")
        let oldTask = makeTodoTask(accountID: "account-a", listID: "old-list", itemID: "old-task")
        let localEvent = CalendarEvent(
            id: "local-event",
            title: "Keep event",
            startTime: Date(timeIntervalSince1970: 10),
            endTime: Date(timeIntervalSince1970: 20),
            source: .apple
        )
        let localTask = TaskItem(id: "local-task", title: "Keep task", source: .apple)
        let appState = AppState.makeForTesting()
        appState.events = [localEvent, oldEvent]
        appState.tasks = [localTask, oldTask]

        do {
            _ = try await engine.performSync(
                currentEvents: [oldEvent],
                currentTasks: [oldTask],
                includeOutlook: true,
                includeTodo: true
            )
            Issue.record("Expected every enabled Microsoft endpoint to fail")
        } catch MicrosoftSyncError.fullSyncFailed(let result) {
            #expect(result.didChangeAccount)
            #expect(appState.applyMicrosoftFailedSyncResult(
                result,
                includeOutlook: true,
                includeTodo: true
            ))
        }

        #expect(appState.events.map(\.id) == [localEvent.id])
        #expect(appState.tasks.map(\.id) == [localTask.id])
        #expect(try await store.loadState().accountID == "account-b")
    }

    @Test("A persisted new-account marker still rejects an old AppState snapshot")
    @MainActor
    func persistedAccountMarkerCannotStrandPreviousAccountSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MicrosoftSyncStateStore(directoryURL: directory)
        // Models a process death after the engine commits B's account marker but before AppState
        // gets to persist the replacement snapshot.
        try await store.saveState(MicrosoftSyncState(accountID: "account-b"))
        try await store.enqueue(MicrosoftTodoOutboxEntry(
            accountID: "account-b",
            listID: "account-b-list",
            taskID: "pending-task",
            targetStatus: .completed
        ))

        let newList = try decodeTodoList(
            """
            {"id":"account-b-list","displayName":"New"}
            """
        )
        let graph = MicrosoftGraphStub(
            listSnapshot: [newList],
            failTaskListID: "account-b-list",
            failStatusUpdates: true
        )
        let engine = MicrosoftSyncEngine(
            graphClient: graph,
            stateStore: store,
            tokenProvider: MicrosoftTokenStub(accountID: "account-b")
        )
        let oldEvent = makeOutlookEvent(accountID: "account-a", itemID: "old-event")
        let oldTask = makeTodoTask(accountID: "account-a", listID: "old-list", itemID: "old-task")
        let appState = AppState.makeForTesting()
        appState.events = [oldEvent]
        appState.tasks = [oldTask]

        do {
            _ = try await engine.performSync(
                currentEvents: [oldEvent],
                currentTasks: [oldTask],
                includeOutlook: true,
                includeTodo: true
            )
            Issue.record("Expected every enabled Microsoft endpoint to fail")
        } catch MicrosoftSyncError.fullSyncFailed(let result) {
            #expect(result.didChangeAccount)
            #expect(appState.applyMicrosoftFailedSyncResult(
                result,
                includeOutlook: true,
                includeTodo: true
            ))
        }

        #expect(appState.events.isEmpty)
        #expect(appState.tasks.isEmpty)
        let outbox = try await store.loadOutbox()
        #expect(outbox.count == 1)
        #expect(outbox.first?.accountID == "account-b")
        #expect(outbox.first?.retryCount == 1)
    }

    @Test("Account switch partial success never regrafts the previous account")
    @MainActor
    func accountSwitchPartialSuccessPurgesFailedProviderSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MicrosoftSyncStateStore(directoryURL: directory)
        try await store.saveState(MicrosoftSyncState(accountID: "account-a"))

        let newEvent = try decodeOutlookEvent(
            """
            {
              "id": "account-b-event",
              "subject": "New account event",
              "start": {"dateTime": "2026-08-13T09:00:00.0000000", "timeZone": "UTC"},
              "end": {"dateTime": "2026-08-13T10:00:00.0000000", "timeZone": "UTC"},
              "isAllDay": false,
              "isCancelled": false
            }
            """
        )
        let newList = try decodeTodoList(
            """
            {"id":"account-b-list","displayName":"New"}
            """
        )
        let graph = MicrosoftGraphStub(
            listSnapshot: [newList],
            failTaskListID: "account-b-list",
            outlookSnapshot: [newEvent]
        )
        let engine = MicrosoftSyncEngine(
            graphClient: graph,
            stateStore: store,
            tokenProvider: MicrosoftTokenStub(accountID: "account-b")
        )
        let oldEvent = makeOutlookEvent(accountID: "account-a", itemID: "old-event")
        let oldTask = makeTodoTask(accountID: "account-a", listID: "old-list", itemID: "old-task")
        let appState = AppState.makeForTesting()
        appState.events = [oldEvent]
        appState.tasks = [oldTask]

        let result = try await engine.performSync(
            currentEvents: [oldEvent],
            currentTasks: [oldTask],
            includeOutlook: true,
            includeTodo: true
        )
        appState.applyMicrosoftSyncResult(
            result,
            includeOutlook: true,
            includeTodo: true
        )

        #expect(result.didChangeAccount)
        #expect(result.warnings.count == 1)
        #expect(appState.events.count == 1)
        #expect(appState.events.first?.title == "New account event")
        #expect(appState.events.first?.externalReference?.accountID == "account-b")
        #expect(appState.tasks.isEmpty)
    }

    @Test("Same-account full failure keeps the offline AppState snapshot")
    @MainActor
    func sameAccountFullFailureKeepsOfflineSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MicrosoftSyncStateStore(directoryURL: directory)
        try await store.saveState(MicrosoftSyncState(accountID: "account-a"))

        let list = try decodeTodoList(
            """
            {"id":"list","displayName":"Existing"}
            """
        )
        let graph = MicrosoftGraphStub(listSnapshot: [list], failTaskListID: "list")
        let engine = MicrosoftSyncEngine(
            graphClient: graph,
            stateStore: store,
            tokenProvider: MicrosoftTokenStub(accountID: "account-a")
        )
        let oldEvent = makeOutlookEvent(accountID: "account-a", itemID: "old-event")
        let oldTask = makeTodoTask(accountID: "account-a", listID: "list", itemID: "old-task")
        let appState = AppState.makeForTesting()
        appState.events = [oldEvent]
        appState.tasks = [oldTask]

        do {
            _ = try await engine.performSync(
                currentEvents: [oldEvent],
                currentTasks: [oldTask],
                includeOutlook: true,
                includeTodo: true
            )
            Issue.record("Expected every enabled Microsoft endpoint to fail")
        } catch MicrosoftSyncError.fullSyncFailed(let result) {
            #expect(!result.didChangeAccount)
            appState.tasks[0].isCompleted = true
            #expect(!appState.applyMicrosoftFailedSyncResult(
                result,
                includeOutlook: true,
                includeTodo: true
            ))
        }

        #expect(appState.events.map(\.id) == [oldEvent.id])
        #expect(appState.tasks.map(\.id) == [oldTask.id])
        #expect(appState.tasks.first?.isCompleted == true)
    }
}
