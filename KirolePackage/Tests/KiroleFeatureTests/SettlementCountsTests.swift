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
}
