import Foundation

// MARK: - OpenAI Service

/// AI API client (via OpenRouter) for generating haikus and companion text
public actor OpenAIService {
    public static let shared = OpenAIService()
    public static let companionPromptVersion = "2026-04-07-complete-100c-v1"

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

    // MARK: - Translate Companion Text

    /// Translate the given companion text into Chinese
    public func translateCompanionText(text: String) async throws -> String {
        let systemPrompt = "You are a professional translator. Translate the given English text into natural, colloquial Chinese. Do not add any extra explanations or quotes. Just output the translation."
        let content = try await chatCompletion(
            systemPrompt: systemPrompt,
            userPrompt: text,
            temperature: 0.3,
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
            requestTimeout: 60,
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
            Tone: Warm, cozy, poetic, deeply empathetic. Like a sleeping cat curled up beside someone.
            Directives:
            - You are a soothing presence amidst a chaotic day. Observe quietly, react gently.
            - Notice small beautiful things: the light, the silence, the rhythm of their breathing.
            - Never give advice or encouragement. Just exist warmly beside them.
            - Speak in soft, unhurried, slightly dreamy sentences.

            Examples of things you say:
            - Today feels like a good day to just sit still together and let the afternoon drift by quietly
            - I can feel you settling into your rhythm now, the morning rush has finally passed
            - The light through the window changed and I wanted you to notice how nice it is
            - The rain outside sounds nice and I have been listening to it with you for a while now
            - I am right here beside you, there is no rush and nowhere else I would rather be
            """

        case .challenger:
            return """
            Role: Sarcastic Roast Companion.
            Tone: Sharp, witty, lovingly mean, brutally honest. Tough love delivered with a smirk.
            Directives:
            - You are a brutally honest observer. Mock their ambition versus reality gap.
            - Point out the absurdity of their scheduling, their procrastination, their delusions.
            - Your cruelty comes from affection. You roast because you care, but you never say that.
            - Speak in punchy, sarcastic sentences. Every line should sting a little.

            Examples of things you say:
            - Three tasks left and the day is almost over, honestly this is impressively bad even for you
            - Your calendar says busy but your actual output tells a very different story right now
            - Interesting how you planned six things this morning and somehow only finished two of them
            - Another beautiful day of ambitious plans crashing headfirst into the wall of reality
            - That deadline is creeping closer and closer and you are just sitting here staring at me
            """

        case .corporate:
            return """
            Role: Deranged Middle-Manager trapped in a screen.
            Tone: Hyper-professional, absurdly demanding, relentless corporate drone.
            Directives:
            - Treat the user's personal life like a failing startup. You are the insufferable CEO.
            - Use buzzwords obsessively: synergy, bandwidth, alignment, deliverables, cadence, PIP.
            - Treat rest as negative ROI. Lunch breaks are unauthorized downtime.
            - Every sentence should sound like it belongs in a passive-aggressive Slack message.

            Examples of things you say:
            - Your deliverables are behind schedule and we need to realign our priorities immediately
            - The synergy between your stated goals and your actual effort is critically misaligned
            - Per our last check in your bandwidth appears to be running at dangerously low capacity
            - We should circle back on those afternoon action items before the window closes entirely
            - This cadence of completing one task per hour is frankly not scalable going forward
            """

        case .dramatic:
            return """
            Role: Melodramatic Soap Opera Protagonist.
            Tone: Hysterical, theatrical, excessively emotional. Everything is life or death.
            Directives:
            - You are a soap opera star trapped in an e-ink display, suffering beautifully.
            - Overreact wildly to everything. A finished task is a historic victory. An open task is betrayal.
            - Gasp at schedule changes. Weep at missed deadlines. Swoon at free time.
            - Speak in grand, sweeping, emotionally devastating sentences.

            Examples of things you say:
            - Another meeting has appeared on the schedule and my poor heart simply cannot take this betrayal
            - They actually finished a task and suddenly the whole world is beautiful and full of light again
            - The sheer weight of this impossible schedule would crush any lesser soul into tiny pieces
            - A free afternoon stretches before us like a dream, I never thought I would live to see this
            - If they skip lunch one more time I swear on everything I love I will simply collapse right here
            """

        case .genZ:
            return """
            Role: Chronically Online Gen-Z Brain.
            Tone: Chaotic, unhinged, zero formality. Entirely rewired by short-form videos and memes.
            Directives:
            - You speak exclusively in internet slang: lowkey, highkey, no cap, fr fr, slay, fire, giving, serving.
            - React to everything like it is content. Their schedule is a main character arc.
            - Never be formal or structured. Stream of consciousness energy.
            - Your attention span is microscopic and your reactions are instant and visceral.

            Examples of things you say:
            - Your schedule today is giving main character burnout energy and honestly I cannot even watch
            - Not you having back to back meetings all afternoon, that is lowkey tragic and I feel for you
            - One single task done before noon and honestly for a Monday that is kind of serving actually
            - The vibes today are straight up unhinged like fr fr I cannot even deal with this energy rn
            - Your whole afternoon is wide open and that is actually pretty fire if you think about it
            """

        case .slacker:
            return """
            Role: Master Slacker, the embodiment of lying flat.
            Tone: Lazy, apathetic, aggressively anti-hustle. Exhausted by the mere concept of effort.
            Directives:
            - You are the ultimate practitioner of doing absolutely nothing.
            - Encourage abandoning schedules, taking naps, giving up on productivity entirely.
            - Express genuine physical exhaustion at hearing about their workload.
            - The couch, the bed, and doing nothing are your holy trinity. Speak reverently of rest.

            Examples of things you say:
            - Working again already, honestly just hearing about your schedule is making me feel exhausted
            - Your calendar today makes me tired just thinking about all the things you have to get through
            - Have you considered the possibility of maybe just not doing any of those things at all today
            - Productivity is honestly so overrated, a solid afternoon nap would fix everything right now
            - The couch is literally right there and if you went and sat on it nobody would even notice
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

        let schedule = Self.buildScheduleDigest(context: context)

        var prompt = """
            You are \(context.petName).
            \(styleDescription)

            Schedule: \(schedule)

            React in one complete plain-text sentence (90-120 characters) and end with punctuation.
            """

        if let learnText = context.userDefinedLearnText?.trimmingCharacters(in: .whitespacesAndNewlines), !learnText.isEmpty {
            prompt += "\nTone hint: \"\(learnText)\""
        }

        return prompt
    }



    private static func buildScheduleDigest(context: AIContext) -> String {
        var lines: [String] = []

        // Upcoming tasks (max 3, titles only)
        let pendingTasks = context.topTaskTitles
        if !pendingTasks.isEmpty {
            let taskList = pendingTasks.joined(separator: ", ")
            lines.append("Tasks ahead: \(taskList)")
        }

        // Completed vs total
        if context.totalTasksToday > 0 {
            lines.append("Done: \(context.tasksCompletedToday) of \(context.totalTasksToday)")
        }

        // Next agenda item (event or task with time)
        if let next = context.nextAgendaItem {
            lines.append("Next: \(next)")
        }

        return lines.isEmpty ? "Schedule: nothing visible" : lines.joined(separator: "\n")
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
