import Foundation

// MARK: - Discovery Source

public enum DiscoverySource: String, CaseIterable, Sendable, Codable, Equatable {
    case chatgpt = "chatgpt"
    case facebook = "facebook"
    case tiktok = "tiktok"
    case twitter = "twitter"
    case instagram = "instagram"
    case kickstarter = "kickstarter"
    case appstore = "appstore"
    case friends = "friends"
    case other = "other"
}

// MARK: - User Type (multiple select)

public enum OnboardingUserType: String, CaseIterable, Sendable, Codable, Equatable {
    case multipleCalendars = "multiple-calendars"
    case juggleWorkHome = "juggle-work-home"
    case brainCluttered = "brain-cluttered"
    case funPlanner = "fun-planner"
}

// MARK: - Struggle

public enum Struggle: String, CaseIterable, Sendable, Codable, Equatable {
    case contextSwitching = "context-switching"
    case tooManyApps = "too-many-apps"
    case loseFocus = "lose-focus"
    case nothing = "nothing"
}

// MARK: - Schedule Fullness

public enum ScheduleFullness: String, CaseIterable, Sendable, Codable, Equatable {
    case multipleDaily = "multiple-daily"
    case absolutelyPacked = "absolutely-packed"
    case fewWeekly = "few-weekly"
    case prettyLight = "pretty-light"
}

// MARK: - Schedule Predictability

public enum SchedulePredictability: String, CaseIterable, Sendable, Codable, Equatable {
    case unpredictable = "unpredictable"
    case depends = "depends"
    case predictable = "predictable"
}

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

// MARK: - Avatar Choice

public enum AvatarChoice: String, CaseIterable, Sendable, Codable, Equatable {
    case inku = "inku"
    case boy = "boy"
    case dog = "dog"
    case girl = "girl"
    case robot = "robot"
    case toaster = "toaster"

    public var imageName: String {
        switch self {
        case .inku: return "inku-main"
        case .boy: return "avatar-boy"
        case .dog: return "avatar-dog"
        case .girl: return "avatar-girl"
        case .robot: return "avatar-robot"
        case .toaster: return "avatar-toaster"
        }
    }

    public var displayName: String {
        switch self {
        case .inku: return "Inku"
        case .boy: return "Alex"
        case .dog: return "Buddy"
        case .girl: return "Sam"
        case .robot: return "Robo"
        case .toaster: return "Toast"
        }
    }
}

// MARK: - Onboarding Profile

public struct OnboardingProfile: Sendable, Codable, Equatable {
    public var discoverySource: DiscoverySource?
    public var userTypes: [OnboardingUserType]
    public var struggle: Struggle?
    public var scheduleFullness: ScheduleFullness?
    public var schedulePredictability: SchedulePredictability?
    public var calendarUsage: CalendarUsage?
    public var taskTracking: TaskTracking?
    public var timeControl: TimeControl?
    public var selectedTheme: String?  // AppTheme.rawValue
    public var selectedAvatar: AvatarChoice?
    public var onboardingCompletedAt: Date?

    public init(
        discoverySource: DiscoverySource? = nil,
        userTypes: [OnboardingUserType] = [],
        struggle: Struggle? = nil,
        scheduleFullness: ScheduleFullness? = nil,
        schedulePredictability: SchedulePredictability? = nil,
        calendarUsage: CalendarUsage? = nil,
        taskTracking: TaskTracking? = nil,
        timeControl: TimeControl? = nil,
        selectedTheme: String? = nil,
        selectedAvatar: AvatarChoice? = nil,
        onboardingCompletedAt: Date? = nil
    ) {
        self.discoverySource = discoverySource
        self.userTypes = userTypes
        self.struggle = struggle
        self.scheduleFullness = scheduleFullness
        self.schedulePredictability = schedulePredictability
        self.calendarUsage = calendarUsage
        self.taskTracking = taskTracking
        self.timeControl = timeControl
        self.selectedTheme = selectedTheme
        self.selectedAvatar = selectedAvatar
        self.onboardingCompletedAt = onboardingCompletedAt
    }
}
