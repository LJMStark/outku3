import Foundation

// MARK: - User Profile

public struct UserProfile: Sendable, Codable, Equatable {
    public var workType: WorkType
    public var primaryGoals: [UserGoal]
    public var companionCharacter: CompanionCharacter
    public var intimacyStage: IntimacyStage
    public var motivationStyle: MotivationStyle?
    public var reminderPreference: ReminderPreference?
    public var taskApproach: TaskApproach?
    public var onboardingCompletedAt: Date?
    /// User's currently picked hardware DisplayScene (e.g. "harbor"). nil → default to harbor on first read.
    /// Decoupled from `currentScene(for: energyBottles)`: bottles only unlock scenes; this stores the explicit pick.
    public var selectedSceneId: String?
    /// If set, the active companion is a user-created CustomCompanion (looked up by id).
    /// When nil, the active companion is the built-in `companionCharacter`.
    /// Keeping `companionCharacter` populated even when a custom is active lets us snap back
    /// to the user's last built-in pick without a second persisted field.
    public var customCompanionId: UUID?

    /// Derived from companionCharacter. Character is the single source of truth.
    public var companionStyle: CompanionStyle {
        companionCharacter.resolvedStyle
    }

    /// Current selection — either a built-in character or a custom companion id.
    /// Use this at the few sites that need to branch on "is custom or not"; everywhere else
    /// keep reading `companionCharacter` directly to avoid churn.
    public var currentSelection: CompanionSelection {
        if let id = customCompanionId {
            return .custom(id)
        }
        return .builtIn(companionCharacter)
    }

    public init(
        workType: WorkType = .other,
        primaryGoals: [UserGoal] = [],
        companionCharacter: CompanionCharacter = .joy,
        intimacyStage: IntimacyStage = .acquaintance,
        motivationStyle: MotivationStyle? = nil,
        reminderPreference: ReminderPreference? = nil,
        taskApproach: TaskApproach? = nil,
        onboardingCompletedAt: Date? = nil,
        selectedSceneId: String? = nil,
        customCompanionId: UUID? = nil
    ) {
        self.workType = workType
        self.primaryGoals = primaryGoals
        self.companionCharacter = companionCharacter
        self.intimacyStage = intimacyStage
        self.motivationStyle = motivationStyle
        self.reminderPreference = reminderPreference
        self.taskApproach = taskApproach
        self.onboardingCompletedAt = onboardingCompletedAt
        self.selectedSceneId = selectedSceneId
        self.customCompanionId = customCompanionId
    }

    private enum CodingKeys: String, CodingKey {
        case workType
        case primaryGoals
        case companionCharacter
        case intimacyStage
        case motivationStyle
        case reminderPreference
        case taskApproach
        case onboardingCompletedAt
        case selectedSceneId
        case customCompanionId
    }

    public static var `default`: UserProfile {
        UserProfile()
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.workType = try container.decodeIfPresent(WorkType.self, forKey: .workType) ?? .other
        self.primaryGoals = try container.decodeIfPresent([UserGoal].self, forKey: .primaryGoals) ?? []
        let characterRaw = try? container.decodeIfPresent(String.self, forKey: .companionCharacter)
        self.companionCharacter = characterRaw.flatMap(CompanionCharacter.init(rawValue:)) ?? .joy
        self.intimacyStage = try container.decodeIfPresent(IntimacyStage.self, forKey: .intimacyStage) ?? .acquaintance
        self.motivationStyle = try container.decodeIfPresent(MotivationStyle.self, forKey: .motivationStyle)
        self.reminderPreference = try container.decodeIfPresent(ReminderPreference.self, forKey: .reminderPreference)
        self.taskApproach = try container.decodeIfPresent(TaskApproach.self, forKey: .taskApproach)
        self.onboardingCompletedAt = try container.decodeIfPresent(Date.self, forKey: .onboardingCompletedAt)
        self.selectedSceneId = try container.decodeIfPresent(String.self, forKey: .selectedSceneId)
        self.customCompanionId = try container.decodeIfPresent(UUID.self, forKey: .customCompanionId)
    }

    /// Map onboarding answers into a UserProfile.
    /// Pass the current profile as `merging:` to preserve fields (workType, primaryGoals)
    /// that live outside the onboarding questionnaire.
    public static func from(onboarding profile: OnboardingProfile, merging existing: UserProfile = .default) -> UserProfile {
        let selectedCharacter = profile.companionCharacter ?? existing.companionCharacter
        let selectedStage: IntimacyStage = selectedCharacter == existing.companionCharacter
            ? existing.intimacyStage
            : .acquaintance

        return UserProfile(
            workType: existing.workType,
            primaryGoals: existing.primaryGoals,
            companionCharacter: selectedCharacter,
            intimacyStage: selectedStage,
            motivationStyle: profile.motivationStyle ?? existing.motivationStyle,
            reminderPreference: profile.reminderPreference ?? existing.reminderPreference,
            taskApproach: profile.taskApproach ?? existing.taskApproach,
            onboardingCompletedAt: profile.onboardingCompletedAt,
            selectedSceneId: existing.selectedSceneId,
            customCompanionId: existing.customCompanionId
        )
    }
}


// MARK: - Work Type

public enum WorkType: String, CaseIterable, Sendable, Codable {
    case remoteWorker = "Remote Worker"
    case student = "Student"
    case freelancer = "Freelancer"
    case officeWorker = "Office Worker"
    case entrepreneur = "Entrepreneur"
    case creative = "Creative Professional"
    case knowledgeWorker = "Knowledge Worker"
    case productManager = "Product Manager"
    case researcher = "Researcher"
    case other = "Other"

    public var displayName: String { rawValue }

    public var iconName: String {
        switch self {
        case .remoteWorker: return "house.fill"
        case .student: return "book.fill"
        case .freelancer: return "briefcase.fill"
        case .officeWorker: return "building.2.fill"
        case .entrepreneur: return "lightbulb.fill"
        case .creative: return "paintbrush.fill"
        case .knowledgeWorker: return "brain.fill"
        case .productManager: return "chart.bar.fill"
        case .researcher: return "magnifyingglass"
        case .other: return "person.fill"
        }
    }
}

// MARK: - User Goal

public enum UserGoal: String, CaseIterable, Sendable, Codable {
    case productivity = "Boost Productivity"
    case habits = "Build Better Habits"
    case procrastination = "Beat Procrastination"
    case workLifeBalance = "Work-Life Balance"
    case focus = "Stay Focused"
    case motivation = "Stay Motivated"

    public var displayName: String { rawValue }

    public var iconName: String {
        switch self {
        case .productivity: return "bolt.fill"
        case .habits: return "repeat"
        case .procrastination: return "clock.arrow.circlepath"
        case .workLifeBalance: return "scale.3d"
        case .focus: return "target"
        case .motivation: return "flame.fill"
        }
    }
}

// MARK: - Companion Style

public enum CompanionStyle: String, CaseIterable, Sendable, Codable {
    case joy = "Joy"
    case silas = "Silas"
    case nova = "Nova"

    public var displayName: String { rawValue }

    public var iconName: String {
        switch self {
        case .joy: return "sparkles"
        case .silas: return "heart.fill"
        case .nova: return "target"
        }
    }

    public var description: String {
        switch self {
        case .joy: return "Joyful, easygoing, and tuned to the small beauty in work"
        case .silas: return "Warm spiritual care that makes work feel held and meaningful"
        case .nova: return "Disciplined focus that filters noise and protects time"
        }
    }
}
