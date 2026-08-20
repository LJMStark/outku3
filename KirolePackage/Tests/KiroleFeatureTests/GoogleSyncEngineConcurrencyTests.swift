import Foundation
import Testing
@testable import KiroleFeature

@Suite("Google sync account isolation")
struct GoogleSyncEngineConcurrencyTests {
    @Test("Google remote refresh keeps local today display selection")
    func googleRemoteKeepsLocalTodayDisplaySelection() {
        let selectedDate = Date(timeIntervalSince1970: 1_700_020_000)
        let local = TaskItem(
            id: "google-1",
            googleTaskId: "google-1",
            googleTaskListId: "list-1",
            title: "Local",
            source: .google,
            todayDisplayDate: selectedDate
        )
        let remote = TaskItem(
            id: "google-1",
            googleTaskId: "google-1",
            googleTaskListId: "list-1",
            title: "Remote",
            source: .google
        )

        let merged = GoogleSyncEngine.mergeRemoteTaskPreservingLocalFields(
            local: local,
            remote: remote
        )

        #expect(merged.title == "Remote")
        #expect(merged.todayDisplayDate == selectedDate)
        #expect(merged.localId == local.localId)
    }

    @Test("A successful suspended pull cannot recreate metadata after reset")
    func successfulPullCannotCommitAfterReset() async throws {
        let calendar = SuspendedGoogleCalendarSyncStub()
        let tasks = RecordingGoogleTasksSyncStub()
        let storage = InMemoryGoogleSyncStateStore()
        let engine = GoogleSyncEngine(
            calendarAPI: calendar,
            tasksAPI: tasks,
            storage: storage
        )

        let sync = Task {
            try await engine.performFullSync(
                currentEvents: [],
                currentTasks: [],
                includeCalendar: true,
                includeTasks: false
            )
        }
        await calendar.waitForFetch()
        try await engine.resetAndDisable()
        await calendar.succeed(with: [])

        await expectStaleGoogleOperation(from: sync)
        #expect(try await storage.loadGoogleSyncMetadata() == nil)
        #expect(await storage.metadataSaveCount() == 0)
    }

    @Test("A failed suspended pull cannot recreate metadata after reset")
    func failedPullCannotCommitAfterReset() async throws {
        let calendar = SuspendedGoogleCalendarSyncStub()
        let tasks = RecordingGoogleTasksSyncStub()
        let storage = InMemoryGoogleSyncStateStore()
        let engine = GoogleSyncEngine(
            calendarAPI: calendar,
            tasksAPI: tasks,
            storage: storage
        )

        let sync = Task {
            try await engine.performFullSync(
                currentEvents: [],
                currentTasks: [],
                includeCalendar: true,
                includeTasks: false
            )
        }
        await calendar.waitForFetch()
        try await engine.resetAndDisable()
        await calendar.fail()

        await expectStaleGoogleOperation(from: sync)
        #expect(try await storage.loadGoogleSyncMetadata() == nil)
        #expect(await storage.metadataSaveCount() == 0)
    }

    @Test("Reset clears persisted outbox and metadata")
    func resetClearsPersistedState() async throws {
        let entry = makeGoogleOutboxEntry(id: "old")
        var metadata = GoogleSyncMetadata()
        metadata.lastFullSyncTime = Date()
        let storage = InMemoryGoogleSyncStateStore(metadata: metadata, outbox: [entry])
        let engine = GoogleSyncEngine(
            calendarAPI: ImmediateGoogleCalendarSyncStub(),
            tasksAPI: RecordingGoogleTasksSyncStub(),
            storage: storage
        )

        try await engine.resetAndDisable()

        #expect(try await storage.loadGoogleSyncMetadata() == nil)
        #expect(try await storage.loadOutbox().isEmpty)
        #expect(await storage.resetCount() == 1)
    }

    @Test("A successful suspended flush stops before the next write and stays cleared")
    func successfulFlushStopsAfterReset() async throws {
        try await verifySuspendedFlushAfterReset(completion: .success)
    }

    @Test("A failed suspended flush stops before the next write and stays cleared")
    func failedFlushStopsAfterReset() async throws {
        try await verifySuspendedFlushAfterReset(completion: .failure)
    }

    @Test("The next authorized account never flushes the previous account outbox")
    func nextAccountDoesNotFlushOldOutbox() async throws {
        let storage = InMemoryGoogleSyncStateStore(outbox: [makeGoogleOutboxEntry(id: "account-a")])
        let tasks = RecordingGoogleTasksSyncStub()
        let engine = GoogleSyncEngine(
            calendarAPI: ImmediateGoogleCalendarSyncStub(),
            tasksAPI: tasks,
            storage: storage
        )

        try await engine.resetAndDisable()
        try await engine.activateAfterAuthorization()
        _ = try await engine.performFullSync(
            currentEvents: [],
            currentTasks: [],
            includeCalendar: false,
            includeTasks: true
        )

        #expect(await tasks.sentEntryIDs().isEmpty)
        #expect(try await storage.loadOutbox().isEmpty)
    }

