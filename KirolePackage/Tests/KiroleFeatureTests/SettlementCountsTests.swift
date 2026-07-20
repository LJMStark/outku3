import Foundation
import Testing
@testable import KiroleFeature

/// 客户 docx「页面四 当日结算」：日程无法打卡，但只要客户未取消即算完成一项任务。
/// 覆盖 DayPackGenerator.settlementCounts 的统计语义 —— 含「只计已结束日程」的时序口径，
/// 防止结算数据在每次 BLE 同步重算时把当天尚未发生的日程提前算成已完成。
@Suite("Settlement Counts")
struct SettlementCountsTests {

    /// 固定参考时刻，避免依赖墙钟造成的边界抖动。
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func task(done: Bool) -> TaskItem {
        TaskItem(title: "task", isCompleted: done)
    }

    /// 已结束日程：endTime 在 now 之前。
    private func pastEvent() -> CalendarEvent {
        CalendarEvent(title: "past",
                      startTime: now.addingTimeInterval(-7200),
                      endTime: now.addingTimeInterval(-3600))
    }

    /// 尚未结束日程：endTime 在 now 之后。
    private func futureEvent() -> CalendarEvent {
        CalendarEvent(title: "future",
                      startTime: now.addingTimeInterval(3600),
                      endTime: now.addingTimeInterval(7200))
    }

    @Test("已结束的未取消日程计入完成数与总数（1完成任务 + 2已结束日程 = 完成3/总4）")
    func occurredEventsCountAsCompleted() {
        let counts = DayPackGenerator.settlementCounts(
            tasks: [task(done: true), task(done: false)],
            events: [pastEvent(), pastEvent()],
            now: now
        )
        #expect(counts.completed == 3) // 1 个已完成任务 + 2 个已结束日程
        #expect(counts.total == 4)     // 2 任务 + 2 已结束日程
    }

    @Test("尚未发生的日程不计入（修复清晨误显示 Perfect day / 满分）")
    func futureEventsAreNotCounted() {
        let counts = DayPackGenerator.settlementCounts(
            tasks: [],
            events: [futureEvent(), futureEvent(), futureEvent()],
            now: now
        )
        #expect(counts.completed == 0)
        #expect(counts.total == 0)
    }

    @Test("混合：仅已结束日程计入，未来日程忽略")
    func mixedPastAndFutureEvents() {
        let counts = DayPackGenerator.settlementCounts(
            tasks: [task(done: true)],
            events: [pastEvent(), futureEvent()],
            now: now
        )
        #expect(counts.completed == 2) // 1 完成任务 + 1 已结束日程
        #expect(counts.total == 2)     // 1 任务 + 1 已结束日程
    }

    @Test("无日程时退化为仅任务统计")
    func noEvents() {
        let counts = DayPackGenerator.settlementCounts(
            tasks: [task(done: true), task(done: false), task(done: true)],
            events: [],
            now: now
        )
        #expect(counts.completed == 2)
        #expect(counts.total == 3)
    }

    @Test("仅已结束日程无任务：全部计为完成")
    func eventsOnly() {
        let counts = DayPackGenerator.settlementCounts(
            tasks: [],
            events: [pastEvent(), pastEvent(), pastEvent()],
            now: now
        )
        #expect(counts.completed == 3)
        #expect(counts.total == 3)
    }

    @Test("空日：完成与总数均为 0")
    func emptyDay() {
        let counts = DayPackGenerator.settlementCounts(tasks: [], events: [], now: now)
        #expect(counts.completed == 0)
        #expect(counts.total == 0)
    }

    @Test("边界：endTime 恰好等于 now 视为已结束（含等号），计入")
    func endTimeExactlyNowCounts() {
        let boundaryEvent = CalendarEvent(title: "boundary",
                                          startTime: now.addingTimeInterval(-3600),
                                          endTime: now)
        let counts = DayPackGenerator.settlementCounts(
            tasks: [], events: [boundaryEvent], now: now
        )
        #expect(counts.completed == 1) // endTime == now → 已结束 → 计入
        #expect(counts.total == 1)
    }

    // MARK: - firstUpLabel (box③ "First up")

