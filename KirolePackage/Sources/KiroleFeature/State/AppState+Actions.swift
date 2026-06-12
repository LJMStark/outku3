import Foundation

enum TaskExternalSyncAction {
    case updateCompletion
    case delete

    var context: String {
        switch self {
        case .updateCompletion:
            return "AppState.toggleTaskCompletion"
        case .delete:
            return "AppState.deleteTask"
        }
    }
}

/// 任务完成切换的触发来源。状态变更（任务状态、宠物积分、持久化、外部同步）对两者一致；
/// 反馈类副作用（声音/震动、completion haiku）只属于实时用户操作——离线事件批量回放
/// 时逐条触发会变成重连瞬间的震动风暴 + N 次 LLM 调用。
public enum TaskToggleSource {
    case user
    case hardwareReplay
}

extension AppState {
    private enum TaskSyncSupport {
        case localOnly
        case remote
    }

    public func toggleTaskCompletion(_ task: TaskItem, source: TaskToggleSource = .user) {
        guard let existingTask = tasks.first(where: { $0.id == task.id }) else { return }

        var updatedTask = existingTask
        updatedTask.isCompleted.toggle()
        updatedTask.lastModified = Date()
        let syncSupport = taskSyncSupport(for: updatedTask, action: .updateCompletion)
        updatedTask.syncStatus = syncSupport == .remote ? .pending : .error
        updatedTask.pendingDeletion = false
        let syncVersion = updatedTask.lastModified
        let isCompleted = updatedTask.isCompleted

        tasks = taskManager.withTask(tasks, updatedTask: updatedTask)
        updatePetForTaskToggle(isCompleted: isCompleted, playFeedback: source == .user)
        updateStatistics()
        requestBLESync(reason: "toggleTaskCompletion")

        Task { @MainActor in
            await persistTaskAndPetState(
                tasks: self.tasks,
                pet: self.pet,
                context: "AppState.toggleTaskCompletion"
            )

            await syncTaskToExternalService(
                updatedTask,
                action: .updateCompletion,
                expectedLastModified: syncVersion
            )
            await updatePetState()

            if isCompleted, source == .user {
                currentHaiku = await haikuService.generateCompletionHaiku(
                    tasksCompleted: statistics.todayCompleted,
                    totalTasks: statistics.todayTotal,
                    petMood: pet.mood
                )
            }
        }
    }

    private func updatePetForTaskToggle(isCompleted: Bool, playFeedback: Bool) {
        var updatedPet = pet

        if isCompleted {
            if playFeedback {
                SoundService.shared.playWithHaptic(.taskComplete, haptic: .success)
            }
            updatedPet.adventuresCount += 1
            updatedPet.points += ProgressConstants.pointsPerTask
            updatedPet.lastInteraction = Date()
        } else {
            if playFeedback {
                SoundService.shared.playWithHaptic(.taskUncomplete, haptic: .light)
            }
            updatedPet.adventuresCount = max(0, updatedPet.adventuresCount - 1)
            updatedPet.points = max(0, updatedPet.points - ProgressConstants.pointsPerTask)
            updatedPet.lastInteraction = Date()
        }

        pet = updatedPet
    }

    private func syncTaskToExternalService(
        _ task: TaskItem,
        action: TaskExternalSyncAction,
        expectedLastModified: Date?
    ) async {
        do {
            try await ExternalSyncDispatcher.syncTaskAction(task, action: action)
            switch action {
            case .updateCompletion:
                await updateTaskSyncStatus(
                    taskId: task.id,
                    expectedLastModified: expectedLastModified,
                    to: .synced,
                    context: "AppState.syncTaskToExternalService.success"
                )
            case .delete:
                await finalizeTaskDeletion(
                    taskId: task.id,
                    expectedLastModified: expectedLastModified,
                    context: "AppState.syncTaskToExternalService.deleteSuccess"
                )
            }
        } catch {
            if action == .updateCompletion {
                let targetStatus: SyncStatus = shouldMarkConflict(for: error) ? .conflict : .error
                await updateTaskSyncStatus(
                    taskId: task.id,
                    expectedLastModified: expectedLastModified,
                    to: targetStatus,
                    context: "AppState.syncTaskToExternalService.failure"
                )
            } else if shouldMarkConflict(for: error) {
                await updateTaskSyncStatus(
                    taskId: task.id,
                    expectedLastModified: expectedLastModified,
                    to: .conflict,
                    context: "AppState.syncTaskToExternalService.deleteConflict"
                )
            }
            reportSyncError(error, component: ExternalSyncDispatcher.componentName(for: task.source), context: action.context)
        }
    }

