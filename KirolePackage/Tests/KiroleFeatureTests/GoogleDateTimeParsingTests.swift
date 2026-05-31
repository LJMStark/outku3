import Foundation
import Testing
@testable import KiroleFeature

@Suite("GoogleDateTime parsing")
struct GoogleDateTimeParsingTests {

    @Test("All-day event resolves to the same calendar day regardless of cached formatter state")
    func allDayResolvesToCalendarDay() throws {
        let value = GoogleDateTime(dateTime: nil, date: "2026-05-31", timeZone: nil)
        let resolved = try #require(value.asDate)

        // Built and read back via the *current* calendar, so the day must round-trip
        // independent of whatever time zone any cached formatter was created in.
        let components = Calendar.current.dateComponents([.year, .month, .day], from: resolved)
        #expect(components.year == 2026)
        #expect(components.month == 5)
        #expect(components.day == 31)
    }

    @Test("Timed event parses RFC3339 with offset")
    func timedEventParsesRFC3339() throws {
        let value = GoogleDateTime(dateTime: "2026-05-31T09:30:00Z", date: nil, timeZone: nil)
        let resolved = try #require(value.asDate)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        let c = utc.dateComponents([.year, .month, .day, .hour, .minute], from: resolved)
        #expect(c.year == 2026)
        #expect(c.month == 5)
        #expect(c.day == 31)
        #expect(c.hour == 9)
        #expect(c.minute == 30)
    }

    @Test("Missing both date and dateTime yields nil")
    func missingBothYieldsNil() {
        let value = GoogleDateTime(dateTime: nil, date: nil, timeZone: nil)
        #expect(value.asDate == nil)
    }

    @Test("Malformed all-day string falls back without crashing")
    func malformedAllDayDoesNotCrash() {
        let value = GoogleDateTime(dateTime: nil, date: "not-a-date", timeZone: nil)
        #expect(value.asDate == nil)
    }
}
