import Foundation

// MARK: - Tab Navigation

public enum AppTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case pet = "Tiko"
    case settings = "Settings"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .home: return "house.fill"
        case .pet: return "pawprint.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

// MARK: - Event Model

public struct CalendarEvent: Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var startTime: Date
    public var endTime: Date
    public var source: EventSource
    public var participants: [Participant]
    public var description: String?
    public var location: String?
    public var isAllDay: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        startTime: Date,
        endTime: Date,
        source: EventSource = .apple,
        participants: [Participant] = [],
        description: String? = nil,
        location: String? = nil,
        isAllDay: Bool = false
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.source = source
        self.participants = participants
        self.description = description
        self.location = location
        self.isAllDay = isAllDay
    }

    public var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    public var durationText: String {
        let hours = Int(duration / 3600)
        let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
        if hours > 0 && minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }
}

public enum EventSource: String, Sendable {
    case apple = "Apple Calendar"
    case google = "Google Calendar"
    case todoist = "Todoist"

    public var iconName: String {
        switch self {
        case .apple: return "apple.logo"
        case .google: return "g.circle.fill"
        case .todoist: return "checkmark.circle.fill"
        }
    }
}

public struct Participant: Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var avatarURL: URL?
    public var initials: String

    public init(id: UUID = UUID(), name: String, avatarURL: URL? = nil) {
        self.id = id
        self.name = name
        self.avatarURL = avatarURL
        let components = name.split(separator: " ")
        if components.count >= 2 {
            self.initials = String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        } else {
            self.initials = String(name.prefix(2)).uppercased()
        }
    }
}

// MARK: - Task Model

public struct TaskItem: Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var isCompleted: Bool
    public var dueDate: Date?
    public var source: EventSource
    public var priority: TaskPriority

    public init(
        id: UUID = UUID(),
        title: String,
        isCompleted: Bool = false,
        dueDate: Date? = nil,
        source: EventSource = .apple,
        priority: TaskPriority = .medium
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.dueDate = dueDate
        self.source = source
        self.priority = priority
    }
}

public enum TaskPriority: Int, Sendable, CaseIterable {
    case low = 0
    case medium = 1
    case high = 2

    public var color: String {
        switch self {
        case .low: return "7CB342"
        case .medium: return "FFB300"
        case .high: return "FF5252"
        }
    }
}

public enum TaskCategory: String, CaseIterable, Identifiable {
    case today = "Today"
    case upcoming = "Upcoming"
    case noDueDate = "No Due Dates"

    public var id: String { rawValue }
}

// MARK: - Pet Model

public struct Pet: Sendable {
    public var name: String
    public var pronouns: PetPronouns
    public var adventuresCount: Int
    public var age: Int // in days
    public var status: PetStatus
    public var stage: PetStage
    public var progress: Double // 0.0 to 1.0
    public var weight: Double // in grams
    public var height: Double // in cm
    public var tailLength: Double // in cm
    public var currentForm: PetForm

    public init(
        name: String = "Baby Waffle",
        pronouns: PetPronouns = .theyThem,
        adventuresCount: Int = 0,
        age: Int = 1,
        status: PetStatus = .happy,
        stage: PetStage = .baby,
        progress: Double = 0.0,
        weight: Double = 50,
        height: Double = 5,
        tailLength: Double = 2,
        currentForm: PetForm = .cat
    ) {
        self.name = name
        self.pronouns = pronouns
        self.adventuresCount = adventuresCount
        self.age = age
        self.status = status
        self.stage = stage
        self.progress = progress
        self.weight = weight
        self.height = height
        self.tailLength = tailLength
        self.currentForm = currentForm
    }
}

public enum PetPronouns: String, CaseIterable, Sendable {
    case heHim = "He/Him"
    case sheHer = "She/Her"
    case theyThem = "They/Them"
}

public enum PetStatus: String, Sendable {
    case happy = "Happy"
    case content = "Content"
    case sleepy = "Sleepy"
    case hungry = "Hungry"
    case excited = "Excited"
}

public enum PetStage: String, Sendable {
    case baby = "Baby"
    case child = "Child"
    case teen = "Teen"
    case adult = "Adult"
    case elder = "Elder"

    public var nextStage: PetStage? {
        switch self {
        case .baby: return .child
        case .child: return .teen
        case .teen: return .adult
        case .adult: return .elder
        case .elder: return nil
        }
    }
}

public enum PetForm: String, CaseIterable, Sendable {
    case cat = "Cat"
    case dog = "Dog"
    case bunny = "Bunny"
    case bird = "Bird"
    case dragon = "Dragon"
}

// MARK: - Streak Model

public struct Streak: Sendable {
    public var currentStreak: Int
    public var longestStreak: Int
    public var lastActiveDate: Date?

    public init(currentStreak: Int = 0, longestStreak: Int = 0, lastActiveDate: Date? = nil) {
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.lastActiveDate = lastActiveDate
    }
}

// MARK: - Statistics Model

public struct TaskStatistics: Sendable {
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

// MARK: - Weather Model

public struct Weather: Sendable {
    public var temperature: Int
    public var condition: WeatherCondition
    public var location: String

    public init(temperature: Int = 22, condition: WeatherCondition = .sunny, location: String = "San Francisco") {
        self.temperature = temperature
        self.condition = condition
        self.location = location
    }
}

public enum WeatherCondition: String, Sendable {
    case sunny = "sun.max.fill"
    case cloudy = "cloud.fill"
    case partlyCloudy = "cloud.sun.fill"
    case rainy = "cloud.rain.fill"
    case snowy = "cloud.snow.fill"
    case stormy = "cloud.bolt.fill"
}

// MARK: - Sun Times

public struct SunTimes: Sendable {
    public var sunrise: Date
    public var sunset: Date

    public init(sunrise: Date, sunset: Date) {
        self.sunrise = sunrise
        self.sunset = sunset
    }

    public static var `default`: SunTimes {
        let calendar = Calendar.current
        let today = Date()
        let sunriseComponents = DateComponents(hour: 6, minute: 45)
        let sunsetComponents = DateComponents(hour: 17, minute: 30)
        return SunTimes(
            sunrise: calendar.date(bySettingHour: sunriseComponents.hour!, minute: sunriseComponents.minute!, second: 0, of: today)!,
            sunset: calendar.date(bySettingHour: sunsetComponents.hour!, minute: sunsetComponents.minute!, second: 0, of: today)!
        )
    }
}

// MARK: - Haiku Model

public struct Haiku: Identifiable, Sendable {
    public let id: UUID
    public var lines: [String]

    public init(id: UUID = UUID(), lines: [String]) {
        self.id = id
        self.lines = lines
    }

    public static var placeholder: Haiku {
        Haiku(lines: [
            "Morning light arrives",
            "Tasks await with gentle hope",
            "One step at a time"
        ])
    }
}

// MARK: - Integration Model

public struct Integration: Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var iconName: String
    public var isConnected: Bool
    public var type: IntegrationType

    public init(id: UUID = UUID(), name: String, iconName: String, isConnected: Bool = false, type: IntegrationType) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.isConnected = isConnected
        self.type = type
    }
}

public enum IntegrationType: String, Sendable {
    case appleCalendar = "Apple Calendar"
    case appleReminders = "Apple Reminders"
    case googleCalendar = "Google Calendar"
    case googleTasks = "Google Tasks"
    case todoist = "Todoist"
}
