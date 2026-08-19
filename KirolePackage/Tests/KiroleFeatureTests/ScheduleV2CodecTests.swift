import Foundation
import Testing
@testable import KiroleFeature

@Suite("Schedule v2 wire protocol")
struct ScheduleV2CodecTests {
    @Test("Zero-event snapshot matches the hardware golden frame payload")
    func zeroEventGoldenBytes() {
        let day = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2026, month: 8, day: 18)
        )!
        #expect(ScheduleV2Codec.encode(day: day, events: []) == Data([0x02, 0x1A, 0x08, 0x12, 0x00]))
    }

    @Test("Single event encodes Time Title Description Category EndTime SupportText")
    func singleEventFieldOrder() {
        let day = Calendar(identifier: .gregorian).date(
            from: DateComponents(year: 2026, month: 8, day: 18)
        )!
        let payload = ScheduleV2Codec.encode(
            day: day,
            events: [
                .init(
                    time: "09:00",
                    title: "Standup",
                    description: "Daily sync",
                    category: .meetings,
                    endTime: "09:30",
                    supportText: "Share blockers"
                )
            ]
        )
        #expect(payload[0] == 0x02)
        #expect(Array(payload[1...4]) == [0x1A, 0x08, 0x12, 0x01])
        var cursor = 5
        #expect(readString(payload, &cursor) == "09:00")
        #expect(readString(payload, &cursor) == "Standup")
        #expect(readString(payload, &cursor) == "Daily sync")
        #expect(payload[cursor] == EventCategory.meetings.rawValue)
        cursor += 1
        #expect(readString(payload, &cursor) == "09:30")
        #expect(readString(payload, &cursor) == "Share blockers")
        #expect(cursor == payload.count)
    }

    @Test("Calendar events get a non-empty description and never emit the old title+HH:mm layout")
    func calendarEventUsesFullRow() {
        let start = Calendar.current.date(bySettingHour: 9, minute: 30, second: 0, of: Date())!
        let event = CalendarEvent(
            title: "Sync",
            startTime: start,
            endTime: start.addingTimeInterval(1800),
            description: nil
        )
        let data = ScheduleV2Codec.encode([event], now: start)
        #expect(data[0] == 0x02)
        #expect(data[4] == 1)
        #expect(data.count > 6)
        #expect(data[5] != 4)
    }

    @Test("Cross-midnight events split into the in-day slice or are omitted")
    func crossMidnightEventIsSplitOrOmitted() throws {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.date(from: DateComponents(year: 2026, month: 8, day: 18, hour: 12))!
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 18, hour: 22))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 8, day: 19, hour: 2))!
        let event = CalendarEvent(
            title: "Late shift",
            startTime: start,
            endTime: end,
            description: "Night coverage"
        )

        let todayRow = try #require(ScheduleV2Codec.dayRows(from: event, on: today, calendar: calendar).first)
        #expect(todayRow.time == "22:00")
        #expect(todayRow.endTime == "23:59")

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let tomorrowRow = try #require(ScheduleV2Codec.dayRows(from: event, on: tomorrow, calendar: calendar).first)
        #expect(tomorrowRow.time == "00:00")
        #expect(tomorrowRow.endTime == "02:00")

        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        #expect(ScheduleV2Codec.dayRows(from: event, on: yesterday, calendar: calendar).isEmpty)
    }

    @Test("All-day events encode empty Time and EndTime")
    func allDayTimesAreEmpty() throws {
        let day = Date()
        let event = CalendarEvent(
            title: "Holiday",
            startTime: day,
            endTime: day,
            description: "Office closed",
            isAllDay: true
        )
        let row = try #require(ScheduleV2Codec.row(from: event))
        #expect(row.time.isEmpty)
        #expect(row.endTime.isEmpty)
        #expect(!row.description.isEmpty)
    }

    private func readString(_ data: Data, _ cursor: inout Int) -> String {
        let length = Int(data[cursor])
        cursor += 1
        let text = String(data: data.subdata(in: cursor..<(cursor + length)), encoding: .utf8) ?? ""
        cursor += length
        return text
    }
}