    private func verifySuspendedFlushAfterReset(
        completion: SuspendedGoogleTasksSyncStub.Completion
    ) async throws {
        let first = makeGoogleOutboxEntry(id: "first")
        let second = makeGoogleOutboxEntry(id: "second")
        let storage = InMemoryGoogleSyncStateStore(outbox: [first, second])
        let tasks = SuspendedGoogleTasksSyncStub()
        let engine = GoogleSyncEngine(
            calendarAPI: ImmediateGoogleCalendarSyncStub(),
            tasksAPI: tasks,
            storage: storage
        )

        let sync = Task {
            try await engine.performFullSync(
                currentEvents: [],
                currentTasks: [],
                includeCalendar: false,
                includeTasks: true
            )
        }
        await tasks.waitForFirstWrite()
        try await engine.resetAndDisable()
        switch completion {
        case .success:
            await tasks.succeedFirstWrite()
        case .failure:
            await tasks.failFirstWrite()
        }

        await expectStaleGoogleOperation(from: sync)
        #expect(await tasks.sentEntryIDs() == ["first"])
        #expect(try await storage.loadOutbox().isEmpty)

        try await engine.activateAfterAuthorization()
        _ = try await engine.performFullSync(
            currentEvents: [],
            currentTasks: [],
            includeCalendar: false,
            includeTasks: true
        )
        #expect(await tasks.sentEntryIDs() == ["first"])
        #expect(try await storage.loadOutbox().isEmpty)
    }
}

private func makeGoogleOutboxEntry(id: String) -> OutboxEntry {
    OutboxEntry(
        taskItem: TaskItem(
            id: id,
            googleTaskId: id,
            googleTaskListId: "list",
            title: id,
            isCompleted: true,
            source: .google
        ),
        action: .updateStatus
    )
}

private func expectStaleGoogleOperation<Success>(
    from task: Task<Success, Error>,
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    do {
        _ = try await task.value
        Issue.record("Expected a stale Google operation", sourceLocation: sourceLocation)
    } catch GoogleSyncEngineError.staleOperation {
        // Expected.
    } catch {
        Issue.record("Expected staleOperation, got \(error)", sourceLocation: sourceLocation)
    }
}

private actor InMemoryGoogleSyncStateStore: GoogleSyncStateStoring {
    private var metadata: GoogleSyncMetadata?
    private var outbox: [OutboxEntry]
    private var metadataSaves = 0
    private var resets = 0

    init(
        metadata: GoogleSyncMetadata? = nil,
        outbox: [OutboxEntry] = []
    ) {
        self.metadata = metadata
        self.outbox = outbox
    }

    func loadGoogleSyncMetadata() throws -> GoogleSyncMetadata? {
        metadata
    }

    func saveGoogleSyncMetadata(_ metadata: GoogleSyncMetadata) throws {
        metadataSaves += 1
        self.metadata = metadata
    }

    func loadOutbox() throws -> [OutboxEntry] {
        outbox
    }

    func saveOutbox(_ entries: [OutboxEntry]) throws {
        outbox = entries
    }

    func resetGoogleSyncState() throws {
        resets += 1
        metadata = nil
        outbox = []
    }

    func metadataSaveCount() -> Int {
        metadataSaves
    }

    func resetCount() -> Int {
        resets
    }
}

private struct ImmediateGoogleCalendarSyncStub: GoogleCalendarSyncServing {
    func fetchTodayEvents() async throws -> [CalendarEvent] { [] }
}

private actor SuspendedGoogleCalendarSyncStub: GoogleCalendarSyncServing {
    private var continuation: CheckedContinuation<[CalendarEvent], Error>?
    private var fetchWaiters: [CheckedContinuation<Void, Never>] = []

    func fetchTodayEvents() async throws -> [CalendarEvent] {
        signalFetchStarted()
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func waitForFetch() async {
        if continuation != nil { return }
        await withCheckedContinuation { fetchWaiters.append($0) }
    }

    func succeed(with events: [CalendarEvent]) {
        continuation?.resume(returning: events)
        continuation = nil
    }

    func fail() {
        continuation?.resume(throwing: GoogleSyncConcurrencyTestError.remoteFailure)
        continuation = nil
    }

    private func signalFetchStarted() {
        let waiters = fetchWaiters
        fetchWaiters = []
        for waiter in waiters { waiter.resume() }
    }
}

private actor RecordingGoogleTasksSyncStub: GoogleTasksSyncServing {
    private var sentIDs: [String] = []

    func fetchTasks(updatedMin: Date?) async throws -> [TaskItem] { [] }

    func send(_ entry: OutboxEntry) async throws {
        sentIDs.append(entry.taskItem.id)
    }

    func sentEntryIDs() -> [String] { sentIDs }
}

private actor SuspendedGoogleTasksSyncStub: GoogleTasksSyncServing {
    enum Completion {
        case success
        case failure
    }

    private var sentIDs: [String] = []
    private var firstWriteContinuation: CheckedContinuation<Void, Error>?
    private var firstWriteWaiters: [CheckedContinuation<Void, Never>] = []

    func fetchTasks(updatedMin: Date?) async throws -> [TaskItem] { [] }

    func send(_ entry: OutboxEntry) async throws {
        sentIDs.append(entry.taskItem.id)
        if sentIDs.count == 1 {
            signalFirstWriteStarted()
            try await withCheckedThrowingContinuation { firstWriteContinuation = $0 }
        }
    }

    func waitForFirstWrite() async {
        if firstWriteContinuation != nil { return }
        await withCheckedContinuation { firstWriteWaiters.append($0) }
    }

    func succeedFirstWrite() {
        firstWriteContinuation?.resume()
        firstWriteContinuation = nil
    }

    func failFirstWrite() {
        firstWriteContinuation?.resume(throwing: GoogleSyncConcurrencyTestError.remoteFailure)
        firstWriteContinuation = nil
    }

    func sentEntryIDs() -> [String] { sentIDs }

    private func signalFirstWriteStarted() {
        let waiters = firstWriteWaiters
        firstWriteWaiters = []
        for waiter in waiters { waiter.resume() }
    }
}

private enum GoogleSyncConcurrencyTestError: Error {
    case remoteFailure
}
