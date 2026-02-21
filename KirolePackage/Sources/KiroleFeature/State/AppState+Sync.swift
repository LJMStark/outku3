import Foundation

extension AppState {
    public func loadGoogleCalendarEvents() async {
        await syncGoogleData()
    }

    public func loadGoogleTasks() async {
        await syncGoogleData()
    }

    public func syncGoogleData() async {
        guard AuthManager.shared.isGoogleConnected else {
            lastGoogleSyncDebug = "Skipped: Google not connected"
            return
        }

        syncGoogleIntegrationStatusFromAuth()

        let syncPlan = (
            calendar: isIntegrationConnected(.googleCalendar) && AuthManager.shared.hasCalendarAccess,
            tasks: isIntegrationConnected(.googleTasks) && AuthManager.shared.hasTasksAccess
        )

        guard syncPlan.calendar || syncPlan.tasks else {
            lastGoogleSyncDebug = "Skipped: integration disabled or scope missing (calendar=\(syncPlan.calendar), tasks=\(syncPlan.tasks))"
            return
        }

        let syncStart = Date()

        do {
            let googleEvents = events.filter { $0.source == .google }
            let googleTasks = tasks.filter { $0.source == .google }

            let (syncedEvents, syncedTasks, syncWarnings) = try await googleSyncEngine.performFullSync(
                currentEvents: googleEvents,
                currentTasks: googleTasks,
                includeCalendar: syncPlan.calendar,
                includeTasks: syncPlan.tasks
            )

            if syncPlan.calendar {
                let nonGoogleEvents = events.filter { $0.source != .google }
                events = nonGoogleEvents + syncedEvents
                try await localStorage.saveEvents(events)
            }

            if syncPlan.tasks {
                let nonGoogleTasks = tasks.filter { $0.source != .google }
                tasks = taskManager.mergedTasks(nonGoogleTasks: nonGoogleTasks, syncedTasks: syncedTasks)
                updateStatistics()
                try await localStorage.saveTasks(tasks)
            }

            let durationMs = Int(Date().timeIntervalSince(syncStart) * 1000)
            let syncedEventCount = syncPlan.calendar ? syncedEvents.count : 0
            let syncedTaskCount = syncPlan.tasks ? syncedTasks.count : 0
            applyGoogleSyncOutcome(
                eventsCount: syncedEventCount,
                tasksCount: syncedTaskCount,
                warnings: syncWarnings,
                durationMs: durationMs
            )

        } catch {
            let appError = AppError.sync(component: "Google", underlying: error.localizedDescription)
            ErrorReporter.log(appError, context: "AppState.syncGoogleData")
            lastError = UserFacingErrorMapper.message(for: appError)
            lastGoogleSyncDebug = "Error: \(error.localizedDescription)"
        }

        await updatePetState()
    }

    public var isAnyAppleIntegrationConnected: Bool {
        isIntegrationConnected(.appleCalendar) || isIntegrationConnected(.appleReminders)
    }

    public func loadAppleCalendarEvents() async {
        guard isIntegrationConnected(.appleCalendar) else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: Date())
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            let appleEvents = try await appleSyncEngine.fetchCalendarEvents(from: startOfDay, to: endOfDay)
            let otherEvents = events.filter { $0.source != .apple }
            events = otherEvents + appleEvents
            try await localStorage.saveEvents(events)
        } catch {
            let appError = AppError.sync(component: "Apple Calendar", underlying: error.localizedDescription)
            lastError = UserFacingErrorMapper.message(for: appError)
            ErrorReporter.log(appError, context: "AppState.loadAppleCalendarEvents")
        }
    }

    public func loadAppleReminders() async {
        guard isIntegrationConnected(.appleReminders) else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let appleTasks = tasks.filter { $0.source == .apple }
            let syncedTasks = try await appleSyncEngine.syncReminders(currentTasks: appleTasks)
            let otherTasks = tasks.filter { $0.source != .apple }
            tasks = otherTasks + syncedTasks
            try await localStorage.saveTasks(tasks)
            updateStatistics()
        } catch {
            let appError = AppError.sync(component: "Apple Reminders", underlying: error.localizedDescription)
            lastError = UserFacingErrorMapper.message(for: appError)
            ErrorReporter.log(appError, context: "AppState.loadAppleReminders")
        }
    }

    public func syncAppleData() async {
        let shouldSyncCalendar = isIntegrationConnected(.appleCalendar)
        let shouldSyncReminders = isIntegrationConnected(.appleReminders)

        if shouldSyncCalendar {
            await loadAppleCalendarEvents()
        }

        if shouldSyncReminders {
            await loadAppleReminders()
        }

        await updatePetState()
    }

    public func requestAppleCalendarAccess() async -> Bool {
        await eventKitService.requestCalendarAccess()
    }

    public func requestAppleRemindersAccess() async -> Bool {
        await eventKitService.requestRemindersAccess()
    }

    public func setupAppleChangeObserver() async {
        await appleSyncEngine.startObservingChanges { [weak self] in
            await self?.syncAppleData()
        }
    }

    func applyGoogleSyncOutcome(
        eventsCount: Int,
        tasksCount: Int,
        warnings: [String],
        durationMs: Int
    ) {
        if warnings.isEmpty {
            lastError = nil
            lastGoogleSyncDebug = "Success: events=\(eventsCount), tasks=\(tasksCount), duration=\(durationMs)ms"
            return
        }

        let warningText = warnings.joined(separator: " | ")
        let appError = AppError.sync(component: "Google", underlying: warningText)
        lastError = UserFacingErrorMapper.message(for: appError)
        lastGoogleSyncDebug = "Partial: events=\(eventsCount), tasks=\(tasksCount), warnings=\(warningText), duration=\(durationMs)ms"
        ErrorReporter.log(appError, context: "AppState.applyGoogleSyncOutcome")
    }
}
