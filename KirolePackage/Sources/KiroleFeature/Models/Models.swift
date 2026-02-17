import Foundation

// MARK: - Calendar Helpers

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

// MARK: - Date Formatting Helpers

public extension Date {
    func formatRelativeDay() -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            return "Today"
        } else if calendar.isDateInTomorrow(self) {
            return "Tomorrow"
        } else {
            return AppDateFormatters.shortDate.string(from: self)
        }
    }
}

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

public struct CalendarEvent: Identifiable, Sendable, Codable {
    public let id: String
    public var localId: UUID
    public var googleEventId: String?
    public var appleEventId: String?
    public var appleCalendarId: String?
    public var title: String
    public var startTime: Date
    public var endTime: Date
    public var source: EventSource
    public var participants: [Participant]
    public var description: String?
    public var location: String?
    public var isAllDay: Bool
    public var syncStatus: SyncStatus
    public var lastModified: Date

    public init(
        id: String = UUID().uuidString,
        localId: UUID = UUID(),
        googleEventId: String? = nil,
        appleEventId: String? = nil,
        appleCalendarId: String? = nil,
        title: String,
        startTime: Date,
        endTime: Date,
        source: EventSource = .apple,
        participants: [Participant] = [],
        description: String? = nil,
        location: String? = nil,
        isAllDay: Bool = false,
        syncStatus: SyncStatus = .synced,
        lastModified: Date = Date()
    ) {
        self.id = id
        self.localId = localId
        self.googleEventId = googleEventId
        self.appleEventId = appleEventId
        self.appleCalendarId = appleCalendarId
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.source = source
        self.participants = participants
        self.description = description
        self.location = location
        self.isAllDay = isAllDay
        self.syncStatus = syncStatus
        self.lastModified = lastModified
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

    // 从 Google API 响应创建
    public static func from(googleEvent: GoogleCalendarEvent, source: EventSource = .google) -> CalendarEvent? {
        guard let startDate = googleEvent.start.asDate,
              let endDate = googleEvent.end.asDate else {
            return nil
        }

        let participants = googleEvent.attendees?.compactMap { attendee -> Participant? in
            guard let name = attendee.displayName ?? attendee.email else { return nil }
            return Participant(name: name)
        } ?? []

        let remoteUpdated: Date? = googleEvent.updated.flatMap { dateString in
            ISO8601DateFormatter().date(from: dateString)
        }

        return CalendarEvent(
            id: googleEvent.id,
            googleEventId: googleEvent.id,
            title: googleEvent.summary ?? "Untitled Event",
            startTime: startDate,
            endTime: endDate,
            source: source,
            participants: participants,
            description: googleEvent.description,
            location: googleEvent.location,
            isAllDay: googleEvent.start.date != nil,
            syncStatus: .synced,
            lastModified: remoteUpdated ?? Date()
        )
    }
}

public enum EventSource: String, Sendable, Codable {
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

public struct Participant: Identifiable, Sendable, Codable {
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

public struct TaskItem: Identifiable, Sendable, Codable {
    public let id: String
    public var localId: UUID
    public var googleTaskId: String?
    public var googleTaskListId: String?
    public var appleReminderId: String?
    public var appleExternalId: String?
    public var appleListId: String?
    public var title: String
    public var isCompleted: Bool
    public var dueDate: Date?
    public var source: EventSource
    public var priority: TaskPriority
    public var syncStatus: SyncStatus
    public var lastModified: Date
    public var microActions: [MicroAction]?
    public var remoteUpdatedAt: Date?
    public var remoteEtag: String?
    public var notes: String?

    public init(
        id: String = UUID().uuidString,
        localId: UUID = UUID(),
        googleTaskId: String? = nil,
        googleTaskListId: String? = nil,
        appleReminderId: String? = nil,
        appleExternalId: String? = nil,
        appleListId: String? = nil,
        title: String,
        isCompleted: Bool = false,
        dueDate: Date? = nil,
        source: EventSource = .apple,
        priority: TaskPriority = .medium,
        syncStatus: SyncStatus = .synced,
        lastModified: Date = Date(),
        microActions: [MicroAction]? = nil,
        remoteUpdatedAt: Date? = nil,
        remoteEtag: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.localId = localId
        self.googleTaskId = googleTaskId
        self.googleTaskListId = googleTaskListId
        self.appleReminderId = appleReminderId
        self.appleExternalId = appleExternalId
        self.appleListId = appleListId
        self.title = title
        self.isCompleted = isCompleted
        self.dueDate = dueDate
        self.source = source
        self.priority = priority
        self.syncStatus = syncStatus
        self.lastModified = lastModified
        self.microActions = microActions
        self.remoteUpdatedAt = remoteUpdatedAt
        self.remoteEtag = remoteEtag
        self.notes = notes
    }

    // 从 Google API 响应创建
    public static func from(googleTask: GoogleTask, taskListId: String) -> TaskItem {
        let remoteUpdated: Date? = googleTask.updated.flatMap { dateString in
            ISO8601DateFormatter().date(from: dateString)
        }

        return TaskItem(
            id: googleTask.id,
            googleTaskId: googleTask.id,
            googleTaskListId: taskListId,
            title: googleTask.title ?? "Untitled Task",
            isCompleted: googleTask.isCompleted,
            dueDate: googleTask.dueDate,
            source: .google,
            priority: .medium,
            syncStatus: .synced,
            lastModified: remoteUpdated ?? Date(),
            remoteUpdatedAt: remoteUpdated,
            remoteEtag: googleTask.etag
        )
    }
}

public enum TaskPriority: Int, Sendable, CaseIterable, Codable {
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

public struct Pet: Sendable, Codable {
    public var name: String
    public var pronouns: PetPronouns
    public var adventuresCount: Int
    public var age: Int // in days
    public var status: PetStatus
    public var mood: PetMood
    public var scene: PetScene
    public var stage: PetStage
    public var progress: Double // 0.0 to 1.0
    public var weight: Double // in grams
    public var height: Double // in cm
    public var tailLength: Double // in cm
    public var currentForm: PetForm
    public var lastInteraction: Date
    public var points: Int // accumulated points from completing tasks

