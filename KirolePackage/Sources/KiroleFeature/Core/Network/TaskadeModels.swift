import Foundation

// MARK: - Taskade API Response Models

// MARK: Workspace

public struct TaskadeWorkspace: Codable, Sendable {
    public let id: String
    public let name: String
}

public struct TaskadeWorkspacesResponse: Codable, Sendable {
    public let items: [TaskadeWorkspace]
}

// MARK: Project

public struct TaskadeProject: Codable, Sendable {
    public let id: String
    public let title: String?
    public let text: String?
}

public struct TaskadeProjectsResponse: Codable, Sendable {
    public let items: [TaskadeProject]
}

// MARK: Task

public struct TaskadeTask: Codable, Sendable {
    public let id: String
    public let text: String
    public let completed: Bool
    public let parentId: String?
    public let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, text, completed
        case parentId = "parent_id"
        case updatedAt = "updated_at"
    }

    public var parsedUpdatedAt: Date? {
        guard let updatedAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: updatedAt)
    }
}

public struct TaskadeTasksResponse: Codable, Sendable {
    public let items: [TaskadeTask]
}

// MARK: Update Request

struct TaskadeUpdateTaskRequest: Encodable {
    let completed: Bool
}

// MARK: - TaskItem Mapping

extension TaskItem {
    public static func from(taskadeTask task: TaskadeTask, projectId: String) -> TaskItem {
        TaskItem(
            id: task.id,
            taskadeTaskId: task.id,
            taskadeProjectId: projectId,
            title: task.text,
            isCompleted: task.completed,
            source: .taskade,
            priority: .medium,
            syncStatus: .synced,
            lastModified: task.parsedUpdatedAt ?? Date(),
            remoteUpdatedAt: task.parsedUpdatedAt
        )
    }
}
