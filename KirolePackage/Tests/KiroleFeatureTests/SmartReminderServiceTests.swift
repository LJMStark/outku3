import Foundation
import Testing
@testable import KiroleFeature

@MainActor
@Suite("Smart Reminder Service")
struct SmartReminderServiceTests {
    @Test("An overdue task is not reported as an approaching deadline")
    func overdueTaskIsNotApproachingDeadline() {
        let now = Date(timeIntervalSince1970: 1_699_956_800)
        let overdue = makeTask(title: "Overdue", dueDate: now.addingTimeInterval(-60))

        let result = SmartReminderService.urgentDeadlineTask(
            in: [overdue],
            now: now,
            calendar: utcCalendar
        )

        #expect(result == nil)
    }

    @Test("A high-priority task due within three hours is an approaching deadline")
    func nearFutureTaskIsApproachingDeadline() {
        let now = Date(timeIntervalSince1970: 1_699_956_800)
        let upcoming = makeTask(title: "Upcoming", dueDate: now.addingTimeInterval(2 * 60 * 60))

        let result = SmartReminderService.urgentDeadlineTask(
            in: [upcoming],
            now: now,
            calendar: utcCalendar
        )

        #expect(result?.id == upcoming.id)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeTask(title: String, dueDate: Date) -> TaskItem {
        TaskItem(
            title: title,
            dueDate: dueDate,
            priority: .high
        )
    }
}
