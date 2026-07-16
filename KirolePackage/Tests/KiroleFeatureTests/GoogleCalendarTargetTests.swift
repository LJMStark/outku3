import Testing
@testable import KiroleFeature

@Suite("Google Calendar Targets")
struct GoogleCalendarTargetTests {
    @Test("The primary alias is not fetched beside CalendarList's real primary id")
    func primaryAliasDoesNotDuplicateRealPrimaryCalendar() {
        let calendars = [
            GoogleCalendarInfo(
                id: "person@example.com",
                summary: "Primary",
                primary: true,
                selected: true,
                hidden: false,
                backgroundColor: nil,
                foregroundColor: nil
            ),
            GoogleCalendarInfo(
                id: "team@example.com",
                summary: "Team",
                primary: false,
                selected: true,
                hidden: false,
                backgroundColor: nil,
                foregroundColor: nil
            ),
        ]

        #expect(GoogleCalendarAPI.targetCalendarIDs(from: calendars) == [
            "person@example.com",
            "team@example.com",
        ])
    }

    @Test("The primary alias remains the fallback when CalendarList has no primary metadata")
    func primaryAliasIsFallbackWithoutPrimaryMetadata() {
        let calendars = [
            GoogleCalendarInfo(
                id: "team@example.com",
                summary: "Team",
                primary: nil,
                selected: true,
                hidden: false,
                backgroundColor: nil,
                foregroundColor: nil
            ),
        ]

        #expect(GoogleCalendarAPI.targetCalendarIDs(from: calendars) == [
            "primary",
            "team@example.com",
        ])
    }
}