    public func editEvent(
        _ event: CalendarEvent,
        title: String,
        startTime: Date,
        endTime: Date,
        location: String?,
        notes: String?
    ) async throws {
        guard let index = events.firstIndex(where: { $0.id == event.id }) else { return }

        var updatedEvent = events[index]
        updatedEvent.title = title
        updatedEvent.startTime = startTime
        updatedEvent.endTime = endTime
        updatedEvent.location = location
        updatedEvent.description = notes
        updatedEvent.lastModified = Date()

        do {
            let syncedEvent = try await ExternalSyncDispatcher.syncEventContentEdit(updatedEvent)
            events[index] = syncedEvent
            await persistEvents(events, context: "AppState.editEvent")
            requestBLESync(reason: "editEvent")
        } catch {
            reportSyncError(error, component: event.source.rawValue, context: "AppState.editEvent")
            throw error
        }
    }

    public func selectEvent(_ event: CalendarEvent) {
        selectedEvent = event
        isEventDetailPresented = true
    }

    public func dismissEventDetail() {
        isEventDetailPresented = false
        selectedEvent = nil
    }

    public func setFocusEnforcementMode(_ mode: FocusEnforcementMode) {
        FocusSessionService.shared.setFocusEnforcementMode(mode)
    }

    public func addTask(_ task: TaskItem) {
        tasks = taskManager.addingTask(tasks, task: task)
        updateStatistics()
        requestBLESync(reason: "addTask")

        Task { @MainActor in
            await persistTasks(tasks, context: "AppState.addTask")
        }
    }

    public func deleteTask(_ task: TaskItem) {
        guard let existingTask = tasks.first(where: { $0.id == task.id }) else { return }
        let support = taskSyncSupport(for: existingTask, action: .delete)

        if support == .localOnly {
            tasks = taskManager.removingTask(tasks, taskID: task.id)
            updateStatistics()
            requestBLESync(reason: "deleteTask.localOnly")

            Task { @MainActor in
                await persistTasks(tasks, context: "AppState.deleteTask.localOnly")
            }
            return
        }

        var deletingTask = existingTask
        deletingTask.pendingDeletion = true
        deletingTask.syncStatus = .pending
        deletingTask.lastModified = Date()
        let deletionVersion = deletingTask.lastModified

        tasks = taskManager.withTask(tasks, updatedTask: deletingTask)
        updateStatistics()
        requestBLESync(reason: "deleteTask.pending")

        Task { @MainActor in
            await persistTasks(tasks, context: "AppState.deleteTask.pending")
            await syncTaskToExternalService(
                deletingTask,
                action: .delete,
                expectedLastModified: deletionVersion
            )
        }
    }

    public func retryTaskSync(_ task: TaskItem) async {
        guard let currentTask = tasks.first(where: { $0.id == task.id }) else { return }

        if currentTask.pendingDeletion {
            await retryTaskDeletion(currentTask)
            return
        }

        var retryTask = currentTask
        retryTask.syncStatus = .pending
        retryTask.lastModified = Date()
        let retryVersion = retryTask.lastModified

        tasks = taskManager.withTask(tasks, updatedTask: retryTask)
        await persistTasks(tasks, context: "AppState.retryTaskSync.pending")
        await syncTaskToExternalService(
            retryTask,
            action: .updateCompletion,
            expectedLastModified: retryVersion
        )
        requestBLESync(reason: "retryTaskSync")
    }

