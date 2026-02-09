import Foundation

// MARK: - OpenAI Service

/// OpenAI API client for generating haikus and companion text
public actor OpenAIService {
    public static let shared = OpenAIService()

    private let networkClient = NetworkClient.shared
    private let baseURL = "https://api.openai.com/v1"

    // TODO: Read from environment variable or secure storage
    private var apiKey: String = ""

    private init() {}

    // MARK: - Configuration

    public var isConfigured: Bool { !apiKey.isEmpty }

    /// Configure the API key
    public func configure(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - Generate Haiku

    /// Generate a haiku based on the current context
    public func generateHaiku(context: HaikuContext) async throws -> Haiku {
        let content = try await chatCompletion(
            systemPrompt: haikuSystemPrompt,
            userPrompt: buildHaikuPrompt(context: context),
            temperature: 0.8,
            maxTokens: 100
        )
        return parseHaiku(content)
    }

    // MARK: - Generate Companion Text

    /// Generate AI companion text based on type and context
    public func generateCompanionText(type: AITextType, context: AIContext) async throws -> String {
        let content = try await chatCompletion(
            systemPrompt: buildCompanionSystemPrompt(context: context),
            userPrompt: buildCompanionUserPrompt(type: type, context: context),
            temperature: 0.9,
            maxTokens: 150
        )
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Chat Completion

    /// Shared helper that sends a chat completion request and returns the response content
    private func chatCompletion(
        systemPrompt: String,
        userPrompt: String,
        temperature: Double,
        maxTokens: Int
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            throw OpenAIError.notConfigured
        }

        let request = ChatCompletionRequest(
            model: "gpt-4o-mini",
            messages: [
                ChatMessage(role: "system", content: systemPrompt),
                ChatMessage(role: "user", content: userPrompt)
            ],
            temperature: temperature,
            maxTokens: maxTokens
        )

        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw OpenAIError.invalidURL
        }

        let response: ChatCompletionResponse = try await networkClient.post(
            url: url,
            headers: [
                "Authorization": "Bearer \(apiKey)",
                "Content-Type": "application/json"
            ],
            body: request,
            responseType: ChatCompletionResponse.self
        )

        guard let content = response.choices.first?.message.content else {
            throw OpenAIError.emptyResponse
        }

        return content
    }

    // MARK: - Companion Prompt Building

    private func buildCompanionSystemPrompt(context: AIContext) -> String {
        let styleDescription: String
        switch context.companionStyle {
        case .encouraging:
            styleDescription = "warm and supportive. You celebrate small wins, offer gentle encouragement, and always remind the user they're doing great. Use a caring, nurturing tone."
        case .strict:
            styleDescription = "direct and accountability-focused. You give honest feedback, set clear expectations, and push the user to do better. Be constructive but firm."
        case .playful:
            styleDescription = "fun and challenge-oriented. You turn tasks into adventures, use playful language, create mini-challenges, and keep things light and exciting."
        case .calm:
            styleDescription = "peaceful and mindful. You encourage balance, use serene language, remind the user to breathe, and focus on well-being over hustle."
        }

        let goalsText = context.primaryGoals.map { $0.rawValue }.joined(separator: ", ")
        let completionPercent = Int(context.recentCompletionRate * 100)

        var prompt = """
            You are \(context.petName), a \(styleDescription)
            The user is a \(context.workType.rawValue)\(goalsText.isEmpty ? "" : ", with goals: \(goalsText)").
            Recent behavior: \(completionPercent)% completion rate this week, \(context.currentStreak)-day streak.
            """

        if let behavior = context.behaviorSummary {
            prompt += "\nAverage \(behavior.averageDailyTasks) tasks/day. Streak record: \(behavior.streakRecord) days."
        }

        if !context.recentTexts.isEmpty {
            let recent = context.recentTexts.prefix(3).joined(separator: " | ")
            prompt += "\nAvoid repeating these recent messages: \(recent)"
        }

        prompt += "\nRespond with ONLY the message text, 1-2 sentences max. Be natural and personal. No quotes."

        return prompt
    }

    private func buildCompanionUserPrompt(type: AITextType, context: AIContext) -> String {
        let timeOfDay = TimeOfDay.current(at: context.currentTime).rawValue
        let moodText = context.petMood.rawValue.lowercased()

        switch type {
        case .morningGreeting:
            return "Generate a morning greeting. It's \(timeOfDay). You're feeling \(moodText). Today has \(context.totalTasksToday) tasks and \(context.eventsToday) events."
        case .dailySummary:
            return "Summarize today's schedule: \(context.totalTasksToday) tasks, \(context.eventsToday) events. Time: \(timeOfDay)."
        case .companionPhrase:
            return "Generate an encouraging companion phrase for the \(timeOfDay). \(context.tasksCompletedToday)/\(context.totalTasksToday) tasks done. You're feeling \(moodText)."
        case .taskEncouragement:
            return "Encourage the user who is about to work on a task. Time: \(timeOfDay). Mood: \(moodText)."
        case .settlementSummary:
            let rate = context.totalTasksToday > 0 ? Int(Double(context.tasksCompletedToday) / Double(context.totalTasksToday) * 100) : 0
            return "Summarize the day: \(context.tasksCompletedToday)/\(context.totalTasksToday) tasks completed (\(rate)%). Streak: \(context.currentStreak) days."
        }
    }

    // MARK: - Haiku Prompt Building

    private var haikuSystemPrompt: String {
        """
        You are a haiku poet who creates gentle, encouraging haikus for a productivity app.
        Your haikus should:
        - Follow the 5-7-5 syllable structure
        - Be calming and motivational
        - Reference nature, seasons, or daily life
        - Be appropriate for any time of day
        - Never be negative or discouraging

        Respond with ONLY the haiku, three lines, no additional text.
        """
    }

    private func buildHaikuPrompt(context: HaikuContext) -> String {
        var prompt = "Create a haiku for someone"

        // Time context
        let hour = Calendar.current.component(.hour, from: context.currentTime)
        if hour < 6 {
            prompt += " in the early morning hours"
        } else if hour < 12 {
            prompt += " starting their morning"
        } else if hour < 17 {
            prompt += " in the afternoon"
        } else if hour < 21 {
            prompt += " in the evening"
        } else {
            prompt += " winding down for the night"
        }

        // Task completion status
        if context.tasksCompletedToday > 0 {
            prompt += " who has completed \(context.tasksCompletedToday) task(s) today"
        }

        if context.totalTasksToday > 0 {
            let remaining = context.totalTasksToday - context.tasksCompletedToday
            if remaining > 0 {
                prompt += " with \(remaining) task(s) remaining"
            } else {
                prompt += " and finished all their tasks"
            }
        }

        // Pet mood
        if let petMood = context.petMood {
            prompt += ". Their pet companion is feeling \(petMood.rawValue.lowercased())"
        }

        // Streak
        if context.currentStreak > 0 {
            prompt += ". They're on a \(context.currentStreak)-day streak"
        }

        prompt += "."

        return prompt
    }

    // MARK: - Parse Response

    private func parseHaiku(_ content: String) -> Haiku {
        let lines = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Ensure we have 3 lines
        if lines.count >= 3 {
            return Haiku(lines: Array(lines.prefix(3)))
        } else if lines.count == 1 {
            // Try splitting by punctuation
            let parts = lines[0].components(separatedBy: CharacterSet(charactersIn: "/|"))
            if parts.count >= 3 {
                return Haiku(lines: Array(parts.prefix(3).map { $0.trimmingCharacters(in: .whitespaces) }))
            }
        }

        // Return default haiku
        return .placeholder
    }
}

