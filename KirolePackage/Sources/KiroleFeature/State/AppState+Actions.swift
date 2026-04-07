import Foundation

extension AppState {
    public func toggleTaskCompletion(_ task: TaskItem) {
        guard let existingTask = tasks.first(where: { $0.id == task.id }) else { return }

        var updatedTask = existingTask
        updatedTask.isCompleted.toggle()
        updatedTask.lastModified = Date()
        let isCompleted = updatedTask.isCompleted

        tasks = taskManager.withTask(tasks, updatedTask: updatedTask)
        updatePetForTaskToggle(isCompleted: isCompleted)
        updateStatistics()

        Task { @MainActor in
            if isCompleted {
                await checkAndTriggerEvolution()
            }

            await persistTaskAndPetState(
                tasks: self.tasks,
                pet: self.pet,
                streak: self.streak,
                context: "AppState.toggleTaskCompletion"
            )

            await syncTaskToExternalService(updatedTask)
            await updatePetState()

            if isCompleted {
                currentHaiku = await haikuService.generateCompletionHaiku(
                    tasksCompleted: statistics.todayCompleted,
                    totalTasks: statistics.todayTotal,
                    petMood: pet.mood,
                    streak: streak.currentStreak
                )
            }
        }
    }

    private func updatePetForTaskToggle(isCompleted: Bool) {
        var updatedPet = pet

        if isCompleted {
            SoundService.shared.playWithHaptic(.taskComplete, haptic: .success)
            updatedPet.adventuresCount += 1
            updatedPet.progress = min(1.0, updatedPet.progress + ProgressConstants.taskCompletionIncrement)
            updatedPet.points += ProgressConstants.pointsPerTask
            updatedPet.lastInteraction = Date()
            streak = petManager.updateStreak(streak)
        } else {
            SoundService.shared.playWithHaptic(.taskUncomplete, haptic: .light)
            updatedPet.adventuresCount = max(0, updatedPet.adventuresCount - 1)
            updatedPet.progress = max(0, updatedPet.progress - ProgressConstants.taskCompletionIncrement)
            updatedPet.points = max(0, updatedPet.points - ProgressConstants.pointsPerTask)
            updatedPet.lastInteraction = Date()
        }

        pet = updatedPet
    }

    private func syncTaskToExternalService(_ task: TaskItem) async {
        switch task.source {
        case .google:
            await googleSyncEngine.enqueueChange(task: task, action: .updateStatus)
            do {
                try await googleTasksAPI.syncTaskCompletion(task)
            } catch {
                reportSyncError(error, component: "Google Tasks", context: "AppState.toggleTaskCompletion")
            }
        case .apple:
            do {
                try await appleSyncEngine.pushReminderUpdate(task)
            } catch {
                reportSyncError(error, component: "Apple Reminders", context: "AppState.toggleTaskCompletion")
            }
        case .notion:
            do {
                guard let accessToken = AuthManager.shared.getNotionAccessToken() else {
                    throw NotionSyncError.notAuthenticated
                }
                try await notionSyncEngine.pushTaskUpdate(task, accessToken: accessToken)
            } catch {
                reportSyncError(error, component: "Notion", context: "AppState.toggleTaskCompletion")
            }
        case .taskade:
            do {
                let accessToken = try await AuthManager.shared.getTaskadeAccessToken()
                try await taskadeSyncEngine.pushTaskUpdate(task, accessToken: accessToken)
            } catch {
                reportSyncError(error, component: "Taskade", context: "AppState.toggleTaskCompletion")
            }
        default:
            break
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
            let syncedEvent = try await syncEventContentEditToExternalService(updatedEvent)
            events[index] = syncedEvent
            await persistEvents(events, context: "AppState.editEvent")
        } catch {
            reportSyncError(error, component: event.source.rawValue, context: "AppState.editEvent")
            throw error
        }
    }

