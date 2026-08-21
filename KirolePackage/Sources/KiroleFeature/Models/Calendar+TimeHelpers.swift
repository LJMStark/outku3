import Foundation

public extension Calendar {
    /// DayPack settlement needs today's display data plus tomorrow's first calendar item.
    internal func dayPackEventSyncRange(containing date: Date = Date()) -> Range<Date> {
        let start = startOfDay(for: date)
        let end = self.date(byAdding: .day, value: 2, to: start)!
        return start..<end
    }

    func isWorkHours(_ date: Date = Date()) -> Bool {
        let hour = component(.hour, from: date)
        return hour >= 9 && hour < 18
    }

    func isWeekend(_ date: Date = Date()) -> Bool {
        let weekday = component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    func isNightTime(_ date: Date = Date()) -> Bool {
        let hour = component(.hour, from: date)
        return hour >= 21 || hour < 6
    }

    func isSleepyTime(_ date: Date = Date()) -> Bool {
        let hour = component(.hour, from: date)
        return hour >= 22 || hour < 6
    }
}
