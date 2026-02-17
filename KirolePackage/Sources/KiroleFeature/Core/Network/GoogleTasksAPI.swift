import Foundation

// MARK: - Google Tasks API

/// Google Tasks API 客户端
public actor GoogleTasksAPI {
    public static let shared = GoogleTasksAPI()

    private let networkClient = NetworkClient.shared
    private let baseURL = "https://tasks.googleapis.com/tasks/v1"

    private init() {}

    // MARK: - Task Lists

    /// 获取任务列表（Task Lists），自动分页
    public func getTaskLists() async throws -> [GoogleTaskList] {
        let accessToken = try await AuthManager.shared.getGoogleAccessToken()
        var allItems: [GoogleTaskList] = []
        var currentPageToken: String? = nil
        let maxPages = 50

        for _ in 0..<maxPages {
            guard var components = URLComponents(string: "\(baseURL)/users/@me/lists") else {
                throw GoogleTasksError.invalidURL
            }
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "maxResults", value: "100")
            ]
            if let pageToken = currentPageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            components.queryItems = queryItems

            guard let url = components.url else {
                throw GoogleTasksError.invalidURL
            }

            let response: GoogleTaskListsResponse = try await networkClient.get(
                url: url,
                headers: ["Authorization": "Bearer \(accessToken)"],
                responseType: GoogleTaskListsResponse.self
            )

            if let items = response.items {
                allItems.append(contentsOf: items)
            }

            currentPageToken = response.nextPageToken
            if currentPageToken == nil {
                break
            }
        }

        return allItems
    }

    // MARK: - Tasks

    /// 获取指定列表中的任务（自动分页）
    /// - Parameters:
    ///   - taskListId: 任务列表 ID
    ///   - showCompleted: 是否显示已完成的任务
    ///   - showHidden: 是否显示隐藏的任务
    ///   - showDeleted: 是否显示已删除的任务
    ///   - dueMin: 最早截止日期
    ///   - dueMax: 最晚截止日期
    ///   - updatedMin: 仅返回此时间之后更新的任务
    public func getTasks(
        taskListId: String,
        showCompleted: Bool = true,
        showHidden: Bool = false,
        showDeleted: Bool = false,
        dueMin: Date? = nil,
        dueMax: Date? = nil,
        updatedMin: Date? = nil,
        maxResults: Int = 100
    ) async throws -> [GoogleTask] {
        let accessToken = try await AuthManager.shared.getGoogleAccessToken()
        let encodedTaskListId = taskListId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? taskListId
        var allItems: [GoogleTask] = []
        var currentPageToken: String? = nil
        let maxPages = 50
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        for _ in 0..<maxPages {
            guard var components = URLComponents(string: "\(baseURL)/lists/\(encodedTaskListId)/tasks") else {
                throw GoogleTasksError.invalidURL
            }
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "maxResults", value: String(maxResults)),
                URLQueryItem(name: "showCompleted", value: String(showCompleted)),
                URLQueryItem(name: "showHidden", value: String(showHidden)),
                URLQueryItem(name: "showDeleted", value: String(showDeleted))
            ]

            if let dueMin = dueMin {
                queryItems.append(URLQueryItem(name: "dueMin", value: formatter.string(from: dueMin)))
            }
            if let dueMax = dueMax {
                queryItems.append(URLQueryItem(name: "dueMax", value: formatter.string(from: dueMax)))
            }
            if let updatedMin = updatedMin {
                queryItems.append(URLQueryItem(name: "updatedMin", value: formatter.string(from: updatedMin)))
            }
            if let pageToken = currentPageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
            }

            components.queryItems = queryItems

            guard let url = components.url else {
                throw GoogleTasksError.invalidURL
            }

            let response: GoogleTaskListResponse = try await networkClient.get(
                url: url,
                headers: ["Authorization": "Bearer \(accessToken)"],
                responseType: GoogleTaskListResponse.self
            )

            if let items = response.items {
                allItems.append(contentsOf: items)
            }

            currentPageToken = response.nextPageToken
            if currentPageToken == nil {
                break
            }
        }

        return allItems
    }

    // MARK: - Create Task

    /// 创建新任务
    public func createTask(
        taskListId: String,
        title: String,
        notes: String? = nil,
        due: String? = nil
    ) async throws -> GoogleTask {
        let accessToken = try await AuthManager.shared.getGoogleAccessToken()

        let encodedListId = taskListId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? taskListId
        guard let url = URL(string: "\(baseURL)/lists/\(encodedListId)/tasks") else {
            throw GoogleTasksError.invalidURL
        }

        let createRequest = GoogleTaskCreateRequest(title: title, notes: notes, due: due)

        return try await networkClient.post(
            url: url,
            headers: ["Authorization": "Bearer \(accessToken)"],
            body: createRequest,
            responseType: GoogleTask.self
        )
    }

    // MARK: - Delete Task

    /// 删除任务
    public func deleteTask(taskListId: String, taskId: String) async throws {
        let accessToken = try await AuthManager.shared.getGoogleAccessToken()

        let encodedListId = taskListId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? taskListId
        let encodedTaskId = taskId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? taskId
        guard let url = URL(string: "\(baseURL)/lists/\(encodedListId)/tasks/\(encodedTaskId)") else {
            throw GoogleTasksError.invalidURL
        }

        try await networkClient.delete(
            url: url,
            headers: ["Authorization": "Bearer \(accessToken)"]
        )
    }

    /// 获取所有列表中的任务（并发获取）
    public func getAllTasks(
        showCompleted: Bool = true,
        dueMin: Date? = nil,
        dueMax: Date? = nil
    ) async throws -> [TaskItem] {
        let taskLists = try await getTaskLists()

        return try await withThrowingTaskGroup(of: [TaskItem].self) { group in
            for taskList in taskLists {
                group.addTask {
                    let tasks = try await self.getTasks(
                        taskListId: taskList.id,
                        showCompleted: showCompleted,
                        dueMin: dueMin,
                        dueMax: dueMax
                    )
                    return tasks.map { TaskItem.from(googleTask: $0, taskListId: taskList.id) }
                }
            }

            var allTasks: [TaskItem] = []
            for try await taskItems in group {
                allTasks.append(contentsOf: taskItems)
            }
            return allTasks
        }
    }

    /// 获取今日任务
    public func getTodayTasks() async throws -> [TaskItem] {
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        return try await getAllTasks(
            showCompleted: true,
            dueMin: startOfDay,
            dueMax: endOfDay
        )
    }

    // MARK: - Update Task

    /// 更新任务状态
    /// - Parameters:
    ///   - taskListId: 任务列表 ID
    ///   - taskId: 任务 ID
    ///   - completed: 是否完成
    public func updateTaskStatus(
        taskListId: String,
        taskId: String,
        completed: Bool
    ) async throws -> GoogleTask {
        let accessToken = try await AuthManager.shared.getGoogleAccessToken()

        let encodedListId = taskListId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? taskListId
        let encodedTaskId = taskId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? taskId
        guard let url = URL(string: "\(baseURL)/lists/\(encodedListId)/tasks/\(encodedTaskId)") else {
            throw GoogleTasksError.invalidURL
        }

        let updateRequest = completed
            ? GoogleTaskUpdateRequest.markCompleted()
            : GoogleTaskUpdateRequest.markIncomplete()

        return try await networkClient.patch(
            url: url,
            headers: ["Authorization": "Bearer \(accessToken)"],
            body: updateRequest,
            responseType: GoogleTask.self
        )
    }

    /// 标记任务为完成
    public func completeTask(taskListId: String, taskId: String) async throws {
        _ = try await updateTaskStatus(taskListId: taskListId, taskId: taskId, completed: true)
    }

    /// 标记任务为未完成
    public func uncompleteTask(taskListId: String, taskId: String) async throws {
        _ = try await updateTaskStatus(taskListId: taskListId, taskId: taskId, completed: false)
    }

    // MARK: - Sync Helper

    /// 同步本地任务状态到 Google
    public func syncTaskCompletion(_ task: TaskItem) async throws {
        guard let taskListId = task.googleTaskListId,
              let taskId = task.googleTaskId else {
            throw GoogleTasksError.missingGoogleIds
        }

        _ = try await updateTaskStatus(
            taskListId: taskListId,
            taskId: taskId,
            completed: task.isCompleted
        )
    }
}

// MARK: - Google Tasks Error

public enum GoogleTasksError: LocalizedError, Sendable {
    case missingGoogleIds
    case taskNotFound
    case listNotFound
    case accessDenied
    case invalidURL

    public var errorDescription: String? {
        switch self {
        case .missingGoogleIds:
            return "Task is not linked to Google Tasks"
        case .taskNotFound:
            return "Task not found"
        case .listNotFound:
            return "Task list not found"
        case .accessDenied:
            return "Tasks access denied"
        case .invalidURL:
            return "Failed to construct tasks API URL"
        }
    }
}
