import Foundation

enum ExternalSyncTarget: CaseIterable, Hashable, Sendable {
    case google
    case apple
    case notion
    case taskade
    case microsoft
    case todoist
    case tickTick
}

extension AppState {
    /// Re-reads `tasks` at write time so concurrent syncs don't clobber each other's results.
    func mergeRemoteTasks(from source: EventSource, with synced: [TaskItem]) {
        let currentTasks = tasks
        let regrafted = Self.regraftTodayDisplayDates(onto: synced, from: currentTasks)
        tasks = currentTasks.filter { $0.source != source } + regrafted
        updateStatistics()
    }

    /// Sync engines merge from a pre-await snapshot. Re-graft the one Kirole-only field from
    /// current memory so a Show/Remove Today tap made during the network wait always wins.
    nonisolated static func regraftTodayDisplayDates(
        onto synced: [TaskItem],
        from current: [TaskItem]
    ) -> [TaskItem] {
        let currentById = current.reduce(into: [String: TaskItem]()) { tasksById, task in
            guard tasksById[task.id] == nil else { return }
            tasksById[task.id] = task
        }

        return synced.map { task in
            guard let currentTask = currentById[task.id] else { return task }
            var regrafted = task
            regrafted.todayDisplayDate = currentTask.todayDisplayDate
            return regrafted
        }
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

        if isIntegrationConnected(.outlookCalendar) || isIntegrationConnected(.microsoftToDo) {
            targets.append(.microsoft)
        }

        if isIntegrationConnected(.todoist) {
            targets.append(.todoist)
        }

        if isIntegrationConnected(.tickTick) {
            targets.append(.tickTick)
        }

        return targets
    }

