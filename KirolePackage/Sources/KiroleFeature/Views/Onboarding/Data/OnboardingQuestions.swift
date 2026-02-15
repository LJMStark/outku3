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
            id: "companionStyle",
            title: "How should Kirole talk to you?",
            subtitle: "This shapes how your companion communicates",
            type: .single,
            category: "Companion Personality",
            options: [
                QuestionOption(id: "Encouraging", label: "Like a supportive friend", sfSymbol: "heart.fill"),
                QuestionOption(id: "Strict", label: "Like a no-nonsense coach", sfSymbol: "scope"),
                QuestionOption(id: "Playful", label: "Like a playful buddy", sfSymbol: "star.fill"),
                QuestionOption(id: "Calm", label: "Like a calm mentor", sfSymbol: "leaf.fill"),
            ]
        ),
        OnboardingQuestion(
            id: "motivationStyle",
            title: "When you're falling behind, what helps most?",
            subtitle: "Kirole will adjust its encouragement to match",
            type: .single,
            category: "Companion Personality",
            options: [
                QuestionOption(id: "encouragement", label: "Gentle encouragement and patience", sfSymbol: "heart.fill"),
                QuestionOption(id: "reality-check", label: "A direct reality check", sfSymbol: "exclamationmark.triangle.fill"),
                QuestionOption(id: "gamify", label: "Making it feel like a game", sfSymbol: "gamecontroller.fill"),
                QuestionOption(id: "space", label: "Quiet space to figure it out", sfSymbol: "leaf.fill"),
            ]
        ),
        OnboardingQuestion(
            id: "calendarUsage",
            title: "How do you use your calendar today?",
            subtitle: "Helps Kirole understand your scheduling style",
            type: .single,
            category: "Calendar & Task Habits",
            options: [
                QuestionOption(id: "work-only", label: "Only for work meetings", sfSymbol: "briefcase.fill"),
                QuestionOption(id: "dont-use", label: "I don't really use one", sfSymbol: "person.fill.questionmark"),
                QuestionOption(id: "everything", label: "Everything goes in my calendar", sfSymbol: "tray.full.fill"),
            ]
        ),
        OnboardingQuestion(
            id: "taskTracking",
            title: "What about tracking tasks and to-dos?",
            subtitle: "No wrong answer here",
            type: .single,
            category: "Calendar & Task Habits",
            options: [
                QuestionOption(id: "wing-it", label: "Nope, I wing it", sfSymbol: "person.fill.questionmark"),
                QuestionOption(id: "work-only", label: "Only work stuff", sfSymbol: "briefcase.fill"),
                QuestionOption(id: "cant-live", label: "Can't live without my task list", sfSymbol: "checkmark.circle.fill"),
            ]
        ),
        OnboardingQuestion(
            id: "distractionSources",
            title: "What pulls you away from deep work?",
            subtitle: "This helps Kirole know when to step in",
            type: .multiple,
            category: "Distraction & Reminders",
            options: [
                QuestionOption(id: "notifications", label: "Phone notifications", sfSymbol: "bell.fill"),
                QuestionOption(id: "app-switching", label: "Switching between apps", sfSymbol: "arrow.triangle.2.circlepath"),
                QuestionOption(id: "meetings", label: "Meetings and interruptions", sfSymbol: "person.2.fill"),
                QuestionOption(id: "wandering-mind", label: "My own wandering mind", sfSymbol: "cloud.fill"),
            ]
        ),
        OnboardingQuestion(
            id: "reminderPreference",
            title: "How would you like to be reminded?",
            subtitle: "Kirole can nudge you in different ways",
            type: .single,
            category: "Distraction & Reminders",
            options: [
                QuestionOption(id: "gentleNudge", label: "Gentle nudges throughout the day", sfSymbol: "bell.fill"),
                QuestionOption(id: "deadline", label: "Only when deadlines are close", sfSymbol: "clock.fill"),
                QuestionOption(id: "streakProtect", label: "Protect my streaks at all costs", sfSymbol: "flame.fill"),
                QuestionOption(id: "minimal", label: "I'll check on my own", sfSymbol: "hand.raised.fill"),
            ]
        ),
        OnboardingQuestion(
            id: "taskApproach",
            title: "How do you handle complex tasks?",
            subtitle: "Kirole can help break things down for you",
            type: .single,
            category: "Focus & Tasks",
            options: [
                QuestionOption(id: "self-break", label: "I break them down myself", sfSymbol: "list.bullet"),
                QuestionOption(id: "jump-in", label: "I jump in and figure it out", sfSymbol: "bolt.fill"),
                QuestionOption(id: "procrastinate", label: "I procrastinate until pressure hits", sfSymbol: "clock.arrow.circlepath"),
                QuestionOption(id: "need-help", label: "I need help getting started", sfSymbol: "questionmark.circle.fill"),
            ]
        ),
        OnboardingQuestion(
            id: "timeControl",
            title: "How much control do you feel over your time?",
            subtitle: "Be honest -- no judgment here",
            type: .single,
            category: "Focus & Tasks",
            options: [
                QuestionOption(id: "barely", label: "Barely keeping up", sfSymbol: "face.dashed"),
                QuestionOption(id: "overwhelmed", label: "Completely overwhelmed", sfSymbol: "exclamationmark.triangle.fill"),
                QuestionOption(id: "in-control", label: "I'm in control", sfSymbol: "checkmark.circle.fill"),
                QuestionOption(id: "some-control", label: "Some control, some chaos", sfSymbol: "sun.min.fill"),
            ]
        ),
    ]
}
