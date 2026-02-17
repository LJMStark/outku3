import EventKit
import Foundation

// MARK: - Apple Sync Engine

public actor AppleSyncEngine {
    public static let shared = AppleSyncEngine()

    private let eventKitService = EventKitService.shared
    private var changeObserver: NSObjectProtocol?
    private var debounceTask: Task<Void, Never>?

    private init() {}

    // MARK: - Calendar Events (Read-Only, Apple is source of truth)

    public func fetchCalendarEvents(from startDate: Date, to endDate: Date) async throws -> [CalendarEvent] {
        try await eventKitService.fetchEvents(from: startDate, to: endDate)
    }

    // MARK: - Reminders Bidirectional Sync

    public func syncReminders(currentTasks: [TaskItem]) async throws -> [TaskItem] {
        let incomplete = try await eventKitService.fetchIncompleteReminders()
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let completed = try await eventKitService.fetchCompletedReminders(from: thirtyDaysAgo, to: Date())
        let remoteAll = incomplete + completed

        // Build lookup by appleExternalId (stable), fallback to appleReminderId
        var remoteByExternalId: [String: TaskItem] = [:]
        var remoteByReminderId: [String: TaskItem] = [:]
        for remote in remoteAll {
            if let extId = remote.appleExternalId, !extId.isEmpty {
                remoteByExternalId[extId] = remote
            }
            if let remId = remote.appleReminderId, !remId.isEmpty {
                remoteByReminderId[remId] = remote
            }
        }

        // Merge logic: Apple is source of truth for Apple fields, keep local-only fields
        var merged: [TaskItem] = []
        var matchedExternalIds: Set<String> = []
        var matchedReminderIds: Set<String> = []

        for local in currentTasks {
            // Try to match by externalId first, then reminderId
            var remote: TaskItem?
            if let extId = local.appleExternalId, !extId.isEmpty, let r = remoteByExternalId[extId] {
                remote = r
                matchedExternalIds.insert(extId)
            } else if let remId = local.appleReminderId, !remId.isEmpty, let r = remoteByReminderId[remId] {
                remote = r
                matchedReminderIds.insert(remId)
            }

            if let remote {
                // Keep local fields: localId, microActions, syncStatus
                var updated = local
                updated.title = remote.title
                updated.isCompleted = remote.isCompleted
                updated.dueDate = remote.dueDate
                updated.priority = remote.priority
                updated.notes = remote.notes
                updated.appleReminderId = remote.appleReminderId
                updated.appleExternalId = remote.appleExternalId
                updated.appleListId = remote.appleListId
                updated.remoteUpdatedAt = remote.remoteUpdatedAt
                updated.lastModified = remote.lastModified
                merged.append(updated)
            } else if let reminderId = local.appleReminderId, !reminderId.isEmpty {
                // Only treat as deleted if it was previously synced to Apple
                continue
            } else {
                // Keep unsynced local items (no Apple identifier yet)
                merged.append(local)
            }
        }

        // Add new reminders from Apple that don't exist locally
        for remote in remoteAll {
            let extId = remote.appleExternalId ?? ""
            let remId = remote.appleReminderId ?? ""
            let alreadyMatched = (!extId.isEmpty && matchedExternalIds.contains(extId))
                || (!remId.isEmpty && matchedReminderIds.contains(remId))
            if !alreadyMatched {
                merged.append(remote)
            }
        }

        return merged
    }

    // MARK: - Reminder Write Operations

    public func pushReminderUpdate(_ task: TaskItem) async throws {
        guard let identifier = task.appleReminderId else { return }
        try await eventKitService.updateReminder(
            identifier: identifier,
            title: task.title,
            dueDate: task.dueDate,
            priority: task.priority,
            notes: task.notes,
            isCompleted: task.isCompleted
        )
    }

    public func pushReminderCreate(_ task: TaskItem, listId: String) async throws -> TaskItem {
        let result = try await eventKitService.createReminder(
            title: task.title,
            dueDate: task.dueDate,
            priority: task.priority,
            notes: task.notes,
            listId: listId
        )
        return TaskItem(
            id: result.identifier,
            appleReminderId: result.identifier,
            appleExternalId: result.externalIdentifier,
            appleListId: listId,
            title: task.title,
            isCompleted: task.isCompleted,
            dueDate: task.dueDate,
            source: .apple,
            priority: task.priority,
            syncStatus: .synced,
            lastModified: Date(),
            notes: task.notes
        )
    }

    public func pushReminderDelete(_ task: TaskItem) async throws {
        guard let identifier = task.appleReminderId else { return }
        try await eventKitService.deleteReminder(identifier: identifier)
    }

    // MARK: - Change Observation

    public func startObservingChanges(onChange: @escaping @Sendable () async -> Void) {
        stopObservingChanges()
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.handleStoreChange(onChange: onChange)
            }
        }
    }

    public func stopObservingChanges() {
        if let observer = changeObserver {
            NotificationCenter.default.removeObserver(observer)
            changeObserver = nil
        }
        debounceTask?.cancel()
        debounceTask = nil
    }

    private func handleStoreChange(onChange: @escaping @Sendable () async -> Void) {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await onChange()
        }
    }
}
