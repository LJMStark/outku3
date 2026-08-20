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

    public func availableEventCalendars() async -> [AppleCalendarDescriptor] {
        await eventKitService.availableEventCalendars()
    }

    public func selectedEventCalendarIdentifiers(
        selectionMode: AppleCalendarSelectionMode? = nil
    ) async -> Set<String> {
        await eventKitService.selectedEventCalendarIdentifiers(selectionMode: selectionMode)
    }

    public func setSelectedEventCalendarIdentifiers(_ identifiers: Set<String>) async {
        await eventKitService.setSelectedEventCalendarIdentifiers(identifiers)
    }

    public func eventCalendarSelectionMode() async -> AppleCalendarSelectionMode {
        await eventKitService.eventCalendarSelectionMode()
    }

    public func setEventCalendarSelectionMode(_ mode: AppleCalendarSelectionMode) async {
        await eventKitService.setEventCalendarSelectionMode(mode)
    }

    // MARK: - Reminders Bidirectional Sync

    public func syncReminders(currentTasks: [TaskItem]) async throws -> [TaskItem] {
        let incomplete = try await eventKitService.fetchIncompleteReminders()
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let completed = try await eventKitService.fetchCompletedReminders(from: thirtyDaysAgo, to: Date())
        let remoteAll = incomplete + completed

        return Self.mergeReminders(currentTasks: currentTasks, remoteTasks: remoteAll)
    }

    /// Full provider identity is the primary key. EventKit's calendar item identifier is retained
    /// only as a legacy fallback for tasks saved before `ProviderItemReference` existed. A raw
    /// external UID is intentionally never used because two accounts/lists may expose the same UID.
    nonisolated static func mergeReminders(
        currentTasks: [TaskItem],
        remoteTasks: [TaskItem]
    ) -> [TaskItem] {
        let remoteByStableReference = Dictionary(
            remoteTasks.compactMap { task -> (String, TaskItem)? in
                guard task.externalReference?.provider == .appleReminders,
                      let stableID = task.externalReference?.stableLocalID else {
                    return nil
                }
                return (stableID, task)
            },
            uniquingKeysWith: { _, last in last }
        )
        let remoteByReminderID = Dictionary(
            remoteTasks.compactMap { task in
                task.appleReminderId.flatMap { id in id.isEmpty ? nil : (id, task) }
            },
            uniquingKeysWith: { _, last in last }
        )

        var matchedStableReferences: Set<String> = []
        var matchedReminderIDs: Set<String> = []

        let merged: [TaskItem] = currentTasks.compactMap { local in
            if local.externalReference?.provider == .appleReminders,
               let stableID = local.externalReference?.stableLocalID,
               let remote = remoteByStableReference[stableID] {
                matchedStableReferences.insert(stableID)
                return Self.mergeLocalWithRemote(local: local, remote: remote)
            }
            if local.externalReference == nil,
               let reminderID = local.appleReminderId,
               !reminderID.isEmpty,
               let remote = remoteByReminderID[reminderID] {
                matchedReminderIDs.insert(reminderID)
                return Self.mergeLocalWithRemote(local: local, remote: remote)
            }
            if local.externalReference?.provider == .appleReminders
                || !(local.appleReminderId ?? "").isEmpty {
                return nil
            }
            return local
        }

        let newFromApple = remoteTasks.filter { remote in
            let stableID = remote.externalReference?.provider == .appleReminders
                ? remote.externalReference?.stableLocalID
                : nil
            let reminderID = remote.appleReminderId
            return !(stableID.map(matchedStableReferences.contains) ?? false)
                && !(reminderID.map(matchedReminderIDs.contains) ?? false)
        }
        return merged + newFromApple
    }

    /// 合并匹配上的本地与远端 Reminder。本地有未推送成功的修改（syncStatus != .synced，如硬件 0x21
    /// 回推的完成、或 push 失败标记的 .pending/.error）时走 Last-Writer-Wins，不无条件用远端旧值覆盖——
    /// 否则 push 失败的下一轮 syncReminders 会把本地修改（含离线/硬件操作）静默回滚丢失。与 Google
    /// 同步的脏检查策略一致。纯函数（无实例依赖），便于单测。
    nonisolated static func mergeLocalWithRemote(local: TaskItem, remote: TaskItem) -> TaskItem {
        if local.syncStatus != .synced {
            let localTime = local.lastModified
            let remoteTime = remote.remoteUpdatedAt ?? remote.lastModified
            if remoteTime <= localTime {
                return local
            }
        }

        var updated = local
        updated.title = remote.title
        updated.isCompleted = remote.isCompleted
        updated.dueDate = remote.dueDate
        updated.priority = remote.priority
        updated.notes = remote.notes
        updated.appleReminderId = remote.appleReminderId
        updated.appleExternalId = remote.appleExternalId
        updated.appleListId = remote.appleListId
        updated.externalReference = remote.externalReference
        updated.remoteUpdatedAt = remote.remoteUpdatedAt
        updated.lastModified = remote.lastModified
        // 采纳远端时也要收敛同步状态，否则本地的 .pending/.error 脏标记会残留——UI 继续显示同步失败，
        // 下一轮还把已按远端收敛的任务当 dirty 处理（与 Google 引擎返回整个远端任务的语义对齐）。
        updated.syncStatus = remote.syncStatus
        return updated
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

    public func pushReminderCompletionUpdate(_ task: TaskItem) async throws {
        guard let identifier = task.appleReminderId else { return }
        try await eventKitService.updateReminderCompletion(
            identifier: identifier,
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
            id: result.reference.stableLocalID,
            appleReminderId: result.calendarItemIdentifier,
            appleExternalId: result.externalIdentifier,
            appleListId: result.listIdentifier,
            externalReference: result.reference,
            title: task.title,
            isCompleted: task.isCompleted,
            dueDate: task.dueDate,
            source: .apple,
            priority: task.priority,
            syncStatus: .synced,
            lastModified: Date(),
            notes: task.notes,
            todayDisplayDate: task.todayDisplayDate
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
