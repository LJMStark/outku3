import Foundation
import Testing
@testable import KiroleFeature

extension MicrosoftSyncEngineTests {
    func decodeOutlookEvent(_ json: String) throws -> MicrosoftOutlookEvent {
        try JSONDecoder().decode(MicrosoftOutlookEvent.self, from: Data(json.utf8))
    }

    func decodeTodoTask(_ json: String) throws -> MicrosoftTodoTask {
        try JSONDecoder().decode(MicrosoftTodoTask.self, from: Data(json.utf8))
    }

    func decodeTodoList(_ json: String) throws -> MicrosoftTodoList {
        try JSONDecoder().decode(MicrosoftTodoList.self, from: Data(json.utf8))
    }

    func makeOutlookEvent(accountID: String, itemID: String) -> CalendarEvent {
        let reference = ProviderItemReference(
            provider: .outlook,
            accountID: accountID,
            containerID: "default",
            itemID: itemID,
            region: .global,
            allowsContentModifications: false
        )
        return CalendarEvent(
            id: reference.stableLocalID,
            externalReference: reference,
            title: "Old account event",
            startTime: Date(timeIntervalSince1970: 1),
            endTime: Date(timeIntervalSince1970: 2),
            source: .outlook
        )
    }

    func makeTodoTask(
        accountID: String,
        listID: String,
        itemID: String,
        isCompleted: Bool = false
    ) -> TaskItem {
        let reference = ProviderItemReference(
            provider: .microsoftToDo,
            accountID: accountID,
            containerID: listID,
            itemID: itemID,
            region: .global,
            allowsContentModifications: true
        )
        return TaskItem(
            id: reference.stableLocalID,
            externalReference: reference,
            title: "Old account task",
            isCompleted: isCompleted,
            source: .microsoftToDo
        )
    }

    func expectStaleOperation(
        from operation: Task<Void, any Error>
    ) async {
        do {
            try await operation.value
            Issue.record("Expected staleOperation")
        } catch MicrosoftSyncError.staleOperation {
            // Expected.
        } catch {
            Issue.record("Expected staleOperation, got \(error)")
        }
    }
}

struct MicrosoftTokenStub: MicrosoftTokenProviding {
    let accountIDValue: String

    init(accountID: String) {
        self.accountIDValue = accountID
    }

    func accessToken() async throws -> String { "token" }
    func forceRefresh() async throws -> String { "token" }
    func accountID() async -> String? { accountIDValue }
}

actor MutableMicrosoftTokenStub: MicrosoftTokenProviding {
    private var currentAccountID: String?

    init(accountID: String?) {
        self.currentAccountID = accountID
    }

    func accessToken() async throws -> String { "token" }
    func forceRefresh() async throws -> String { "token" }
    func accountID() async -> String? { currentAccountID }

    func setAccountID(_ accountID: String?) {
        currentAccountID = accountID
    }
}

struct InjectedMicrosoftStateSaveError: LocalizedError {
    var errorDescription: String? { "injected state save failure" }
}

struct InjectedMicrosoftOutboxSaveError: LocalizedError {
    var errorDescription: String? { "injected outbox save failure" }
}

