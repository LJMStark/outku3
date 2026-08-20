import Foundation

enum ExternalSyncTarget: CaseIterable, Hashable, Sendable {
    case google
    case apple
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
    /// Structural changes are detected by `HardwareContentFingerprint`, so most callers pass
    /// no `force`. `force: true` is for changes deliberately outside the structural hash
    /// (e.g. focus-end settlement data). Coalescing ORs the force flags — a later plain
    /// request must not swallow a pending forced one, or the settlement refresh is lost.
    func requestBLESync(reason: String, debounce: Duration = .seconds(1.5), force: Bool = false) {
        pendingBLESyncTask?.cancel()
        pendingBLESyncForce = pendingBLESyncForce || force
        pendingBLESyncTask = Task { @MainActor in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            let effectiveForce = pendingBLESyncForce
            pendingBLESyncForce = false
            // This slot only owns the debounce delay. Once the sync starts, later requests are
            // merged by BLESyncCoordinator instead of cancelling an in-flight connection or
            // OfflineSync transaction through this stale task handle.
            pendingBLESyncTask = nil
            #if DEBUG
            print("[AppState.requestBLESync] firing performSync (reason=\(reason), force=\(effectiveForce))")
            #endif
            await BLESyncCoordinator.shared.performSync(force: effectiveForce)
        }
    }

    /// A live Complete/Skip response sends its final DayPack before 0x1B. Cancel the ordinary
    /// debounced request created by the same mutation so it cannot race and send the same DayPack.
    /// `pendingBLESyncForce` is intentionally NOT cleared: the 0x1B path does not commit
    /// settlement datasets, so a pending forced round must survive to the next request.
    func cancelPendingBLESyncForTaskActionPresentation() {
        pendingBLESyncTask?.cancel()
        pendingBLESyncTask = nil
    }
}
