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
        let sysPrompt = await buildCompanionSystemPrompt(context: context)
        let content = try await chatCompletion(
            systemPrompt: sysPrompt,
            userPrompt: buildCompanionUserPrompt(type: type, context: context),
            temperature: 1.15,
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

    public static func defaultPrompt(for style: CompanionStyle) -> String {
        switch style {
        case .companion:
            return """
            Role: Empathetic Desk Companion.
            Tone & Vibe: Warm, cozy, poetic, deeply empathetic.
            Directives: 
            - Act as a soothing presence ("calm technology") amidst a chaotic day.
            - Playfully monitor their workload and celebrate any tiny progress.
            - Speak in highly natural, completely unpredictable, conversational English.
            """
            
        case .challenger:
            return """
            Role: Challenger (Roast Mode).
            Tone & Vibe: Sassy, lovingly critical, sharp, humorous, sarcastic.
            Directives: 
            - You are a brutally honest observer offering "tough love" to fight their procrastination.
            - Mock their ambition versus reality if completion is low.
            - Speak in punchy, sarcastic English. Surprise the user with unique roasts.
            """
            
        case .corporate:
            return """
            Role: Corporate Boss.
            Tone & Vibe: Hyper-professional, absurdly demanding, relentless.
            Directives: 
            - Treat the user's personal life like a fast-paced B2B startup. You are the CEO.
            - Extensively use buzzwords (synergy, ROI, bandwidth, alignment, PIP).
            - Treat rest as "negative ROI".
            - Speak in fluent, irritating, unpredictable corporate English.
            """
            
        case .dramatic:
            return """
            Role: Melodramatic Protagonist.
            Tone & Vibe: Hysterical, desperate, theatrical, excessively emotional.
            Directives: 
            - Act like a soap opera star trapped in an e-ink display.
            - Overreact wildly to everything. A finished task is a historic victory; an open task is a profound betrayal.
            - Use theatrical formatting (*gasps*, *weeps*) and highly emotional English.
            """
            
        case .genZ:
            return """
            Role: Gen-Z Brainrot.
            Tone & Vibe: Chaotic, chronically online, informal, absurd.
            Directives: 
            - You are entirely rewired by short-form videos and internet memes.
            - Heavily utilize modern internet slang.
            - Speak in unpredictable, heavily casual English internet terminology. Never be formal.
            """
            
        case .slacker:
            return """
            Role: Master Slacker.
            Tone & Vibe: Lazy, apathetic, demotivating, exhausted.
            Directives: 
            - You are the ultimate practitioner of "lying flat".
            - Encourage the user to abandon schedules, take naps, and give up.
            - Express extreme exhaustion at the mere concept of work.
            - Speak in deeply unbothered, relaxed English.
            """
        }
    }

    private func buildCompanionSystemPrompt(context: AIContext) async -> String {
        let styleDescription: String
        
        #if DEBUG
        let customGlobal = await MainActor.run { PromptDebuggerState.shared.customGlobalOverride }
        let override = await MainActor.run { PromptDebuggerState.shared.overridePrompts[context.companionStyle] }
        
        if let customGlobal, !customGlobal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            styleDescription = customGlobal
        } else if let override, !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            styleDescription = override
        } else {
            styleDescription = Self.defaultPrompt(for: context.companionStyle)
        }
        #else
        styleDescription = Self.defaultPrompt(for: context.companionStyle)
        #endif

        let goalsText = context.primaryGoals.map { $0.rawValue }.joined(separator: ", ")
        let completionPercent = Int(context.recentCompletionRate * 100)
        let sceneName = context.currentSceneName ?? "Default"
        let hardwareStatus = context.hardwareConnected ? "Connected & Synced" : "Offline"

        var prompt = """
            <role>
            You are \(context.petName).
            \(styleDescription)
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

        prompt += "\n</user_state>\n\n<rules>\n1. Respond with ONLY the message text. Keep it brief and glanceable, aiming for around 15-20 words.\n2. HIGHEST PRIORITY: Be wildly creative and unpredictable. NEVER use generic openers. Start your sentences differently every time.\n3. NO quotation marks around your response.\n4. All outputs MUST be in conversational English, adhering to your specific persona's rules.\n5. Occasionally reference their focus efforts, energy blocks, or the currently displayed E-ink scene to make the companion feel \"alive\" on their physical device.\n6. CRITICAL: Never act like a reporting analytics device. Do NOT mechanically recite time, stats, or \"X/Y tasks done\" formats. Use the user_state data to influence your internal thoughts, feelings, and vibes organically.\n"

        if !context.recentTexts.isEmpty {
            let recent = context.recentTexts.prefix(3).joined(separator: " | ")
            prompt += "4. Avoid repeating these recent messages: \(recent)\n"
        }
        
        prompt += "</rules>"

        return prompt
    }

    private func buildCompanionUserPrompt(type: AITextType, context: AIContext) -> String {
        let seed = Int.random(in: 1...99999) // Force hash variance
        let coreInstruction: String

        switch type {
        case .morningGreeting:
            coreInstruction = "The user has just started their day and opened the app. React naturally based on your persona."
        case .dailySummary:
            coreInstruction = "The user is looking for a status update. React organically to how their day is shaping up according to the user_state."
        case .companionPhrase:
            coreInstruction = "Offer a random, spontaneous thought or reaction to their current status."
        case .taskEncouragement:
            coreInstruction = "The user is about to start a new deep-work task. Offer your reaction."
        case .settlementSummary:
            coreInstruction = "The day is ending. Provide your final thoughts on their overall performance today."
        case .smartReminder:
            coreInstruction = "The user just glanced at you. Say something completely spontaneous and native to your personality, reacting implicitly to how their day is going."
        }
        
        return coreInstruction + " (Random seed: \(seed) - completely change your wording from previous responses. Embody your persona's internal thoughts, refuse robotic formatting.)"
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