actor MicrosoftGraphStub: MicrosoftGraphServing {
    let listSnapshot: [MicrosoftTodoList]
    let failTaskListID: String?
    let failStatusUpdates: Bool
    let statusUpdateError: (any Error)?
    let outlookSnapshot: [MicrosoftOutlookEvent]?
    private var statusUpdates = 0

    init(
        listSnapshot: [MicrosoftTodoList],
        failTaskListID: String? = nil,
        failStatusUpdates: Bool = false,
        statusUpdateError: (any Error)? = nil,
        outlookSnapshot: [MicrosoftOutlookEvent]? = nil
    ) {
        self.listSnapshot = listSnapshot
        self.failTaskListID = failTaskListID
        self.failStatusUpdates = failStatusUpdates
        self.statusUpdateError = statusUpdateError
        self.outlookSnapshot = outlookSnapshot
    }

    func fetchDefaultCalendarDelta(
        deltaLink: String?,
        start: Date,
        end: Date,
        accessToken: String?
    ) async throws -> MicrosoftDeltaBatch<MicrosoftOutlookEvent> {
        guard let outlookSnapshot else {
            throw MicrosoftGraphError.invalidResponse
        }
        return MicrosoftDeltaBatch(items: outlookSnapshot, deltaLink: "fresh-outlook-delta")
    }

    func fetchTodoListsDelta(
        deltaLink: String?,
        accessToken: String?
    ) async throws -> MicrosoftDeltaBatch<MicrosoftTodoList> {
        if deltaLink != nil {
            throw MicrosoftGraphError.deltaTokenExpired
        }
        return MicrosoftDeltaBatch(items: listSnapshot, deltaLink: "fresh-lists-delta")
    }

    func fetchTodoTasksDelta(
        listID: String,
        deltaLink: String?,
        accessToken: String?
    ) async throws -> MicrosoftDeltaBatch<MicrosoftTodoTask> {
        if listID == failTaskListID {
            throw MicrosoftGraphError.invalidResponse
        }
        return MicrosoftDeltaBatch(items: [], deltaLink: "fresh-task-delta-\(listID)")
    }

    func updateTodoTaskStatus(
        listID: String,
        taskID: String,
        status: MicrosoftTodoStatus,
        accessToken: String?
    ) async throws {
        statusUpdates += 1
        if let statusUpdateError {
            throw statusUpdateError
        }
        if failStatusUpdates {
            throw MicrosoftGraphError.invalidResponse
        }
    }

    func statusUpdateCallCount() -> Int {
        statusUpdates
    }
}

actor SuspendedMicrosoftGraphStub: MicrosoftGraphServing {
    private var calendarContinuation:
        CheckedContinuation<MicrosoftDeltaBatch<MicrosoftOutlookEvent>, any Error>?
    private var calendarStarted = false
    private var calendarStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var statusContinuation: CheckedContinuation<Void, any Error>?
    private var statusStarted = false
    private var statusStartWaiters: [CheckedContinuation<Void, Never>] = []

    func fetchDefaultCalendarDelta(
        deltaLink: String?,
        start: Date,
        end: Date,
        accessToken: String?
    ) async throws -> MicrosoftDeltaBatch<MicrosoftOutlookEvent> {
        calendarStarted = true
        let waiters = calendarStartWaiters
        calendarStartWaiters.removeAll()
        waiters.forEach { $0.resume() }
        return try await withCheckedThrowingContinuation { continuation in
            calendarContinuation = continuation
        }
    }

    func fetchTodoListsDelta(
        deltaLink: String?,
        accessToken: String?
    ) async throws -> MicrosoftDeltaBatch<MicrosoftTodoList> {
        MicrosoftDeltaBatch(items: [], deltaLink: "lists-delta")
    }

    func fetchTodoTasksDelta(
        listID: String,
        deltaLink: String?,
        accessToken: String?
    ) async throws -> MicrosoftDeltaBatch<MicrosoftTodoTask> {
        MicrosoftDeltaBatch(items: [], deltaLink: "tasks-delta")
    }

    func updateTodoTaskStatus(
        listID: String,
        taskID: String,
        status: MicrosoftTodoStatus,
        accessToken: String?
    ) async throws {
        statusStarted = true
        let waiters = statusStartWaiters
        statusStartWaiters.removeAll()
        waiters.forEach { $0.resume() }
        try await withCheckedThrowingContinuation { continuation in
            statusContinuation = continuation
        }
    }

    func waitForCalendarRequest() async {
        guard !calendarStarted else { return }
        await withCheckedContinuation { continuation in
            calendarStartWaiters.append(continuation)
        }
    }

    func succeedCalendar(with items: [MicrosoftOutlookEvent]) {
        calendarContinuation?.resume(returning: MicrosoftDeltaBatch(
            items: items,
            deltaLink: "calendar-delta"
        ))
        calendarContinuation = nil
    }

    func waitForStatusUpdate() async {
        guard !statusStarted else { return }
        await withCheckedContinuation { continuation in
            statusStartWaiters.append(continuation)
        }
    }

    func succeedStatusUpdate() {
        statusContinuation?.resume()
        statusContinuation = nil
    }

    func failStatusUpdate() {
        statusContinuation?.resume(throwing: MicrosoftGraphError.invalidResponse)
        statusContinuation = nil
    }
}
