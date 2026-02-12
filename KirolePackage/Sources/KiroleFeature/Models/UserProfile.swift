import Foundation

// MARK: - User Profile

public struct UserProfile: Sendable, Codable, Equatable {
    public var workType: WorkType
    public var primaryGoals: [UserGoal]
    public var companionStyle: CompanionStyle
    public var onboardingCompletedAt: Date?

    public init(
        workType: WorkType = .other,
        primaryGoals: [UserGoal] = [],
        companionStyle: CompanionStyle = .encouraging,
        onboardingCompletedAt: Date? = nil
    ) {
        self.workType = workType
        self.primaryGoals = primaryGoals
        self.companionStyle = companionStyle
        self.onboardingCompletedAt = onboardingCompletedAt
    }

    public static var `default`: UserProfile {
        UserProfile()
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
    case encouraging = "Encouraging"
    case strict = "Strict"
    case playful = "Playful"
    case calm = "Calm"

    public var displayName: String { rawValue }

    public var iconName: String {
        switch self {
        case .encouraging: return "heart.fill"
        case .strict: return "scope"
        case .playful: return "star.fill"
        case .calm: return "leaf.fill"
        }
    }

    public var description: String {
        switch self {
        case .encouraging: return "Gentle reminders and celebrations"
        case .strict: return "Direct feedback and accountability"
        case .playful: return "Fun challenges and rewards"
        case .calm: return "Mindful reminders and peace"
        }
    }
}
