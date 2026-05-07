import Foundation

enum ExternalSyncTarget: Hashable, Sendable {
    case google
    case apple
    case notion
    case taskade
}

extension AppState {
    /// Re-reads `tasks` at write time so concurrent syncs don't clobber each other's results.
    func mergeRemoteTasks(from source: EventSource, with synced: [TaskItem]) {
        tasks = tasks.filter { $0.source != source } + synced
        updateStatistics()
    }

    func connectedExternalSyncTargets() -> [ExternalSyncTarget] {
        var targets: [ExternalSyncTarget] = []

        if hasAnyGoogleIntegrationConnected {
            targets.append(.google)
        }

        if isAnyAppleIntegrationConnected {
            targets.append(.apple)
        }

        if isIntegrationConnected(.notion) {
            targets.append(.notion)
        }

        if isIntegrationConnected(.taskade) {
            targets.append(.taskade)
        }

        return targets
    }

    public func syncConnectedExternalData() async {
        syncIntegrationStatusFromAuth()

        for target in connectedExternalSyncTargets() {
            switch target {
            case .google:
                await syncGoogleData()
            case .apple:
                await syncAppleData()
            case .notion:
                await syncNotionData()
            case .taskade:
                await syncTaskadeData()
            }
        }
    }

    public func syncGoogleData() async {
        guard !activeSyncs.contains(.google) else { return }
        activeSyncs.insert(.google)
        defer { activeSyncs.remove(.google) }

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
                mergeRemoteTasks(from: .google, with: syncedTasks)
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

        await applyPostSyncHooks()
    }

    public var isAnyAppleIntegrationConnected: Bool {
        isIntegrationConnected(.appleCalendar) || isIntegrationConnected(.appleReminders)
    }

    public func syncAppleCalendarEvents() async {
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
            ErrorReporter.log(appError, context: "AppState.syncAppleCalendarEvents")
        }
    }

    public func syncAppleReminders() async {
        guard isIntegrationConnected(.appleReminders) else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let appleTasks = tasks.filter { $0.source == .apple }
            let syncedTasks = try await appleSyncEngine.syncReminders(currentTasks: appleTasks)
            mergeRemoteTasks(from: .apple, with: syncedTasks)
            try await localStorage.saveTasks(tasks)
        } catch {
            let appError = AppError.sync(component: "Apple Reminders", underlying: error.localizedDescription)
            lastError = UserFacingErrorMapper.message(for: appError)
            ErrorReporter.log(appError, context: "AppState.syncAppleReminders")
        }
    }

    public func syncAppleData() async {
        guard !activeSyncs.contains(.apple) else { return }
        activeSyncs.insert(.apple)
        defer { activeSyncs.remove(.apple) }

        let shouldSyncCalendar = isIntegrationConnected(.appleCalendar)
        let shouldSyncReminders = isIntegrationConnected(.appleReminders)

        if shouldSyncCalendar {
            await syncAppleCalendarEvents()
        }

        if shouldSyncReminders {
            await syncAppleReminders()
        }

        await applyPostSyncHooks()
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

    // MARK: - Notion Sync

    public func syncNotionData() async {
        guard isIntegrationConnected(.notion) else { return }
        guard !activeSyncs.contains(.notion) else { return }
        activeSyncs.insert(.notion)
        defer { activeSyncs.remove(.notion) }

        isLoading = true
        defer { isLoading = false }

        do {
            guard let accessToken = AuthManager.shared.getNotionAccessToken() else {
                throw NotionSyncError.notAuthenticated
            }
            let notionTasks = tasks.filter { $0.source == .notion }
            let syncedTasks = try await notionSyncEngine.syncTasks(
                currentTasks: notionTasks,
                accessToken: accessToken
            )
            mergeRemoteTasks(from: .notion, with: syncedTasks)
            try await localStorage.saveTasks(tasks)
        } catch {
            let appError = AppError.sync(component: "Notion", underlying: error.localizedDescription)
            lastError = UserFacingErrorMapper.message(for: appError)
            ErrorReporter.log(appError, context: "AppState.syncNotionData")
        }

        await applyPostSyncHooks()
    }

    // MARK: - Taskade Sync

    public func syncTaskadeData() async {
        guard isIntegrationConnected(.taskade) else { return }
        guard !activeSyncs.contains(.taskade) else { return }
        activeSyncs.insert(.taskade)
        defer { activeSyncs.remove(.taskade) }

        isLoading = true
        defer { isLoading = false }

        do {
            let accessToken = try await AuthManager.shared.getTaskadeAccessToken()
            let taskadeTasks = tasks.filter { $0.source == .taskade }
            let syncedTasks = try await taskadeSyncEngine.syncTasks(
                currentTasks: taskadeTasks,
                accessToken: accessToken
            )
            mergeRemoteTasks(from: .taskade, with: syncedTasks)
            try await localStorage.saveTasks(tasks)
        } catch {
            let appError = AppError.sync(component: "Taskade", underlying: error.localizedDescription)
            lastError = UserFacingErrorMapper.message(for: appError)
            ErrorReporter.log(appError, context: "AppState.syncTaskadeData")
        }

        await applyPostSyncHooks()
    }

    // MARK: - Post-Sync Hooks

    /// Every public sync* MUST end with this so all external sources trigger
    /// consistent home companion refresh after data merge.
    private func applyPostSyncHooks() async {
        await updatePetState()
        await refreshSharedPetDialogueIfNeeded()
        await refreshHomeCompanionPresentation()
    }
}
