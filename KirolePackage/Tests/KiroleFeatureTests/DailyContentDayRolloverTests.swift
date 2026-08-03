import Foundation
import Testing
@testable import KiroleFeature

@Suite("Daily content local-day rollover", .serialized)
@MainActor
struct DailyContentDayRolloverTests {
    @Test("Yesterday's package becomes unavailable at local midnight")
    func yesterdayPackageIsInvalidAfterMidnight() throws {
        let calendar = try makeCalendar()
        let beforeMidnight = try date(
            calendar: calendar,
            day: 3,
            hour: 23,
            minute: 59
        )
        let afterMidnight = try date(calendar: calendar, day: 4, hour: 0, minute: 0)
        let package = makeDailyPackage(date: beforeMidnight, calendar: calendar)

        #expect(DailyContentLocalDayPolicy.packageForDisplay(
            package,
            at: beforeMidnight,
            calendar: calendar
        ) == package)
        #expect(DailyContentLocalDayPolicy.packageForDisplay(
            package,
            at: afterMidnight,
            calendar: calendar
        ) == nil)
    }

    @Test("A new day resets both projections and promotes an immediate library recompute")
    func rolloverPromotesTaskLibraryAndBypassesScheduleWindow() async throws {
        let calendar = try makeCalendar()
        let beforeMidnight = try date(
            calendar: calendar,
            day: 3,
            hour: 23,
            minute: 59
        )
        let afterMidnight = try date(calendar: calendar, day: 4, hour: 0, minute: 0)
        let oldEvent = CalendarEvent(
            id: "event",
            title: "Yesterday",
            startTime: beforeMidnight.addingTimeInterval(-3_600),
            endTime: beforeMidnight.addingTimeInterval(-1_800)
        )
        var editedEvent = oldEvent
        editedEvent.title = "Edited yesterday"
        // 昨天到期的任务：跨日后不再属于今天集，重算后会成为增量 deletion。
        let task = TaskItem(id: "task", title: "Keep me", dueDate: beforeMidnight)
        let state = AppState.makeForTesting()
        state.taskLibraryNowProvider = { afterMidnight }
        state.dailyContentCalendarProvider = { calendar }
        state.dailyContentObservedDate = DailyContentDate(
            date: beforeMidnight,
            calendar: calendar
        )
        state.suppressesDailyContentChangeTracking = true
        state.events = [oldEvent]
        state.suppressesDailyContentChangeTracking = false
        state.dailyContentNowProvider = { beforeMidnight }
        state.events = [editedEvent]
        state.suppressesTaskLibraryChangeTracking = true
        state.tasks = [task]
        state.suppressesTaskLibraryChangeTracking = false
        state.taskLibraryHardwareTasksBaseline = [task]
        var refreshCount = 0
        var syncTriggers: [BLESyncTrigger] = []
        state.dailyContentDayRefreshExecutor = { refreshCount += 1 }
        state.bleSyncExecutor = { syncTriggers.append($0) }

        let changed = await state.observeDailyContentDay(
            at: afterMidnight,
            calendar: calendar,
            userDefaults: isolatedDefaults()
        )
        await state.pendingBLESyncTask?.value

        #expect(changed)
        #expect(refreshCount == 1)
        #expect(syncTriggers == [.automatic])
        #expect(state.dailyContentStabilityState.changedEventIDs.isEmpty)
        #expect(state.dailyContentHardwareEventsBaseline == nil)
        // v2.16.0（仅今天任务库）：跨日必须整库立即重算——冻结投影作废、readyScope 立即 .complete，
        // 与 0x24 同一轮 sync 送达（0x23 先行）。App 侧任务数据本身不动。
        #expect(state.taskLibraryStabilityState.hasUrgentCompleteUpdate)
        #expect(state.taskLibraryReadyUpdate()?.scope == .complete)
        #expect(state.taskLibraryHardwareTasksBaseline == nil)
        #expect(state.tasks.map(\.id) == [task.id])
        state.taskLibraryStabilityTask?.cancel()
    }

    @Test("A new-day calendar import does not reopen the three-minute window")
    func rolloverCalendarImportRemainsImmediatelySendable() async throws {
        let calendar = try makeCalendar()
        let yesterday = try date(calendar: calendar, day: 3, hour: 23, minute: 59)
        let today = try date(calendar: calendar, day: 4, hour: 0, minute: 0)
        let yesterdayEvent = CalendarEvent(
            id: "yesterday",
            title: "Yesterday",
            startTime: yesterday.addingTimeInterval(-3_600),
            endTime: yesterday.addingTimeInterval(-1_800)
        )
        let todayEvent = CalendarEvent(
            id: "today",
            title: "Today",
            startTime: today.addingTimeInterval(3_600),
            endTime: today.addingTimeInterval(5_400)
        )
        let state = AppState.makeForTesting()
        state.dailyContentObservedDate = DailyContentDate(date: yesterday, calendar: calendar)
        state.suppressesDailyContentChangeTracking = true
        state.events = [yesterdayEvent]
        state.suppressesDailyContentChangeTracking = false
        var triggers: [BLESyncTrigger] = []
        state.dailyContentDayRefreshExecutor = {
            state.replaceCalendarEventsFromSync(
                [todayEvent],
                tracksDailyContentChanges: false
            )
        }
        state.bleSyncExecutor = { triggers.append($0) }

        let changed = await state.observeDailyContentDay(
            at: today,
            calendar: calendar,
            userDefaults: isolatedDefaults()
        )
        await state.pendingBLESyncTask?.value
        let presentation = state.dailyContentPresentationSnapshot()

        #expect(changed)
        #expect(presentation.events.map(\.id) == [todayEvent.id])
        #expect(!presentation.usesFrozenBaseline)
        #expect(state.dailyContentStabilityState.changedEventIDs.isEmpty)
        #expect(triggers == [.automatic])
    }

    @Test("Relaunch detects a persisted prior day without wall-clock waiting")
    func relaunchDetectsPersistedPriorDay() async throws {
        let calendar = try makeCalendar()
        let yesterday = try date(calendar: calendar, day: 3, hour: 18, minute: 0)
        let today = try date(calendar: calendar, day: 4, hour: 8, minute: 0)
        let defaults = isolatedDefaults()
        LocalStorage.saveDailyContentObservedDate(
            DailyContentDate(date: yesterday, calendar: calendar),
            userDefaults: defaults
        )
        let state = AppState.makeForTesting()
        var refreshCount = 0
        state.dailyContentDayRefreshExecutor = { refreshCount += 1 }

        let changed = await state.observeDailyContentDay(
            at: today,
            calendar: calendar,
            userDefaults: defaults
        )
        await state.pendingBLESyncTask?.value

        #expect(changed)
        #expect(refreshCount == 1)
        #expect(LocalStorage.loadDailyContentObservedDate(userDefaults: defaults)
            == DailyContentDate(date: today, calendar: calendar))
    }

    @Test("The next rollover deadline is the next local midnight across DST")
    func nextBoundaryUsesCalendarDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 8,
            hour: 0,
            minute: 30
        )))

        let boundary = try #require(DailyContentDayBoundary.next(after: now, calendar: calendar))
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: boundary)

        #expect(components.year == 2026)
        #expect(components.month == 3)
        #expect(components.day == 9)
        #expect(components.hour == 0)
        #expect(boundary.timeIntervalSince(now) == 22.5 * 60 * 60)
    }

    @Test("A persisted prior-day delivery cannot match the new-day source")
    func sourceFingerprintIncludesLocalDate() throws {
        let calendar = try makeCalendar()
        let yesterday = try date(calendar: calendar, day: 3, hour: 23, minute: 59)
        let today = try date(calendar: calendar, day: 4, hour: 0, minute: 0)
        let profile = UserProfile.default

        let oldSource = DailyContentSource.packageSourceFingerprint(
            events: [],
            tasks: [],
            pet: Pet(),
            usageDays: 1,
            sceneID: "harbor",
            focusMinutes: 0,
            at: yesterday,
            calendar: calendar,
            userProfile: profile,
            customCompanions: []
        )
        let newSource = DailyContentSource.packageSourceFingerprint(
            events: [],
            tasks: [],
            pet: Pet(),
            usageDays: 1,
            sceneID: "harbor",
            focusMinutes: 0,
            at: today,
            calendar: calendar,
            userProfile: profile,
            customCompanions: []
        )

        #expect(oldSource != newSource)
    }

    @Test("A timezone change refreshes the same displayed date and forces time sync")
    func timezoneChangeRefreshesSameDate() async throws {
        let calendar = try makeCalendar()
        let now = try date(calendar: calendar, day: 4, hour: 10, minute: 0)
        let state = AppState.makeForTesting()
        state.dailyContentNowProvider = { now }
        state.dailyContentCalendarProvider = { calendar }
        var refreshCount = 0
        var triggers: [BLESyncTrigger] = []
        state.dailyContentDayRefreshExecutor = { refreshCount += 1 }
        state.bleSyncExecutor = { triggers.append($0) }

        await state.handleDailyContentTimeZoneChange(userDefaults: isolatedDefaults())
        await state.pendingBLESyncTask?.value

        #expect(refreshCount == 1)
        #expect(triggers == [.manual])
        #expect(state.dailyContentObservedDate == DailyContentDate(
            date: now,
            calendar: calendar
        ))
    }

    @Test("Restarting the monitor during a rollover retries the cancelled refresh")
    func monitorRestartRetriesCancelledRollover() async throws {
        let calendar = try makeCalendar()
        let yesterday = try date(calendar: calendar, day: 3, hour: 23, minute: 59)
        let today = try date(calendar: calendar, day: 4, hour: 0, minute: 0)
        let defaults = isolatedDefaults()
        let state = AppState.makeForTesting()
        state.dailyContentObservedDate = DailyContentDate(date: yesterday, calendar: calendar)
        state.dailyContentNowProvider = { today }
        state.dailyContentCalendarProvider = { calendar }
        var refreshCount = 0
        var releaseFirstRefresh: CheckedContinuation<Void, Never>?
        var triggers: [BLESyncTrigger] = []
        state.dailyContentDayRefreshExecutor = {
            refreshCount += 1
            if refreshCount == 1 {
                await withCheckedContinuation { continuation in
                    releaseFirstRefresh = continuation
                }
            }
        }
        state.bleSyncExecutor = { triggers.append($0) }

        let rolloverTask = Task { @MainActor in
            _ = await state.observeDailyContentDay(
                at: today,
                calendar: calendar,
                userDefaults: defaults
            )
        }
        state.dailyContentDayRolloverTask = rolloverTask
        while releaseFirstRefresh == nil {
            await Task.yield()
        }

        let restartTask = Task { @MainActor in
            await state.startDailyContentDayRolloverMonitoring(userDefaults: defaults)
        }
        await Task.yield()
        releaseFirstRefresh?.resume()
        await restartTask.value
        await rolloverTask.value
        await state.pendingBLESyncTask?.value
        state.dailyContentDayRolloverTask?.cancel()

        #expect(refreshCount == 2)
        #expect(triggers == [.automatic])
        #expect(state.dailyContentObservedDate == DailyContentDate(
            date: today,
            calendar: calendar
        ))
        #expect(LocalStorage.loadDailyContentObservedDate(userDefaults: defaults)
            == DailyContentDate(date: today, calendar: calendar))
    }
}

private func makeCalendar() throws -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
    return calendar
}

private func date(
    calendar: Calendar,
    day: Int,
    hour: Int,
    minute: Int
) throws -> Date {
    try #require(calendar.date(from: DateComponents(
        year: 2026,
        month: 8,
        day: day,
        hour: hour,
        minute: minute
    )))
}

private func isolatedDefaults() -> UserDefaults {
    let suiteName = "DailyContentDayRolloverTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private func makeDailyPackage(date: Date, calendar: Calendar) -> DailyContentPackage {
    DailyContentPackage(
        localDate: DailyContentDate(date: date, calendar: calendar),
        morningDialogue: "Morning",
        idleDialogue: "Idle",
        closingDialogue: "Closing",
        daySummary: "Summary",
        screensaverQuote: "Quote",
        screensaverAuthor: "Joy",
        settlementReview: "Review",
        settlementQuote: "Closing quote",
        events: []
    )
}
