import Foundation
import Testing
@testable import KiroleFeature

// 联审 2026-07-16 F10 相邻缺陷：统计缓存不换日。口径本身（整段按 endTime 归属）保持不变，
// 这里钉住两件事：① todayFocusTimeIncludingActive 按 now 判日、纯读；② 换日后
// refreshStatisticsIfDayChanged 重算缓存、同日 no-op。
@Suite("Focus Statistics Midnight Rollover")
struct FocusStatisticsMidnightTests {
    private static let calendar = Calendar.current

    /// 2026-01-01 的固定时刻（本地时区），避免真实 Date() 参与判日。
    private static func jan1(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: hour, minute: minute))!
    }

    private static func jan2(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: hour, minute: minute))!
    }

    @MainActor
    private func makeServiceWithSettledSession(
        start: Date,
        end: Date
    ) async -> FocusSessionService {
        let guardService = MockStatisticsFocusGuardService()
        let service = FocusSessionService.makeForTesting(focusGuardService: guardService, persistenceEnabled: false)
        await service.startSession(taskId: "midnight-\(UUID().uuidString)", taskTitle: "Midnight Task",
                                   mode: .standard, startTime: start)
        service.endSession(reason: .completed, endTime: end)
        return service
    }

    @Test("Settled session counts toward Today only on its endTime day")
    @MainActor
    func settledSessionFollowsEndTimeDay() async {
        let service = await makeServiceWithSettledSession(start: Self.jan1(10), end: Self.jan1(10, 30))

        let sameDay = service.todayFocusTimeIncludingActive(now: Self.jan1(23))
        let nextDay = service.todayFocusTimeIncludingActive(now: Self.jan2(0, 10))

        #expect(sameDay > 0)
        #expect(nextDay == 0)
    }

    @Test("Active session spanning midnight keeps its whole countable time in Today")
    @MainActor
    func activeSessionKeepsWholeCountableTime() async {
        let guardService = MockStatisticsFocusGuardService()
        let service = FocusSessionService.makeForTesting(focusGuardService: guardService, persistenceEnabled: false)
        await service.startSession(taskId: "cross-\(UUID().uuidString)", taskTitle: "Cross Midnight",
                                   mode: .standard, startTime: Self.jan1(23, 40))

        // 口径：整段按（假设的）endTime 归属——现在结束即整体归今天，不做午夜切分。
        let today = service.todayFocusTimeIncludingActive(now: Self.jan2(0, 20))
        #expect(today >= 39 * 60, "40 分钟跨午夜会话应整段计入，而不是只算午夜后的 20 分钟")

        service.endSession(reason: .completed, endTime: Self.jan2(0, 20))
    }

    @Test("Day rollover recomputes the cached statistics; same day is a no-op")
    @MainActor
    func dayRolloverRecomputesCachedStatistics() async {
        let service = await makeServiceWithSettledSession(start: Self.jan1(10), end: Self.jan1(10, 30))

        service.updateStatistics(now: Self.jan1(12))
        #expect(service.statistics.todayFocusTime > 0)

        // 同日刷新：缓存不变。
        service.refreshStatisticsIfDayChanged(now: Self.jan1(23, 59))
        #expect(service.statistics.todayFocusTime > 0)

        // 换日刷新：昨天的会话不再计入 today。
        service.refreshStatisticsIfDayChanged(now: Self.jan2(0, 10))
        #expect(service.statistics.todayFocusTime == 0)
    }
}

// MARK: - Minimal guard-service stub

@MainActor
private final class MockStatisticsFocusGuardService: FocusGuardService {
    var authorizationStatus: FocusAuthorizationStatus = .approved
    var isDeepFocusFeatureEnabled = true
    var isDeepFocusCapable = true
    var canShowDeepFocusEntry: Bool { true }
    var selectedApplicationCount = 0
    var isPickerPresented = false

    func refreshAuthorizationStatus() async {}
    func requestAuthorization() async -> FocusAuthorizationStatus { authorizationStatus }
    func presentAppPicker() {}
    func applyShield(selection: FocusAppSelection) throws {}
    func clearShield() {}
    func currentSelection() -> FocusAppSelection? { nil }
}
