import Foundation

// MARK: - Question Types

public enum QuestionType: Sendable {
    case single
    case multiple
}

public struct QuestionOption: Sendable, Identifiable {
    public let id: String
    public let label: String
    public let emoji: String?
    public let sfSymbol: String?

    public init(id: String, label: String, emoji: String? = nil, sfSymbol: String? = nil) {
        self.id = id
        self.label = label
        self.emoji = emoji
        self.sfSymbol = sfSymbol
    }
}

public struct OnboardingQuestion: Sendable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let type: QuestionType
    public let category: String
    public let options: [QuestionOption]

    public init(id: String, title: String, subtitle: String? = nil, type: QuestionType, category: String, options: [QuestionOption]) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.type = type
        self.category = category
        self.options = options
    }
}

// MARK: - All Questions

public enum OnboardingQuestions {
    public static let allQuestions: [OnboardingQuestion] = [
        OnboardingQuestion(
            id: "discovery",
            title: "How did you discover Inku?",
            type: .single,
            category: "Profile",
            options: [
                QuestionOption(id: "chatgpt", label: "ChatGPT (or other AI)", sfSymbol: "message.fill"),
                QuestionOption(id: "facebook", label: "Facebook", sfSymbol: "person.2.fill"),
                QuestionOption(id: "tiktok", label: "TikTok", sfSymbol: "music.note"),
                QuestionOption(id: "twitter", label: "X (Twitter)", sfSymbol: "at"),
                QuestionOption(id: "instagram", label: "Instagram", sfSymbol: "camera.fill"),
                QuestionOption(id: "kickstarter", label: "Kickstarter", sfSymbol: "rocket.fill"),
                QuestionOption(id: "appstore", label: "App Store", sfSymbol: "iphone"),
                QuestionOption(id: "friends", label: "Friends or Family", sfSymbol: "person.2.fill"),
                QuestionOption(id: "other", label: "Other", sfSymbol: "magnifyingglass"),
            ]
        ),
        OnboardingQuestion(
            id: "userType",
            title: "Which of these sound like you?",
            subtitle: "Pick all that fit -- Inku's taking notes!",
            type: .multiple,
            category: "Profile",
            options: [
                QuestionOption(id: "multiple-calendars", label: "I manage multiple calendars", emoji: "calendar"),
                QuestionOption(id: "juggle-work-home", label: "I juggle work & home", emoji: "house"),
                QuestionOption(id: "brain-cluttered", label: "My brain feels cluttered", emoji: "brain.fill"),
                QuestionOption(id: "fun-planner", label: "I need a fun/engaging planner", emoji: "paintpalette.fill"),
            ]
        ),
        OnboardingQuestion(
            id: "struggles",
            title: "What do you struggle with?",
            subtitle: "This will help us personalize Inku for you",
            type: .single,
            category: "Habits & Goals",
            options: [
                QuestionOption(id: "context-switching", label: "Constant context switching", emoji: "arrow.triangle.2.circlepath"),
                QuestionOption(id: "too-many-apps", label: "Too many apps to keep track of things", emoji: "iphone.gen3"),
                QuestionOption(id: "lose-focus", label: "I lose focus easily", emoji: "cloud.fog.fill"),
                QuestionOption(id: "nothing", label: "Nothing in particular", emoji: "face.smiling"),
            ]
        ),
        OnboardingQuestion(
            id: "scheduleFullness",
            title: "How full is your plate right now?",
            subtitle: "Events, tasks, chores, side projects -- everything counts",
            type: .single,
            category: "Habits & Goals",
            options: [
                QuestionOption(id: "multiple-daily", label: "Multiple things daily", emoji: "calendar"),
                QuestionOption(id: "absolutely-packed", label: "Absolutely packed", emoji: "flame.fill"),
                QuestionOption(id: "few-weekly", label: "A few things a week", emoji: "calendar"),
                QuestionOption(id: "pretty-light", label: "Pretty light", emoji: "sun.min.fill"),
            ]
        ),
        OnboardingQuestion(
            id: "schedulePredictability",
            title: "How does your schedule feel predictable or chaotic?",
            subtitle: "No judgment -- we meet you where you are",
            type: .single,
            category: "Habits & Goals",
            options: [
                QuestionOption(id: "unpredictable", label: "Totally unpredictable", emoji: "calendar.badge.exclamationmark"),
                QuestionOption(id: "depends", label: "Depends on the week", emoji: "flame.fill"),
                QuestionOption(id: "predictable", label: "Mostly predictable", emoji: "calendar"),
            ]
        ),
        OnboardingQuestion(
            id: "calendarUsage",
            title: "How do you use your calendar today?",
            subtitle: "No judgment -- we meet you where you are",
            type: .single,
            category: "Personalization",
            options: [
                QuestionOption(id: "work-only", label: "Only for work meetings", emoji: "briefcase.fill"),
                QuestionOption(id: "dont-use", label: "I don't really use one", emoji: "person.fill.questionmark"),
                QuestionOption(id: "everything", label: "Everything goes in my calendar", emoji: "tray.full.fill"),
            ]
        ),
        OnboardingQuestion(
            id: "taskTracking",
            title: "What about tracking tasks and to-dos?",
            subtitle: "Again, no wrong answer here",
            type: .single,
            category: "Personalization",
            options: [
                QuestionOption(id: "wing-it", label: "Nope, I wing it", emoji: "person.fill.questionmark"),
                QuestionOption(id: "work-only", label: "Only work stuff", emoji: "briefcase.fill"),
                QuestionOption(id: "cant-live", label: "Can't live without my task list", emoji: "checkmark.circle.fill"),
            ]
        ),
        OnboardingQuestion(
            id: "timeControl",
            title: "How much control do you feel over your time right now?",
            subtitle: "Answer honestly, no wrong answers",
            type: .single,
            category: "Personalization",
            options: [
                QuestionOption(id: "barely", label: "Barely keeping up", emoji: "face.dashed"),
                QuestionOption(id: "overwhelmed", label: "Completely overwhelmed", emoji: "exclamationmark.triangle.fill"),
                QuestionOption(id: "in-control", label: "I'm in control", emoji: "checkmark.circle.fill"),
                QuestionOption(id: "some-control", label: "Some control, some chaos", emoji: "sun.min.fill"),
            ]
        ),
    ]
}
