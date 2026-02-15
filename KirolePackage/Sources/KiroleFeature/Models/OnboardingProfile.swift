import Foundation

// MARK: - Calendar Usage

public enum CalendarUsage: String, CaseIterable, Sendable, Codable, Equatable {
    case workOnly = "work-only"
    case dontUse = "dont-use"
    case everything = "everything"
}

// MARK: - Task Tracking

public enum TaskTracking: String, CaseIterable, Sendable, Codable, Equatable {
    case wingIt = "wing-it"
    case workOnly = "work-only"
    case cantLive = "cant-live"
}

// MARK: - Time Control

public enum TimeControl: String, CaseIterable, Sendable, Codable, Equatable {
    case barely = "barely"
    case overwhelmed = "overwhelmed"
    case inControl = "in-control"
    case someControl = "some-control"
}

// MARK: - Motivation Style

public enum MotivationStyle: String, CaseIterable, Sendable, Codable, Equatable {
    case encouragement = "encouragement"
    case realityCheck = "reality-check"
    case gamify = "gamify"
    case space = "space"
}

// MARK: - Distraction Source

public enum DistractionSource: String, CaseIterable, Sendable, Codable, Equatable {
    case notifications = "notifications"
    case appSwitching = "app-switching"
    case meetings = "meetings"
    case wanderingMind = "wandering-mind"
}

// MARK: - Reminder Preference

public enum ReminderPreference: String, CaseIterable, Sendable, Codable, Equatable {
    case gentleNudge = "gentleNudge"
    case deadline = "deadline"
    case streakProtect = "streakProtect"
    case minimal = "minimal"
}

// MARK: - Task Approach

public enum TaskApproach: String, CaseIterable, Sendable, Codable, Equatable {
    case selfBreak = "self-break"
    case jumpIn = "jump-in"
    case procrastinate = "procrastinate"
    case needHelp = "need-help"
}

// MARK: - Onboarding Profile

public struct OnboardingProfile: Sendable, Codable, Equatable {
    public var companionStyle: CompanionStyle?
    public var motivationStyle: MotivationStyle?
    public var calendarUsage: CalendarUsage?
    public var taskTracking: TaskTracking?
    public var distractionSources: [DistractionSource]
    public var reminderPreference: ReminderPreference?
    public var taskApproach: TaskApproach?
    public var timeControl: TimeControl?
    public var selectedTheme: String?
    public var customPhotoData: Data?
    public var onboardingCompletedAt: Date?

    public init(
        companionStyle: CompanionStyle? = nil,
        motivationStyle: MotivationStyle? = nil,
        calendarUsage: CalendarUsage? = nil,
        taskTracking: TaskTracking? = nil,
        distractionSources: [DistractionSource] = [],
        reminderPreference: ReminderPreference? = nil,
        taskApproach: TaskApproach? = nil,
        timeControl: TimeControl? = nil,
        selectedTheme: String? = nil,
        customPhotoData: Data? = nil,
        onboardingCompletedAt: Date? = nil
    ) {
        self.companionStyle = companionStyle
        self.motivationStyle = motivationStyle
        self.calendarUsage = calendarUsage
        self.taskTracking = taskTracking
        self.distractionSources = distractionSources
        self.reminderPreference = reminderPreference
        self.taskApproach = taskApproach
        self.timeControl = timeControl
        self.selectedTheme = selectedTheme
        self.customPhotoData = customPhotoData
        self.onboardingCompletedAt = onboardingCompletedAt
    }
}
