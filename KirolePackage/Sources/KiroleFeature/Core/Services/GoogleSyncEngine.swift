import Foundation

// MARK: - Injectable Google boundaries

protocol GoogleCalendarSyncServing: Sendable {
    func fetchTodayEvents() async throws -> [CalendarEvent]
}

protocol GoogleTasksSyncServing: Sendable {
    func fetchTasks(updatedMin: Date?) async throws -> [TaskItem]
    func send(_ entry: OutboxEntry) async throws
}

protocol GoogleSyncStateStoring: Sendable {
    func loadGoogleSyncMetadata() async throws -> GoogleSyncMetadata?
    func saveGoogleSyncMetadata(_ metadata: GoogleSyncMetadata) async throws
    func loadOutbox() async throws -> [OutboxEntry]
    func saveOutbox(_ entries: [OutboxEntry]) async throws
    func resetGoogleSyncState() async throws
}

private struct LiveGoogleCalendarSyncService: GoogleCalendarSyncServing {
    let api: GoogleCalendarAPI

    init(api: GoogleCalendarAPI = .shared) {
        self.api = api
    }

    func fetchTodayEvents() async throws -> [CalendarEvent] {
        try await api.getTodayEvents()
    }
}

private struct LiveGoogleTasksSyncService: GoogleTasksSyncServing {
    let api: GoogleTasksAPI

    init(api: GoogleTasksAPI = .shared) {
        self.api = api
    }

    func fetchTasks(updatedMin: Date?) async throws -> [TaskItem] {
        guard let updatedMin else {
            return try await api.getAllTasks(showCompleted: true)
        }

        let taskLists = try await api.getTaskLists()
        return try await withThrowingTaskGroup(of: [TaskItem].self) { group in
            for taskList in taskLists {
                group.addTask {
                    let tasks = try await api.getTasks(
                        taskListId: taskList.id,
                        showCompleted: true,
                        showHidden: false,
                        showDeleted: true,
                        dueMin: nil,
                        dueMax: nil,
                        updatedMin: updatedMin,
                        maxResults: 100
                    )
                    return tasks.map { googleTask in
                        var task = TaskItem.from(googleTask: googleTask, taskListId: taskList.id)
                        if googleTask.deleted == true {
                            task.syncStatus = .deleted
                        }
                        return task
                    }
                }
            }

            var allTasks: [TaskItem] = []
            for try await items in group {
                allTasks.append(contentsOf: items)
            }
            return allTasks
        }
    }

    func send(_ entry: OutboxEntry) async throws {
        switch entry.action {
        case .updateStatus:
            try await api.syncTaskCompletion(entry.taskItem)
        case .updateTask:
            _ = try await api.syncTaskUpdate(entry.taskItem)
        case .create:
            guard let listID = entry.taskItem.googleTaskListId else { return }
            _ = try await api.createTask(
                taskListId: listID,
                title: entry.taskItem.title
            )
        case .delete:
            guard let listID = entry.taskItem.googleTaskListId,
                  let taskID = entry.taskItem.googleTaskId else { return }
            try await api.deleteTask(taskListId: listID, taskId: taskID)
        }
    }
}

private struct LiveGoogleSyncStateStore: GoogleSyncStateStoring {
    let storage: LocalStorage

    init(storage: LocalStorage = .shared) {
        self.storage = storage
    }

    func loadGoogleSyncMetadata() async throws -> GoogleSyncMetadata? {
        try await storage.loadGoogleSyncMetadata()
    }

    func saveGoogleSyncMetadata(_ metadata: GoogleSyncMetadata) async throws {
        try await storage.saveGoogleSyncMetadata(metadata)
    }

    func loadOutbox() async throws -> [OutboxEntry] {
        try await storage.loadOutbox()
    }

    func saveOutbox(_ entries: [OutboxEntry]) async throws {
        try await storage.saveOutbox(entries)
    }

    func resetGoogleSyncState() async throws {
        try await storage.resetGoogleSyncState()
    }
}

private struct GoogleSyncOperationLease: Sendable {
    let generation: UInt64
}

// MARK: - Google Sync Engine

