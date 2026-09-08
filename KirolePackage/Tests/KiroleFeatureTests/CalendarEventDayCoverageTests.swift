import Foundation
import Testing
@testable import KiroleFeature

/// Real-device finding D05 (build 663): an Outlook all-day event covering Sep 7–8 arrives as
/// Sep 7 00:00 → Sep 9 00:00 and appeared on the timeline under Sep 7 only.
@Suite("CalendarEvent day coverage")
struct CalendarEventDayCoverageTests {

    /// Local zone on purpose. `ScheduleV2Codec.dayRows` takes a calendar for its day boundaries
    /// but formats the wire times with a plain `DateFormatter`, which follows `TimeZone.current`.
    /// Pinning this to GMT would make the two halves disagree in the test and nowhere else —
    /// production always passes `Calendar.current`, whose zone already matches the formatter.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private func event(start: Date, end: Date, isAllDay: Bool = false) -> CalendarEvent {
        CalendarEvent(title: "QA", startTime: start, endTime: end, isAllDay: isAllDay)
    }

    // MARK: - The reported case

    @Test("An all-day event covering Sep 7-8 lists under both days")
    func allDayEventSpansBothDays() {
        let subject = event(start: date(7), end: date(9), isAllDay: true)

        #expect(subject.covers(day: date(7), calendar: calendar))
        #expect(subject.covers(day: date(8), calendar: calendar))
    }

    @Test("It does not leak onto the midnight it ends at")
    func allDayEventStopsAtItsEndMidnight() {
        let subject = event(start: date(7), end: date(9), isAllDay: true)

        // The half-open test is the whole point: `endTime >= dayStart` would list Sep 9 too,
        // because an all-day event ends at the *next* midnight.
        #expect(!subject.covers(day: date(9), calendar: calendar))
        #expect(!subject.covers(day: date(6), calendar: calendar))
    }

    // MARK: - Boundaries

    @Test("An event ending exactly at midnight stays on the day before")
    func eventEndingAtMidnightDoesNotSpill() {
        let subject = event(start: date(7, 23), end: date(8))

        #expect(subject.covers(day: date(7), calendar: calendar))
        #expect(!subject.covers(day: date(8), calendar: calendar))
    }

    @Test("A timed event crossing midnight lists under both days")
    func timedEventCrossingMidnight() {
        let subject = event(start: date(7, 22), end: date(8, 2))

        #expect(subject.covers(day: date(7), calendar: calendar))
        #expect(subject.covers(day: date(8), calendar: calendar))
        #expect(!subject.covers(day: date(9), calendar: calendar))
    }

    @Test("A zero-length event on midnight still lists under its own day")
    func zeroLengthMidnightEventSurvives() {
        // The span test alone (`endTime > dayStart`) would drop this. The start-day branch is
        // what guarantees the rule can only add days, never remove one the old filter matched.
        let subject = event(start: date(7), end: date(7))

        #expect(subject.covers(day: date(7), calendar: calendar))
        #expect(!subject.covers(day: date(8), calendar: calendar))
    }

    @Test("An ordinary same-day event is unaffected")
    func ordinaryEventUnchanged() {
        let subject = event(start: date(7, 17), end: date(7, 18))

        #expect(subject.covers(day: date(7), calendar: calendar))
        #expect(!subject.covers(day: date(6), calendar: calendar))
        #expect(!subject.covers(day: date(8), calendar: calendar))
    }

    // MARK: - The hardware wire keeps its own rule

    @Test("A multi-day all-day event still spends only one Schedule slot, on its start day")
    func allDayEventDoesNotMultiplyOnTheWire() {
        let subject = event(start: date(7), end: date(9), isAllDay: true)

        #expect(ScheduleV2Codec.dayRows(from: subject, on: date(7), calendar: calendar).count == 1)
        // Deliberate divergence from the timeline: the wire carries 8 events
        // (`ScheduleV2Codec.maxEvents`), so repeating one event across days would evict real ones.
        #expect(ScheduleV2Codec.dayRows(from: subject, on: date(8), calendar: calendar).isEmpty)
        #expect(subject.covers(day: date(8), calendar: calendar))
    }

    // MARK: - Day boundaries under DST

    @Test("A day that springs forward at midnight does not absorb the next day's early events")
    func dstMidnightShiftDoesNotAbsorbNextDay() throws {
        var santiago = Calendar(identifier: .gregorian)
        santiago.timeZone = try #require(TimeZone(identifier: "America/Santiago"))

        let dstDay = try #require(santiago.date(from: DateComponents(year: 2027, month: 9, day: 5)))
        let dayInterval = try #require(santiago.dateInterval(of: .day, for: dstDay))
        // Premise check: Chile jumps 00:00 to 01:00, so this day starts at 01:00 and runs 23h.
        // `startOfDay + 1 day` therefore lands at 01:00 the next morning — an hour past the real
        // boundary — which is exactly the window the events below fall into.
        #expect(dayInterval.duration == 23 * 3600)
        let naiveEnd = try #require(santiago.date(byAdding: .day, value: 1, to: dayInterval.start))
        #expect(naiveEnd > dayInterval.end)

        let nextDay = try #require(santiago.date(from: DateComponents(year: 2027, month: 9, day: 6)))
        let earlyNextMorning = try #require(
            santiago.date(from: DateComponents(year: 2027, month: 9, day: 6, hour: 0, minute: 30))
        )
        let subject = CalendarEvent(
            title: "Next morning",
            startTime: earlyNextMorning,
            endTime: earlyNextMorning.addingTimeInterval(1800)
        )

        #expect(!subject.covers(day: dstDay, calendar: santiago))
        #expect(subject.covers(day: nextDay, calendar: santiago))
        // The wire encoder carried the same boundary bug independently of the timeline.
        #expect(ScheduleV2Codec.dayRows(from: subject, on: dstDay, calendar: santiago).isEmpty)
        #expect(ScheduleV2Codec.dayRows(from: subject, on: nextDay, calendar: santiago).count == 1)
    }

    // MARK: - Per-day slices drive what the timeline prints

    @Test("A continuation day shows its own slice, not the previous day's start time")
    func continuationDayShowsItsOwnSlice() throws {
        let subject = event(start: date(7, 22), end: date(8, 2))

        let firstDay = try #require(subject.slice(on: date(7), calendar: calendar))
        let secondDay = try #require(subject.slice(on: date(8), calendar: calendar))

        #expect(firstDay.start == date(7, 22))
        #expect(firstDay.end == date(8))
        // The reported defect: this used to print 22:00 and the event's whole 4h span.
        #expect(secondDay.start == date(8))
        #expect(secondDay.end == date(8, 2))
        #expect(CalendarEvent.durationText(for: secondDay.duration) == "2h")
    }

    @Test("A single-day event slices to itself, so its row is unchanged")
    func sameDayEventSlicesToItself() throws {
        let subject = event(start: date(7, 17), end: date(7, 18))

        let slice = try #require(subject.slice(on: date(7), calendar: calendar))

        #expect(slice.start == subject.startTime)
        #expect(slice.end == subject.endTime)
        #expect(CalendarEvent.durationText(for: slice.duration) == subject.durationText)
    }

    @Test("A day the event does not cover has no slice")
    func uncoveredDayHasNoSlice() {
        let subject = event(start: date(7, 17), end: date(7, 18))

        #expect(subject.slice(on: date(8), calendar: calendar) == nil)
    }

    @Test("For timed events the wire already agreed with the timeline, and still slices per day")
    func timedEventAgreesWithTheWire() {
        let subject = event(start: date(7, 22), end: date(8, 2))

        // `dayRows` has always used the same half-open span test; the timeline was the one out
        // of step. Continuation days open at 00:00, first days close at 23:59.
        let firstDay = ScheduleV2Codec.dayRows(from: subject, on: date(7), calendar: calendar)
        let secondDay = ScheduleV2Codec.dayRows(from: subject, on: date(8), calendar: calendar)

        #expect(firstDay.count == 1)
        #expect(firstDay.first?.time == "22:00")
        #expect(firstDay.first?.endTime == "23:59")
        #expect(secondDay.count == 1)
        #expect(secondDay.first?.time == "00:00")
        #expect(secondDay.first?.endTime == "02:00")
    }
}
