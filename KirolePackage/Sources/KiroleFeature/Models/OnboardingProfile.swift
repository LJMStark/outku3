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
    public var companionCharacter: CompanionCharacter?
    public var motivationStyle: MotivationStyle?
    public var calendarUsage: CalendarUsage?
    public var taskTracking: TaskTracking?
    public var distractionSources: [DistractionSource]
    public var reminderPreference: ReminderPreference?
    public var taskApproach: TaskApproach?
    public var timeControl: TimeControl?
    public var selectedTheme: String?
    public var onboardingCompletedAt: Date?

    // MARK: - Custom Companion (B-plan)
    /// Filled when the user uploads + names a custom companion on PersonalizationPage.
    /// Consumed in completeOnboarding to call `addCustomCompanion`. When any required
    /// piece is missing the onboarding flow falls back to the built-in 3-IP selection.
    public var customCompanionName: String?
    public var customCompanionRelationship: CompanionRelationship?
    public var customCompanionVoice: CompanionPersonaVoice?
    public var customCompanionRoast: Bool
    /// PNG preview produced by AvatarImageProcessor.process — feeds Settings avatar art.
    public var customAvatarPreviewData: Data?
    /// BLE-encoded pixel payload (BLEDataEncoder.encodePixelData) for the E-ink display.
    public var customAvatarPixelData: Data?

    public init(
        companionCharacter: CompanionCharacter? = nil,
        motivationStyle: MotivationStyle? = nil,
        calendarUsage: CalendarUsage? = nil,
        taskTracking: TaskTracking? = nil,
        distractionSources: [DistractionSource] = [],
        reminderPreference: ReminderPreference? = nil,
        taskApproach: TaskApproach? = nil,
        timeControl: TimeControl? = nil,
        selectedTheme: String? = nil,
        onboardingCompletedAt: Date? = nil,
        customCompanionName: String? = nil,
        customCompanionRelationship: CompanionRelationship? = nil,
        customCompanionVoice: CompanionPersonaVoice? = nil,
        customCompanionRoast: Bool = false,
        customAvatarPreviewData: Data? = nil,
        customAvatarPixelData: Data? = nil
    ) {
        self.companionCharacter = companionCharacter
        self.motivationStyle = motivationStyle
        self.calendarUsage = calendarUsage
        self.taskTracking = taskTracking
        self.distractionSources = distractionSources
        self.reminderPreference = reminderPreference
        self.taskApproach = taskApproach
        self.timeControl = timeControl
        self.selectedTheme = selectedTheme
        self.onboardingCompletedAt = onboardingCompletedAt
        self.customCompanionName = customCompanionName
        self.customCompanionRelationship = customCompanionRelationship
        self.customCompanionVoice = customCompanionVoice
        self.customCompanionRoast = customCompanionRoast
        self.customAvatarPreviewData = customAvatarPreviewData
        self.customAvatarPixelData = customAvatarPixelData
    }

    /// True when PersonalizationPage has captured a complete custom companion definition
    /// (photo processed + name filled). Used by completeOnboarding to decide whether to
    /// create a CustomCompanion.
    public var hasCustomCompanionDraft: Bool {
        guard let name = customCompanionName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty,
              customAvatarPreviewData != nil,
              customAvatarPixelData != nil else {
            return false
        }
        return true
    }
}

