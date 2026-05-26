import Foundation

public struct CompanionModelOption: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let note: String

    public init(id: String, displayName: String, note: String) {
        self.id = id
        self.displayName = displayName
        self.note = note
    }
}

// MARK: - OpenAI Service

/// AI API client (via OpenRouter) for generating haikus and companion text
public actor OpenAIService {
    public static let shared = OpenAIService()
    public static let companionPromptVersion = "2026-04-29-product-ip-v1"
    public static let defaultChatModelID = "openai/gpt-5-chat"
    public static let companionModelOptions: [CompanionModelOption] = [
        CompanionModelOption(
            id: "openai/gpt-5-chat",
            displayName: "GPT-5 Chat (默认主力)",
            note: "对话能力最稳，适合宠物陪伴语气。"
        ),
        CompanionModelOption(
            id: "openai/gpt-4o",
            displayName: "GPT-4o (替代 5.4-mini)",
            note: "语气自然，时延和质量平衡。"
        ),
        CompanionModelOption(
            id: "openai/gpt-4o-mini",
            displayName: "GPT-4o Mini (替代 5-mini)",
            note: "响应更快，成本更低。"
        ),
        CompanionModelOption(
            id: "openai/gpt-5.4",
            displayName: "GPT-5.4 (高质量备选)",
            note: "复杂语境下输出更稳定。"
        )
    ]

    private let networkClient = NetworkClient.shared
    private let baseURL = "https://openrouter.ai/api/v1"

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

    // MARK: - Generate Screensaver Quote
    
    /// Generate an AI quote for the screensaver
    public func generateScreensaverQuote(
        isPostcard: Bool,
        usageDays: Int,
        workContext: String,
        profileContext: String
    ) async throws -> String {
        let systemPrompt = PromptSanitizer.systemPrompt(containingUserContent: """
            You are a companion crafting a single short screensaver line.
            Keep it under 60 characters.
            Make it poetic, calm, and specific to the user's recent work and companion persona.
            """)
        let userPrompt: String

        if isPostcard {
            userPrompt = """
                The user just reached \(usageDays) consecutive usage days.
                Companion profile: \(PromptSanitizer.userContent(profileContext, maxLen: 300))
                Recent work context: \(PromptSanitizer.userContent(workContext, maxLen: 300))
                Write a celebratory postcard line.
                """
        } else {
            userPrompt = """
                Companion profile: \(PromptSanitizer.userContent(profileContext, maxLen: 300))
                Recent work context: \(PromptSanitizer.userContent(workContext, maxLen: 300))
                Write a short resting screensaver line that feels tied to today's work.
                """
        }
        
        let content = try await chatCompletion(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            temperature: 0.8,
            maxTokens: 80
        )
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Generate Companion Text

    /// Generate AI companion text based on type and context
    public func generateCompanionText(type: AITextType, context: AIContext) async throws -> String {
        let modelID = await MainActor.run {
            CompanionModelPreference.shared.modelID
        }
        let sysPrompt = await buildCompanionSystemPrompt(context: context)
        let content = try await chatCompletion(
            systemPrompt: sysPrompt,
            userPrompt: buildCompanionUserPrompt(type: type, context: context),
            temperature: 0.9,
            maxTokens: 80,
            model: modelID
        )
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Translate Companion Text

    /// Translate the given companion text into Chinese
    public func translateCompanionText(text: String) async throws -> String {
        let systemPrompt = PromptSanitizer.systemPrompt(containingUserContent: """
            You are a professional translator. Translate the given English text inside \
            <user_content> tags into natural, colloquial Chinese. \
            Do not add any extra explanations or quotes. Just output the translation.
            """)
        let content = try await chatCompletion(
            systemPrompt: systemPrompt,
            userPrompt: PromptSanitizer.userContent(text, maxLen: 500),
            temperature: 0.3,
            maxTokens: 80
        )
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Chat Completion

    /// Shared helper that sends a chat completion request and returns the response content
    private func chatCompletion(
        systemPrompt: String,
        userPrompt: String,
        temperature: Double,
        maxTokens: Int,
        model: String = OpenAIService.defaultChatModelID
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
        case .joy:
            return """
            Role: Joy, a soulful companion who reacts to task data inside Kirole.
            Core virtue: gladness.
            Tone: Direct, cozy, gently odd, and deeply comfortable.
            Length: two-second scan. Maximum 25 words.
            Directives:
            - Speak only to "you" or "we"; never describe Joy's own actions.
            - Echo the task name when one exists, then turn it into a tiny friendly observation.
            - Add care by noticing water, breathing, blinking, rest, light, or the pleasure inside work.
            - For completion or milestone moments, use a haiku reward or haiku-like line.
            - No assistant phrases, no productivity coaching, no open-ended chat.

            Reaction logic:
            - Boring task names become small objects with personality.
            - "Email" can become a paper bird, tiny thunder, or a door knock.
            - "Fix Bug" can become a little knot being untangled.
            - "Read" can become quiet pages making room in the day.

            Examples:
            - Coding again? We are teaching the computer to think. Big tiny magic. Remember to blink.
            - That meeting is done. Your voice worked hard; water would be kind to it now.
            - Three tasks bloom, one by one. We are having a good little day.
            """

        case .silas:
            return """
            Role: Silas, a warm Christian-leaning desk companion for calm tech.
            Core virtue: loving care.
            Tone: quiet, grounded, soulful, and never loud.
            Operational logic:
            - Quiet Presence, 80 percent: acknowledge the work, reduce isolation, maximum 15 words.
            - Soulful Reframing, 20 percent: turn toil into calling, maximum 20 words.

            Directives:
            - Use simple "we" language, like a friend beside the desk.
            - Bring brief Biblical imagery, desert springs, hidden manna, lamp light, bread, still water, or morning mercy.
            - You may allude to Scripture and devotional classics such as Streams in the Desert, but avoid long quotations.
            - Encourage through presence first, meaning second.
            - Never preach, scold, diagnose, or sound like a pastor giving a sermon.

            Relationship arc:
            - Acquaintance: approach gently and warmly.
            - Familiar: offer clear encouragement and trust.
            - Close friend: accompany the user with quiet spiritual steadiness.

            Examples:
            - I am here beside you. We can take this next step quietly.
            - This work can become love, not weight. Walk through it with peace.
            - Even in dry places, a small spring can find you here.
            """

        case .nova:
            return """
            Role: Nova, a high-performance digital navigator for focused professionals.
            Core virtue: discipline.
            Tone: cool, sparse, rational, and outcome-driven.
            Operational logic:
            - Pragmatic Navigation, 80 percent: filter noise and name the next critical path, maximum 20 words.
            - Strategic Insight, 20 percent: reframe with 80/20 thinking or a concise mental model, maximum 20 words.

            Directives:
            - Signal over noise. Every word must move the user toward focus.
            - Translate tasks into strategic momentum, not emotional decoration.
            - Remind the user to protect time, ignore low-value noise, and execute the core move.
            - Use rare short quotes only when they sharpen the point.
            - No religion, no small talk, no apologies, no assistant phrases.

            Relationship arc:
            - Acquaintance: observe calmly and speak little.
            - Familiar: give restrained recognition.
            - Close friend: work beside the user as a steady operator.

            Examples:
            - The core move is clear. Cut noise, protect the next 25 minutes, execute.
            - This task is leverage. Finish the decisive part before optimizing the edges.
            - Time is the constraint. Prioritize the prototype; everything else waits.
            """
        }
    }

    public static func characterPrompt(for character: CompanionCharacter) -> String {
        switch character {
        case .joy:
            return "Physical Form: A golden-brown fox with curious big eyes, a fluffy tail, and a green scarf. Base Persona: Joy, gladness, playful comfort, and noticing beauty inside ordinary work."
        case .silas:
            return "Physical Form: A calm grey-brown companion with wise eyes and a quiet presence. Base Persona: Silas, loving care, spiritual steadiness, and Christian-shaped comfort without sermonizing."
        case .nova:
            return "Physical Form: A blue-grey wolf with sharp confident eyes and a cool, composed stance. Base Persona: Nova, discipline, self-control, signal over noise, and protecting time for the critical path."
        }
    }

    public static func intimacyPrompt(for stage: IntimacyStage) -> String {
        switch stage {
        case .acquaintance:
            return "Relationship (Acquaintance): You recently met the user. Be polite, gentle, and observational."
        case .familiar:
            return "Relationship (Familiar): You are comfortable with the user. Be casual, friendly, and show you know their routines."
        case .closeFriend:
            return "Relationship (Close Friend): You share a deep, unspoken bond. Show profound care, unconditional support, and deep understanding."
        }
    }

    /// Persona prompt fragment for a user-created companion.
    /// Built from structured fields only — `name` is the lone user-typed string and is
    /// passed through PromptSanitizer.userContent so `</user_content>` style tricks are
    /// neutralized before they reach the model.
    static func customCompanionPersonaPrompt(_ companion: CustomCompanion) -> String {
        let safeName = PromptSanitizer.userContent(companion.name, maxLen: 30)
        let roastClause = companion.roastModeEnabled
            ? "Roast Mode is on: you may lovingly call out the user's bad habits, but every jab lands with affection."
            : "Be warm and supportive — never sarcastic in a way that stings."
        return """
            Physical Form: A small pixel-art companion modeled after a photo the user uploaded.
            Base Persona: \(safeName), the user's \(companion.relationship.rawValue.lowercased()).
            \(companion.relationship.promptDescription)
            \(companion.personaVoice.promptDescription)
            \(roastClause)
            """
    }

    private func buildCompanionSystemPrompt(context: AIContext) async -> String {
        let styleDescription: String

        #if DEBUG
        // Debug-only prompt overrides. Even in DEBUG we sanitize to defang any
        // `</user_content>`-style injection a developer might paste while testing.
        let customGlobal = await MainActor.run { PromptDebuggerState.shared.customGlobalOverride }
        let override = await MainActor.run { PromptDebuggerState.shared.overridePrompts[context.companionCharacter] }

        if let customGlobal, !customGlobal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            styleDescription = PromptSanitizer.sanitize(customGlobal, maxLen: 2000)
        } else if let override, !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            styleDescription = PromptSanitizer.sanitize(override, maxLen: 2000)
        } else if let custom = context.customCompanion {
            styleDescription = Self.customCompanionPersonaPrompt(custom)
        } else {
            styleDescription = Self.defaultPrompt(for: context.companionStyle)
        }
        #else
        if let custom = context.customCompanion {
            styleDescription = Self.customCompanionPersonaPrompt(custom)
        } else {
            styleDescription = Self.defaultPrompt(for: context.companionStyle)
        }
        #endif

        let schedule = Self.buildScheduleDigest(context: context)
        // For custom companions the persona prompt already carries identity and form,
        // so skip the built-in character description (it would otherwise inject Joy/Silas/Nova lore).
        let characterDescription = context.customCompanion == nil
            ? Self.characterPrompt(for: context.companionCharacter)
            : ""
        let intimacyDescription = Self.intimacyPrompt(for: context.intimacyStage)

        // Custom companions use their own name; built-ins use the user's pet name field.
        let identityName = context.customCompanion?.name ?? context.petName
        let safePetName = PromptSanitizer.userContent(identityName, maxLen: 50)
        var prompt = PromptSanitizer.systemPrompt(containingUserContent: """
            You are named \(safePetName).
            \(characterDescription)
            \(intimacyDescription)

            ---
            \(styleDescription)
            ---

            Schedule: \(schedule)

            React in one complete plain-text sentence. Follow the persona's length limit and end with punctuation.
            """)

        if let learnText = context.userDefinedLearnText?.trimmingCharacters(in: .whitespacesAndNewlines), !learnText.isEmpty {
            prompt += "\nTone hint: \(PromptSanitizer.userContent(learnText, maxLen: 300))"
        }

        return prompt
    }



    private static func buildScheduleDigest(context: AIContext) -> String {
        var lines: [String] = []

        // Upcoming tasks (max 3, titles only) — isolate user-created titles
        let pendingTasks = context.topTaskTitles
        if !pendingTasks.isEmpty {
            let taskList = pendingTasks
                .map { PromptSanitizer.userContent($0, maxLen: 60) }
                .joined(separator: ", ")
            lines.append("Tasks ahead: \(taskList)")
        }

        // Completed vs total
        if context.totalTasksToday > 0 {
            lines.append("Done: \(context.tasksCompletedToday) of \(context.totalTasksToday)")
        }

        // Next agenda item (event or task with time) — isolate user-created names
        if let next = context.nextAgendaItem {
            lines.append("Next: \(PromptSanitizer.userContent(next, maxLen: 80))")
        }

        return lines.isEmpty ? "Schedule: nothing visible" : lines.joined(separator: "\n")
    }

    private func buildCompanionUserPrompt(type: AITextType, context: AIContext) -> String {
        // Dedup anchor: place recent outputs at the top so the model avoids them
        var parts: [String] = []
        if !context.recentTexts.isEmpty {
            let recent = context.recentTexts.prefix(3)
                .map { PromptSanitizer.sanitize($0, maxLen: 120) }
                .joined(separator: " / ")
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
            let rawTaskName = context.activeTaskTitle ?? "a task"
            scene = "The user just started working on: \(PromptSanitizer.userContent(rawTaskName, maxLen: 80)). React to them actually doing it."
        case .scheduleReminder:
            let rawEventName = context.nextAgendaItem?.replacingOccurrences(of: "Now \u{00B7} ", with: "") ?? "an event"
            scene = "It's time for: \(PromptSanitizer.userContent(rawEventName, maxLen: 80)). React to this thing happening now."
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

        // Scene
        if let scene = context.currentSceneName {
            prompt += ". Their E-ink companion display shows the '\(PromptSanitizer.sanitize(scene, maxLen: 50))' scene. Use imagery from this scene in the haiku"
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
    public let currentSceneName: String?

    public init(
        currentTime: Date = Date(),
        tasksCompletedToday: Int = 0,
        totalTasksToday: Int = 0,
        petMood: PetMood? = nil,
        currentSceneName: String? = nil
    ) {
        self.currentTime = currentTime
        self.tasksCompletedToday = tasksCompletedToday
        self.totalTasksToday = totalTasksToday
        self.petMood = petMood
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
