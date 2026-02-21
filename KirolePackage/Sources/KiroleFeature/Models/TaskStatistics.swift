import Foundation

public struct TaskStatistics: Sendable, Codable {
    public var todayCompleted: Int
    public var todayTotal: Int
    public var pastWeekCompleted: Int
    public var pastWeekTotal: Int
    public var last30DaysCompleted: Int
    public var last30DaysTotal: Int

    public init(
        todayCompleted: Int = 0,
        todayTotal: Int = 0,
        pastWeekCompleted: Int = 0,
        pastWeekTotal: Int = 0,
        last30DaysCompleted: Int = 0,
        last30DaysTotal: Int = 0
    ) {
        self.todayCompleted = todayCompleted
        self.todayTotal = todayTotal
        self.pastWeekCompleted = pastWeekCompleted
        self.pastWeekTotal = pastWeekTotal
        self.last30DaysCompleted = last30DaysCompleted
        self.last30DaysTotal = last30DaysTotal
    }

    public var todayPercentage: Double {
        guard todayTotal > 0 else { return 0 }
        return Double(todayCompleted) / Double(todayTotal)
    }

    public var pastWeekPercentage: Double {
        guard pastWeekTotal > 0 else { return 0 }
        return Double(pastWeekCompleted) / Double(pastWeekTotal)
    }

    public var last30DaysPercentage: Double {
        guard last30DaysTotal > 0 else { return 0 }
        return Double(last30DaysCompleted) / Double(last30DaysTotal)
    }
}
