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

    // Day-at-a-glance summary (v2.5.7: box② — emotion-oriented, events-only overview plus one
    // practical suggestion. Distinct from the pet bubble; empty until generated.)
    public let daySummary: String

    // box③ "First up" (v2.5.8): next upcoming event label ("HH:mm Title"), else the first
    // incomplete task title, else "". Computed App-side so firmware just renders it.
    public let firstUp: String

    // 页面四 每日总结（v2.5.30，客户 2026-07-20）——三段文案，固件长按"完成当日"时展示：
    // 概况点评（死线必提、专注>2h 必提时长）；金句/明日鼓励（三分支）；明日第一件事
    // （"HH:mm Title" 同 firstUp 格式，空串 = 固件隐藏该行）。
    public let settlementReview: String
    public let settlementQuote: String
    public let tomorrowFirstUp: String

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
        daySummary: String = "",
        firstUp: String = "",
        settlementReview: String = "",
        settlementQuote: String = "",
        tomorrowFirstUp: String = "",
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
        self.daySummary = daySummary
        self.firstUp = firstUp
        self.settlementReview = settlementReview
        self.settlementQuote = settlementQuote
        self.tomorrowFirstUp = tomorrowFirstUp
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

        // Weather 刻意不进指纹：encodeDayPack 不编码任何天气字节（顶栏天气走独立 0x04 帧，
        // performSync 每轮无条件发）。留在指纹只会让天气变化触发一次"没有天气字节的 DayPack
        // 全刷"——硬件白刷屏、新天气还是没送到（2026-07-04 审计 F1 的连带修复）。

        parts.append("petDialogue=\(petDialogue)")
        parts.append("daySummary=\(daySummary)")
        parts.append("firstUp=\(firstUp)")
        // v2.5.30 上 wire 的字段必进指纹，否则内容变化会被去重掉、硬件永远收不到新文案。
        parts.append("settlementReview=\(settlementReview)")
        parts.append("settlementQuote=\(settlementQuote)")
        parts.append("tomorrowFirstUp=\(tomorrowFirstUp)")
        parts.append("events.count=\(events.count)")
        for event in events {
            parts.append("event.time=\(event.time)")
            parts.append("event.endTime=\(event.endTime)")
            parts.append("event.title=\(event.title)")
            parts.append("event.desc=\(event.description)")
            // Category joins the fingerprint so an async classification landing later (cache miss →
            // AI result on the next generate) re-pushes the DayPack instead of being deduped away.
            parts.append("event.category=\(event.category.rawValue)")
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

        var framedParts = Data()
        for part in parts {
            let bytes = Data(part.utf8)
            var byteCount = UInt64(bytes.count).bigEndian
            Swift.withUnsafeBytes(of: &byteCount) { lengthBytes in
                framedParts.append(contentsOf: lengthBytes)
            }
            framedParts.append(bytes)
        }

        let digest = SHA256.hash(data: framedParts)
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

/// 事件摘要（用于 DayPack 概览面板的事件卡：时间 + 标题 + 描述 + 类别图标信号）
public struct EventSummary: Codable, Sendable {
    public let time: String          // "HH:mm"，全天事件为空串
    /// "HH:mm" 结束时间（v2.5.30）：固件用它算「前一日程结束→下一日程开始」间隔（页面二
    /// <10min/>10min 布局分支）与页面一时间轴末端标注。全天事件为空串；结束时间落在开始
    /// 时间之后的日历日（跨午夜）时按 "23:59" 封顶——App 是展示口径的决策侧（§6.5）。
    public let endTime: String
    public let title: String
    public let description: String
    /// 六大类标签（AI 打标，v2.5.27 起随 DayPack 下发 1 字节；.unknown = 固件不画图标）。
    public let category: EventCategory

    public init(time: String, endTime: String = "", title: String, description: String, category: EventCategory = .unknown) {
        self.time = time
        self.endTime = endTime
        self.title = title
        self.description = description
        self.category = category
    }

    public init(from event: CalendarEvent, category: EventCategory = .unknown) {
        if event.isAllDay {
            self.time = ""
            self.endTime = ""
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "HH:mm"
            self.time = formatter.string(from: event.startTime)
            if Calendar.current.isDate(event.endTime, inSameDayAs: event.startTime) {
                self.endTime = formatter.string(from: event.endTime)
            } else {
                self.endTime = "23:59"
            }
        }
        self.title = event.title
        self.description = event.description ?? ""
        self.category = category
    }

    /// 同内容换类别的拷贝（分类结果落地时用，保持结构体不可变语义）。
    public func withCategory(_ category: EventCategory) -> EventSummary {
        EventSummary(time: time, endTime: endTime, title: title, description: description, category: category)
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
