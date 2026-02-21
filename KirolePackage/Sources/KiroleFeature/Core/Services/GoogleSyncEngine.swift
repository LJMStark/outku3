import Foundation

// MARK: - Google Sync Engine

/// Orchestrates incremental sync between local data and Google Calendar/Tasks APIs.
/// Uses an outbox pattern for offline-first writes and Last-Writer-Wins conflict resolution.
public actor GoogleSyncEngine {
    public static let shared = GoogleSyncEngine()

    private let calendarAPI = GoogleCalendarAPI.shared
    private let tasksAPI = GoogleTasksAPI.shared
    private let storage = LocalStorage.shared

    private var isSyncing = false
    private var metadata: GoogleSyncMetadata
    private var outbox: [OutboxEntry]

    private static let maxRetryCount = 5
    // 5-minute overlap to catch updates near the boundary
    private static let syncOverlapInterval: TimeInterval = -5 * 60

    private init() {
        self.metadata = GoogleSyncMetadata()
        self.outbox = []
        // Async load deferred to first sync
    }

    // MARK: - Initialization

    private func loadPersistedState() async {
        metadata = (try? await storage.loadGoogleSyncMetadata()) ?? GoogleSyncMetadata()
        outbox = (try? await storage.loadOutbox()) ?? []
    }

    // MARK: - Main Entry Point

    /// Perform a full sync cycle: flush outbox, pull calendar events, pull tasks.
    public func performFullSync(
        currentEvents: [CalendarEvent],
        currentTasks: [TaskItem],
        includeCalendar: Bool = true,
        includeTasks: Bool = true
    ) async throws -> (events: [CalendarEvent], tasks: [TaskItem], warnings: [String]) {
        guard !isSyncing else { return (currentEvents, currentTasks, []) }
        isSyncing = true
        defer { isSyncing = false }

        await loadPersistedState()

        var events = currentEvents
        var tasks = currentTasks
        var warnings: [String] = []
        var successCount = 0
        let attemptedCount = (includeCalendar ? 1 : 0) + (includeTasks ? 1 : 0)

        if includeCalendar {
            switch await runSyncStep(name: "Calendar", operation: { try await self.syncCalendar() }) {
            case .success(let syncedEvents):
                events = syncedEvents
                successCount += 1
            case .failure(let warning):
                warnings.append(warning)
            }
        }

        if includeTasks {
            switch await runSyncStep(name: "Tasks", operation: { try await self.syncTasks(currentTasks: currentTasks) }) {
            case .success(let syncedTasks):
                tasks = syncedTasks
                successCount += 1
            case .failure(let warning):
                warnings.append(warning)
            }
        }

        metadata.lastFullSyncTime = Date()
        try? await storage.saveGoogleSyncMetadata(metadata)

        guard attemptedCount == 0 || successCount > 0 else {
            throw GoogleSyncEngineError.fullSyncFailed(warnings)
        }

        return (events, tasks, warnings)
    }

    private func runSyncStep<T>(
        name: String,
        operation: () async throws -> T
    ) async -> SyncStepResult<T> {
        do {
            return .success(try await operation())
        } catch {
            let warning = "\(name) sync failed: \(error.localizedDescription)"
            #if DEBUG
            print("[GoogleSyncEngine] \(name) sync failed: \(error)")
            #endif
            return .failure(warning)
        }
    }

    // MARK: - Calendar Sync

    private func syncCalendar() async throws -> [CalendarEvent] {
        // NOTE:
        // Current calendar sync is day-scoped + multi-calendar full fetch.
        // Previous token-based incremental sync could return partial changes only
        // and accidentally replace full local Google event lists.
        // Keep token cleared until we implement per-calendar incremental merge.
        if metadata.calendarSyncToken != nil {
            metadata.calendarSyncToken = nil
            try? await storage.saveGoogleSyncMetadata(metadata)
        }

        let events = try await calendarAPI.getTodayEvents()
        #if DEBUG
        print("[GoogleSyncEngine] Full calendar sync events=\(events.count)")
        #endif
        return events
    }

    // MARK: - Tasks Sync

    public func syncTasks(currentTasks: [TaskItem]) async throws -> [TaskItem] {
        await flushOutbox()

        let remoteTasks: [TaskItem]
        if let lastSync = metadata.lastTasksSyncTime {
            let updatedMin = lastSync.addingTimeInterval(Self.syncOverlapInterval)
            remoteTasks = try await fetchAllTasksIncremental(updatedMin: updatedMin)
        } else {
            remoteTasks = try await tasksAPI.getAllTasks(showCompleted: true)
        }

        let merged = mergeTasks(local: currentTasks, remote: remoteTasks)
        metadata.lastTasksSyncTime = Date()
        try? await storage.saveGoogleSyncMetadata(metadata)

        return merged
    }

    /// Fetch tasks from all lists with updatedMin filter for incremental sync
    private func fetchAllTasksIncremental(updatedMin: Date) async throws -> [TaskItem] {
        let taskLists = try await tasksAPI.getTaskLists()

        return try await withThrowingTaskGroup(of: [TaskItem].self) { group in
            for taskList in taskLists {
                group.addTask {
                    let tasks = try await self.tasksAPI.getTasks(
                        taskListId: taskList.id,
                        showCompleted: true,
                        showDeleted: true,
                        updatedMin: updatedMin
                    )
                    return tasks.compactMap { googleTask in
                        // Mark deleted tasks so merge logic can handle them
                        if googleTask.deleted == true {
                            var item = TaskItem.from(googleTask: googleTask, taskListId: taskList.id)
                            item.syncStatus = .deleted
                            return item
                        }
                        return TaskItem.from(googleTask: googleTask, taskListId: taskList.id)
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

    // MARK: - Merge Logic

    /// Merge remote tasks into local list using Last-Writer-Wins by googleTaskId.
    private func mergeTasks(local: [TaskItem], remote: [TaskItem]) -> [TaskItem] {
        var localByGoogleId: [String: TaskItem] = [:]
        var localWithoutGoogleId: [TaskItem] = []

        for task in local {
            if let gid = task.googleTaskId {
                localByGoogleId[gid] = task
            } else {
                localWithoutGoogleId.append(task)
            }
        }

        var result = localWithoutGoogleId

        for remoteTask in remote {
            guard let gid = remoteTask.googleTaskId else { continue }

            if let localTask = localByGoogleId.removeValue(forKey: gid) {
                // Existing task - check sync status
                if remoteTask.syncStatus == .deleted {
                    // Remote was deleted - remove from local (don't add to result)
                    continue
                } else if localTask.syncStatus == .synced {
                    // Local is clean - accept remote
                    result.append(remoteTask)
                } else {
                    // Local is dirty - Last-Writer-Wins
                    let localTime = localTask.lastModified
                    let remoteTime = remoteTask.remoteUpdatedAt ?? remoteTask.lastModified
                    if remoteTime > localTime {
                        result.append(remoteTask)
                    } else {
                        result.append(localTask)
                    }
                }
            } else {
                // New remote task - add it (skip if deleted)
                if remoteTask.syncStatus != .deleted {
                    result.append(remoteTask)
                }
            }
        }

        // Keep remaining local tasks that weren't matched
        for (_, task) in localByGoogleId {
            result.append(task)
        }

        return result
    }

    // MARK: - Outbox

    public func enqueueChange(task: TaskItem, action: OutboxAction) async {
        let entry = OutboxEntry(taskItem: task, action: action)
        outbox.append(entry)
        try? await storage.saveOutbox(outbox)
    }

    private func flushOutbox() async {
        guard !outbox.isEmpty else { return }

        var remaining: [OutboxEntry] = []

        for var entry in outbox {
            do {
                switch entry.action {
                case .updateStatus:
                    try await tasksAPI.syncTaskCompletion(entry.taskItem)
                case .create:
                    guard let listId = entry.taskItem.googleTaskListId else {
                        continue // Drop entries without a list ID
                    }
                    _ = try await tasksAPI.createTask(
                        taskListId: listId,
                        title: entry.taskItem.title
                    )
                case .delete:
                    guard let listId = entry.taskItem.googleTaskListId,
                          let taskId = entry.taskItem.googleTaskId else {
                        continue
                    }
                    try await tasksAPI.deleteTask(taskListId: listId, taskId: taskId)
                }
                // Success - entry is consumed
            } catch {
                entry.retryCount += 1
                if entry.retryCount <= Self.maxRetryCount {
                    remaining.append(entry)
                }
                // Discard entries that exceeded max retries
            }
        }

        outbox = remaining
        try? await storage.saveOutbox(outbox)
    }
}

private enum SyncStepResult<T> {
    case success(T)
    case failure(String)
}

// MARK: - Google Sync Engine Error

public enum GoogleSyncEngineError: LocalizedError, Sendable {
    case fullSyncFailed([String])

    public var errorDescription: String? {
        switch self {
        case .fullSyncFailed(let warnings):
            if warnings.isEmpty {
                return "Google sync failed"
            }
            return warnings.joined(separator: " | ")
        }
    }
}
