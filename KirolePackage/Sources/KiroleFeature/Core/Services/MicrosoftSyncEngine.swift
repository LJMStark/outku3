import Foundation

protocol MicrosoftGraphServing: Sendable {
    func fetchDefaultCalendarDelta(
        deltaLink: String?,
        start: Date,
        end: Date,
        accessToken: String?
    ) async throws -> MicrosoftDeltaBatch<MicrosoftOutlookEvent>
    func fetchTodoListsDelta(
        deltaLink: String?,
        accessToken: String?
    ) async throws -> MicrosoftDeltaBatch<MicrosoftTodoList>
    func fetchTodoTasksDelta(
        listID: String,
        deltaLink: String?,
        accessToken: String?
    ) async throws -> MicrosoftDeltaBatch<MicrosoftTodoTask>
    func updateTodoTaskStatus(
        listID: String,
        taskID: String,
        status: MicrosoftTodoStatus,
        accessToken: String?
    ) async throws
}

extension MicrosoftGraphClient: MicrosoftGraphServing {}

typealias MicrosoftSyncStateSaver = @Sendable (MicrosoftSyncState, UInt64) async throws -> Void
typealias MicrosoftAccountBoundaryOutboxReconciler = @Sendable (String, UInt64) async throws -> Void

@MainActor
enum MicrosoftSyncCommitGate {
    struct Boundary: Sendable, Equatable {
        fileprivate let id: UUID
    }

    private static var generation: UInt64 = 0
    private static var activeBoundaryID: UUID?

    static func beginTransition() throws -> Boundary {
        guard activeBoundaryID == nil else {
            throw MicrosoftSyncError.accountTransitionInProgress
        }
        generation &+= 1
        let boundary = Boundary(id: UUID())
        activeBoundaryID = boundary.id
        return boundary
    }

    static func finishTransition(_ boundary: Boundary) {
        guard activeBoundaryID == boundary.id else { return }
        generation &+= 1
        activeBoundaryID = nil
    }

    static func captureGeneration() -> UInt64? {
        guard activeBoundaryID == nil else { return nil }
        return generation
    }

    static func accepts(_ expectedGeneration: UInt64?) -> Bool {
        guard activeBoundaryID == nil,
              let expectedGeneration else { return false }
        return generation == expectedGeneration
    }
}

fileprivate struct MicrosoftSyncOperationOwner: Sendable, Hashable {
    let accountID: String
    let generation: UInt64
}

fileprivate struct MicrosoftSyncOperationContext: Sendable {
    let owner: MicrosoftSyncOperationOwner
    let storeEpoch: UInt64
    let commitGeneration: UInt64
    let accessToken: String

    var resultLease: MicrosoftSyncResultLease {
        MicrosoftSyncResultLease(
            owner: owner,
            storeEpoch: storeEpoch,
            commitGeneration: commitGeneration
        )
    }
}

fileprivate struct MicrosoftSyncResultLease: Sendable {
    let owner: MicrosoftSyncOperationOwner
    let storeEpoch: UInt64
    let commitGeneration: UInt64
}

struct MicrosoftSyncAccountTransition: Sendable, Equatable {
    fileprivate let id: UUID
}

public struct MicrosoftSyncResult: Sendable {
    public let events: [CalendarEvent]
    public let tasks: [TaskItem]
    public let warnings: [String]
    /// True when this sync crossed a Microsoft account boundary. Consumers must replace every
    /// Microsoft provider snapshot in that case, even when the new account's first pull fails.
    public let didChangeAccount: Bool
    fileprivate let operationLease: MicrosoftSyncResultLease?

    @MainActor
    var isCurrentForAppStateCommit: Bool {
        MicrosoftSyncCommitGate.accepts(operationLease?.commitGeneration)
    }

    public init(
        events: [CalendarEvent],
        tasks: [TaskItem],
        warnings: [String],
        didChangeAccount: Bool = false
    ) {
        self.events = events
        self.tasks = tasks
        self.warnings = warnings
        self.didChangeAccount = didChangeAccount
        self.operationLease = nil
    }