    public func syncConnectedExternalData() async {
        // 等启动本地加载完成再同步：否则会抢在集成连接状态恢复之前按 defaultIntegrations(Apple=true)
        // 同步，把用户刚断开/清掉的 Apple 数据又导入回来（B4 启动竞态）。
        await ensureInitialLoadComplete()
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
            case .microsoft:
                await syncMicrosoftData()
            case .todoist:
                await syncTodoistData()
            case .tickTick:
                await syncTickTickData()
            }
        }
    }

    public func syncGoogleData() async {
        guard let syncGeneration = beginExternalSync(.google) else { return }
        defer { finishExternalSync(.google, generation: syncGeneration) }

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
            guard canCommitExternalSync(.google, generation: syncGeneration) else { return }

            if syncPlan.calendar {
                // Offline / failure safety (intentional ordering — keep; do NOT move before the fetch):
                // - Full Google failure throws → jumps to catch, so non-Google events (Apple/EventKit,
                //   read locally and offline-safe) are preserved, never cleared.
                // - Partial calendar failure does NOT throw: performFullSync returns the *previous*
                //   Google events (syncedEvents == the .google set passed in), so recombining here keeps
                //   them stale rather than dropping the failed calendar's events.
                let nonGoogleEvents = events.filter { $0.source != .google }
                events = nonGoogleEvents + syncedEvents
                try await localStorage.saveEvents(events)
                guard canCommitExternalSync(.google, generation: syncGeneration) else { return }
            }

            if syncPlan.tasks {
                mergeRemoteTasks(from: .google, with: syncedTasks)
                try await localStorage.saveTasks(tasks)
                guard canCommitExternalSync(.google, generation: syncGeneration) else { return }
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
            guard canCommitExternalSync(.google, generation: syncGeneration) else { return }
            let underlying = error.localizedDescription
            ErrorReporter.log(
                AppError.sync(component: "Google", underlying: underlying),
                context: "AppState.syncGoogleData"
            )
            remoteSyncWarnings.removeValue(forKey: "Google")
            if Self.isOfflineErrorDescription(underlying) {
                // 离线不是错误态（Google offline-sync 指南）：中性提示，联网后自动重试；
                // 不点红点、不进红色 remoteSyncErrors。
                lastError = nil
                remoteSyncErrors.removeValue(forKey: "Google")
                remoteSyncWarnings["Google"] = "Offline — will sync when reconnected"
            } else {
                lastError = "Google sync failed — check your Google account connection"
                remoteSyncErrors["Google"] = lastError
            }
            lastGoogleSyncDebug = "Error: \(underlying)"
        }

        guard canCommitExternalSync(.google, generation: syncGeneration) else { return }
        await applyPostSyncHooks()
    }

    public var isAnyAppleIntegrationConnected: Bool {
        isIntegrationConnected(.appleCalendar) || isIntegrationConnected(.appleReminders)
    }

    public func syncAppleCalendarEvents() async {
        guard isIntegrationConnected(.appleCalendar) else { return }
        let syncGeneration = externalSyncGeneration(for: .apple)

        isLoading = true
        defer { isLoading = false }

        do {
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: Date())
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            let appleEvents = try await appleSyncEngine.fetchCalendarEvents(from: startOfDay, to: endOfDay)
            guard canCommitExternalSync(.apple, generation: syncGeneration) else { return }
            let otherEvents = events.filter { $0.source != .apple }
            events = otherEvents + appleEvents
            try await localStorage.saveEvents(events)
            guard canCommitExternalSync(.apple, generation: syncGeneration) else { return }
            remoteSyncErrors.removeValue(forKey: "Apple Calendar")
            markIntegrationSynced("Apple Calendar")
        } catch {
            guard canCommitExternalSync(.apple, generation: syncGeneration) else { return }
            let appError = AppError.sync(component: "Apple Calendar", underlying: error.localizedDescription)
            lastError = UserFacingErrorMapper.message(for: appError)
            remoteSyncErrors["Apple Calendar"] = lastError
            ErrorReporter.log(appError, context: "AppState.syncAppleCalendarEvents")
        }
    }

    public func syncAppleReminders() async {
        guard isIntegrationConnected(.appleReminders) else { return }
        let syncGeneration = externalSyncGeneration(for: .apple)

        isLoading = true
        defer { isLoading = false }

        do {
            let appleTasks = tasks.filter { $0.source == .apple }
            let syncedTasks = try await appleSyncEngine.syncReminders(currentTasks: appleTasks)
            guard canCommitExternalSync(.apple, generation: syncGeneration) else { return }
            mergeRemoteTasks(from: .apple, with: syncedTasks)
            try await localStorage.saveTasks(tasks)
            guard canCommitExternalSync(.apple, generation: syncGeneration) else { return }
            remoteSyncErrors.removeValue(forKey: "Apple Reminders")
            markIntegrationSynced("Apple Reminders")
        } catch {
            guard canCommitExternalSync(.apple, generation: syncGeneration) else { return }
            let appError = AppError.sync(component: "Apple Reminders", underlying: error.localizedDescription)
            lastError = UserFacingErrorMapper.message(for: appError)
            remoteSyncErrors["Apple Reminders"] = lastError
            ErrorReporter.log(appError, context: "AppState.syncAppleReminders")
        }
    }

    public func syncAppleData() async {
        // 纵深防御：syncAppleData 是 public，且 Apple change observer 回调会直接调它（绕过
        // syncConnectedExternalData）。自带等待，确保任何入口都不会在集成连接状态恢复前导入。
        await ensureInitialLoadComplete()
        guard let syncGeneration = beginExternalSync(.apple) else { return }
        defer { finishExternalSync(.apple, generation: syncGeneration) }

        let shouldSyncCalendar = isIntegrationConnected(.appleCalendar)
        let shouldSyncReminders = isIntegrationConnected(.appleReminders)

        if shouldSyncCalendar {
            await syncAppleCalendarEvents()
        }

        if shouldSyncReminders {
            await syncAppleReminders()
        }

        guard canCommitExternalSync(.apple, generation: syncGeneration) else { return }
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

    /// 离线类错误的字符串启发式。GoogleSyncEngineError 只携带 warning 字符串（不带原始
    /// Error 类型），联调期按文案特征区分「离线」与「真错误」已足够；若需精确分类，
    /// 应让引擎透传原始错误类型而不是在这里加关键词。
    nonisolated static func isOfflineErrorDescription(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("offline")
            || lowered.contains("internet connection")
            || lowered.contains("network connection was lost")
    }

    /// 记录集成最近一次成功应用数据的时间（卡片 "Synced X ago" 的数据源）并异步落盘。
    func markIntegrationSynced(_ providerKey: String, at date: Date = Date()) {
        integrationLastSyncedAt[providerKey] = date
        Task { @MainActor in
            do {
                // Read at task execution time so two providers completing together cannot let
                // an older captured dictionary overwrite a newer provider timestamp on disk.
                try await localStorage.saveIntegrationSyncTimes(integrationLastSyncedAt)
            } catch {
                reportPersistenceError(error, operation: "save", target: "integration_sync_times.json")
                ErrorReporter.log(error, context: "AppState.markIntegrationSynced")
            }
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
            remoteSyncErrors.removeValue(forKey: "Google")
            remoteSyncWarnings.removeValue(forKey: "Google")
            markIntegrationSynced("Google")
            lastGoogleSyncDebug = "Success: events=\(eventsCount), tasks=\(tasksCount), duration=\(durationMs)ms"
            return
        }

        // 部分失败：数据已应用（失败的那一步保留上轮数据），属降级不属阻塞——
        // 走黄色 remoteSyncWarnings，不进红色、不点亮齿轮红点（红色只留整轮失败）。
        let warningText = warnings.joined(separator: " | ")
        lastError = nil
        remoteSyncErrors.removeValue(forKey: "Google")
        remoteSyncWarnings["Google"] = "Synced with warnings — \(warningText)"
        markIntegrationSynced("Google")
        lastGoogleSyncDebug = "Partial: events=\(eventsCount), tasks=\(tasksCount), warnings=\(warningText), duration=\(durationMs)ms"
        ErrorReporter.log(
            AppError.sync(component: "Google", underlying: warningText),
            context: "AppState.applyGoogleSyncOutcome"
        )
    }

    // MARK: - Notion Sync

    public func syncNotionData() async {
        guard isIntegrationConnected(.notion) else { return }
        guard let syncGeneration = beginExternalSync(.notion) else { return }
        defer { finishExternalSync(.notion, generation: syncGeneration) }

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
            guard canCommitExternalSync(.notion, generation: syncGeneration) else { return }
            mergeRemoteTasks(from: .notion, with: syncedTasks)
            try await localStorage.saveTasks(tasks)
            guard canCommitExternalSync(.notion, generation: syncGeneration) else { return }
            remoteSyncErrors.removeValue(forKey: "Notion")
            markIntegrationSynced("Notion")
        } catch {
            guard canCommitExternalSync(.notion, generation: syncGeneration) else { return }
            let appError = AppError.sync(component: "Notion", underlying: error.localizedDescription)
            lastError = UserFacingErrorMapper.message(for: appError)
            remoteSyncErrors["Notion"] = lastError
            ErrorReporter.log(appError, context: "AppState.syncNotionData")
        }

        guard canCommitExternalSync(.notion, generation: syncGeneration) else { return }
        await applyPostSyncHooks()
    }

    // MARK: - Taskade Sync

    public func syncTaskadeData() async {
        guard isIntegrationConnected(.taskade) else { return }
        guard let syncGeneration = beginExternalSync(.taskade) else { return }
        defer { finishExternalSync(.taskade, generation: syncGeneration) }

        isLoading = true
        defer { isLoading = false }

        do {
            let accessToken = try await AuthManager.shared.getTaskadeAccessToken()
            guard canCommitExternalSync(.taskade, generation: syncGeneration) else { return }
            let taskadeTasks = tasks.filter { $0.source == .taskade }
            let syncedTasks = try await taskadeSyncEngine.syncTasks(
                currentTasks: taskadeTasks,
                accessToken: accessToken
            )
            guard canCommitExternalSync(.taskade, generation: syncGeneration) else { return }
            mergeRemoteTasks(from: .taskade, with: syncedTasks)
            try await localStorage.saveTasks(tasks)
            guard canCommitExternalSync(.taskade, generation: syncGeneration) else { return }
            remoteSyncErrors.removeValue(forKey: "Taskade")
            markIntegrationSynced("Taskade")
        } catch {
            guard canCommitExternalSync(.taskade, generation: syncGeneration) else { return }
            let appError = AppError.sync(component: "Taskade", underlying: error.localizedDescription)
            lastError = UserFacingErrorMapper.message(for: appError)
            remoteSyncErrors["Taskade"] = lastError
            ErrorReporter.log(appError, context: "AppState.syncTaskadeData")
        }

        guard canCommitExternalSync(.taskade, generation: syncGeneration) else { return }
        await applyPostSyncHooks()
    }

    // MARK: - Microsoft Sync

    public func syncMicrosoftData() async {
        guard let syncGeneration = beginExternalSync(.microsoft) else { return }
        defer { finishExternalSync(.microsoft, generation: syncGeneration) }

        let includeOutlook = isIntegrationConnected(.outlookCalendar)
            && AuthManager.shared.hasMicrosoftCalendarAccess
        let includeTodo = isIntegrationConnected(.microsoftToDo)
            && AuthManager.shared.hasMicrosoftTodoAccess
        guard includeOutlook || includeTodo else { return }

        do {
            let result = try await microsoftSyncEngine.performSync(
                currentEvents: events.filter { $0.source == .outlook },
                currentTasks: tasks.filter { $0.source == .microsoftToDo },
                includeOutlook: includeOutlook,
                includeTodo: includeTodo
            )
            guard canCommitExternalSync(.microsoft, generation: syncGeneration),
                  result.isCurrentForAppStateCommit else { return }
            applyMicrosoftSyncResult(
                result,
                includeOutlook: includeOutlook,
                includeTodo: includeTodo
            )
            try await persistMicrosoftSyncResult(
                result,
                includeOutlook: includeOutlook,
                includeTodo: includeTodo
            )
            guard canCommitExternalSync(.microsoft, generation: syncGeneration),
                  result.isCurrentForAppStateCommit else { return }
            lastError = nil
            remoteSyncErrors.removeValue(forKey: "Microsoft")
            if result.warnings.isEmpty {
                remoteSyncWarnings.removeValue(forKey: "Microsoft")
            } else {
                remoteSyncWarnings["Microsoft"] = result.warnings.joined(separator: " | ")
            }
            markIntegrationSynced("Microsoft")
        } catch MicrosoftSyncError.fullSyncFailed(let result) {
            guard canCommitExternalSync(.microsoft, generation: syncGeneration),
                  isMicrosoftResultCurrent(result) else { return }
            guard await handleMicrosoftFailedSyncResult(
                result,
                error: MicrosoftSyncError.fullSyncFailed(result),
                includeOutlook: includeOutlook,
                includeTodo: includeTodo,
                syncGeneration: syncGeneration
            ) else { return }
        } catch MicrosoftSyncError.stateIOFailed(let failure) {
            guard canCommitExternalSync(.microsoft, generation: syncGeneration),
                  isMicrosoftResultCurrent(failure.result) else { return }
            guard await handleMicrosoftFailedSyncResult(
                failure.result,
                error: MicrosoftSyncError.stateIOFailed(failure),
                includeOutlook: includeOutlook,
                includeTodo: includeTodo,
                syncGeneration: syncGeneration
            ) else { return }
        } catch MicrosoftSyncError.staleOperation {
            return
        } catch {
            guard canCommitExternalSync(.microsoft, generation: syncGeneration) else { return }
            recordProviderSyncFailure(error, provider: "Microsoft", context: "AppState.syncMicrosoftData")
        }

        guard canCommitExternalSync(.microsoft, generation: syncGeneration) else { return }
        await applyPostSyncHooks()
    }

    /// Applies and durably mirrors an account boundary before exposing the sync error. The state
    /// cursor may have failed to save, but account B's new/empty snapshots must still replace A.
    private func handleMicrosoftFailedSyncResult(
        _ result: MicrosoftSyncResult,
        error: MicrosoftSyncError,
        includeOutlook: Bool,
        includeTodo: Bool,
        syncGeneration: UInt64
    ) async -> Bool {
        guard canCommitExternalSync(.microsoft, generation: syncGeneration),
              isMicrosoftResultCurrent(result) else { return false }
        let appliedAccountBoundary = applyMicrosoftFailedSyncResult(
            result,
            includeOutlook: includeOutlook,
            includeTodo: includeTodo
        )
        if appliedAccountBoundary {
            do {
                try await persistMicrosoftSyncResult(
                    result,
                    includeOutlook: includeOutlook,
                    includeTodo: includeTodo
                )
            } catch {
                ErrorReporter.log(
                    .persistence(
                        operation: "save",
                        target: "Microsoft provider snapshots",
                        underlying: error.localizedDescription
                    ),
                    context: "AppState.syncMicrosoftData.accountBoundary"
                )
            }
        }
        guard canCommitExternalSync(.microsoft, generation: syncGeneration),
              isMicrosoftResultCurrent(result) else { return false }
        recordProviderSyncFailure(
            error,
            provider: "Microsoft",
            context: "AppState.syncMicrosoftData"
        )
        return true
    }

    private func isMicrosoftResultCurrent(_ result: MicrosoftSyncResult) -> Bool {
        result.isCurrentForAppStateCommit
    }

    /// Applies one provider-scoped Microsoft result without touching unrelated sources.
    /// An account change replaces both Microsoft snapshots so data from the previous identity
    /// cannot survive behind a disabled scope or a failed first pull.
    func applyMicrosoftSyncResult(
        _ result: MicrosoftSyncResult,
        includeOutlook: Bool,
        includeTodo: Bool
    ) {
        if includeOutlook || result.didChangeAccount {
            events = events.filter { $0.source != .outlook } + result.events
        }
        if includeTodo || result.didChangeAccount {
            mergeRemoteTasks(from: .microsoftToDo, with: result.tasks)
        }
    }

    /// A failed sync only carries a replacement instruction when the account changed. Same-account
    /// failures leave the current in-memory snapshot alone so concurrent local edits cannot be
    /// overwritten by the pre-request snapshot held by the sync engine.
    @discardableResult
    func applyMicrosoftFailedSyncResult(
        _ result: MicrosoftSyncResult,
        includeOutlook: Bool,
        includeTodo: Bool
    ) -> Bool {
        guard result.didChangeAccount else { return false }
        applyMicrosoftSyncResult(
            result,
            includeOutlook: includeOutlook,
            includeTodo: includeTodo
        )
        return true
    }

    /// Attempts both provider files even if the first write fails. Their files are individually
    /// atomic; this prevents one failed save from leaving the other account snapshot untouched.
    private func persistMicrosoftSyncResult(
        _ result: MicrosoftSyncResult,
        includeOutlook: Bool,
        includeTodo: Bool
    ) async throws {
        var firstError: (any Error)?
        if includeOutlook || result.didChangeAccount {
            do {
                try await localStorage.saveEvents(events)
            } catch {
                firstError = error
            }
        }
        if includeTodo || result.didChangeAccount {
            do {
                try await localStorage.saveTasks(tasks)
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }
        if let firstError {
            throw firstError
        }
    }

    // MARK: - Todoist Sync

    public func syncTodoistData() async {
        guard isIntegrationConnected(.todoist),
              let syncGeneration = beginExternalSync(.todoist) else { return }
        defer { finishExternalSync(.todoist, generation: syncGeneration) }

        do {
            let accessToken = try await AuthManager.shared.getTodoistAccessToken()
            guard canCommitExternalSync(.todoist, generation: syncGeneration) else { return }
            let selection = await providerProjectSelectionStore.selectedProjectIDs(for: .todoist)
            guard canCommitExternalSync(.todoist, generation: syncGeneration) else { return }
            let synced = try await todoistSyncEngine.taskItems(
                accessToken: accessToken,
                selectedProjectIDs: selection
            )
            guard canCommitExternalSync(.todoist, generation: syncGeneration) else { return }
            mergeRemoteTasks(from: .todoist, with: synced)
            try await localStorage.saveTasks(tasks)
            guard canCommitExternalSync(.todoist, generation: syncGeneration) else { return }
            remoteSyncErrors.removeValue(forKey: "Todoist")
            remoteSyncWarnings.removeValue(forKey: "Todoist")
            markIntegrationSynced("Todoist")
        } catch {
            guard canCommitExternalSync(.todoist, generation: syncGeneration) else { return }
            recordProviderSyncFailure(error, provider: "Todoist", context: "AppState.syncTodoistData")
        }

        guard canCommitExternalSync(.todoist, generation: syncGeneration) else { return }
        await applyPostSyncHooks()
    }

    // MARK: - TickTick / Dida Sync

    public func syncTickTickData(force: Bool = false) async {
        guard isIntegrationConnected(.tickTick),
              let syncGeneration = beginExternalSync(.tickTick) else { return }
        defer { finishExternalSync(.tickTick, generation: syncGeneration) }

        do {
            let credentials = try await AuthManager.shared.getTickTickCredentials()
            guard canCommitExternalSync(.tickTick, generation: syncGeneration) else { return }
            let selectionKey = ProviderProjectSelectionKey.tickTick(credentials.region)
            let selection = await providerProjectSelectionStore.selectedProjectIDs(for: selectionKey)
            guard canCommitExternalSync(.tickTick, generation: syncGeneration) else { return }
            let engine = tickTickEngine(for: credentials.region)
            let synced = try await engine.taskItems(
                credentials: credentials,
                selectedProjectIDs: selection,
                force: force
            )
            guard canCommitExternalSync(.tickTick, generation: syncGeneration) else { return }
            mergeRemoteTasks(from: .tickTick, with: synced)
            try await localStorage.saveTasks(tasks)
            guard canCommitExternalSync(.tickTick, generation: syncGeneration) else { return }
            remoteSyncErrors.removeValue(forKey: "TickTick")
            remoteSyncWarnings.removeValue(forKey: "TickTick")
            markIntegrationSynced("TickTick")
        } catch {
            guard canCommitExternalSync(.tickTick, generation: syncGeneration) else { return }
            recordProviderSyncFailure(error, provider: "TickTick", context: "AppState.syncTickTickData")
        }

        guard canCommitExternalSync(.tickTick, generation: syncGeneration) else { return }
        await applyPostSyncHooks()
    }

    public func availableTodoistProjects() async throws -> [ProviderProjectDescriptor] {
        let token = try await AuthManager.shared.getTodoistAccessToken()
        _ = try await todoistSyncEngine.synchronize(accessToken: token)
        return try await todoistSyncEngine.currentProjects().map {
            ProviderProjectDescriptor(id: $0.id, name: $0.name)
        }
    }

    public func availableTickTickProjects() async throws -> [ProviderProjectDescriptor] {
        let credentials = try await AuthManager.shared.getTickTickCredentials()
        return try await tickTickEngine(for: credentials.region)
            .availableProjects(accessToken: credentials.accessToken)
            .map { ProviderProjectDescriptor(id: $0.id, name: $0.name) }
    }

    public func selectedProjectIDs(for key: ProviderProjectSelectionKey) async -> Set<String> {
        await providerProjectSelectionStore.selectedProjectIDs(for: key)
    }

    public func saveProjectSelection(
        _ identifiers: Set<String>,
        for key: ProviderProjectSelectionKey
    ) async {
        await providerProjectSelectionStore.save(identifiers, for: key)
    }

    private func tickTickEngine(for region: TickTickRegion) -> TickTickSyncEngine {
        switch region {
        case .international: tickTickInternationalSyncEngine
        case .china: didaSyncEngine
        }
    }

    private func recordProviderSyncFailure(_ error: Error, provider: String, context: String) {
        let appError = AppError.sync(component: provider, underlying: error.localizedDescription)
        lastError = UserFacingErrorMapper.message(for: appError)
        remoteSyncErrors[provider] = lastError
        ErrorReporter.log(appError, context: context)
    }

    // MARK: - Post-Sync Hooks

    /// Every public sync* MUST end with this so all external sources trigger
    /// consistent home companion refresh after data merge.
    private func applyPostSyncHooks() async {
        await updatePetState()
        await refreshSharedPetDialogueIfNeeded()
        await refreshHomeCompanionPresentation()
        requestBLESync(reason: "external-sync", debounce: .seconds(3))
    }

    // MARK: - BLE Sync Request

    /// Single entry-point used by every write site (and external sync hook)
    /// to request a BLE push. Multiple calls within `debounce` are coalesced
    /// to one `BLESyncCoordinator.performSync()` invocation.
    ///
    /// `BLESyncPolicy.shouldSync` already returns `true` whenever the
    /// DayPack fingerprint changed, so we never need `force: true` here.
    func requestBLESync(reason: String, debounce: Duration = .seconds(1.5)) {
        pendingBLESyncTask?.cancel()
        pendingBLESyncTask = Task { @MainActor in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            #if DEBUG
            print("[AppState.requestBLESync] firing performSync (reason=\(reason))")
            #endif
            await BLESyncCoordinator.shared.performSync()
        }
    }

    /// A live Complete/Skip response sends its final DayPack before 0x1B. Cancel the ordinary
    /// debounced request created by the same mutation so it cannot race and send the same DayPack.
    func cancelPendingBLESyncForTaskActionPresentation() {
        pendingBLESyncTask?.cancel()
        pendingBLESyncTask = nil
    }
}
