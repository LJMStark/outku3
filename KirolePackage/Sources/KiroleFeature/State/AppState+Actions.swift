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
public enum TaskToggleSource: Equatable {
    case user
    case hardwareReplay

    func companionMotion(isCompleted: Bool) -> CompanionMotion? {
        guard self == .user, isCompleted else { return nil }
        return .celebrate
    }
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
        if let motion = source.companionMotion(isCompleted: isCompleted) {
            emitCompanionMotion(motion)
        }
        updateStatistics()
        requestBLESync(reason: "toggleTaskCompletion")

        let externalSyncTask = taskExternalSyncQueue.enqueue(for: updatedTask.id) { [weak self] in
            guard let self else { return }
            await self.syncTaskToExternalService(
                updatedTask,
                action: .updateCompletion,
                expectedLastModified: syncVersion
            )
        }

        Task { @MainActor in
            await persistTaskAndPetState(
                tasks: self.tasks,
                pet: self.pet,
                context: "AppState.toggleTaskCompletion"
            )

            await externalSyncTask.value
            await updatePetState()

            if isCompleted,
               source == .user,
               let currentTask = tasks.first(where: { $0.id == updatedTask.id }),
               currentTask.lastModified == syncVersion,
               currentTask.isCompleted {
                currentHaiku = await haikuService.generateCompletionHaiku(
                    tasksCompleted: statistics.todayCompleted,
                    totalTasks: statistics.todayTotal,
                    petMood: pet.mood
                )
            }
        }
    }

    /// Emits one non-overlapping companion motion. Repeated events are coalesced while the
    /// current one-shot is visible, so rapid completions do not keep restarting frame one.
    public func emitCompanionMotion(_ motion: CompanionMotion) {
        guard pendingCompanionMotionTrigger == nil else { return }

        let trigger = CompanionMotionTrigger(motion: motion)
        pendingCompanionMotionTrigger = trigger
        companionMotionClearTask?.cancel()
        let duration = CompanionAnimationCatalog.animationDefinition(
            for: .joy,
            artwork: .reading,
            motion: motion
        )?.totalDuration ?? 0.8

        companionMotionClearTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(duration))
            } catch {
                return
            }
            guard self?.pendingCompanionMotionTrigger?.id == trigger.id else { return }
            self?.pendingCompanionMotionTrigger = nil
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
        let expectedLastModified = updatedEvent.lastModified
        updatedEvent.title = title
        updatedEvent.startTime = startTime
        updatedEvent.endTime = endTime
        updatedEvent.location = location
        updatedEvent.description = notes
        updatedEvent.lastModified = Date()

        do {
            let syncedEvent = try await ExternalSyncDispatcher.syncEventContentEdit(updatedEvent)
            guard let reconciled = Self.replacingEvent(
                in: events,
                with: syncedEvent,
                matching: event.id,
                expectedLastModified: expectedLastModified
            ) else {
                return
            }
            events = reconciled
            await persistEvents(events, context: "AppState.editEvent")
            requestBLESync(reason: "editEvent")
        } catch {
            reportSyncError(error, component: event.source.rawValue, context: "AppState.editEvent")
            throw error
        }
    }

    /// Applies an awaited remote edit only when the same local version still exists. A sync,
    /// delete, or second edit may reorder or replace `events` while the network request is in
    /// flight, so an array index captured before `await` is never safe to reuse.
    nonisolated static func replacingEvent(
        in events: [CalendarEvent],
        with syncedEvent: CalendarEvent,
        matching eventID: String,
        expectedLastModified: Date
    ) -> [CalendarEvent]? {
        guard let currentIndex = events.firstIndex(where: { $0.id == eventID }),
              events[currentIndex].lastModified == expectedLastModified else {
            return nil
        }

        var updatedEvents = events
        updatedEvents[currentIndex] = syncedEvent
        return updatedEvents
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

    /// Adds or removes a task from today's App and hardware display without changing its real
    /// due date or writing anything back to Google Tasks, Apple Reminders, or other providers.
    public func setTaskDisplayedToday(
        _ task: TaskItem,
        displayed: Bool,
        now: Date = Date()
    ) async {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }

        var updatedTask = tasks[index]
        updatedTask.todayDisplayDate = displayed ? now : nil
        tasks = taskManager.withTask(tasks, updatedTask: updatedTask)
        updateStatistics()
        requestBLESync(reason: displayed ? "addTaskToTodayDisplay" : "removeTaskFromTodayDisplay")

        await persistTasks(tasks, context: "AppState.setTaskDisplayedToday")
        await updatePetState()
        await refreshSharedPetDialogueIfNeeded()
        await refreshHomeCompanionPresentation()
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

        let externalSyncTask = taskExternalSyncQueue.enqueue(for: deletingTask.id) { [weak self] in
            guard let self else { return }
            await self.syncTaskToExternalService(
                deletingTask,
                action: .delete,
                expectedLastModified: deletionVersion
            )
        }
        Task { @MainActor in
            await persistTasks(tasks, context: "AppState.deleteTask.pending")
            await externalSyncTask.value
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
        let externalSyncTask = taskExternalSyncQueue.enqueue(for: retryTask.id) { [weak self] in
            guard let self else { return }
            await self.syncTaskToExternalService(
                retryTask,
                action: .updateCompletion,
                expectedLastModified: retryVersion
            )
        }
        await persistTasks(tasks, context: "AppState.retryTaskSync.pending")
        await externalSyncTask.value
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

        let baselineTask = tasks[index]
        var updatedTask = baselineTask
        updatedTask.title = title
        updatedTask.priority = priority
        updatedTask.dueDate = dueDate
        updatedTask.notes = notes
        updatedTask.lastModified = Date()

        do {
            let syncedTask = try await taskExternalSyncQueue.run(for: updatedTask.id) {
                try await ExternalSyncDispatcher.syncTaskContentEdit(updatedTask)
            }
            guard let reconciled = Self.replacingTask(
                in: tasks,
                with: syncedTask,
                matching: task.id,
                baseline: baselineTask
            ) else {
                return
            }
            tasks = reconciled
            updateStatistics()
            await persistTasks(tasks, context: "AppState.editTask")
            requestBLESync(reason: "editTask")
        } catch {
            reportSyncError(error, component: task.source.rawValue, context: "AppState.editTask")
            throw error
        }
    }

    /// Applies an awaited remote edit only if the task still exists at the same local version.
    /// Completion changes, deletion, sync, and a second edit may all happen while awaiting the
    /// provider, so the old response must not overwrite whichever state won locally.
    nonisolated static func replacingTask(
        in tasks: [TaskItem],
        with syncedTask: TaskItem,
        matching taskID: String,
        baseline: TaskItem
    ) -> [TaskItem]? {
        guard let currentIndex = tasks.firstIndex(where: { $0.id == taskID }) else {
            return nil
        }

        let current = tasks[currentIndex]
        let contentIsUnchanged = current.title == baseline.title
            && current.priority == baseline.priority
            && current.dueDate == baseline.dueDate
            && current.notes == baseline.notes
        guard !current.pendingDeletion,
              current.lastModified == baseline.lastModified || contentIsUnchanged else {
            return nil
        }

        var reconciledTask = syncedTask
        // `setTaskDisplayedToday` intentionally does not change `lastModified`, so this
        // local-only presentation field must always win over the awaited provider result.
        reconciledTask.todayDisplayDate = current.todayDisplayDate
        if current.lastModified != baseline.lastModified {
            // A completion toggle may win while the content request is in flight. Keep that newer
            // local state and version, but apply the requested content and remote metadata.
            reconciledTask.isCompleted = current.isCompleted
            reconciledTask.pendingDeletion = current.pendingDeletion
            reconciledTask.syncStatus = current.syncStatus
            reconciledTask.lastModified = current.lastModified
        }

        var updatedTasks = tasks
        updatedTasks[currentIndex] = reconciledTask
        return updatedTasks
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
        let externalSyncTask = taskExternalSyncQueue.enqueue(for: retryTask.id) { [weak self] in
            guard let self else { return }
            await self.syncTaskToExternalService(
                retryTask,
                action: .delete,
                expectedLastModified: retryVersion
            )
        }
        await persistTasks(tasks, context: "AppState.retryTaskDeletion.pending")
        await externalSyncTask.value
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
