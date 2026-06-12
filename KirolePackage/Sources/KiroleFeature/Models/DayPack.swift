import CryptoKit
import Foundation

// MARK: - Day Pack

/// 发送到 E-ink 设备的每日数据包
/// 包含 4 个页面的所有数据
public struct DayPack: Codable, Sendable {
    public let id: UUID
    public let date: Date
    public let weather: WeatherInfo?
    public let deviceMode: DeviceMode
    public let focusChallengeEnabled: Bool

    // Pet dialogue bubble (v2.5.0: single line, sourced from App currentPetDialogue —
    // phase-aware, so it's a morning greeting in the morning and a settlement line at night).
    public let petDialogue: String

    // Overview panel data
    public let events: [EventSummary]
    public let topTasks: [TaskSummary]

    // Task detail (态 C) is dynamic via TaskInPage (0x11) + FocusStatus (0x14), not in DayPack.

    // Settlement numeric data (progress bar + focus stats)
    public let settlementData: SettlementData

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        weather: WeatherInfo? = nil,
        deviceMode: DeviceMode = .interactive,
        focusChallengeEnabled: Bool = false,
        petDialogue: String,
        events: [EventSummary] = [],
        topTasks: [TaskSummary] = [],
        settlementData: SettlementData
    ) {
        self.id = id
        self.date = date
        self.weather = weather
        self.deviceMode = deviceMode
        self.focusChallengeEnabled = focusChallengeEnabled
        self.petDialogue = petDialogue
        self.events = events
        self.topTasks = topTasks
        self.settlementData = settlementData
    }

    public func stableFingerprint() -> String {
        let dateFormatter = DateFormatter()
        // 不设 locale 时继承设备区域（如泰国佛历 yyyy=2569），指纹会随 locale 漂移。
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)

        var parts: [String] = []
        parts.append("date=\(dateString)")
        parts.append("deviceMode=\(deviceMode.rawValue)")
        parts.append("focusChallenge=\(focusChallengeEnabled)")

        if let weatherInfo = weather {
            parts.append("weather.temp=\(weatherInfo.temperature)")
            parts.append("weather.high=\(weatherInfo.highTemp)")
            parts.append("weather.low=\(weatherInfo.lowTemp)")
            parts.append("weather.cond=\(weatherInfo.condition)")
            parts.append("weather.icon=\(weatherInfo.iconName)")
        } else {
            parts.append("weather=none")
        }

        parts.append("petDialogue=\(petDialogue)")
        parts.append("events.count=\(events.count)")
        for event in events {
            parts.append("event.time=\(event.time)")
            parts.append("event.title=\(event.title)")
            parts.append("event.desc=\(event.description)")
        }

        parts.append("topTasks.count=\(topTasks.count)")
        for task in topTasks {
            parts.append("task.id=\(task.id)")
            parts.append("task.title=\(task.title)")
            parts.append("task.completed=\(task.isCompleted ? 1 : 0)")
            parts.append("task.priority=\(task.priority)")
            parts.append("task.due=\(task.dueTime ?? "")")
        }

        parts.append("settlement.completed=\(settlementData.tasksCompleted)")
        parts.append("settlement.total=\(settlementData.tasksTotal)")
        parts.append("settlement.points=\(settlementData.pointsEarned)")
        parts.append("settlement.mood=\(settlementData.petMood)")
        parts.append("settlement.focusMinutes=\(settlementData.totalFocusMinutes)")
        parts.append("settlement.focusSessions=\(settlementData.focusSessionCount)")
        parts.append("settlement.longestFocus=\(settlementData.longestFocusMinutes)")
        parts.append("settlement.interruptionCount=\(settlementData.interruptionCount)")
        parts.append("settlement.totalEnergyBottles=\(settlementData.totalEnergyBottles)")

        let combined = parts.joined(separator: "|")
        let digest = SHA256.hash(data: Data(combined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Weather Info

/// 天气信息（用于 Day Pack）
public struct WeatherInfo: Codable, Sendable {
    public let temperature: Int
    public let highTemp: Int
    public let lowTemp: Int
    public let condition: String
    public let iconName: String

    public init(
        temperature: Int,
        highTemp: Int,
        lowTemp: Int,
        condition: String,
        iconName: String
    ) {
        self.temperature = temperature
        self.highTemp = highTemp
        self.lowTemp = lowTemp
        self.condition = condition
        self.iconName = iconName
    }

    public init(from weather: Weather) {
        self.temperature = weather.temperature
        self.highTemp = weather.highTemp
        self.lowTemp = weather.lowTemp
        self.condition = weather.condition.rawValue
        self.iconName = weather.condition.rawValue
    }
}

// MARK: - Task Summary

/// 任务摘要（用于 Day Pack Overview 页面）
public struct TaskSummary: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let isCompleted: Bool
    public let priority: Int
    public let dueTime: String?

    public init(
        id: String,
        title: String,
        isCompleted: Bool,
        priority: Int = 1,
        dueTime: String? = nil
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.priority = priority
        self.dueTime = dueTime
    }

    public init(from task: TaskItem) {
        self.id = task.id
        self.title = task.title
        self.isCompleted = task.isCompleted
        self.priority = task.priority.rawValue
        if let dueDate = task.dueDate {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "HH:mm"
            self.dueTime = formatter.string(from: dueDate)
        } else {
            self.dueTime = nil
        }
    }
}

// MARK: - Event Summary

/// 事件摘要（用于 DayPack 概览面板的事件卡：时间 + 标题 + 描述）
public struct EventSummary: Codable, Sendable {
    public let time: String          // "HH:mm"，全天事件为空串
    public let title: String
    public let description: String

    public init(time: String, title: String, description: String) {
        self.time = time
        self.title = title
        self.description = description
    }

    public init(from event: CalendarEvent) {
        if event.isAllDay {
            self.time = ""
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "HH:mm"
            self.time = formatter.string(from: event.startTime)
        }
        self.title = event.title
        self.description = event.description ?? ""
    }
}

// MARK: - Settlement Data

/// 每日结算数据
public struct SettlementData: Codable, Sendable {
    public let tasksCompleted: Int
    public let tasksTotal: Int
    public let pointsEarned: Int
    public let petMood: String
    public let summaryMessage: String
    public let encouragementMessage: String
    public let totalFocusMinutes: Int
    public let focusSessionCount: Int
    public let longestFocusMinutes: Int
    public let interruptionCount: Int
    public let totalEnergyBottles: Int

    public init(
        tasksCompleted: Int,
        tasksTotal: Int,
        pointsEarned: Int,
        petMood: String,
        summaryMessage: String,
        encouragementMessage: String,
        totalFocusMinutes: Int = 0,
        focusSessionCount: Int = 0,
        longestFocusMinutes: Int = 0,
        interruptionCount: Int = 0,
        totalEnergyBottles: Int = 0
    ) {
        self.tasksCompleted = tasksCompleted
        self.tasksTotal = tasksTotal
        self.pointsEarned = pointsEarned
        self.petMood = petMood
        self.summaryMessage = summaryMessage
        self.encouragementMessage = encouragementMessage
        self.totalFocusMinutes = totalFocusMinutes
        self.focusSessionCount = focusSessionCount
        self.longestFocusMinutes = longestFocusMinutes
        self.interruptionCount = interruptionCount
        self.totalEnergyBottles = totalEnergyBottles
    }

    public var completionRate: Double {
        guard tasksTotal > 0 else { return 0 }
        return Double(tasksCompleted) / Double(tasksTotal)
    }
}

// MARK: - Task In Page Data

/// Task In 页面数据（动态生成）
public struct TaskInPageData: Codable, Sendable {
    public let taskId: String
    public let taskTitle: String
    public let taskDescription: String?
    public let encouragement: String
    public let focusChallengeActive: Bool

    public init(
        taskId: String,
        taskTitle: String,
        taskDescription: String? = nil,
        encouragement: String,
        focusChallengeActive: Bool = false
    ) {
        self.taskId = taskId
        self.taskTitle = taskTitle
        self.taskDescription = taskDescription
        self.encouragement = encouragement
        self.focusChallengeActive = focusChallengeActive
    }
}