    public func editTask(
        _ task: TaskItem,
        title: String,
        priority: TaskPriority,
        dueDate: Date?,
        notes: String?
    ) async throws {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }

        var updatedTask = tasks[index]
        updatedTask.title = title
        updatedTask.priority = priority
        updatedTask.dueDate = dueDate
        updatedTask.notes = notes
        updatedTask.lastModified = Date()

        do {
            let syncedTask = try await ExternalSyncDispatcher.syncTaskContentEdit(updatedTask)
            tasks = taskManager.withTask(tasks, updatedTask: syncedTask)
            updateStatistics()
            await persistTasks(tasks, context: "AppState.editTask")
            requestBLESync(reason: "editTask")
        } catch {
            reportSyncError(error, component: task.source.rawValue, context: "AppState.editTask")
            throw error
        }
    }

    private func updateTaskSyncStatus(
        taskId: String,
        expectedLastModified: Date?,
        to status: SyncStatus,
        context: String
    ) async {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        if let expectedLastModified, tasks[index].lastModified != expectedLastModified {
            return
        }
        tasks[index].syncStatus = status
        await persistTasks(tasks, context: context)
    }

    private func finalizeTaskDeletion(
        taskId: String,
        expectedLastModified: Date?,
        context: String
    ) async {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        if let expectedLastModified, tasks[index].lastModified != expectedLastModified {
            return
        }
        tasks = taskManager.removingTask(tasks, taskID: taskId)
        updateStatistics()
        await persistTasks(tasks, context: context)
    }

    private func retryTaskDeletion(_ task: TaskItem) async {
        var retryTask = task
        retryTask.pendingDeletion = true
        retryTask.syncStatus = .pending
        retryTask.lastModified = Date()
        let retryVersion = retryTask.lastModified

        tasks = taskManager.withTask(tasks, updatedTask: retryTask)
        await persistTasks(tasks, context: "AppState.retryTaskDeletion.pending")
        await syncTaskToExternalService(
            retryTask,
            action: .delete,
            expectedLastModified: retryVersion
        )
    }

    private func taskSyncSupport(for task: TaskItem, action: TaskExternalSyncAction) -> TaskSyncSupport {
        switch action {
        case .updateCompletion:
            switch task.source {
            case .google, .apple, .notion, .taskade:
                return .remote
            case .todoist:
                return .localOnly
            }
        case .delete:
            switch task.source {
            case .google:
                return (task.googleTaskListId != nil && task.googleTaskId != nil) ? .remote : .localOnly
            case .apple:
                return task.appleReminderId != nil ? .remote : .localOnly
            case .taskade:
                return (task.taskadeProjectId != nil && task.taskadeTaskId != nil) ? .remote : .localOnly
            case .notion, .todoist:
                return .localOnly
            }
        }
    }

    private func shouldMarkConflict(for error: Error) -> Bool {
        guard let editingError = error as? ExternalEditingError else { return true }
        if case .integrationReadOnly = editingError {
            return false
        }
        return true
    }

    public func updateEvents(_ newEvents: [CalendarEvent]) {
        events = newEvents
        Task { @MainActor in
            await persistEvents(events, context: "AppState.updateEvents")
        }
    }

    public func updateTasks(_ newTasks: [TaskItem]) {
        tasks = newTasks
        updateStatistics()
        Task { @MainActor in
            await persistTasks(tasks, context: "AppState.updateTasks")
        }
    }

    func reportSyncError(_ error: Error, component: String, context: String) {
        if error is ExternalEditingError {
            lastError = UserFacingErrorMapper.message(for: error)
            ErrorReporter.log(AppError.unknown(error.localizedDescription), context: context)
            return
        }
        let appError = AppError.sync(component: component, underlying: error.localizedDescription)
        lastError = UserFacingErrorMapper.message(for: appError)
        ErrorReporter.log(appError, context: context)
    }
}