    fileprivate init(
        events: [CalendarEvent],
        tasks: [TaskItem],
        warnings: [String],
        didChangeAccount: Bool,
        operationContext: MicrosoftSyncOperationContext
    ) {
        self.events = events
        self.tasks = tasks
        self.warnings = warnings
        self.didChangeAccount = didChangeAccount
        self.operationLease = operationContext.resultLease
    }
}

/// Incremental sync for Outlook's default calendar and Microsoft To Do.
///
/// Outlook is intentionally read-only. To Do completion writes use a durable target-state outbox;
/// failures never erase the local task and are retried before the next remote pull.
public actor MicrosoftSyncEngine {
    public static let shared = MicrosoftSyncEngine()

    private let graphClient: any MicrosoftGraphServing
    private let stateStore: MicrosoftSyncStateStore
    private let stateSaver: MicrosoftSyncStateSaver
    private let accountBoundaryOutboxReconciler: MicrosoftAccountBoundaryOutboxReconciler
    private let tokenProvider: any MicrosoftTokenProviding
    private var operationGeneration: UInt64 = 0
    private var activeSyncOwners: Set<MicrosoftSyncOperationOwner> = []
    private var activeAccountTransitionID: UUID?

    private static let outlookPastWindow: TimeInterval = 24 * 60 * 60
    private static let outlookFutureWindow: TimeInterval = 30 * 24 * 60 * 60
    private static let outlookWindowRefreshLead: TimeInterval = 7 * 24 * 60 * 60

    init(
        graphClient: any MicrosoftGraphServing = MicrosoftGraphClient.shared,
        stateStore: MicrosoftSyncStateStore = .shared,
        stateSaver: MicrosoftSyncStateSaver? = nil,
        accountBoundaryOutboxReconciler: MicrosoftAccountBoundaryOutboxReconciler? = nil,
        tokenProvider: any MicrosoftTokenProviding = MicrosoftTokenProviderBridge()
    ) {
        self.graphClient = graphClient
        self.stateStore = stateStore
        self.stateSaver = stateSaver ?? { state, expectedEpoch in
            try await stateStore.saveState(state, expectedEpoch: expectedEpoch)
        }
        self.accountBoundaryOutboxReconciler = accountBoundaryOutboxReconciler
            ?? { accountID, expectedEpoch in
                try await stateStore.retainOutbox(
                    forAccountID: accountID,
                    expectedEpoch: expectedEpoch
                )
        }
        self.tokenProvider = tokenProvider
    }

    public func performSync(
        currentEvents: [CalendarEvent],
        currentTasks: [TaskItem],
        includeOutlook: Bool,
        includeTodo: Bool
    ) async throws -> MicrosoftSyncResult {
        let owner = try await captureOperationOwner()
        let context = try await captureOperationContext(owner: owner)
        guard !activeSyncOwners.contains(owner) else {
            return MicrosoftSyncResult(
                events: currentEvents,
                tasks: currentTasks,
                warnings: [],
                didChangeAccount: false,
                operationContext: context
            )
        }
        activeSyncOwners.insert(owner)
        defer { activeSyncOwners.remove(owner) }

        let accountID = owner.accountID
        let scopedCurrentEvents = currentEvents.filter { event in
            event.source != .outlook || event.externalReference?.accountID == accountID
        }
        let scopedCurrentTasks = currentTasks.filter { task in
            task.source != .microsoftToDo || task.externalReference?.accountID == accountID
        }
        let snapshotContainsDifferentAccount = scopedCurrentEvents.count != currentEvents.count
            || scopedCurrentTasks.count != currentTasks.count
        var state: MicrosoftSyncState
        do {
            state = try await stateStore.loadState()
            try await validateOperation(context)
        } catch MicrosoftSyncError.staleOperation {
            throw MicrosoftSyncError.staleOperation
        } catch {
            try await validateOperation(context)
            guard snapshotContainsDifferentAccount else { throw error }
            throw MicrosoftSyncError.stateIOFailed(
                MicrosoftSyncStateIOFailure(
                    operation: .loadState,
                    result: MicrosoftSyncResult(
                        events: scopedCurrentEvents,
                        tasks: scopedCurrentTasks,
                        warnings: [],
                        didChangeAccount: true,
                        operationContext: context
                    ),
                    underlyingDescription: error.localizedDescription
                )
            )
        }
        let storedAccountDidChange = state.accountID != accountID
        // The state marker and AppState snapshots live in separate atomic files. Also inspect the
        // data itself so a process death between those commits cannot strand account A behind B's
        // already-persisted marker on the next full network failure.
        let didChangeAccount = storedAccountDidChange
            || snapshotContainsDifferentAccount
        if storedAccountDidChange {
            state = MicrosoftSyncState(accountID: accountID)
            // Remove writes owned by the old identity while retaining any current-account intent
            // created after an earlier state-save failure. The account marker is committed only
            // once at the end with its final cursors, so retrying the boundary remains safe.
            let accountBoundaryResult = MicrosoftSyncResult(
                events: scopedCurrentEvents,
                tasks: scopedCurrentTasks,
                warnings: [],
                didChangeAccount: true,
                operationContext: context
            )
            do {
                try await validateOperation(context)
                try await accountBoundaryOutboxReconciler(accountID, context.storeEpoch)
                try await validateOperation(context)
            } catch MicrosoftSyncError.staleOperation {
                throw MicrosoftSyncError.staleOperation
            } catch is MicrosoftSyncStoreEpochMismatch {
                throw MicrosoftSyncError.staleOperation
            } catch {
                try await validateOperation(context)
                let storeFailure = error as? MicrosoftSyncStoreIOFailure
                throw MicrosoftSyncError.stateIOFailed(
                    MicrosoftSyncStateIOFailure(
                        operation: storeFailure?.operation ?? .saveOutbox,
                        result: accountBoundaryResult,
                        underlyingDescription: storeFailure?.underlyingDescription
                            ?? error.localizedDescription
                    )
                )
            }
        }

        var events = scopedCurrentEvents
        var tasks = scopedCurrentTasks
        var warnings: [String] = []
        var successfulSteps = 0
        let attemptedSteps = (includeOutlook ? 1 : 0) + (includeTodo ? 1 : 0)

        if includeTodo {
            let outboxWarnings = try await flushTodoOutbox(context: context)
            warnings.append(contentsOf: outboxWarnings)
        }

        if includeOutlook {
            do {
                events = try await syncOutlook(
                    currentEvents: scopedCurrentEvents,
                    accountID: accountID,
                    state: &state,
                    context: context
                )
                successfulSteps += 1
            } catch MicrosoftSyncError.staleOperation {
                throw MicrosoftSyncError.staleOperation
            } catch {
                try await validateOperation(context)
                warnings.append("Outlook Calendar sync failed: \(error.localizedDescription)")
            }
        }

        if includeTodo {
            do {
                // A provider step is transactional from the cursor's point of view. Do not
                // persist list/task delta links unless every list snapshot completed.
                var candidateState = state
                tasks = try await syncTodo(
                    currentTasks: scopedCurrentTasks,
                    accountID: accountID,
                    state: &candidateState,
                    context: context
                )
                state = candidateState
                successfulSteps += 1
            } catch MicrosoftSyncError.staleOperation {
                throw MicrosoftSyncError.staleOperation
            } catch {
                try await validateOperation(context)
                warnings.append("Microsoft To Do sync failed: \(error.localizedDescription)")
            }
        }

        let result = MicrosoftSyncResult(
            events: events,
            tasks: tasks,
            warnings: warnings,
            didChangeAccount: didChangeAccount,
            operationContext: context
        )
        do {
            try await validateOperation(context)
            try await stateSaver(state, context.storeEpoch)
            try await validateOperation(context)
        } catch MicrosoftSyncError.staleOperation {
            throw MicrosoftSyncError.staleOperation
        } catch is MicrosoftSyncStoreEpochMismatch {
            throw MicrosoftSyncError.staleOperation
        } catch {
            try await validateOperation(context)
            throw MicrosoftSyncError.stateIOFailed(
                MicrosoftSyncStateIOFailure(
                    operation: .saveState,
                    result: result,
                    underlyingDescription: error.localizedDescription
                )
            )
        }
        guard attemptedSteps == 0 || successfulSteps > 0 else {
            // The replacement snapshot is part of the failure: after an account switch it is
            // empty by design, while a same-account failure carries the offline snapshot through.
            throw MicrosoftSyncError.fullSyncFailed(result)
        }
        try await validateOperation(context)
        return result
    }

    // MARK: Outlook

    private func syncOutlook(
        currentEvents: [CalendarEvent],
        accountID: String,
        state: inout MicrosoftSyncState,
        context: MicrosoftSyncOperationContext
    ) async throws -> [CalendarEvent] {
        let now = Date()
        let defaultStart = now.addingTimeInterval(-Self.outlookPastWindow)
        let defaultEnd = now.addingTimeInterval(Self.outlookFutureWindow)
        if let storedEnd = state.outlookWindowEnd,
           storedEnd <= now.addingTimeInterval(Self.outlookWindowRefreshLead) {
            state.outlookWindowStart = nil
            state.outlookWindowEnd = nil
            state.outlookDeltaLink = nil
        }
        let start = state.outlookWindowStart ?? defaultStart
        let end = state.outlookWindowEnd ?? defaultEnd

        let delta: MicrosoftDeltaBatch<MicrosoftOutlookEvent>
        do {
            delta = try await graphClient.fetchDefaultCalendarDelta(
                deltaLink: state.outlookDeltaLink,
                start: start,
                end: end,
                accessToken: context.accessToken
            )
            try await validateOperation(context)
        } catch MicrosoftGraphError.deltaTokenExpired {
            try await validateOperation(context)
            state.outlookDeltaLink = nil
            state.outlookWindowStart = defaultStart
            state.outlookWindowEnd = defaultEnd
            let full = try await graphClient.fetchDefaultCalendarDelta(
                deltaLink: nil,
                start: defaultStart,
                end: defaultEnd,
                accessToken: context.accessToken
            )
            try await validateOperation(context)
            state.outlookDeltaLink = full.deltaLink
            return Self.applyOutlookDelta(
                full.items,
                to: [],
                accountID: accountID
            )
        }

        let baseline = state.outlookDeltaLink == nil ? [] : currentEvents
        state.outlookWindowStart = start
        state.outlookWindowEnd = end
        state.outlookDeltaLink = delta.deltaLink
        return Self.applyOutlookDelta(delta.items, to: baseline, accountID: accountID)
    }

    // MARK: Microsoft To Do

    private func syncTodo(
        currentTasks: [TaskItem],
        accountID: String,
        state: inout MicrosoftSyncState,
        context: MicrosoftSyncOperationContext
    ) async throws -> [TaskItem] {
        let oldListIDs = Set(state.todoListIDs)
        var loadedListDelta: MicrosoftDeltaBatch<MicrosoftTodoList>?
        var isFreshListSnapshot = false
        do {
            loadedListDelta = try await graphClient.fetchTodoListsDelta(
                deltaLink: state.todoListsDeltaLink,
                accessToken: context.accessToken
            )
            try await validateOperation(context)
            isFreshListSnapshot = state.todoListsDeltaLink == nil
        } catch MicrosoftGraphError.deltaTokenExpired {
            try await validateOperation(context)
            state.todoListsDeltaLink = nil
            loadedListDelta = try await graphClient.fetchTodoListsDelta(
                deltaLink: nil,
                accessToken: context.accessToken
            )
            try await validateOperation(context)
            isFreshListSnapshot = true
        }
        guard let listDelta = loadedListDelta else {
            throw MicrosoftGraphError.invalidResponse
        }

        var listIDs = isFreshListSnapshot ? Set<String>() : oldListIDs
        var removedListIDs = Set<String>()
        for list in listDelta.items {
            if list.removed != nil {
                listIDs.remove(list.id)
                removedListIDs.insert(list.id)
                state.todoTaskDeltaLinks.removeValue(forKey: list.id)
            } else {
                listIDs.insert(list.id)
            }
        }
        if isFreshListSnapshot {
            // A fresh list delta is a complete snapshot. Preserve the old IDs until the request
            // succeeds, then remove tasks and task cursors for lists absent from that snapshot.
            removedListIDs.formUnion(oldListIDs.subtracting(listIDs))
            for removedListID in removedListIDs {
                state.todoTaskDeltaLinks.removeValue(forKey: removedListID)
            }
        }
        state.todoListsDeltaLink = listDelta.deltaLink

        var tasks = currentTasks.filter { task in
            guard task.externalReference?.provider == .microsoftToDo else { return true }
            guard let listID = task.externalReference?.containerID else { return false }
            return !removedListIDs.contains(listID)
        }

        for listID in listIDs.sorted() {
            let existingDeltaLink = state.todoTaskDeltaLinks[listID]
            var loadedTaskDelta: MicrosoftDeltaBatch<MicrosoftTodoTask>?
            do {
                loadedTaskDelta = try await graphClient.fetchTodoTasksDelta(
                    listID: listID,
                    deltaLink: existingDeltaLink,
                    accessToken: context.accessToken
                )
                try await validateOperation(context)
            } catch MicrosoftGraphError.deltaTokenExpired {
                try await validateOperation(context)
                state.todoTaskDeltaLinks.removeValue(forKey: listID)
                tasks.removeAll {
                    $0.externalReference?.provider == .microsoftToDo
                        && $0.externalReference?.accountID == accountID
                        && $0.externalReference?.containerID == listID
                }
                loadedTaskDelta = try await graphClient.fetchTodoTasksDelta(
                    listID: listID,
                    deltaLink: nil,
                    accessToken: context.accessToken
                )
                try await validateOperation(context)
            }
            guard let taskDelta = loadedTaskDelta else {
                throw MicrosoftGraphError.invalidResponse
            }

            if existingDeltaLink == nil {
                tasks.removeAll {
                    $0.externalReference?.provider == .microsoftToDo
                        && $0.externalReference?.accountID == accountID
                        && $0.externalReference?.containerID == listID
                }
            }
            tasks = Self.applyTodoDelta(
                taskDelta.items,
                listID: listID,
                to: tasks,
                accountID: accountID
            )
            state.todoTaskDeltaLinks[listID] = taskDelta.deltaLink
        }

        state.todoListIDs = listIDs.sorted()
        return tasks
    }

    // MARK: To Do writeback

    public func pushTodoCompletion(_ task: TaskItem) async throws {
        guard let reference = task.externalReference,
              reference.provider == .microsoftToDo,
              let listID = reference.containerID else {
            throw MicrosoftSyncError.missingRemoteIdentifier
        }
        let owner = try await captureOperationOwner(expectedAccountID: reference.accountID)
        let context = try await captureOperationContext(owner: owner)
        let targetStatus = MicrosoftTodoStatus.targetStatus(
            isCompleted: task.isCompleted,
            previousRemoteStatus: reference.previousRemoteStatus ?? reference.remoteStatus
        )
        let entry = MicrosoftTodoOutboxEntry(
            accountID: reference.accountID,
            listID: listID,
            taskID: reference.itemID,
            targetStatus: targetStatus
        )
        let loadedOutbox = try await stateStore.loadOutbox()
        try await validateOperation(context)
        let attemptedEntries = loadedOutbox.filter {
            $0.accountID == entry.accountID
                && $0.listID == entry.listID
                && $0.taskID == entry.taskID
        }

        do {
            try await graphClient.updateTodoTaskStatus(
                listID: listID,
                taskID: reference.itemID,
                status: targetStatus,
                accessToken: context.accessToken
            )
        } catch {
            try await validateOperation(context)
            do {
                try await stateStore.commitOutboxAttempt(
                    attempted: attemptedEntries,
                    retrying: MicrosoftSyncError.isPermanentTodoWriteFailure(error) ? [] : [entry],
                    expectedEpoch: context.storeEpoch
                )
            } catch is MicrosoftSyncStoreEpochMismatch {
                throw MicrosoftSyncError.staleOperation
            }
            try await validateOperation(context)
            throw error
        }
        try await validateOperation(context)
        do {
            try await stateStore.commitOutboxAttempt(
                attempted: attemptedEntries,
                retrying: [],
                expectedEpoch: context.storeEpoch
            )
        } catch is MicrosoftSyncStoreEpochMismatch {
            throw MicrosoftSyncError.staleOperation
        }
        try await validateOperation(context)
    }

    private func flushTodoOutbox(
        context: MicrosoftSyncOperationContext
    ) async throws -> [String] {
        let accountID = context.owner.accountID
        let loaded: [MicrosoftTodoOutboxEntry]
        do {
            loaded = try await stateStore.loadOutbox()
            try await validateOperation(context)
        } catch MicrosoftSyncError.staleOperation {
            throw MicrosoftSyncError.staleOperation
        } catch {
            try await validateOperation(context)
            return ["Microsoft To Do outbox load failed: \(error.localizedDescription)"]
        }

        var remaining: [MicrosoftTodoOutboxEntry] = []
        var warnings: [String] = []
        for var entry in loaded where entry.accountID == accountID {
            do {
                try await graphClient.updateTodoTaskStatus(
                    listID: entry.listID,
                    taskID: entry.taskID,
                    status: entry.targetStatus,
                    accessToken: context.accessToken
                )
                try await validateOperation(context)
            } catch MicrosoftSyncError.staleOperation {
                throw MicrosoftSyncError.staleOperation
            } catch {
                try await validateOperation(context)
                if MicrosoftSyncError.isPermanentTodoWriteFailure(error) {
                    warnings.append(
                        "Microsoft To Do write was discarded after a permanent failure: \(error.localizedDescription)"
                    )
                    continue
                }
                if entry.retryCount < Int.max {
                    entry.retryCount += 1
                }
                // A transient failure must never erase the user's latest intended state. The
                // target-state patch is idempotent, so retain it until Graph confirms success.
                remaining.append(entry)
                warnings.append(
                    "Microsoft To Do write retry \(entry.retryCount) failed and remains queued: \(error.localizedDescription)"
                )
            }
        }
        do {
            try await validateOperation(context)
            try await stateStore.commitOutboxAttempt(
                attempted: loaded.filter { $0.accountID == accountID },
                retrying: remaining,
                expectedEpoch: context.storeEpoch
            )
            try await validateOperation(context)
        } catch MicrosoftSyncError.staleOperation {
            throw MicrosoftSyncError.staleOperation
        } catch is MicrosoftSyncStoreEpochMismatch {
            throw MicrosoftSyncError.staleOperation
        } catch {
            try await validateOperation(context)
            warnings.append("Microsoft To Do outbox save failed: \(error.localizedDescription)")
        }
        return warnings
    }

    func beginAccountTransition(
        clearingProviderState: Bool
    ) async throws -> MicrosoftSyncAccountTransition {
        guard activeAccountTransitionID == nil else {
            throw MicrosoftSyncError.accountTransitionInProgress
        }
        let transition = MicrosoftSyncAccountTransition(id: UUID())
        activeAccountTransitionID = transition.id
        // Invalidate the actor generation before the first await so suspended work cannot resume
        // into the authorization/disconnect window.
        operationGeneration &+= 1
        do {
            if clearingProviderState {
                try await stateStore.reset()
            } else {
                await stateStore.invalidateOperations()
            }
        } catch {
            operationGeneration &+= 1
            activeAccountTransitionID = nil
            throw error
        }
        return transition
    }

    func finishAccountTransition(_ transition: MicrosoftSyncAccountTransition) async {
        guard activeAccountTransitionID == transition.id else { return }
        // Publish a second generation after MSAL has either committed or rejected the identity.
        // Keep the transition blocked until the store rejects every pre-publication lease too.
        operationGeneration &+= 1
        await stateStore.invalidateOperations()
        guard activeAccountTransitionID == transition.id else { return }
        activeAccountTransitionID = nil
    }

    public func clearProviderState() async throws {
        let commitBoundary = try await MicrosoftSyncCommitGate.beginTransition()
        do {
            let transition = try await beginAccountTransition(clearingProviderState: true)
            await finishAccountTransition(transition)
            await MicrosoftSyncCommitGate.finishTransition(commitBoundary)
        } catch {
            await MicrosoftSyncCommitGate.finishTransition(commitBoundary)
            throw error
        }
    }

    private func captureOperationOwner(
        expectedAccountID: String? = nil
    ) async throws -> MicrosoftSyncOperationOwner {
        guard activeAccountTransitionID == nil else {
            throw MicrosoftSyncError.staleOperation
        }
        let generation = operationGeneration
        guard let accountID = await tokenProvider.accountID() else {
            throw MicrosoftAuthError.notAuthenticated
        }
        guard generation == operationGeneration,
              activeAccountTransitionID == nil else {
            throw MicrosoftSyncError.staleOperation
        }
        if let expectedAccountID, expectedAccountID != accountID {
            throw MicrosoftSyncError.accountMismatch
        }
        return MicrosoftSyncOperationOwner(accountID: accountID, generation: generation)
    }

    private func captureOperationContext(
        owner: MicrosoftSyncOperationOwner
    ) async throws -> MicrosoftSyncOperationContext {
        try await validateOperationOwner(owner)
        guard let commitGeneration = await MicrosoftSyncCommitGate.captureGeneration() else {
            throw MicrosoftSyncError.staleOperation
        }
        try await validateOperationOwner(owner)
        let accessToken = try await tokenProvider.accessToken()
        try await validateOperationOwner(owner)
        let storeEpoch = await stateStore.currentOperationEpoch()
        try await validateOperationOwner(owner)
        guard await MicrosoftSyncCommitGate.accepts(commitGeneration) else {
            throw MicrosoftSyncError.staleOperation
        }
        return MicrosoftSyncOperationContext(
            owner: owner,
            storeEpoch: storeEpoch,
            commitGeneration: commitGeneration,
            accessToken: accessToken
        )
    }

    private func validateOperation(
        _ context: MicrosoftSyncOperationContext
    ) async throws {
        try await validateOperationOwner(context.owner)
        let currentStoreEpoch = await stateStore.currentOperationEpoch()
        try await validateOperationOwner(context.owner)
        guard currentStoreEpoch == context.storeEpoch,
              await MicrosoftSyncCommitGate.accepts(context.commitGeneration) else {
            throw MicrosoftSyncError.staleOperation
        }
    }

    private func validateOperationOwner(
        _ owner: MicrosoftSyncOperationOwner
    ) async throws {
        guard operationGeneration == owner.generation,
              activeAccountTransitionID == nil else {
            throw MicrosoftSyncError.staleOperation
        }
        let currentAccountID = await tokenProvider.accountID()
        guard operationGeneration == owner.generation,
              activeAccountTransitionID == nil,
              currentAccountID == owner.accountID else {
            throw MicrosoftSyncError.staleOperation
        }
    }
}