    private func upcoming(_ title: String, minutes: Double, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(title: title,
                      startTime: now.addingTimeInterval(minutes * 60),
                      endTime: now.addingTimeInterval(minutes * 60 + 3600),
                      isAllDay: allDay)
    }

    /// 用与 firstUpLabel 相同的 formatter 算期望值 —— 时区无关，测的是格式逻辑而非硬编码时刻。
    private func timedLabel(_ event: CalendarEvent) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return "\(f.string(from: event.startTime)) \(event.title)"
    }

    @Test("firstUp: 下一个未来事件，格式 HH:mm Title，优先于任务")
    func firstUpPicksUpcomingEvent() {
        let next = upcoming("Standup", minutes: 90)
        let label = DayPackGenerator.firstUpLabel(
            events: [pastEvent(), next], fallbackTaskTitle: "Some task", now: now
        )
        #expect(label == timedLabel(next))
    }

    @Test("firstUp: 多个未来事件取最早的（与输入顺序无关）")
    func firstUpPicksEarliestUpcoming() {
        let later = upcoming("Later", minutes: 180)
        let earlier = upcoming("Earlier", minutes: 30)
        let label = DayPackGenerator.firstUpLabel(
            events: [later, earlier], fallbackTaskTitle: nil, now: now
        )
        #expect(label == timedLabel(earlier))
    }

    @Test("firstUp: 无未来事件时退化为置顶任务标题")
    func firstUpFallsBackToTask() {
        let label = DayPackGenerator.firstUpLabel(
            events: [pastEvent()], fallbackTaskTitle: "Plan BLE", now: now
        )
        #expect(label == "Plan BLE")
    }

    @Test("firstUp: 无事件无任务回退为空串")
    func firstUpEmptyWhenNothing() {
        let label = DayPackGenerator.firstUpLabel(events: [], fallbackTaskTitle: nil, now: now)
        #expect(label == "")
    }

    @Test("firstUp: 全天未来事件只显示标题（无时间前缀）")
    func firstUpAllDayEventTitleOnly() {
        let allDay = upcoming("Release Day", minutes: 120, allDay: true)
        let label = DayPackGenerator.firstUpLabel(
            events: [allDay], fallbackTaskTitle: "task", now: now
        )
        #expect(label == "Release Day")
    }

    // MARK: - scheduledEventMinutes + settlementQuoteBranch（页面四 金句三分支）

    private func timedEvent(minutes: Double, allDay: Bool = false) -> CalendarEvent {
        CalendarEvent(title: "e",
                      startTime: now,
                      endTime: now.addingTimeInterval(minutes * 60),
                      isAllDay: allDay)
    }

    @Test("scheduledEventMinutes: 非全天事件时长求和（同起点事件按合并语义取并集）")
    func scheduledMinutesSumsTimedEvents() {
        // 两事件同起点（0-60 与 0-90）→ 并集 90 分钟，不是 150（客户拍板重叠不相加）。
        let total = DayPackGenerator.scheduledEventMinutes(
            events: [timedEvent(minutes: 60), timedEvent(minutes: 90)]
        )
        #expect(total == 90)
    }

    @Test("scheduledEventMinutes: 全天事件排除（防止冲垮 4h 阈值）")
    func scheduledMinutesExcludesAllDay() {
        let total = DayPackGenerator.scheduledEventMinutes(
            events: [timedEvent(minutes: 24 * 60, allDay: true), timedEvent(minutes: 30)]
        )
        #expect(total == 30)
    }

    @Test("scheduledEventMinutes: 负跨度脏数据忽略")
    func scheduledMinutesIgnoresNegativeSpan() {
        let total = DayPackGenerator.scheduledEventMinutes(
            events: [timedEvent(minutes: -45), timedEvent(minutes: 20)]
        )
        #expect(total == 20)
    }

    private func spanEvent(startMinutes: Double, endMinutes: Double) -> CalendarEvent {
        CalendarEvent(title: "span",
                      startTime: now.addingTimeInterval(startMinutes * 60),
                      endTime: now.addingTimeInterval(endMinutes * 60))
    }

    @Test("scheduledEventMinutes: 重叠区间合并不重复计（客户拍板 2026-07-20）")
    func scheduledMinutesMergesOverlaps() {
        // 2-4 点 + 3-5 点 → 实占 2-5 点 = 180 分钟，不是 240
        let total = DayPackGenerator.scheduledEventMinutes(
            events: [spanEvent(startMinutes: 0, endMinutes: 120), spanEvent(startMinutes: 60, endMinutes: 180)]
        )
        #expect(total == 180)
    }

    @Test("scheduledEventMinutes: 完全包含的区间不额外计")
    func scheduledMinutesContainedInterval() {
        let total = DayPackGenerator.scheduledEventMinutes(
            events: [spanEvent(startMinutes: 0, endMinutes: 120), spanEvent(startMinutes: 30, endMinutes: 60)]
        )
        #expect(total == 120)
    }

    @Test("scheduledEventMinutes: 相接区间合并、分离区间相加")
    func scheduledMinutesAdjacentAndDisjoint() {
        // 0-60 与 60-90 相接 → 90；120-150 分离 → +30 = 120
        let total = DayPackGenerator.scheduledEventMinutes(
            events: [spanEvent(startMinutes: 0, endMinutes: 60),
                     spanEvent(startMinutes: 60, endMinutes: 90),
                     spanEvent(startMinutes: 120, endMinutes: 150)]
        )
        #expect(total == 120)
    }

    @Test("branch: 全部完成且无未结束日程 → celebration（与投入时长无关）")
    func branchCelebrationWhenAllDone() {
        #expect(DayPackGenerator.settlementQuoteBranch(completed: 3, total: 3, unfinishedEvents: 0, combinedMinutes: 0) == .celebration)
        #expect(DayPackGenerator.settlementQuoteBranch(completed: 5, total: 5, unfinishedEvents: 0, combinedMinutes: 999) == .celebration)
    }

    @Test("branch: 还有未结束日程不触发庆祝（客户拍板 2026-07-20）")
    func branchUnfinishedEventsBlockCelebration() {
        #expect(DayPackGenerator.settlementQuoteBranch(completed: 3, total: 3, unfinishedEvents: 1, combinedMinutes: 0) == .fullSchedule)
        #expect(DayPackGenerator.settlementQuoteBranch(completed: 3, total: 3, unfinishedEvents: 2, combinedMinutes: 300) == .overloadedDay)
    }

    @Test("branch: total=0 不算全完成，空日走 fullSchedule")
    func branchEmptyDayIsNotCelebration() {
        #expect(DayPackGenerator.settlementQuoteBranch(completed: 0, total: 0, unfinishedEvents: 0, combinedMinutes: 0) == .fullSchedule)
    }

    @Test("branch: 未完成且投入 241 分钟 → overloadedDay（阈值严格大于 240）")
    func branchOverloadedAboveThreshold() {
        #expect(DayPackGenerator.settlementQuoteBranch(completed: 1, total: 3, unfinishedEvents: 0, combinedMinutes: 241) == .overloadedDay)
    }

    @Test("branch: 未完成且投入恰好 240 分钟 → fullSchedule（客户确认默认口径）")
    func branchFullScheduleAtThreshold() {
        #expect(DayPackGenerator.settlementQuoteBranch(completed: 1, total: 3, unfinishedEvents: 0, combinedMinutes: 240) == .fullSchedule)
    }

    // MARK: - taskOverview (AI generates + self-judges; offline → verbatim fallback)

    @Test @MainActor func overviewNilWhenNoNotes() async {
        #expect(await DayPackGenerator.shared.taskOverview(for: nil) == nil)
        #expect(await DayPackGenerator.shared.taskOverview(for: "   ") == nil)
    }

    @Test @MainActor func overviewShowsShortNoteVerbatim() async {
        let note = "Quick sync with design"
        #expect(await DayPackGenerator.shared.taskOverview(for: note) == note)
    }

    @Test @MainActor func overviewTruncatesLongNoteWhenAIUnavailable() async {
        // AI unavailable (no API key in tests) → fall back to the user's verbatim note, truncated.
        let long = String(repeating: "buy milk; call bank; send invoice; ", count: 5)
        let result = await DayPackGenerator.shared.taskOverview(for: long)
        #expect(result != nil)
        #expect((result?.utf8.count ?? 999) <= DayPackGenerator.taskDescriptionByteBudget)
        #expect(long.hasPrefix(result ?? "x"))   // a prefix of the user's own words, not a rewrite
    }
}
