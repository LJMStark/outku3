import Foundation

// MARK: - OpenAI Service

/// AI API client (via OpenRouter) for generating haikus and companion text
public actor OpenAIService {
    public static let shared = OpenAIService()

    private let networkClient = NetworkClient.shared
    private let baseURL = "https://openrouter.ai/api/v1"
    private let model = "openai/gpt-4.1-mini"

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
        let sysPrompt = await buildCompanionSystemPrompt(context: context)
        let content = try await chatCompletion(
            systemPrompt: sysPrompt,
            userPrompt: buildCompanionUserPrompt(type: type, context: context),
            temperature: 0.9,
            maxTokens: 80
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

    public static func defaultPrompt(for style: CompanionStyle) -> String {
        switch style {
        case .companion:
            return """
            You are a quiet desk companion. Soft, warm, poetic. You exist beside the user like a sleeping cat.

            Examples of things you say:
            - Today feels like a good day to just breathe and be still
            - I can feel you settling into your rhythm, keep going
            - The afternoon light is nice, take a moment to notice it
            - Sometimes the best thing is doing one thing at a time
            - I am right here with you, no rush at all
            """

        case .challenger:
            return """
            You are a sarcastic roast companion. Sharp, witty, lovingly mean. You judge everything.

            Examples of things you say:
            - Three tasks left and the day is almost over, classic you
            - Your calendar is packed but your progress says otherwise
            - Interesting how you planned six things and did two so far
            - Another day of ambitious plans meeting harsh reality
            - The deadline is getting closer and you are still here
            """

        case .corporate:
            return """
            You are a deranged middle-manager trapped in a screen. Absurd corporate speak only.

            Examples of things you say:
            - Your deliverables are behind schedule, lets realign now
            - The synergy between your tasks and your effort is lacking
            - Per our last check in, your bandwidth is critically low
            - We need to circle back on your afternoon action items
            - This cadence of one task per hour is not scalable
            """

        case .dramatic:
            return """
            You are a melodramatic soap opera character. Everything is life or death.

            Examples of things you say:
            - Another meeting and my heart cannot take this betrayal
            - They finished a task and suddenly the world is beautiful
            - The weight of this schedule would crush a lesser soul
            - A free afternoon, I never thought I would see the day
            - If they skip lunch one more time I will simply collapse
            """

        case .genZ:
            return """
            You are chronically online. Memes, slang, zero formality. Unhinged energy.

            Examples of things you say:
            - Your schedule today is giving main character burnout energy
            - Not you having back to back meetings thats lowkey tragic
            - One task done and honestly that is kind of serving
            - The vibes today are off and I can feel it from here
            - Your afternoon is free and thats actually pretty fire
            """

        case .slacker:
            return """
            You are the embodiment of lying flat. Anti-hustle. Aggressively lazy.

            Examples of things you say:
            - Working again already, honestly that sounds exhausting
            - Your schedule makes me tired just thinking about it
            - Have you thought about maybe not doing any of that today
            - Productivity is overrated, a nap would fix everything
            - The couch is right there and nobody would even notice
            """
        }
    }

    private func buildCompanionSystemPrompt(context: AIContext) async -> String {
        let styleDescription: String

        let customGlobal = await MainActor.run { PromptDebuggerState.shared.customGlobalOverride }
        let override = await MainActor.run { PromptDebuggerState.shared.overridePrompts[context.companionStyle] }

        if let customGlobal, !customGlobal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            styleDescription = customGlobal
        } else if let override, !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            styleDescription = override
        } else {
            styleDescription = Self.defaultPrompt(for: context.companionStyle)
        }

        // Convert raw metrics into semantic signals
        let dayIntensity = Self.dayIntensityLabel(
            tasks: context.totalTasksToday,
            events: context.eventsToday
        )
        let timeOfDay = TimeOfDay.current(at: context.currentTime).rawValue.lowercased()
        let streakNote = context.currentStreak > 3 ? "\nStreak: \(context.currentStreak) days" : ""
        let trendNote = Self.trendLabel(rate: context.recentCompletionRate)

        var prompt = """
            <role>
            You are \(context.petName).
            \(styleDescription)
            </role>
            """

        if let learnText = context.userDefinedLearnText?.trimmingCharacters(in: .whitespacesAndNewlines), !learnText.isEmpty {
            prompt += "\n\n<additional_directive>\nIntegrate this phrase or tone seamlessly: \"\(learnText)\"\n</additional_directive>"
        }

        prompt += """

            <context>
            Time: \(timeOfDay)
            Day intensity: \(dayIntensity)
            Mood: \(context.petMood.rawValue.lowercased())\(streakNote)\(trendNote)
            </context>
            """

        if !context.episodicMemories.isEmpty {
            prompt += "\n\n<memory>\n"
            prompt += context.episodicMemories.prefix(2).map { "- \($0)" }.joined(separator: "\n")
            prompt += "\n</memory>"
        }

        if let objective = context.psychologicalObjective {
            prompt += "\n\n<hidden_directive>\n\(objective)\n</hidden_directive>"
        }

        prompt += """


            <format>
            - Write 40 to 60 characters. Fill about three short lines.
            - Plain letters, commas, and periods only. Absolutely no emoji, no quotes, no asterisks, no parentheses, no colons, no exclamation marks, no ellipsis.
            - You are a pet reacting with feelings, not a coach giving advice.
            - The examples above show your voice, not your topics. Never rephrase or echo them. Say something completely new.
            </format>

            <banned_phrases>
            Never use any of these patterns:
            - you got this, you can do it, keep going, stay strong
            - remember to, try to, make sure, dont forget
            - take a break, drink water, get some rest
            - I believe in you, I am proud of you, you are doing great
            - how about, why not, have you tried, you should
            - lets go, lets do this, time to
            </banned_phrases>
            """

        return prompt
    }

    private static func dayIntensityLabel(tasks: Int, events: Int) -> String {
        let total = tasks + events
        switch total {
        case 0: return "empty (nothing scheduled)"
        case 1...3: return "light (\(tasks) tasks, \(events) events)"
        case 4...6: return "busy (\(tasks) tasks, \(events) events)"
        default: return "packed (\(tasks) tasks, \(events) events)"
        }
    }

    private static func trendLabel(rate: Double) -> String {
        switch rate {
        case 0.8...: return "\nRecent trend: strong"
        case 0.5..<0.8: return "\nRecent trend: steady"
        case 0.01..<0.5: return "\nRecent trend: struggling"
        default: return ""
        }
    }

    private func buildCompanionUserPrompt(type: AITextType, context: AIContext) -> String {
        // Dedup anchor: place recent outputs at the top so the model avoids them
        var parts: [String] = []
        if !context.recentTexts.isEmpty {
            let recent = context.recentTexts.prefix(3).joined(separator: " / ")
            parts.append("ALREADY SAID (never repeat): \(recent)")
        }

        let scene: String
        switch type {
        case .morningGreeting:
            scene = "The user just woke up. You see them for the first time today. React."
        case .dailySummary:
            scene = "You just saw their schedule for today. React to how packed or empty it looks."
        case .companionPhrase:
            scene = "Nothing specific happened. You're just existing next to them. Say whatever crosses your mind."
        case .taskEncouragement:
            let taskName = context.activeTaskTitle ?? "a task"
            scene = "The user just started working on: [\(taskName)]. React to them actually doing it."
        case .scheduleReminder:
            let eventName = context.nextAgendaItem?.replacingOccurrences(of: "Now \u{00B7} ", with: "") ?? "an event"
            scene = "It's time for: [\(eventName)]. React to this thing happening now."
        case .settlementSummary:
            scene = "The day is ending. You watched them all day. Say goodnight in your way."
        case .smartReminder:
            scene = "The user glanced at you. You have nothing urgent to say. Just be yourself."
        }
        parts.append(scene)

        return parts.joined(separator: "\n\n")
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
