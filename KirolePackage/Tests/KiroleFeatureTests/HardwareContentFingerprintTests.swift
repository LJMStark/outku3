import Foundation
import Testing
@testable import KiroleFeature

@Suite("Hardware content fingerprint")
struct HardwareContentFingerprintTests {
    private let now = Date(timeIntervalSince1970: 1_786_396_800)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test("identical task and schedule state hashes the same")
    func identicalStateIsStable() {
        let first = HardwareContentFingerprint.structural(
            tasks: [task()],
            events: [event()],
            now: now,
            screenSize: .fourInch,
            deviceMode: .interactive,
            calendar: calendar
        )
        let second = HardwareContentFingerprint.structural(
            tasks: [task()],
            events: [event()],
            now: now,
            screenSize: .fourInch,
            deviceMode: .interactive,
            calendar: calendar
        )
        #expect(first == second)
    }

    @Test("task title or completion changes the structural hash")
    func taskMutationChangesHash() {
        let base = HardwareContentFingerprint.structural(
            tasks: [task()],
            events: [event()],
            now: now,
            screenSize: .fourInch,
            deviceMode: .interactive,
            calendar: calendar
        )
        let renamed = HardwareContentFingerprint.structural(
            tasks: [task(title: "Write spec")],
            events: [event()],
            now: now,
            screenSize: .fourInch,
            deviceMode: .interactive,
            calendar: calendar
        )
        let completed = HardwareContentFingerprint.structural(
            tasks: [task(isCompleted: true)],
            events: [event()],
            now: now,
            screenSize: .fourInch,
            deviceMode: .interactive,
            calendar: calendar
        )
        #expect(base != renamed)
        #expect(base != completed)
    }

    @Test("event time or title changes the structural hash")
    func eventMutationChangesHash() {
        let base = HardwareContentFingerprint.structural(
            tasks: [task()],
            events: [event()],
            now: now,
            screenSize: .fourInch,
            deviceMode: .interactive,
            calendar: calendar
        )
        let moved = HardwareContentFingerprint.structural(
            tasks: [task()],
            events: [event(startOffset: 7200)],
            now: now,
            screenSize: .fourInch,
            deviceMode: .interactive,
            calendar: calendar
        )
        #expect(base != moved)
    }

    @Test("companion switch changes the structural hash but dialogue does not")
    func companionSwitchChangesHash() {
        let joy = HardwareContentFingerprint.structural(
            tasks: [task()],
            events: [event()],
            now: now,
            screenSize: .fourInch,
            deviceMode: .interactive,
            companionKey: "builtIn:joy",
            calendar: calendar
        )
        let silas = HardwareContentFingerprint.structural(
            tasks: [task()],
            events: [event()],
            now: now,
            screenSize: .fourInch,
            deviceMode: .interactive,
            companionKey: "builtIn:silas",
            calendar: calendar
        )
        #expect(joy != silas)
        #expect(
            HardwareContentFingerprint.companionKey(
                from: UserProfile(companionCharacter: .joy)
            ) == "builtIn:joy"
        )
    }

    @Test("entering the current event changes the agenda slot")
    func agendaSlotChangesWhenEventStarts() {
        let before = HardwareContentFingerprint.structural(
            tasks: [task()],
            events: [event(startOffset: 60, duration: 3600)],
            now: now,
            screenSize: .fourInch,
            deviceMode: .interactive,
            calendar: calendar
        )
        let during = HardwareContentFingerprint.structural(
            tasks: [task()],
            events: [event(startOffset: 60, duration: 3600)],
            now: now.addingTimeInterval(120),
            screenSize: .fourInch,
            deviceMode: .interactive,
            calendar: calendar
        )
        #expect(before != during)
        #expect(
            HardwareContentFingerprint.currentAgendaKey(
                events: [event(startOffset: 60, duration: 3600)],
                topTasks: [TaskSummary(from: task())],
                now: now
            ) == "next-event:event-1"
        )
        #expect(
            HardwareContentFingerprint.currentAgendaKey(
                events: [event(startOffset: 60, duration: 3600)],
                topTasks: [TaskSummary(from: task())],
                now: now.addingTimeInterval(120)
            ) == "now-event:event-1"
        )
    }

    private func task(
        title: String = "Plan BLE",
        isCompleted: Bool = false
    ) -> TaskItem {
        TaskItem(
            id: "task-1",
            title: title,
            isCompleted: isCompleted,
            dueDate: now,
            todayDisplayDate: now
        )
    }

    private func event(
        startOffset: TimeInterval = 3600,
        duration: TimeInterval = 1800
    ) -> CalendarEvent {
        CalendarEvent(
            id: "event-1",
            title: "Hardware sync",
            startTime: now.addingTimeInterval(startOffset),
            endTime: now.addingTimeInterval(startOffset + duration)
        )
    }
}
