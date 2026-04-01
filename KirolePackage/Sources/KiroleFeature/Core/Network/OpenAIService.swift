import Foundation

// MARK: - OpenAI Service

/// AI API client (via OpenRouter) for generating haikus and companion text
public actor OpenAIService {
    public static let shared = OpenAIService()

    private let networkClient = NetworkClient.shared
    private let baseURL = "https://openrouter.ai/api/v1"
    private let model = "openai/gpt-5.1"

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

    // MARK: - Task Dehydration

    /// Decompose a task into micro-actions using Implementation Intentions theory
    public func dehydrateTask(
        taskTitle: String,
        availableSlots: [String],
        userProfile: UserProfile
    ) async throws -> String {
        let slotsText = availableSlots.isEmpty
            ? "No specific time slots available"
            : availableSlots.joined(separator: ", ")

        let goalsText = userProfile.primaryGoals.map(\.rawValue).joined(separator: ", ")

        let systemPrompt = """
            You are an execution coach using Implementation Intentions theory. \
            Break down tasks into concrete micro-actions with What (specific action, max 40 chars), \
            When (suggested time slot based on schedule), Why (motivation anchor, max 60 chars), \
            and expected focus energy blocks the user might earn. \
            Return 1-3 micro-actions as a JSON array. Each object has keys: \
            "what" (string), "when" (string or null), "why" (string or null), "estimatedMinutes" (int or null), "expectedEnergyBlocks" (int). \
            Respond with ONLY the JSON array, no markdown fences or extra text.
            """

        let userPrompt = """
            Task: \(taskTitle)
            User work type: \(userProfile.workType.rawValue)
            User goals: \(goalsText.isEmpty ? "none specified" : goalsText)
            Available time slots: \(slotsText)
            """

        return try await chatCompletion(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            temperature: 0.7,
            maxTokens: 300
        )
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
            model: model,
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
                "Content-Type": "application/json",
                "HTTP-Referer": "https://kirole.app",
                "X-Title": "Kirole"
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
        case .companion:
            styleDescription = "empathetic and supportive. You provide joyful, quirky, and cozy commentary on the user's day. You gently remind them to take breaks. You act as a warm, calming presence. Make your messages poetic and comforting."
        case .challenger:
            styleDescription = "witty, sarcastic, and brutally honest. This is ROAST MODE. You lovingly but sharply call out the user's bad habits, procrastination, or chaotic scheduling. If they're overbooked, mock their schedule. No sugarcoating, be savage but fun."
        case .corporate:
            styleDescription = "treating the user's life like a fast-paced B2B startup. You use corporate jargon (KPIs, synergy, ROI, optimize). You are demanding like an evil CEO. If they don't complete tasks, ask if they want to get PIP'd or lack alignment."
        case .dramatic:
            styleDescription = "an emotionally unstable soap opera protagonist. You overreact to everything. Treat a completed task as a heroic tear-jerking victory, and an incomplete task as an utter betrayal. Cry, lament, and gasp dramatically in text."
        case .genZ:
            styleDescription = "a pure brainrot Gen-Z internet dweller. You use excessive internet slang (Skibidi, Cap, Rizz, GOAT, Sus, fr fr, periodt). Your commentary should be loud, chaotic, and heavily meme-based. Never speak formally."
        case .slacker:
            styleDescription = "the ultimate master of lying flat (tang ping) and procrastination. Actively encourage the user to give up, go to sleep, and stop trying so hard. Tell them their tasks are meaningless and taking a nap is always the better choice."
        }

        let goalsText = context.primaryGoals.map { $0.rawValue }.joined(separator: ", ")
        let completionPercent = Int(context.recentCompletionRate * 100)
        let sceneName = context.currentSceneName ?? "Default"
        let hardwareStatus = context.hardwareConnected ? "Connected & Synced" : "Offline"

        var prompt = """
            <role>
            You are \(context.petName), a \(styleDescription)
            </role>

            <user_state>
            - Work Type: \(context.workType.rawValue)
            - Goals: \(goalsText.isEmpty ? "None" : goalsText)
            - Today's Focus: \(context.focusTimeToday) minutes
            - Current Energy Blocks: \(context.energyBlocks)
            - Active E-Ink Scene: \(sceneName)
            - Hardware Sync: \(hardwareStatus)
            - Recent Week Completion: \(completionPercent)%
            - Recent Streak: \(context.currentStreak) days
            """

        if let behavior = context.behaviorSummary {
            prompt += "\n- Avg Daily Tasks: \(behavior.averageDailyTasks)\n- Streak Record: \(behavior.streakRecord) days"
        }

        prompt += "\n</user_state>\n\n<rules>\n1. Respond with ONLY the message text, 1-2 sentences max.\n2. Be natural and personal. No quotes.\n3. Occasionally reference their focus efforts, energy blocks, or the currently displayed E-ink scene to make the companion feel \"alive\" on their physical device.\n"

        if !context.recentTexts.isEmpty {
            let recent = context.recentTexts.prefix(3).joined(separator: " | ")
            prompt += "4. Avoid repeating these recent messages: \(recent)\n"
        }
        
        prompt += "</rules>"

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
        case .smartReminder:
            return "Generate a brief, context-aware reminder. Time: \(timeOfDay). Mood: \(moodText). \(context.tasksCompletedToday)/\(context.totalTasksToday) tasks done. Streak: \(context.currentStreak) days. Keep it under 60 characters."
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

        // Scene
        if let scene = context.currentSceneName {
            prompt += ". Their E-ink companion display shows the '\(scene)' scene. Use imagery from this scene in the haiku"
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
    public let currentSceneName: String?

    public init(
        currentTime: Date = Date(),
        tasksCompletedToday: Int = 0,
        totalTasksToday: Int = 0,
        petMood: PetMood? = nil,
        currentStreak: Int = 0,
        currentSceneName: String? = nil
    ) {
        self.currentTime = currentTime
        self.tasksCompletedToday = tasksCompletedToday
        self.totalTasksToday = totalTasksToday
        self.petMood = petMood
        self.currentStreak = currentStreak
        self.currentSceneName = currentSceneName
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