    public init(
        name: String = "Baby Waffle",
        pronouns: PetPronouns = .theyThem,
        adventuresCount: Int = 0,
        age: Int = 1,
        status: PetStatus = .happy,
        mood: PetMood = .happy,
        scene: PetScene = .indoor,
        stage: PetStage = .baby,
        progress: Double = 0.0,
        weight: Double = 50,
        height: Double = 5,
        tailLength: Double = 2,
        currentForm: PetForm = .cat,
        lastInteraction: Date = Date(),
        points: Int = 0
    ) {
        self.name = name
        self.pronouns = pronouns
        self.adventuresCount = adventuresCount
        self.age = age
        self.status = status
        self.mood = mood
        self.scene = scene
        self.stage = stage
        self.progress = progress
        self.weight = weight
        self.height = height
        self.tailLength = tailLength
        self.currentForm = currentForm
        self.lastInteraction = lastInteraction
        self.points = points
    }
}

// MARK: - Pet Mood

public enum PetMood: String, Codable, Sendable, CaseIterable {
    case happy = "Happy"
    case excited = "Excited"
    case focused = "Focused"
    case sleepy = "Sleepy"
    case missing = "Missing You"
}

// MARK: - Pet Scene

public enum PetScene: String, Codable, Sendable, CaseIterable {
    case indoor = "Indoor"
    case outdoor = "Outdoor"
    case night = "Night"
    case work = "Work"
}

public enum PetPronouns: String, CaseIterable, Sendable, Codable {
    case heHim = "He/Him"
    case sheHer = "She/Her"
    case theyThem = "They/Them"
}

public enum PetStatus: String, Sendable, Codable {
    case happy = "Happy"
    case content = "Content"
    case sleepy = "Sleepy"
    case hungry = "Hungry"
    case excited = "Excited"
}

public enum PetStage: String, Sendable, Codable {
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

public enum PetForm: String, CaseIterable, Sendable, Codable {
    case cat = "Cat"
    case dog = "Dog"
    case bunny = "Bunny"
    case bird = "Bird"
    case dragon = "Dragon"

    public var iconName: String {
        switch self {
        case .cat: return "cat.fill"
        case .dog: return "dog.fill"
        case .bunny: return "hare.fill"
        case .bird: return "bird.fill"
        case .dragon: return "flame.fill"
        }
    }
}

// MARK: - Streak Model

public struct Streak: Sendable, Codable {
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

// MARK: - Weather Model

public struct Weather: Sendable, Codable {
    public var temperature: Int
    public var highTemp: Int
    public var lowTemp: Int
    public var condition: WeatherCondition
    public var location: String

    public init(
        temperature: Int = 22,
        highTemp: Int = 85,
        lowTemp: Int = 64,
        condition: WeatherCondition = .sunny,
        location: String = "San Francisco"
    ) {
        self.temperature = temperature
        self.highTemp = highTemp
        self.lowTemp = lowTemp
        self.condition = condition
        self.location = location
    }
}

public enum WeatherCondition: String, Sendable, Codable {
    case sunny = "sun.max.fill"
    case cloudy = "cloud.fill"
    case partlyCloudy = "cloud.sun.fill"
    case rainy = "cloud.rain.fill"
    case snowy = "cloud.snow.fill"
    case stormy = "cloud.bolt.fill"
}

// MARK: - Sun Times

public struct SunTimes: Sendable, Codable {
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

public struct Haiku: Identifiable, Sendable, Codable {
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

public struct Integration: Identifiable, Sendable, Codable {
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

public enum IntegrationType: String, Sendable, Codable, CaseIterable {
    case googleCalendar = "Google Calendar"
    case outlookCalendar = "Outlook Calendar"
    case appleCalendar = "Apple Calendar"
    case appleReminders = "Apple Reminders"
    case googleTasks = "Google Tasks"
    case microsoftToDo = "Microsoft To Do"
    case todoist = "Todoist"
    case tickTick = "TickTick"
    case notion = "Notion"
    case caldav = "CalDAV"
    case icalWebcal = "iCal/WebCal"

    public var isSupported: Bool {
        switch self {
        case .googleCalendar, .googleTasks, .appleCalendar, .appleReminders:
            return true
        default:
            return false
        }
    }

    public var iconName: String {
        switch self {
        case .googleCalendar: return "g.circle.fill"
        case .googleTasks: return "checkmark.circle.fill"
        case .appleCalendar: return "calendar"
        case .appleReminders: return "checklist"
        case .outlookCalendar: return "calendar.badge.clock"
        case .microsoftToDo: return "checkmark.circle"
        case .todoist: return "checklist.checked"
        case .tickTick: return "checkmark.circle"
        case .notion: return "doc.text"
        case .caldav: return "calendar"
        case .icalWebcal: return "calendar"
        }
    }

    public var isExperimental: Bool {
        self == .notion
    }

    public static var displayOrder: [IntegrationType] {
        [.googleCalendar, .outlookCalendar, .appleCalendar, .appleReminders,
         .googleTasks, .microsoftToDo, .todoist, .tickTick, .notion, .caldav, .icalWebcal]
    }
}
