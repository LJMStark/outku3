import Foundation
import Testing
@testable import KiroleFeature

@Suite("App Date Formatters Tests")
struct AppDateFormattersTests {
    @Test("Shared formatters keep English output under a Chinese locale")
    @MainActor
    func sharedFormattersUseEnglishPOSIXLocale() {
        let formatters = [
            AppDateFormatters.headerDate,
            AppDateFormatters.time,
            AppDateFormatters.separatorDate,
            AppDateFormatters.shortDate,
            AppDateFormatters.eventDetailDate,
        ]

        for formatter in formatters {
            #expect(formatter.locale?.identifier == "en_US_POSIX")
        }

        let januaryDate = Date(timeIntervalSince1970: 1_768_478_400)
        let output = AppDateFormatters.headerDate.string(from: januaryDate)
        #expect(output.contains("Jan"))
        #expect(!output.contains("月"))

        let relativeOutput = AppDateFormatters.relativeTimeText(
            for: januaryDate.addingTimeInterval(-3_600),
            relativeTo: januaryDate
        )
        #expect(relativeOutput == "1 hour ago")
    }

    @Test("Header time reports the selected timezone instead of hard-coded GMT")
    func headerTimeUsesActualTimezoneLabel() throws {
        let shanghai = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let date = Date(timeIntervalSince1970: 1_768_478_400)

        let label = AppDateFormatters.timeZoneLabel(for: date, timeZone: shanghai)
        let output = AppDateFormatters.headerTimeText(for: date, timeZone: shanghai)

        #expect(label != "GMT")
        #expect(output.hasPrefix("8:00pm"))
        #expect(output.hasSuffix("(\(label))"))
        #expect(!output.hasSuffix("(GMT)"))
    }
}
