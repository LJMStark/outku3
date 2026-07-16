import Foundation

// MARK: - External Sync Dispatcher

/// Dispatches App-side edits/actions to the correct external source's API
/// (Google / Apple / Notion / Taskade) based on `EventSource`.
///
/// Pure dispatch — no AppState reads/writes. State mutations (sync status
/// flags, error reporting) stay in `AppState+Actions`. Adding a new source
/// only requires adding a switch case here, not touching action functions.
@MainActor
enum ExternalSyncDispatcher {
    // MARK: - Task: Completion / Deletion

    static func syncTaskAction(_ task: TaskItem, action: TaskExternalSyncAction) async throws {
        switch task.source {
        case .google:
            try await syncGoogleTask(task, action: action)
        case .apple:
            try await syncAppleTask(task, action: action)
        case .notion:
            try await syncNotionTask(task, action: action)
        case .taskade:
            try await syncTaskadeTask(task, action: action)
        case .todoist:
            throw ExternalEditingError.integrationReadOnly("Todoist")
        }
    }

    // MARK: - Task: Content Edit (title / priority / due / notes)

    static func syncTaskContentEdit(_ task: TaskItem) async throws -> TaskItem {
        switch task.source {
        case .google:
            let remoteTask = try await GoogleTasksAPI.shared.syncTaskUpdate(task)
            var syncedTask = task
            syncedTask.title = remoteTask.title
            syncedTask.isCompleted = remoteTask.isCompleted
            syncedTask.dueDate = remoteTask.dueDate
            syncedTask.notes = remoteTask.notes
            syncedTask.remoteUpdatedAt = remoteTask.remoteUpdatedAt
            syncedTask.remoteEtag = remoteTask.remoteEtag
            syncedTask.lastModified = remoteTask.remoteUpdatedAt ?? remoteTask.lastModified
            syncedTask.syncStatus = .synced
            return syncedTask
        case .apple:
            if task.appleReminderId != nil {
                try await AppleSyncEngine.shared.pushReminderUpdate(task)
            }
            var syncedTask = task
            syncedTask.remoteUpdatedAt = Date()
            syncedTask.syncStatus = .synced
            return syncedTask
        case .notion, .taskade, .todoist:
            throw ExternalEditingError.integrationReadOnly(componentName(for: task.source))
        }
    }

    // MARK: - Event: Content Edit (title / time / location / notes)

    static func syncEventContentEdit(_ event: CalendarEvent) async throws -> CalendarEvent {
        switch event.source {
        case .apple:
            guard let identifier = event.appleEventId else {
                return event
            }
            try await EventKitService.shared.updateEvent(
                identifier: identifier,
                title: event.title,
                startDate: event.startTime,
                endDate: event.endTime,
                location: event.location,
                notes: event.description
            )
            var syncedEvent = event
            syncedEvent.syncStatus = .synced
            return syncedEvent
        case .google:
            guard AuthManager.shared.hasCalendarWriteAccess else {
                throw ExternalEditingError.integrationReadOnly("Google Calendar")
            }
            guard let eventId = event.googleEventId else {
                throw ExternalEditingError.missingRemoteIdentifier("Google Calendar")
            }
            guard let calendarId = event.googleCalendarId else {
                throw ExternalEditingError.missingRemoteIdentifier("Google Calendar")
            }

            var syncedEvent = try await GoogleCalendarAPI.shared.patchEvent(
                calendarId: calendarId,
                eventId: eventId,
                title: event.title,
                startTime: event.startTime,
                endTime: event.endTime,
                isAllDay: event.isAllDay,
                location: event.location,
                description: event.description
            )
            syncedEvent.localId = event.localId
            syncedEvent.syncStatus = .synced
            return syncedEvent
        case .todoist, .notion, .taskade:
            throw ExternalEditingError.integrationReadOnly(componentName(for: event.source))
        }
    }

    // MARK: - Error Component Name

    static func componentName(for source: EventSource) -> String {
        switch source {
        case .google:
            return "Google Tasks"
        case .apple:
            return "Apple Reminders"
        case .notion:
            return "Notion"
        case .taskade:
            return "Taskade"
        case .todoist:
            return "Todoist"
        }
    }

    // MARK: - Private Per-Source Task Action Helpers

    private static func syncGoogleTask(_ task: TaskItem, action: TaskExternalSyncAction) async throws {
        let api = GoogleTasksAPI.shared
        let engine = GoogleSyncEngine.shared
        switch action {
        case .updateCompletion:
            do {
                try await api.syncTaskCompletion(task)
                await engine.clearQueuedChanges(
                    for: task.id,
                    action: .updateStatus,
                    upToLastModified: task.lastModified
                )
            } catch {
                await engine.enqueueChange(task: task, action: .updateStatus)
                throw error
            }
        case .delete:
            guard let taskListId = task.googleTaskListId,
                  let taskId = task.googleTaskId else {
                throw GoogleTasksError.missingGoogleIds
            }
            do {
                try await api.deleteTask(taskListId: taskListId, taskId: taskId)
                await engine.clearQueuedChanges(
                    for: task.id,
                    action: .delete,
                    upToLastModified: task.lastModified
                )
            } catch {
                await engine.enqueueChange(task: task, action: .delete)
                throw error
            }
        }
    }

    private static func syncAppleTask(_ task: TaskItem, action: TaskExternalSyncAction) async throws {
        let engine = AppleSyncEngine.shared
        switch action {
        case .updateCompletion:
            if task.appleReminderId != nil {
                try await engine.pushReminderCompletionUpdate(task)
            }
        case .delete:
            try await engine.pushReminderDelete(task)
        }
    }

    private static func syncNotionTask(_ task: TaskItem, action: TaskExternalSyncAction) async throws {
        switch action {
        case .updateCompletion:
            guard let accessToken = AuthManager.shared.getNotionAccessToken() else {
                throw NotionSyncError.notAuthenticated
            }
            try await NotionSyncEngine.shared.pushTaskUpdate(task, accessToken: accessToken)
        case .delete:
            throw ExternalEditingError.integrationReadOnly("Notion")
        }
    }

    private static func syncTaskadeTask(_ task: TaskItem, action: TaskExternalSyncAction) async throws {
        let accessToken = try await AuthManager.shared.getTaskadeAccessToken()
        switch action {
        case .updateCompletion:
            try await TaskadeSyncEngine.shared.pushTaskUpdate(task, accessToken: accessToken)
        case .delete:
            try await TaskadeSyncEngine.shared.pushTaskDelete(task, accessToken: accessToken)
        }
    }
}
