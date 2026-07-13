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

        let remoteByExternalId = Dictionary(
            remoteAll.compactMap { r in r.appleExternalId.flatMap { id in id.isEmpty ? nil : (id, r) } },
            uniquingKeysWith: { _, last in last }
        )
        let remoteByReminderId = Dictionary(
            remoteAll.compactMap { r in r.appleReminderId.flatMap { id in id.isEmpty ? nil : (id, r) } },
            uniquingKeysWith: { _, last in last }
        )

        var matchedExternalIds: Set<String> = []
        var matchedReminderIds: Set<String> = []

        let merged: [TaskItem] = currentTasks.compactMap { local in
            if let extId = local.appleExternalId, !extId.isEmpty, let remote = remoteByExternalId[extId] {
                matchedExternalIds.insert(extId)
                return Self.mergeLocalWithRemote(local: local, remote: remote)
            }
            if let remId = local.appleReminderId, !remId.isEmpty, let remote = remoteByReminderId[remId] {
                matchedReminderIds.insert(remId)
                return Self.mergeLocalWithRemote(local: local, remote: remote)
            }
            // Previously synced but no longer in Apple -- treat as deleted
            if local.appleReminderId != nil, !(local.appleReminderId ?? "").isEmpty {
                return nil
            }
            return local
        }

        let newFromApple = remoteAll.filter { remote in
            let extId = remote.appleExternalId ?? ""
            let remId = remote.appleReminderId ?? ""
            let alreadyMatched = (!extId.isEmpty && matchedExternalIds.contains(extId))
                || (!remId.isEmpty && matchedReminderIds.contains(remId))
            return !alreadyMatched
        }

        return merged + newFromApple
    }

    /// 合并匹配上的本地与远端 Reminder。本地有未推送成功的修改（syncStatus != .synced，如硬件 0x21
    /// 回推的完成、或 push 失败标记的 .pending/.error）时走 Last-Writer-Wins，不无条件用远端旧值覆盖——
    /// 否则 push 失败的下一轮 syncReminders 会把本地修改（含离线/硬件操作）静默回滚丢失。与 Google/Notion
    /// 引擎的脏检查策略对齐。纯函数（无实例依赖），便于单测。
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
