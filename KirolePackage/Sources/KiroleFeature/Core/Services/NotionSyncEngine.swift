import Foundation

// MARK: - Notion Sync Engine

/// Orchestrates sync between local tasks and Notion databases.
/// Uses heuristic property detection and Last-Writer-Wins merge strategy.
public actor NotionSyncEngine {
    public static let shared = NotionSyncEngine()

    private let notionAPI = NotionAPI.shared

    private var isSyncing = false

    private init() {}

    // MARK: - Sync Tasks

    /// Fetch tasks from all Notion databases and merge with local tasks
    public func syncTasks(
        currentTasks: [TaskItem],
        accessToken: String
    ) async throws -> [TaskItem] {
        guard !isSyncing else { return currentTasks }
        isSyncing = true
        defer { isSyncing = false }

        let databases = try await notionAPI.searchDatabases(accessToken: accessToken)

        var remoteTasks: [TaskItem] = []

        for database in databases {
            let pages = try await notionAPI.getAllPages(
                databaseId: database.id,
                accessToken: accessToken
            )

            let tasks = pages
                .filter { !$0.archived }
                .compactMap { page -> TaskItem? in
                    guard page.extractedTitle != nil else { return nil }
                    return TaskItem.from(notionPage: page, databaseId: database.id)
                }

            remoteTasks.append(contentsOf: tasks)
        }

        return mergeTasks(local: currentTasks, remote: remoteTasks)
    }

    // MARK: - Push Update

    /// Update task completion status back to Notion
    public func pushTaskUpdate(_ task: TaskItem, accessToken: String) async throws {
        guard let pageId = task.notionPageId else {
            throw NotionSyncError.syncFailed("Task has no Notion page ID")
        }

        // Detect the actual checkbox property name from the page
        let checkboxPropertyName = try await detectCheckboxPropertyName(
            pageId: pageId,
            accessToken: accessToken
        )

        try await notionAPI.updatePageCheckbox(
            pageId: pageId,
            propertyName: checkboxPropertyName,
            checked: task.isCompleted,
            accessToken: accessToken
        )
    }

    // MARK: - Merge Logic

    /// Last-Writer-Wins merge by notionPageId
    private func mergeTasks(local: [TaskItem], remote: [TaskItem]) -> [TaskItem] {
        var localByNotionId: [String: TaskItem] = [:]
        var localWithoutNotionId: [TaskItem] = []

        for task in local {
            if let nid = task.notionPageId {
                localByNotionId[nid] = task
            } else {
                localWithoutNotionId.append(task)
            }
        }

        var result = localWithoutNotionId

        for remoteTask in remote {
            guard let nid = remoteTask.notionPageId else { continue }
            guard let localTask = localByNotionId.removeValue(forKey: nid) else {
                result.append(remoteTask)
                continue
            }

            if localTask.syncStatus == .synced {
                result.append(remoteTask)
                continue
            }

            // LWW
            let localTime = localTask.lastModified
            let remoteTime = remoteTask.remoteUpdatedAt ?? remoteTask.lastModified
            result.append(remoteTime > localTime ? remoteTask : localTask)
        }

        // Keep remaining local tasks not matched
        for (_, task) in localByNotionId {
            result.append(task)
        }

        return result
    }

    // MARK: - Helpers

    /// Detect the checkbox property name by inspecting the page's properties.
    /// Notion databases use varying names for their checkbox columns.
    private func detectCheckboxPropertyName(
        pageId: String,
        accessToken: String
    ) async throws -> String {
        // Query the page to get its properties and find the first checkbox type
        guard let url = URL(string: "https://api.notion.com/v1/pages/\(pageId)") else {
            throw NotionSyncError.syncFailed("Invalid Notion page URL")
        }

        let page: NotionPage = try await NetworkClient.shared.get(
            url: url,
            headers: [
                "Authorization": "Bearer \(accessToken)",
                "Notion-Version": "2022-06-28"
            ],
            responseType: NotionPage.self
        )

        // Find the first checkbox property in the page
        for (name, value) in page.properties {
            if value.type == "checkbox" {
                return name
            }
        }

        // Fallback: try well-known names
        let commonNames = ["Done", "Completed", "Complete", "Status", "Checkbox"]
        for name in commonNames where page.properties[name] != nil {
            return name
        }

        throw NotionSyncError.syncFailed("No checkbox property found in Notion page")
    }
}

// MARK: - Notion Sync Error

public enum NotionSyncError: LocalizedError, Sendable {
    case notAuthenticated
    case syncFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated with Notion"
        case .syncFailed(let detail):
            return "Notion sync failed: \(detail)"
        }
    }
}
