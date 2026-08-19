import Foundation

/// Schedule v2 (`0x03`) snapshot: one calendar day, up to 8 full event rows.
public enum ScheduleV2Codec {
    public static let subVersion: UInt8 = 0x02
    public static let maxEvents = 8
    public static let titleLimit = 40
    public static let descriptionLimit = 120
    public static let supportTextLimit = 120

    private enum Fallback {
        static let title = "Calendar Event"
        static let description = "Details forthcoming."
    }

    public struct Event: Sendable, Equatable {
        public var time: String
        public var title: String
        public var description: String
        public var category: EventCategory
        public var endTime: String
        public var supportText: String

        public init(
            time: String,
            title: String,
            description: String,
            category: EventCategory,
            endTime: String,
            supportText: String
        ) {
            self.time = time
            self.title = title
            self.description = description
            self.category = category
            self.endTime = endTime
            self.supportText = supportText
        }
    }

    public static func encode(day: Date, events: [Event]) -> Data {
        var data = Data([subVersion])
        let components = Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day],
            from: day
        )
        data.append(UInt8(clamping: max(0, (components.year ?? 2000) - 2000)))
        data.append(UInt8(clamping: components.month ?? 1))
        data.append(UInt8(clamping: components.day ?? 1))
        let rows = Array(events.prefix(maxEvents))
        data.append(UInt8(rows.count))
        for event in rows {
            data.appendString(event.time, maxLength: 5)
            data.appendString(
                event.title,
                maxLength: titleLimit,
                fallbackIfSanitizedEmpty: Fallback.title
            )
            data.appendString(
                event.description,
                maxLength: descriptionLimit,
                fallbackIfSanitizedEmpty: Fallback.description
            )
            data.append(event.category.rawValue)
            data.appendString(event.endTime, maxLength: 5)
            data.appendString(event.supportText, maxLength: supportTextLimit)
        }
        return data
    }

    public static func encode(_ events: [CalendarEvent], now: Date = Date()) -> Data {
        let calendar = Calendar(identifier: .gregorian)
        var encoded: [Event] = []
        for event in events {
            encoded.append(contentsOf: dayRows(from: event, on: now, calendar: calendar))
            if encoded.count >= maxEvents { break }
        }
        return encode(day: now, events: Array(encoded.prefix(maxEvents)))
    }

    public static func row(from event: CalendarEvent) -> Event? {
        dayRows(from: event, on: event.startTime, calendar: Calendar(identifier: .gregorian)).first
    }

    /// Split a cross-midnight event into the in-day slice for `day`, or omit it.
    public static func dayRows(
        from event: CalendarEvent,
        on day: Date,
        calendar: Calendar
    ) -> [Event] {
        let category = scheduleCategory(for: event)
        let description = visibleDescription(from: event)
        let support = FallbackText.eventSupportText(for: category, seed: event.title)

        if event.isAllDay {
            guard calendar.isDate(event.startTime, inSameDayAs: day) else { return [] }
            return [
                Event(
                    time: "",
                    title: event.title,
                    description: description,
                    category: category,
                    endTime: "",
                    supportText: support
                )
            ]
        }

        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        let start = event.startTime
        let end = event.endTime
        guard start < dayEnd, end > dayStart else { return [] }

        let sliceStart = max(start, dayStart)
        let sliceEnd = min(end, dayEnd)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        let time: String
        let endTime: String
        if sliceEnd == dayEnd {
            time = formatter.string(from: sliceStart)
            endTime = "23:59"
        } else if sliceStart == dayStart && !calendar.isDate(start, inSameDayAs: day) {
            time = "00:00"
            endTime = formatter.string(from: sliceEnd)
        } else {
            time = formatter.string(from: sliceStart)
            endTime = formatter.string(from: sliceEnd)
        }
        guard time.count == 5, endTime.count == 5, endTime > time else { return [] }
        return [
            Event(
                time: time,
                title: event.title,
                description: description,
                category: category,
                endTime: endTime,
                supportText: support
            )
        ]
    }

    private static func visibleDescription(from event: CalendarEvent) -> String {
        let raw = event.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !raw.isEmpty { return raw }
        let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !location.isEmpty { return location }
        // Firmware rejects empty Description. Placeholder is H4 in the hardware negotiation list.
        return Fallback.description
    }

    public static func scheduleCategory(for event: CalendarEvent) -> EventCategory {
        let text = "\(event.title) \(event.description ?? "")"
        let guessed = EventCategory.heuristic(for: text)
        return guessed == .unknown ? .admin : guessed
    }
}
