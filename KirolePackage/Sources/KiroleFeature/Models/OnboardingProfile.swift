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
    public var customCompanionPrompt: String?
    public var customCompanionRoast: Bool
    /// PNG preview produced by AvatarImageProcessor.process — feeds Settings avatar art.
    public var customAvatarPreviewData: Data?
    /// Source PNG produced by AvatarImageProcessor.process; converted to KRI for the
    /// v2.7 CustomAvatarFrame transaction after onboarding completes.
    public var customAvatarImageData: Data?

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
        customCompanionPrompt: String? = nil,
        customCompanionRoast: Bool = false,
        customAvatarPreviewData: Data? = nil,
        customAvatarImageData: Data? = nil
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
        self.customCompanionPrompt = customCompanionPrompt
        self.customCompanionRoast = customCompanionRoast
        self.customAvatarPreviewData = customAvatarPreviewData
        self.customAvatarImageData = customAvatarImageData
    }

    /// True when PersonalizationPage has captured a complete custom companion definition
    /// (photo processed + name filled). Used by completeOnboarding to decide whether to
    /// create a CustomCompanion.
    public var hasCustomCompanionDraft: Bool {
        guard let name = customCompanionName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty,
              customAvatarPreviewData != nil,
              customAvatarImageData != nil else {
            return false
        }
        return true
    }

    private enum CodingKeys: String, CodingKey {
        case companionCharacter
        case motivationStyle
        case calendarUsage
        case taskTracking
        case distractionSources
        case reminderPreference
        case taskApproach
        case timeControl
        case selectedTheme
        case onboardingCompletedAt
        case customCompanionName
        case customCompanionRelationship
        case customCompanionVoice
        case customCompanionPrompt
        case customCompanionRoast
        case customAvatarPreviewData
        case customAvatarImageData
    }

    /// Hand-written decoder tolerates pre-B-plan onboarding_profile.json shapes:
    /// old TestFlight files lack the customCompanion* keys entirely, and any
    /// legacy `customPhotoData` or `customAvatarPixelData` key (pre-v2.5.24
    /// 4bpp payload — deliberately invalidated by the PNG switch) is silently
    /// ignored (Swift's default behavior for keys absent from CodingKeys).
    /// Without this, synthesized Codable would throw the moment it reached the
    /// non-optional `customCompanionRoast: Bool`, AppState+Loading would discard
    /// the file, and mid-onboarding users would lose their progress on upgrade.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.companionCharacter = try c.decodeIfPresent(CompanionCharacter.self, forKey: .companionCharacter)
        self.motivationStyle = try c.decodeIfPresent(MotivationStyle.self, forKey: .motivationStyle)
        self.calendarUsage = try c.decodeIfPresent(CalendarUsage.self, forKey: .calendarUsage)
        self.taskTracking = try c.decodeIfPresent(TaskTracking.self, forKey: .taskTracking)
        self.distractionSources = (try c.decodeIfPresent([DistractionSource].self, forKey: .distractionSources)) ?? []
        self.reminderPreference = try c.decodeIfPresent(ReminderPreference.self, forKey: .reminderPreference)
        self.taskApproach = try c.decodeIfPresent(TaskApproach.self, forKey: .taskApproach)
        self.timeControl = try c.decodeIfPresent(TimeControl.self, forKey: .timeControl)
        self.selectedTheme = try c.decodeIfPresent(String.self, forKey: .selectedTheme)
        self.onboardingCompletedAt = try c.decodeIfPresent(Date.self, forKey: .onboardingCompletedAt)
        self.customCompanionName = try c.decodeIfPresent(String.self, forKey: .customCompanionName)
        self.customCompanionRelationship = try c.decodeIfPresent(CompanionRelationship.self, forKey: .customCompanionRelationship)
        self.customCompanionVoice = try c.decodeIfPresent(CompanionPersonaVoice.self, forKey: .customCompanionVoice)
        self.customCompanionPrompt = try c.decodeIfPresent(String.self, forKey: .customCompanionPrompt)
        self.customCompanionRoast = (try c.decodeIfPresent(Bool.self, forKey: .customCompanionRoast)) ?? false
        self.customAvatarPreviewData = try c.decodeIfPresent(Data.self, forKey: .customAvatarPreviewData)
        self.customAvatarImageData = try c.decodeIfPresent(Data.self, forKey: .customAvatarImageData)
    }
}
