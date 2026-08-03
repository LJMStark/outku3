import Foundation

extension AppState {
    /// Starts one calendar-aware wait for the next local midnight. iOS may suspend the process;
    /// foreground entry calls this again, compares the persisted date, and catches up immediately.
    func startDailyContentDayRolloverMonitoring(
        userDefaults: UserDefaults = .standard
    ) async {
        let previousTask = dailyContentDayRolloverTask
        previousTask?.cancel()
        await previousTask?.value
        dailyContentDayRolloverTask = nil
        let now = dailyContentNowProvider()
        let calendar = dailyContentCalendarProvider()
        _ = await observeDailyContentDay(
            at: now,
            calendar: calendar,
            userDefaults: userDefaults
        )
        scheduleDailyContentDayRollover(userDefaults: userDefaults)
    }

    /// Returns true only for a real local-date transition. Since v2.16.0 (2026-08-04, today-only
    /// task library) the day boundary invalidates BOTH stability projections: the schedule window
    /// resets and the task library promotes an immediate complete recompute — yesterday's due and
    /// manual-today tasks leave the device on the next sync round. Any active focus session stays
    /// deliberately untouched.
    @discardableResult
    func observeDailyContentDay(
        at now: Date,
        calendar: Calendar = .current,
        userDefaults: UserDefaults = .standard
    ) async -> Bool {
        let currentDate = DailyContentDate(date: now, calendar: calendar)
        let previousDate = dailyContentObservedDate
            ?? LocalStorage.loadDailyContentObservedDate(userDefaults: userDefaults)
        guard let previousDate else {
            dailyContentObservedDate = currentDate
            LocalStorage.saveDailyContentObservedDate(currentDate, userDefaults: userDefaults)
            return false
        }
        guard previousDate != currentDate else { return false }
        guard dailyContentDayRolloverInProgressDate != currentDate else { return false }
        dailyContentDayRolloverInProgressDate = currentDate
        dailyContentObservedDate = currentDate
        defer { dailyContentDayRolloverInProgressDate = nil }

        resetDailyContentScheduleWindow(userDefaults: userDefaults)
        // 两个投影同刻作废；任务 provider 不在午夜拉取——重算只用既有本地任务数据，
        // 变化的只是过滤基准日。promote 幂等，monitor 重启重试无害。
        invalidateTaskLibraryWindowForNewLocalDay()

        if let dailyContentDayRefreshExecutor {
            await dailyContentDayRefreshExecutor()
        } else {
            // Calendar integrations are date-windowed. Fetch the new local day before preparing
            // 0x24 so the first replacement is complete instead of briefly committing an empty day.
            await syncCurrentDayCalendarEvents()
        }
        guard !Task.isCancelled else {
            dailyContentObservedDate = previousDate
            return false
        }
        requestBLESync(reason: "dailyContentDayRollover", debounce: .zero)
        LocalStorage.saveDailyContentObservedDate(currentDate, userDefaults: userDefaults)
        return true
    }

    /// A timezone change can move events across the local-day boundary even when the displayed
    /// YYYY-MM-DD stays the same. Refresh that date explicitly and force one time-sync round.
    func handleDailyContentTimeZoneChange(
        userDefaults: UserDefaults = .standard
    ) async {
        let previousTask = dailyContentDayRolloverTask
        previousTask?.cancel()
        await previousTask?.value
        dailyContentDayRolloverTask = nil
        resetDailyContentScheduleWindow(userDefaults: userDefaults)
        // 时区变了但本地日相同时：今天集不变 → planner 空增量短路，零 wire 流量，自熄。
        invalidateTaskLibraryWindowForNewLocalDay()
        let now = dailyContentNowProvider()
        let currentDate = DailyContentDate(
            date: now,
            calendar: dailyContentCalendarProvider()
        )
        dailyContentObservedDate = currentDate
        if let dailyContentDayRefreshExecutor {
            await dailyContentDayRefreshExecutor()
        } else {
            await syncCurrentDayCalendarEvents()
        }
        guard !Task.isCancelled else { return }
        LocalStorage.saveDailyContentObservedDate(currentDate, userDefaults: userDefaults)
        requestBLESync(
            reason: "dailyContentTimeZoneChange",
            trigger: .manual,
            debounce: .zero
        )
        scheduleDailyContentDayRollover(userDefaults: userDefaults)
    }

    private func resetDailyContentScheduleWindow(userDefaults: UserDefaults) {
        dailyContentStabilityTask?.cancel()
        dailyContentStabilityTask = nil
        dailyContentStabilityState = DailyContentStabilityState()
        dailyContentHardwareEventsBaseline = nil
        LocalStorage.clearDailyContentStabilityCheckpoint(userDefaults: userDefaults)
    }

    private func scheduleDailyContentDayRollover(userDefaults: UserDefaults) {
        dailyContentDayRolloverTask?.cancel()
        dailyContentDayRolloverTask = nil
        let now = dailyContentNowProvider()
        let calendar = dailyContentCalendarProvider()
        guard let boundary = DailyContentDayBoundary.next(after: now, calendar: calendar) else {
            return
        }
        let delay = max(0, boundary.timeIntervalSince(now))
        dailyContentDayRolloverTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await dailyContentDayRolloverSleeper(.seconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            _ = await observeDailyContentDay(
                at: dailyContentNowProvider(),
                calendar: dailyContentCalendarProvider(),
                userDefaults: userDefaults
            )
            guard !Task.isCancelled else { return }
            scheduleDailyContentDayRollover(userDefaults: userDefaults)
        }
    }
}