/// Orchestrates Google Calendar/Tasks sync. Every operation carries an actor-owned generation
/// lease so account removal can invalidate suspended network and persistence work before its first
/// suspension point. The outbox is intentionally reset at every Google account boundary because
/// the legacy format has no account owner and must never be replayed into a later authorization.
public actor GoogleSyncEngine {
    public static let shared = GoogleSyncEngine()

    private let calendarAPI: any GoogleCalendarSyncServing
    private let tasksAPI: any GoogleTasksSyncServing
    private let storage: any GoogleSyncStateStoring

    private var operationGeneration: UInt64 = 0
    private var isEnabled = true
    private var resetRequiredBeforeActivation = false
    private var activeTransitionID: UUID?
    private var activeSyncID: UUID?
    private var activeFlushID: UUID?
    private var hasLoadedPersistedState = false

    private var metadata = GoogleSyncMetadata()
    private var outbox: [OutboxEntry] = []
    /// The batch currently waiting on Google. Persistence includes this batch until it settles so
    /// a process kill retries rather than silently losing a user action.
    private var inFlightOutbox: [OutboxEntry] = []

    private static let maxRetryCount = 5
    private static let syncOverlapInterval: TimeInterval = -5 * 60

    init(
        calendarAPI: any GoogleCalendarSyncServing = LiveGoogleCalendarSyncService(),
        tasksAPI: any GoogleTasksSyncServing = LiveGoogleTasksSyncService(),
        storage: any GoogleSyncStateStoring = LiveGoogleSyncStateStore()
    ) {
        self.calendarAPI = calendarAPI
        self.tasksAPI = tasksAPI
        self.storage = storage
    }

    // MARK: - Account boundary

    /// Invalidates all existing leases before the first await, blocks new work, clears every
    /// in-memory queue, then atomically asks the storage actor to delete and verify provider state.
    public func resetAndDisable() async throws {
        guard activeTransitionID == nil else {
            throw GoogleSyncEngineError.accountTransitionInProgress
        }

        let transitionID = UUID()
        activeTransitionID = transitionID
        operationGeneration &+= 1
        isEnabled = false
        resetRequiredBeforeActivation = true
        activeSyncID = nil
        activeFlushID = nil
        metadata = GoogleSyncMetadata()
        outbox = []
        inFlightOutbox = []
        hasLoadedPersistedState = true

        do {
            try await storage.resetGoogleSyncState()
            guard activeTransitionID == transitionID else {
                throw GoogleSyncEngineError.staleOperation
            }
            operationGeneration &+= 1
            resetRequiredBeforeActivation = false
            activeTransitionID = nil
        } catch {
            if activeTransitionID == transitionID {
                operationGeneration &+= 1
                activeTransitionID = nil
            }
            if let engineError = error as? GoogleSyncEngineError {
                throw engineError
            }
            throw GoogleSyncEngineError.stateResetFailed(error.localizedDescription)
        }
    }

    /// Opens a fresh generation only after the new Google authorization is fully committed.
    public func activateAfterAuthorization() throws {
        guard activeTransitionID == nil else {
            throw GoogleSyncEngineError.accountTransitionInProgress
        }
        guard !resetRequiredBeforeActivation else {
            throw GoogleSyncEngineError.stateResetRequired
        }
        operationGeneration &+= 1
        isEnabled = true
    }

    // MARK: - Main entry point

    public func performFullSync(
        currentEvents: [CalendarEvent],
        currentTasks: [TaskItem],
        includeCalendar: Bool = true,
        includeTasks: Bool = true
    ) async throws -> (events: [CalendarEvent], tasks: [TaskItem], warnings: [String]) {
        let lease = try captureOperationLease()
        guard activeSyncID == nil else { return (currentEvents, currentTasks, []) }
        let syncID = UUID()
        activeSyncID = syncID
        defer {
            if activeSyncID == syncID {
                activeSyncID = nil
            }
        }

        try await loadPersistedState(for: lease)

        var events = currentEvents
        var tasks = currentTasks
        var warnings: [String] = []
        var successCount = 0
        let attemptedCount = (includeCalendar ? 1 : 0) + (includeTasks ? 1 : 0)

        if includeCalendar {
            switch try await runSyncStep(
                name: "Calendar",
                lease: lease,
                operation: { try await self.syncCalendar(lease: lease) }
            ) {
            case .success(let syncedEvents):
                events = syncedEvents
                successCount += 1
            case .failure(let warning):
                warnings.append(warning)
            }
        }

        if includeTasks {
            switch try await runSyncStep(
                name: "Tasks",
                lease: lease,
                operation: { try await self.syncTasks(currentTasks: currentTasks, lease: lease) }
            ) {
            case .success(let syncedTasks):
                tasks = syncedTasks
                successCount += 1
            case .failure(let warning):
                warnings.append(warning)
            }
        }

        try validateOperation(lease)
        metadata.lastFullSyncTime = Date()
        try await persistMetadata(
            lease: lease,
            context: "GoogleSyncEngine.performFullSync"
        )

        guard attemptedCount == 0 || successCount > 0 else {
            throw GoogleSyncEngineError.fullSyncFailed(warnings)
        }
        try validateOperation(lease)
        return (events, tasks, warnings)
    }

    private func runSyncStep<T>(
        name: String,
        lease: GoogleSyncOperationLease,
        operation: () async throws -> T
    ) async throws -> SyncStepResult<T> {
        do {
            let value = try await operation()
            try validateOperation(lease)
            return .success(value)
        } catch {
            // If reset happened while either the success or failure response was suspended, this
            // validation throws staleOperation instead of converting an old-account result into a
            // warning and committing lastFullSyncTime afterward.
            try validateOperation(lease)
            let warning = "\(name) sync failed: \(error.localizedDescription)"
            #if DEBUG
            print("[GoogleSyncEngine] \(name) sync failed: \(error)")
            #endif
            return .failure(warning)
        }
    }

    // MARK: - Persisted state

    private func loadPersistedState(for lease: GoogleSyncOperationLease) async throws {
        guard !hasLoadedPersistedState else {
            try validateOperation(lease)
            return
        }

        var loadedMetadata = GoogleSyncMetadata()
        do {
            let candidate = try await storage.loadGoogleSyncMetadata() ?? GoogleSyncMetadata()
            try validateOperation(lease)
            loadedMetadata = candidate
        } catch {
            try validateOperation(lease)
            ErrorReporter.log(
                .persistence(
                    operation: "load",
                    target: "google_sync_metadata.json",
                    underlying: error.localizedDescription
                ),
                context: "GoogleSyncEngine.loadPersistedState"
            )
        }

        var loadedOutbox: [OutboxEntry] = []
        do {
            let candidate = try await storage.loadOutbox()
            try validateOperation(lease)
            loadedOutbox = candidate
        } catch {
            try validateOperation(lease)
            ErrorReporter.log(
                .persistence(
                    operation: "load",
                    target: "outbox.json",
                    underlying: error.localizedDescription
                ),
                context: "GoogleSyncEngine.loadPersistedState"
            )
        }

        try validateOperation(lease)
        metadata = loadedMetadata
        outbox = loadedOutbox
        hasLoadedPersistedState = true
    }

    private func persistMetadata(
        lease: GoogleSyncOperationLease,
        context: String
    ) async throws {
        try validateOperation(lease)
        do {
            try await storage.saveGoogleSyncMetadata(metadata)
        } catch {
            try validateOperation(lease)
            ErrorReporter.log(
                .persistence(
                    operation: "save",
                    target: "google_sync_metadata.json",
                    underlying: error.localizedDescription
                ),
                context: context
            )
            throw error
        }
        try validateOperation(lease)
    }

    private func persistOutbox(
        lease: GoogleSyncOperationLease,
        context: String
    ) async throws {
        try validateOperation(lease)
        do {
            try await storage.saveOutbox(inFlightOutbox + outbox)
        } catch {
            try validateOperation(lease)
            ErrorReporter.log(
                .persistence(
                    operation: "save",
                    target: "outbox.json",
                    underlying: error.localizedDescription
                ),
                context: context
            )
            throw error
        }
        try validateOperation(lease)
    }

    // MARK: - Calendar sync

    private func syncCalendar(lease: GoogleSyncOperationLease) async throws -> [CalendarEvent] {
        if metadata.calendarSyncToken != nil {
            metadata.calendarSyncToken = nil
            try await persistMetadata(
                lease: lease,
                context: "GoogleSyncEngine.syncCalendar"
            )
        }

        let events = try await calendarAPI.fetchTodayEvents()
        try validateOperation(lease)
        #if DEBUG
        print("[GoogleSyncEngine] Full calendar sync events=\(events.count)")
        #endif
        return events
    }

    // MARK: - Tasks sync

    public func syncTasks(currentTasks: [TaskItem]) async throws -> [TaskItem] {
        let lease = try captureOperationLease()
        try await loadPersistedState(for: lease)
        return try await syncTasks(currentTasks: currentTasks, lease: lease)
    }

    private func syncTasks(
        currentTasks: [TaskItem],
        lease: GoogleSyncOperationLease
    ) async throws -> [TaskItem] {
        try await flushOutbox(lease: lease)
        try validateOperation(lease)

        let hasLocalGoogleTasks = currentTasks.contains { $0.googleTaskId != nil }
        let updatedMin = metadata.lastTasksSyncTime.flatMap { lastSync in
            hasLocalGoogleTasks
                ? lastSync.addingTimeInterval(Self.syncOverlapInterval)
                : nil
        }
        let remoteTasks = try await tasksAPI.fetchTasks(updatedMin: updatedMin)
        try validateOperation(lease)

        let merged = mergeTasks(local: currentTasks, remote: remoteTasks)
        metadata.lastTasksSyncTime = Date()
        try await persistMetadata(
            lease: lease,
            context: "GoogleSyncEngine.syncTasks"
        )
        return merged
    }

    // MARK: - Merge logic

    private func mergeTasks(local: [TaskItem], remote: [TaskItem]) -> [TaskItem] {
        var localByGoogleID: [String: TaskItem] = [:]
        var localWithoutGoogleID: [TaskItem] = []

        for task in local {
            if let googleID = task.googleTaskId {
                localByGoogleID[googleID] = task
            } else {
                localWithoutGoogleID.append(task)
            }
        }

        var result = localWithoutGoogleID
        for remoteTask in remote {
            guard let googleID = remoteTask.googleTaskId else { continue }
            guard let localTask = localByGoogleID.removeValue(forKey: googleID) else {
                if remoteTask.syncStatus != .deleted {
                    result.append(remoteTask)
                }
                continue
            }

            if remoteTask.syncStatus == .deleted { continue }
            if localTask.syncStatus == .synced {
                result.append(Self.mergeRemoteTaskPreservingLocalFields(
                    local: localTask,
                    remote: remoteTask
                ))
                continue
            }

            let remoteTime = remoteTask.remoteUpdatedAt ?? remoteTask.lastModified
            result.append(
                remoteTime > localTask.lastModified
                    ? Self.mergeRemoteTaskPreservingLocalFields(local: localTask, remote: remoteTask)
                    : localTask
            )
        }

        result.append(contentsOf: localByGoogleID.values)
        return result
    }

    nonisolated static func mergeRemoteTaskPreservingLocalFields(
        local: TaskItem,
        remote: TaskItem
    ) -> TaskItem {
        var merged = remote
        merged.localId = local.localId
        merged.todayDisplayDate = local.todayDisplayDate
        return merged
    }

    // MARK: - Outbox

    public func enqueueChange(task: TaskItem, action: OutboxAction) async {
        guard let lease = try? captureOperationLease() else { return }
        do {
            try await loadPersistedState(for: lease)
            if let existingIndex = outbox.lastIndex(where: {
                $0.taskItem.id == task.id && $0.action == action
            }) {
                let existing = outbox[existingIndex]
                if existing.taskItem.lastModified >= task.lastModified { return }
                outbox.remove(at: existingIndex)
            }
            outbox.append(OutboxEntry(taskItem: task, action: action))
            try await persistOutbox(
                lease: lease,
                context: "GoogleSyncEngine.enqueueChange"
            )
        } catch {
            if case GoogleSyncEngineError.staleOperation = error { return }
            ErrorReporter.log(error, context: "GoogleSyncEngine.enqueueChange")
        }
    }

    public func clearQueuedChanges(
        for taskID: String,
        action: OutboxAction,
        upToLastModified: Date? = nil
    ) async {
        guard let lease = try? captureOperationLease() else { return }
        do {
            try await loadPersistedState(for: lease)
            let originalCount = outbox.count
            outbox.removeAll { entry in
                guard entry.taskItem.id == taskID, entry.action == action else {
                    return false
                }
                guard let upToLastModified else { return true }
                return entry.taskItem.lastModified <= upToLastModified
            }
            guard outbox.count != originalCount else { return }
            try await persistOutbox(
                lease: lease,
                context: "GoogleSyncEngine.clearQueuedChanges"
            )
        } catch {
            if case GoogleSyncEngineError.staleOperation = error { return }
            ErrorReporter.log(error, context: "GoogleSyncEngine.clearQueuedChanges")
        }
    }

    private func flushOutbox(lease: GoogleSyncOperationLease) async throws {
        guard activeFlushID == nil else {
            try validateOperation(lease)
            return
        }
        guard !outbox.isEmpty else { return }

        let flushID = UUID()
        activeFlushID = flushID
        defer {
            if activeFlushID == flushID {
                activeFlushID = nil
            }
        }

        let batch = outbox
        outbox = []
        inFlightOutbox = batch
        var remaining: [OutboxEntry] = []

        for var entry in batch {
            try validateOperation(lease)
            if entry.retryCount > Self.maxRetryCount {
                ErrorReporter.log(
                    .sync(
                        component: "Google Tasks Outbox",
                        underlying: "Discarding stale entry \(entry.action.rawValue):\(entry.taskItem.id) already past max retries"
                    ),
                    context: "GoogleSyncEngine.flushOutbox"
                )
                continue
            }

            do {
                try await tasksAPI.send(entry)
                try validateOperation(lease)
            } catch {
                // A reset changes the generation before its storage await. Revalidate before
                // recording a retry so a late success and a late failure have identical stale
                // semantics and neither can send the next entry.
                try validateOperation(lease)
                entry.retryCount += 1
                let actionName = entry.action.rawValue
                let taskID = entry.taskItem.id
                let context = "GoogleSyncEngine.flushOutbox[\(actionName):\(taskID)]"
                if entry.retryCount <= Self.maxRetryCount {
                    remaining.append(entry)
                    ErrorReporter.log(
                        .sync(
                            component: "Google Tasks Outbox",
                            underlying: "Action \(actionName) failed (\(entry.retryCount)/\(Self.maxRetryCount)); will retry. \(error.localizedDescription)"
                        ),
                        context: context
                    )
                } else {
                    ErrorReporter.log(
                        .sync(
                            component: "Google Tasks Outbox",
                            underlying: "Action \(actionName) dropped after \(Self.maxRetryCount) retries. \(error.localizedDescription)"
                        ),
                        context: context
                    )
                }
            }
        }

        try validateOperation(lease)
        inFlightOutbox = []
        outbox = remaining + outbox
        try await persistOutbox(
            lease: lease,
            context: "GoogleSyncEngine.flushOutbox"
        )
    }

    // MARK: - Lease validation

    private func captureOperationLease() throws -> GoogleSyncOperationLease {
        guard isEnabled,
              activeTransitionID == nil,
              !resetRequiredBeforeActivation else {
            throw GoogleSyncEngineError.providerDisabled
        }
        return GoogleSyncOperationLease(generation: operationGeneration)
    }

    private func validateOperation(_ lease: GoogleSyncOperationLease) throws {
        guard isEnabled,
              activeTransitionID == nil,
              !resetRequiredBeforeActivation,
              lease.generation == operationGeneration else {
            throw GoogleSyncEngineError.staleOperation
        }
    }
}

private enum SyncStepResult<T> {
    case success(T)
    case failure(String)
}

// MARK: - Google Sync Engine Error

public enum GoogleSyncEngineError: LocalizedError, Sendable {
    case fullSyncFailed([String])
    case staleOperation
    case providerDisabled
    case accountTransitionInProgress
    case stateResetRequired
    case stateResetFailed(String)

    public var errorDescription: String? {
        switch self {
        case .fullSyncFailed(let warnings):
            return warnings.isEmpty ? "Google sync failed" : warnings.joined(separator: " | ")
        case .staleOperation:
            return "The Google operation belongs to an old account session"
        case .providerDisabled:
            return "Google sync is disabled until authorization completes"
        case .accountTransitionInProgress:
            return "A Google account transition is already in progress"
        case .stateResetRequired:
            return "Google sync state must be cleared before authorization can continue"
        case .stateResetFailed(let description):
            return "Google sync state could not be cleared: \(description)"
        }
    }
}
