import Foundation

public extension Calendar {
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
