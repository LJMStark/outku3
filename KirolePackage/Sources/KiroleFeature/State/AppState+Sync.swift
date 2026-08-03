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
        let currentTasks = tasks
        let regrafted = Self.regraftTodayDisplayDates(onto: synced, from: currentTasks)
        tasks = currentTasks.filter { $0.source != source } + regrafted
        updateStatistics()
    }

    /// Sync engines merge from a pre-await snapshot. Re-graft Kirole-only state from current
    /// memory so provider responses cannot erase local display choices or skip idempotency.
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
            regrafted.hardwareSkipOperationKey = currentTask.hardwareSkipOperationKey
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

        return targets
    }

    /// Claims one provider sync. A duplicate request waits for the active operation and then
    /// reuses its result instead of returning early with stale data.
    func claimExternalSync(_ target: ExternalSyncTarget) async -> Bool {
        guard activeSyncs.contains(target) else {
            activeSyncs.insert(target)
            return true
        }
        await withCheckedContinuation { continuation in
            externalSyncWaiters[target, default: []].append(continuation)
        }
        return false
    }

    func finishExternalSync(_ target: ExternalSyncTarget) {
        activeSyncs.remove(target)
        let waiters = externalSyncWaiters.removeValue(forKey: target) ?? []
        waiters.forEach { $0.resume() }
    }

    public func syncConnectedExternalData(scheduleBLESync: Bool = true) async {
        // 等启动本地加载完成再同步：否则会抢在集成连接状态恢复之前按 defaultIntegrations(Apple=true)
        // 同步，把用户刚断开/清掉的 Apple 数据又导入回来（B4 启动竞态）。
        await ensureInitialLoadComplete()
        syncIntegrationStatusFromAuth()

        for target in connectedExternalSyncTargets() {
            switch target {
            case .google:
                await syncGoogleData(scheduleBLESync: false)
            case .apple:
                await syncAppleData(scheduleBLESync: false)
            case .notion:
                await syncNotionData(scheduleBLESync: false)
            case .taskade:
                await syncTaskadeData(scheduleBLESync: false)
            }
        }

        if scheduleBLESync {
            requestBLESync(reason: "external-sync-batch", debounce: .seconds(3))
        } else {
            cancelPendingBLESync()
        }
    }

    public func syncGoogleData(scheduleBLESync: Bool = true) async {
        await syncGoogleData(
            scheduleBLESync: scheduleBLESync,
            includesTasks: true,
            waitsForFreshTurn: false,
            tracksDailyContentChanges: true
        )
    }

    private func syncGoogleData(
        scheduleBLESync: Bool,
        includesTasks: Bool,
        waitsForFreshTurn: Bool,
        tracksDailyContentChanges: Bool
    ) async {
        var ownsSync = await claimExternalSync(.google)
        while waitsForFreshTurn, !ownsSync, !Task.isCancelled {
            ownsSync = await claimExternalSync(.google)
        }
        guard ownsSync else {
            if !scheduleBLESync { cancelPendingBLESync() }
            return
        }
        defer { finishExternalSync(.google) }

        guard AuthManager.shared.isGoogleConnected else {
            lastGoogleSyncDebug = "Skipped: Google not connected"
            return
        }

        syncGoogleIntegrationStatusFromAuth()

        let syncPlan = (
            calendar: isIntegrationConnected(.googleCalendar) && AuthManager.shared.hasCalendarAccess,
            tasks: includesTasks
                && isIntegrationConnected(.googleTasks)
                && AuthManager.shared.hasTasksAccess
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
                // Offline / failure safety (intentional ordering — keep; do NOT move before the fetch):
                // - Full Google failure throws → jumps to catch, so non-Google events (Apple/EventKit,
                //   read locally and offline-safe) are preserved, never cleared.
                // - Partial calendar failure does NOT throw: performFullSync returns the *previous*
                //   Google events (syncedEvents == the .google set passed in), so recombining here keeps
                //   them stale rather than dropping the failed calendar's events.
                let nonGoogleEvents = events.filter { $0.source != .google }
                replaceCalendarEventsFromSync(
                    nonGoogleEvents + syncedEvents,
                    tracksDailyContentChanges: tracksDailyContentChanges
                )
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

        await applyPostSyncHooks(scheduleBLESync: scheduleBLESync)
    }

    public var isAnyAppleIntegrationConnected: Bool {
        isIntegrationConnected(.appleCalendar) || isIntegrationConnected(.appleReminders)
    }

    public func syncAppleCalendarEvents(
        tracksDailyContentChanges: Bool = true
    ) async {
        guard isIntegrationConnected(.appleCalendar) else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: Date())
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            let appleEvents = try await appleSyncEngine.fetchCalendarEvents(from: startOfDay, to: endOfDay)
            let otherEvents = events.filter { $0.source != .apple }
            replaceCalendarEventsFromSync(
                otherEvents + appleEvents,
                tracksDailyContentChanges: tracksDailyContentChanges
            )
            try await localStorage.saveEvents(events)
            remoteSyncErrors.removeValue(forKey: "Apple Calendar")
            markIntegrationSynced("Apple Calendar")
        } catch {
            let appError = AppError.sync(component: "Apple Calendar", underlying: error.localizedDescription)
            lastError = UserFacingErrorMapper.message(for: appError)
            remoteSyncErrors["Apple Calendar"] = lastError
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
            remoteSyncErrors.removeValue(forKey: "Apple Reminders")
            markIntegrationSynced("Apple Reminders")
        } catch {
            let appError = AppError.sync(component: "Apple Reminders", underlying: error.localizedDescription)
            lastError = UserFacingErrorMapper.message(for: appError)
            remoteSyncErrors["Apple Reminders"] = lastError
            ErrorReporter.log(appError, context: "AppState.syncAppleReminders")
        }
    }

    public func syncAppleData(scheduleBLESync: Bool = true) async {
        await syncAppleData(
            scheduleBLESync: scheduleBLESync,
            includesReminders: true,
            waitsForFreshTurn: false,
            tracksDailyContentChanges: true
        )
    }

    private func syncAppleData(
        scheduleBLESync: Bool,
        includesReminders: Bool,
        waitsForFreshTurn: Bool,
        tracksDailyContentChanges: Bool
    ) async {
        // 纵深防御：syncAppleData 是 public，且 Apple change observer 回调会直接调它（绕过
        // syncConnectedExternalData）。自带等待，确保任何入口都不会在集成连接状态恢复前导入。
        await ensureInitialLoadComplete()
        var ownsSync = await claimExternalSync(.apple)
        while waitsForFreshTurn, !ownsSync, !Task.isCancelled {
            ownsSync = await claimExternalSync(.apple)
        }
        guard ownsSync else {
            if !scheduleBLESync { cancelPendingBLESync() }
            return
        }
        defer { finishExternalSync(.apple) }

        let shouldSyncCalendar = isIntegrationConnected(.appleCalendar)
        let shouldSyncReminders = includesReminders && isIntegrationConnected(.appleReminders)

        if shouldSyncCalendar {
            await syncAppleCalendarEvents(
                tracksDailyContentChanges: tracksDailyContentChanges
            )
        }

        if shouldSyncReminders {
            await syncAppleReminders()
        }

        await applyPostSyncHooks(scheduleBLESync: scheduleBLESync)
    }

    /// Refreshes only date-windowed calendar sources for a new local day. Task providers are
    /// intentionally excluded so midnight itself cannot reorder or replace the independent 0x23
    /// library. If a provider sync is already running, wait for it and then take one fresh turn;
    /// a request that began before midnight is not proof that the new date was fetched.
    func syncCurrentDayCalendarEvents() async {
        await ensureInitialLoadComplete()
        syncIntegrationStatusFromAuth()

        if isIntegrationConnected(.googleCalendar), AuthManager.shared.hasCalendarAccess {
            await syncGoogleData(
                scheduleBLESync: false,
                includesTasks: false,
                waitsForFreshTurn: true,
                tracksDailyContentChanges: false
            )
        }
        if isIntegrationConnected(.appleCalendar) {
            await syncAppleData(
                scheduleBLESync: false,
                includesReminders: false,
                waitsForFreshTurn: true,
                tracksDailyContentChanges: false
            )
        }
    }

    /// Applies only the synchronous assignment under change-tracking suppression. Network awaits
    /// stay outside this scope, so a real user edit made while a provider request is in flight is
    /// still recorded and keeps its ordinary three-minute window.
    func replaceCalendarEventsFromSync(
        _ syncedEvents: [CalendarEvent],
        tracksDailyContentChanges: Bool
    ) {
        let previousSuppression = suppressesDailyContentChangeTracking
        suppressesDailyContentChangeTracking = previousSuppression || !tracksDailyContentChanges
        events = syncedEvents
        suppressesDailyContentChangeTracking = previousSuppression
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

    public func syncNotionData(scheduleBLESync: Bool = true) async {
        guard isIntegrationConnected(.notion) else { return }
        guard await claimExternalSync(.notion) else {
            if !scheduleBLESync { cancelPendingBLESync() }
            return
        }
        defer { finishExternalSync(.notion) }

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
            remoteSyncErrors.removeValue(forKey: "Notion")
            markIntegrationSynced("Notion")
        } catch {
            let appError = AppError.sync(component: "Notion", underlying: error.localizedDescription)
            lastError = UserFacingErrorMapper.message(for: appError)
            remoteSyncErrors["Notion"] = lastError
            ErrorReporter.log(appError, context: "AppState.syncNotionData")
        }

        await applyPostSyncHooks(scheduleBLESync: scheduleBLESync)
    }

    // MARK: - Taskade Sync

    public func syncTaskadeData(scheduleBLESync: Bool = true) async {
        guard isIntegrationConnected(.taskade) else { return }
        guard await claimExternalSync(.taskade) else {
            if !scheduleBLESync { cancelPendingBLESync() }
            return
        }
        defer { finishExternalSync(.taskade) }

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
            remoteSyncErrors.removeValue(forKey: "Taskade")
            markIntegrationSynced("Taskade")
        } catch {
            let appError = AppError.sync(component: "Taskade", underlying: error.localizedDescription)
            lastError = UserFacingErrorMapper.message(for: appError)
            remoteSyncErrors["Taskade"] = lastError
            ErrorReporter.log(appError, context: "AppState.syncTaskadeData")
        }

        await applyPostSyncHooks(scheduleBLESync: scheduleBLESync)
    }

    // MARK: - Post-Sync Hooks

    /// Every public sync* MUST end with this so all external sources trigger
    /// consistent home companion refresh after data merge.
    private func applyPostSyncHooks(scheduleBLESync: Bool) async {
        await updatePetState()
        await refreshSharedPetDialogueIfNeeded()
        await refreshHomeCompanionPresentation()
        if scheduleBLESync {
            requestBLESync(reason: "external-sync", debounce: .seconds(3))
        }
    }

    // MARK: - Task Library Stability Window

    func promoteTaskLibraryImmediateRemoval(taskID: String) {
        taskLibraryStabilityState.promoteImmediateRemoval(taskID: taskID)
        taskLibraryHardwareTasksBaseline?.removeAll { $0.hardwareIdentifier == taskID }
        persistTaskLibraryStabilityCheckpoint()
        scheduleTaskLibraryStabilityDeadline()
        requestBLESync(reason: "taskLibraryImmediateRemoval", debounce: .zero)
    }

    /// Task rows for hardware presentation. Ordinary edits remain frozen until their stability
    /// deadline; urgent completion/removal is reflected immediately without exposing other drafts.
    func tasksForHardwarePresentation() -> [TaskItem] {
        taskLibraryPresentationSnapshot().tasks
    }

    func petDialogueForHardwarePresentation() -> String {
        taskLibraryPresentationSnapshot().petDialogue
    }

    func taskLibraryPresentationSnapshot() -> (
        tasks: [TaskItem],
        petDialogue: String,
        readyUpdate: (scope: TaskLibraryUpdateScope, generation: UInt64)?,
        usesFrozenBaseline: Bool
    ) {
        let scope = taskLibraryStabilityState.readyScope(at: taskLibraryNowProvider())
        let readyUpdate = scope.map { ($0, taskLibraryStabilityState.generation) }
        let usesFrozenBaseline = taskLibraryHardwareTasksBaseline != nil && scope != .complete
        return (
            usesFrozenBaseline ? taskLibraryHardwareTasksBaseline ?? tasks : tasks,
            usesFrozenBaseline ? taskLibraryHardwarePetDialogueBaseline : currentPetDialogue,
            readyUpdate,
            usesFrozenBaseline
        )
    }

    func taskLibraryReadyUpdate() -> (scope: TaskLibraryUpdateScope, generation: UInt64)? {
        guard let scope = taskLibraryStabilityState.readyScope(at: taskLibraryNowProvider()) else {
            return nil
        }
        return (scope, taskLibraryStabilityState.generation)
    }

    func currentPreparedTaskLibraryPhaseTexts(
        for sourceTasks: [TaskItem]? = nil
    ) -> [String: TaskLibraryPhaseTexts] {
        var result: [String: TaskLibraryPhaseTexts] = [:]
        for task in sourceTasks ?? tasks where !task.isCompleted && !task.pendingDeletion {
            let taskID = task.hardwareIdentifier
            let fingerprint = TaskLibraryPhaseSourceFingerprint.make(
                task: task,
                userProfile: userProfile,
                customCompanions: customCompanions
            )
            if let prepared = preparedTaskLibraryPhaseTexts[taskID],
               prepared.fingerprint == fingerprint {
                result[taskID] = prepared.texts
            }
        }
        return result
    }

    func markTaskLibraryUpdateCommitted(
        scope: TaskLibraryUpdateScope,
        generation: UInt64
    ) {
        let clearsHardwareBaseline = scope == .complete
            && taskLibraryStabilityState.generation == generation
        taskLibraryStabilityState.markCommitted(
            scope: scope,
            capturedGeneration: generation
        )
        if clearsHardwareBaseline {
            taskLibraryHardwareTasksBaseline = nil
            taskLibraryHardwarePetDialogueBaseline = ""
        }
        persistTaskLibraryStabilityCheckpoint()
        scheduleTaskLibraryStabilityDeadline()
    }

    func scheduleTaskLibraryStabilityDeadline() {
        taskLibraryStabilityTask?.cancel()
        taskLibraryStabilityTask = nil
        guard let deadline = taskLibraryStabilityState.deadline,
              !taskLibraryStabilityState.stableTaskIDs.isEmpty else {
            return
        }
        let generation = taskLibraryStabilityState.generation
        let remaining = max(0, deadline.timeIntervalSince(taskLibraryNowProvider()))
        taskLibraryStabilityTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await bleSyncSleeper(.seconds(remaining))
            } catch {
                return
            }
            guard !Task.isCancelled,
                  taskLibraryStabilityState.generation == generation,
                  taskLibraryStabilityState.readyScope(at: taskLibraryNowProvider()) != nil else {
                return
            }
            requestBLESync(reason: "taskLibraryStabilityDeadline", debounce: .zero)
        }
    }

    // MARK: - Daily Content Stability Window

    func dailyContentPresentationSnapshot() -> (
        events: [CalendarEvent],
        readyGeneration: UInt64?,
        usesFrozenBaseline: Bool
    ) {
        let readyGeneration = dailyContentStabilityState.readyGeneration(
            at: dailyContentNowProvider()
        )
        let usesFrozenBaseline = dailyContentHardwareEventsBaseline != nil
            && readyGeneration == nil
        return (
            usesFrozenBaseline ? dailyContentHardwareEventsBaseline ?? events : events,
            readyGeneration,
            usesFrozenBaseline
        )
    }

    func markDailyContentCommitted(capturedGeneration: UInt64?) {
        guard let capturedGeneration else { return }
        dailyContentStabilityState.markCommitted(capturedGeneration: capturedGeneration)
        if dailyContentStabilityState.changedEventIDs.isEmpty {
            dailyContentHardwareEventsBaseline = nil
        }
        persistDailyContentStabilityCheckpoint()
        scheduleDailyContentStabilityDeadline()
    }

    func scheduleDailyContentStabilityDeadline() {
        dailyContentStabilityTask?.cancel()
        dailyContentStabilityTask = nil
        guard let deadline = dailyContentStabilityState.deadline,
              !dailyContentStabilityState.changedEventIDs.isEmpty else {
            return
        }
        let generation = dailyContentStabilityState.generation
        let remaining = max(0, deadline.timeIntervalSince(dailyContentNowProvider()))
        dailyContentStabilityTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await bleSyncSleeper(.seconds(remaining))
            } catch {
                return
            }
            guard !Task.isCancelled,
                  dailyContentStabilityState.generation == generation,
                  dailyContentStabilityState.readyGeneration(
                    at: dailyContentNowProvider()
                  ) != nil else {
                return
            }
            requestBLESync(reason: "dailyContentStabilityDeadline", debounce: .zero)
        }
    }

    // MARK: - BLE Sync Request

    /// Single entry-point used by every write site (and external sync hook)
    /// to request a BLE push. Multiple calls within `debounce` are coalesced
    /// to one `BLESyncCoordinator.performSync()` invocation while preserving
    /// the highest-priority trigger.
    ///
    /// `BLESyncPolicy.shouldSync` already returns `true` whenever the
    /// DayPack fingerprint changed, so we never need `force: true` here.
    func requestBLESync(
        reason: String,
        trigger: BLESyncTrigger = .automatic,
        debounce: Duration = .seconds(1.5)
    ) {
        let mergedTrigger = pendingBLESyncTrigger?.merged(with: trigger) ?? trigger
        pendingBLESyncTask?.cancel()
        pendingBLESyncTrigger = mergedTrigger
        pendingBLESyncRequestGeneration &+= 1
        let requestGeneration = pendingBLESyncRequestGeneration
        pendingBLESyncTask = Task { @MainActor in
            try? await bleSyncSleeper(debounce)
            guard !Task.isCancelled else { return }
            #if DEBUG
            print(
                "[AppState.requestBLESync] firing performSync "
                    + "(reason=\(reason), trigger=\(mergedTrigger))"
            )
            #endif
            if let bleSyncExecutor {
                await bleSyncExecutor(mergedTrigger)
            } else {
                await BLESyncCoordinator.shared.performSync(trigger: mergedTrigger)
            }
            guard pendingBLESyncRequestGeneration == requestGeneration else { return }
            pendingBLESyncTask = nil
            pendingBLESyncTrigger = nil
        }
    }

    /// A caller that is about to perform one explicit final sync can consume the debounced
    /// automatic request created by its preceding state updates, avoiding two DayPacks for one
    /// user action.
    func cancelPendingBLESync() {
        pendingBLESyncTask?.cancel()
        pendingBLESyncTask = nil
        pendingBLESyncTrigger = nil
        pendingBLESyncRequestGeneration &+= 1
    }

    /// A live Complete/Skip response sends its final DayPack before 0x1B. Cancel the ordinary
    /// debounced request created by the same mutation so it cannot race and send the same DayPack.
    /// Identity/manual triggers are preserved and resumed after that transaction — the final
    /// DayPack path does not send PetStatus(0x01).
    func cancelPendingBLESyncForTaskActionPresentation() {
        if let trigger = pendingBLESyncTrigger, trigger.survivesTaskActionPresentation {
            deferredBLESyncTriggerAfterTaskAction =
                deferredBLESyncTriggerAfterTaskAction?.merged(with: trigger) ?? trigger
        }
        cancelPendingBLESync()
    }

    /// Re-queues identity/manual presentation updates that were parked during Complete/Skip.
    func resumeDeferredBLESyncAfterTaskActionPresentation() {
        if let trigger = deferredBLESyncTriggerAfterTaskAction {
            deferredBLESyncTriggerAfterTaskAction = nil
            requestBLESync(
                reason: "deferredAfterTaskAction",
                trigger: trigger,
                debounce: taskLibraryReadyUpdate() == nil ? .seconds(1.5) : .zero
            )
            return
        }
        if taskLibraryReadyUpdate() != nil {
            requestBLESync(reason: "taskLibraryAfterTaskAction", debounce: .zero)
        }
    }
}
