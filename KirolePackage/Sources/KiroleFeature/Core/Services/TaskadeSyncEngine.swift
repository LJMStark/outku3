import Foundation

// MARK: - Taskade Sync Engine

/// Orchestrates sync between local tasks and Taskade projects.
/// Uses Last-Writer-Wins merge strategy consistent with GoogleSyncEngine.
public actor TaskadeSyncEngine {
    public static let shared = TaskadeSyncEngine()

    private let taskadeAPI = TaskadeAPI.shared

    private var isSyncing = false

    private init() {}

    // MARK: - Sync Tasks

    /// Fetch tasks from all Taskade workspaces/projects and merge with local tasks
    public func syncTasks(
        currentTasks: [TaskItem],
        accessToken: String
    ) async throws -> [TaskItem] {
        guard !isSyncing else { return currentTasks }
        isSyncing = true
        defer { isSyncing = false }

        let remoteTasks = try await taskadeAPI.getAllTasks(accessToken: accessToken)
        return mergeTasks(local: currentTasks, remote: remoteTasks)
    }

    // MARK: - Push Update

    /// Update task completion status back to Taskade
    public func pushTaskUpdate(
        _ task: TaskItem,
        accessToken: String
    ) async throws {
        guard let projectId = task.taskadeProjectId,
              let taskId = task.taskadeTaskId else {
            throw TaskadeSyncError.missingTaskIds
        }

        try await taskadeAPI.updateTaskStatus(
            projectId: projectId,
            taskId: taskId,
            completed: task.isCompleted,
            accessToken: accessToken
        )
    }

    /// Delete task on Taskade
    public func pushTaskDelete(
        _ task: TaskItem,
        accessToken: String
    ) async throws {
        guard let projectId = task.taskadeProjectId,
              let taskId = task.taskadeTaskId else {
            throw TaskadeSyncError.missingTaskIds
        }

        try await taskadeAPI.deleteTask(
            projectId: projectId,
            taskId: taskId,
            accessToken: accessToken
        )
    }

    // MARK: - Merge Logic

    /// Last-Writer-Wins merge by taskadeTaskId
    private func mergeTasks(local: [TaskItem], remote: [TaskItem]) -> [TaskItem] {
        var localByTaskadeId: [String: TaskItem] = [:]
        var localWithoutTaskadeId: [TaskItem] = []

        for task in local {
            if let tid = task.taskadeTaskId {
                localByTaskadeId[tid] = task
            } else {
                localWithoutTaskadeId.append(task)
            }
        }

        var result = localWithoutTaskadeId

        for remoteTask in remote {
            guard let tid = remoteTask.taskadeTaskId else { continue }
            guard let localTask = localByTaskadeId.removeValue(forKey: tid) else {
                result.append(remoteTask)
                continue
            }

            if localTask.syncStatus == .synced {
                result.append(Self.mergeRemoteTaskPreservingLocalFields(local: localTask, remote: remoteTask))
                continue
            }

            // LWW
            let localTime = localTask.lastModified
            let remoteTime = remoteTask.remoteUpdatedAt ?? remoteTask.lastModified
            if remoteTime > localTime {
                result.append(Self.mergeRemoteTaskPreservingLocalFields(local: localTask, remote: remoteTask))
            } else {
                result.append(localTask)
            }
        }

        // Keep remaining local tasks not matched
        for (_, task) in localByTaskadeId {
            result.append(task)
        }

        return result
    }

    /// Taskade remote payloads are sparse (title/completed only).
    /// Preserve locally maintained fields to prevent accidental data loss.
    nonisolated static func mergeRemoteTaskPreservingLocalFields(local: TaskItem, remote: TaskItem) -> TaskItem {
        var merged = remote
        merged.localId = local.localId
        merged.dueDate = remote.dueDate ?? local.dueDate
        merged.notes = remote.notes ?? local.notes
        merged.microActions = remote.microActions ?? local.microActions
        if remote.priority == .medium {
            merged.priority = local.priority
        }
        return merged
    }
}

// MARK: - Taskade Sync Error

public enum TaskadeSyncError: LocalizedError, Sendable {
    case notAuthenticated
    case missingTaskIds
    case syncFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated with Taskade"
        case .missingTaskIds:
            return "Task is not linked to Taskade"
        case .syncFailed(let detail):
            return "Taskade sync failed: \(detail)"
        }
    }
}
