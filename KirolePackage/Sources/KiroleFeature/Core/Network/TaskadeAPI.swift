import Foundation

// MARK: - Taskade API

/// Taskade API client for workspaces, projects, and tasks
public actor TaskadeAPI {
    public static let shared = TaskadeAPI()

    private let networkClient = NetworkClient.shared
    private let baseURL = "https://www.taskade.com/api/v1"

    private init() {}

    // MARK: - Workspaces

    /// Get all workspaces accessible by the authenticated user
    public func getWorkspaces(accessToken: String) async throws -> [TaskadeWorkspace] {
        guard let url = URL(string: "\(baseURL)/workspaces") else {
            throw TaskadeAPIError.invalidURL
        }

        let response: TaskadeWorkspacesResponse = try await networkClient.get(
            url: url,
            headers: makeHeaders(accessToken),
            responseType: TaskadeWorkspacesResponse.self
        )

        return response.items
    }

    // MARK: - Projects

    /// Get projects in a workspace
    public func getProjects(
        workspaceId: String,
        accessToken: String
    ) async throws -> [TaskadeProject] {
        guard let url = URL(string: "\(baseURL)/workspaces/\(workspaceId)/projects") else {
            throw TaskadeAPIError.invalidURL
        }

        let response: TaskadeProjectsResponse = try await networkClient.get(
            url: url,
            headers: makeHeaders(accessToken),
            responseType: TaskadeProjectsResponse.self
        )

        return response.items
    }

    // MARK: - Tasks

    /// Get tasks in a project
    public func getProjectTasks(
        projectId: String,
        accessToken: String
    ) async throws -> [TaskadeTask] {
        guard let url = URL(string: "\(baseURL)/projects/\(projectId)/tasks") else {
            throw TaskadeAPIError.invalidURL
        }

        let response: TaskadeTasksResponse = try await networkClient.get(
            url: url,
            headers: makeHeaders(accessToken),
            responseType: TaskadeTasksResponse.self
        )

        return response.items
    }

    /// Get all tasks across all projects in all workspaces
    public func getAllTasks(accessToken: String) async throws -> [TaskItem] {
        let workspaces = try await getWorkspaces(accessToken: accessToken)

        return try await withThrowingTaskGroup(of: [TaskItem].self) { group in
            for workspace in workspaces {
                group.addTask {
                    try await self.getTasksForWorkspace(
                        workspaceId: workspace.id,
                        accessToken: accessToken
                    )
                }
            }

            var allTasks: [TaskItem] = []
            for try await tasks in group {
                allTasks.append(contentsOf: tasks)
            }
            return allTasks
        }
    }

    private func getTasksForWorkspace(
        workspaceId: String,
        accessToken: String
    ) async throws -> [TaskItem] {
        let projects = try await getProjects(
            workspaceId: workspaceId,
            accessToken: accessToken
        )

        return try await withThrowingTaskGroup(of: [TaskItem].self) { group in
            for project in projects {
                group.addTask {
                    let tasks = try await self.getProjectTasks(
                        projectId: project.id,
                        accessToken: accessToken
                    )
                    return tasks.map { TaskItem.from(taskadeTask: $0, projectId: project.id) }
                }
            }

            var allTasks: [TaskItem] = []
            for try await tasks in group {
                allTasks.append(contentsOf: tasks)
            }
            return allTasks
        }
    }

    // MARK: - Update Task

    /// Update task completion status
    public func updateTaskStatus(
        projectId: String,
        taskId: String,
        completed: Bool,
        accessToken: String
    ) async throws {
        guard let url = URL(string: "\(baseURL)/projects/\(projectId)/tasks/\(taskId)") else {
            throw TaskadeAPIError.invalidURL
        }

        let body = TaskadeUpdateTaskRequest(completed: completed)

        _ = try await networkClient.patch(
            url: url,
            headers: makeHeaders(accessToken),
            body: body,
            responseType: TaskadeTask.self
        )
    }

    // MARK: - Helpers

    private func makeHeaders(_ accessToken: String) -> [String: String] {
        ["Authorization": "Bearer \(accessToken)"]
    }
}

// MARK: - Taskade API Error

public enum TaskadeAPIError: LocalizedError, Sendable {
    case invalidURL
    case projectNotFound
    case accessDenied

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Failed to construct Taskade API URL"
        case .projectNotFound:
            return "Taskade project not found"
        case .accessDenied:
            return "Taskade access denied"
        }
    }
}
