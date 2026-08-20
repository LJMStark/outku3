import Foundation

// MARK: - External Sync Dispatcher

/// Dispatches App-side edits/actions to the correct external source's API
/// (Google / Apple) based on `EventSource`.
///
/// Pure dispatch — no AppState reads/writes. State mutations (sync status
/// flags and error reporting stay in `AppState+Actions`.
@MainActor
enum ExternalSyncDispatcher {
    // MARK: - Task: Completion / Deletion

    static func syncTaskAction(_ task: TaskItem, action: TaskExternalSyncAction) async throws {
        switch task.source {
        case .google:
            try await syncGoogleTask(task, action: action)
        case .apple:
            try await syncAppleTask(task, action: action)
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
        }
    }

    // MARK: - Error Component Name

    static func componentName(for source: EventSource) -> String {
        switch source {
        case .google:
            return "Google Tasks"
        case .apple:
            return "Apple Reminders"
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
}
