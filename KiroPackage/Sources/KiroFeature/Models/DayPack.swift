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

    // Page 1: Start of Day
    public let morningGreeting: String
    public let dailySummary: String
    public let firstItem: String

    // Page 2: Overview
    public let currentScheduleSummary: String?
    public let topTasks: [TaskSummary]
    public let companionPhrase: String

    // Page 3: Task In (动态生成，不在 DayPack 中)

    // Page 4: Daily Settlement
    public let settlementData: SettlementData

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        weather: WeatherInfo? = nil,
        deviceMode: DeviceMode = .interactive,
        focusChallengeEnabled: Bool = false,
        morningGreeting: String,
        dailySummary: String,
        firstItem: String,
        currentScheduleSummary: String? = nil,
        topTasks: [TaskSummary] = [],
        companionPhrase: String,
        settlementData: SettlementData
    ) {
        self.id = id
        self.date = date
        self.weather = weather
        self.deviceMode = deviceMode
        self.focusChallengeEnabled = focusChallengeEnabled
        self.morningGreeting = morningGreeting
        self.dailySummary = dailySummary
        self.firstItem = firstItem
        self.currentScheduleSummary = currentScheduleSummary
        self.topTasks = topTasks
        self.companionPhrase = companionPhrase
        self.settlementData = settlementData
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
            formatter.dateFormat = "HH:mm"
            self.dueTime = formatter.string(from: dueDate)
        } else {
            self.dueTime = nil
        }
    }
}

// MARK: - Settlement Data

/// 每日结算数据
public struct SettlementData: Codable, Sendable {
    public let tasksCompleted: Int
    public let tasksTotal: Int
    public let pointsEarned: Int
    public let streakDays: Int
    public let petMood: String
    public let summaryMessage: String
    public let encouragementMessage: String

    public init(
        tasksCompleted: Int,
        tasksTotal: Int,
        pointsEarned: Int,
        streakDays: Int,
        petMood: String,
        summaryMessage: String,
        encouragementMessage: String
    ) {
        self.tasksCompleted = tasksCompleted
        self.tasksTotal = tasksTotal
        self.pointsEarned = pointsEarned
        self.streakDays = streakDays
        self.petMood = petMood
        self.summaryMessage = summaryMessage
        self.encouragementMessage = encouragementMessage
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
    public let estimatedDuration: String?
    public let encouragement: String
    public let focusChallengeActive: Bool

    public init(
        taskId: String,
        taskTitle: String,
        taskDescription: String? = nil,
        estimatedDuration: String? = nil,
        encouragement: String,
        focusChallengeActive: Bool = false
    ) {
        self.taskId = taskId
        self.taskTitle = taskTitle
        self.taskDescription = taskDescription
        self.estimatedDuration = estimatedDuration
        self.encouragement = encouragement
        self.focusChallengeActive = focusChallengeActive
    }
}