// MARK: - Haiku Context

public struct HaikuContext: Sendable {
    public let currentTime: Date
    public let tasksCompletedToday: Int
    public let totalTasksToday: Int
    public let petMood: PetMood?
    public let currentStreak: Int

    public init(
        currentTime: Date = Date(),
        tasksCompletedToday: Int = 0,
        totalTasksToday: Int = 0,
        petMood: PetMood? = nil,
        currentStreak: Int = 0
    ) {
        self.currentTime = currentTime
        self.tasksCompletedToday = tasksCompletedToday
        self.totalTasksToday = totalTasksToday
        self.petMood = petMood
        self.currentStreak = currentStreak
    }
}

// MARK: - OpenAI Error

public enum OpenAIError: LocalizedError, Sendable {
    case notConfigured
    case emptyResponse
    case rateLimited
    case invalidAPIKey
    case invalidURL

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "OpenAI API key not configured"
        case .emptyResponse:
            return "Empty response from OpenAI"
        case .rateLimited:
            return "Rate limited - please try again later"
        case .invalidAPIKey:
            return "Invalid API key"
        case .invalidURL:
            return "Invalid API URL"
        }
    }
}

// MARK: - OpenAI API Models

private struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
    }
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ChatCompletionResponse: Codable {
    let choices: [ChatChoice]
}

private struct ChatChoice: Codable {
    let message: ChatMessage
}
