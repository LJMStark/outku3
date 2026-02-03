import Foundation

// MARK: - Google Tasks API

/// Google Tasks API 客户端
public actor GoogleTasksAPI {
    public static let shared = GoogleTasksAPI()

    private let networkClient = NetworkClient.shared
    private let baseURL = "https://tasks.googleapis.com/tasks/v1"

    private init() {}

    // MARK: - Task Lists

    /// 获取任务列表（Task Lists）
    public func getTaskLists() async throws -> [GoogleTaskList] {
        let accessToken = try await AuthManager.shared.getGoogleAccessToken()

        let url = URL(string: "\(baseURL)/users/@me/lists")!

        let response: GoogleTaskListsResponse = try await networkClient.get(
            url: url,
            headers: ["Authorization": "Bearer \(accessToken)"],
            responseType: GoogleTaskListsResponse.self
        )

        return response.items ?? []
    }

    // MARK: - Tasks

    /// 获取指定列表中的任务
    /// - Parameters:
    ///   - taskListId: 任务列表 ID
    ///   - showCompleted: 是否显示已完成的任务
    ///   - showHidden: 是否显示隐藏的任务
    ///   - dueMin: 最早截止日期
    ///   - dueMax: 最晚截止日期
    public func getTasks(
        taskListId: String,
        showCompleted: Bool = true,
        showHidden: Bool = false,
        dueMin: Date? = nil,
        dueMax: Date? = nil,
        maxResults: Int = 100
    ) async throws -> [GoogleTask] {
        let accessToken = try await AuthManager.shared.getGoogleAccessToken()

        var components = URLComponents(string: "\(baseURL)/lists/\(taskListId)/tasks")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "maxResults", value: String(maxResults)),
            URLQueryItem(name: "showCompleted", value: String(showCompleted)),
            URLQueryItem(name: "showHidden", value: String(showHidden))
        ]

        let formatter = ISO8601DateFormatter()

        if let dueMin = dueMin {
            queryItems.append(URLQueryItem(name: "dueMin", value: formatter.string(from: dueMin)))
        }
        if let dueMax = dueMax {
            queryItems.append(URLQueryItem(name: "dueMax", value: formatter.string(from: dueMax)))
        }

        components.queryItems = queryItems

        let response: GoogleTaskListResponse = try await networkClient.get(
            url: components.url!,
            headers: ["Authorization": "Bearer \(accessToken)"],
            responseType: GoogleTaskListResponse.self
        )

        return response.items ?? []
    }

    /// 获取所有列表中的任务
    public func getAllTasks(
        showCompleted: Bool = true,
        dueMin: Date? = nil,
        dueMax: Date? = nil
    ) async throws -> [TaskItem] {
        let taskLists = try await getTaskLists()

        var allTasks: [TaskItem] = []

        for taskList in taskLists {
            let tasks = try await getTasks(
                taskListId: taskList.id,
                showCompleted: showCompleted,
                dueMin: dueMin,
                dueMax: dueMax
            )

            let taskItems = tasks.map { TaskItem.from(googleTask: $0, taskListId: taskList.id) }
            allTasks.append(contentsOf: taskItems)
        }

        return allTasks
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

        let url = URL(string: "\(baseURL)/lists/\(taskListId)/tasks/\(taskId)")!

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
        }
    }
}