    private func syncEventContentEditToExternalService(_ event: CalendarEvent) async throws -> CalendarEvent {
        switch event.source {
        case .apple:
            guard let identifier = event.appleEventId else {
                return event
            }
            try await eventKitService.updateEvent(
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

            var syncedEvent = try await googleCalendarAPI.patchEvent(
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
        case .todoist:
            throw ExternalEditingError.integrationReadOnly("Todoist")
        case .notion:
            throw ExternalEditingError.integrationReadOnly("Notion")
        case .taskade:
            throw ExternalEditingError.integrationReadOnly("Taskade")
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

    public func setPetForm(_ form: PetForm) {
        var updatedPet = pet
        updatedPet.currentForm = form
        pet = updatedPet

        Task { @MainActor in
            await persistPet(updatedPet, context: "AppState.setPetForm")
        }
    }

    public func setFocusEnforcementMode(_ mode: FocusEnforcementMode) {
        focusEnforcementMode = mode

        Task {
            await localStorage.saveFocusEnforcementMode(mode)
        }
    }

    public func addTask(_ task: TaskItem) {
        tasks = taskManager.addingTask(tasks, task: task)
        updateStatistics()

        Task { @MainActor in
            await persistTasks(tasks, context: "AppState.addTask")
        }
    }

    public func deleteTask(_ task: TaskItem) {
        tasks = taskManager.removingTask(tasks, taskID: task.id)
        updateStatistics()

        Task { @MainActor in
            await persistTasks(tasks, context: "AppState.deleteTask")
        }
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
            let syncedTask = try await syncTaskContentEditToExternalService(updatedTask)
            tasks = taskManager.withTask(tasks, updatedTask: syncedTask)
            updateStatistics()
            await persistTasks(tasks, context: "AppState.editTask")
        } catch {
            reportSyncError(error, component: task.source.rawValue, context: "AppState.editTask")
            throw error
        }
    }

    private func syncTaskContentEditToExternalService(_ task: TaskItem) async throws -> TaskItem {
        switch task.source {
        case .google:
            let remoteTask = try await googleTasksAPI.syncTaskUpdate(task)
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
                try await appleSyncEngine.pushReminderUpdate(task)
            }
            var syncedTask = task
            syncedTask.remoteUpdatedAt = Date()
            syncedTask.syncStatus = .synced
            return syncedTask
        case .notion:
            throw ExternalEditingError.integrationReadOnly("Notion")
        case .taskade:
            throw ExternalEditingError.integrationReadOnly("Taskade")
        default:
            throw ExternalEditingError.integrationReadOnly(task.source.rawValue)
        }
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

    func checkAndTriggerEvolution() async {
        guard let nextStage = await petManager.canEvolve(pet: pet, petStateService: petStateService) else {
            return
        }

        evolutionFromStage = pet.stage
        evolutionToStage = nextStage
        showEvolutionAnimation = true
    }

    public func completeEvolution() {
        guard let toStage = evolutionToStage else { return }

        pet = petManager.completeEvolution(from: pet, to: toStage)
        showEvolutionAnimation = false
        evolutionFromStage = nil
        evolutionToStage = nil

        Task { @MainActor in
            await persistPet(pet, context: "AppState.completeEvolution")
        }
    }

    public func dismissEvolution() {
        showEvolutionAnimation = false
        evolutionFromStage = nil
        evolutionToStage = nil
    }

    func persistTaskAndPetState(tasks: [TaskItem], pet: Pet, streak: Streak, context: String) async {
        do {
            try await localStorage.saveTasks(tasks)
            try await localStorage.savePet(pet)
            try await localStorage.saveStreak(streak)
        } catch {
            reportPersistenceError(error, operation: "save", target: "tasks/pet/streak")
            ErrorReporter.log(error, context: context)
        }
    }

    func persistPet(_ pet: Pet, context: String) async {
        do {
            try await localStorage.savePet(pet)
        } catch {
            reportPersistenceError(error, operation: "save", target: "pet.json")
            ErrorReporter.log(error, context: context)
        }
    }

    func persistTasks(_ tasks: [TaskItem], context: String) async {
        do {
            try await localStorage.saveTasks(tasks)
        } catch {
            reportPersistenceError(error, operation: "save", target: "tasks.json")
            ErrorReporter.log(error, context: context)
        }
    }

    func persistEvents(_ events: [CalendarEvent], context: String) async {
        do {
            try await localStorage.saveEvents(events)
        } catch {
            reportPersistenceError(error, operation: "save", target: "events.json")
            ErrorReporter.log(error, context: context)
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
