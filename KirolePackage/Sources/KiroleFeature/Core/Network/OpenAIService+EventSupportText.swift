import Foundation

// MARK: - Event Support Text

extension OpenAIService {
    /// One numbered event as fed to the support-text prompt: the title carries the content, the
    /// category number selects which of the customer's six writing rules the model must obey.
    struct EventSupportTextInput: Sendable, Equatable {
        let title: String
        let category: EventCategory
        /// Whether today's schedule reads as busy (see `FallbackText.isDayBusy`).
        ///
        /// The client's Wellness rule is "if the schedule looks packed, acknowledge that, then give
        /// a gentle nudge" — a per-event title and category cannot express that, so the density is
        /// computed App-side from the day's start/end times and passed in as a flag. Surfaces in the
        /// prompt for Wellness ONLY: that is the one category the client made schedule-dependent.
        let isDayPacked: Bool

        init(title: String, category: EventCategory, isDayPacked: Bool = false) {
            self.title = title
            self.category = category
            self.isDayPacked = isDayPacked
        }
    }

    /// Generates the per-event support line shown while an event is in progress (§4.7 Events[]
    /// SupportText). One batched call for the whole day, mirroring `classifyEventCategories`:
    /// the reply is machine-parsed `N|text` lines and any misalignment throws so the caller can
    /// fall back to the per-category template pool.
    ///
    /// Returns lines in input order, one per input event.
    func generateEventSupportTexts(events: [EventSupportTextInput]) async throws -> [String] {
        guard !events.isEmpty else { return [] }
        let compiled = compileEventSupportTextPrompt(events: events)
        let tool = Self.promptTool("eventSupportText")
        let content = try await chatCompletion(
            systemPrompt: compiled.systemPrompt,
            userPrompt: compiled.userPrompt,
            temperature: tool.parameters.temperature,
            maxTokens: tool.parameters.maxTokens
        )
        return try Self.parseSupportTextReply(content, expectedCount: events.count)
    }

    private func compileEventSupportTextPrompt(
        events: [EventSupportTextInput]
    ) -> (systemPrompt: String, userPrompt: String) {
        let tool = Self.promptTool("eventSupportText")
        let numberedList = events.enumerated()
            .map { index, event in
                let title = PromptSanitizer.sanitize(event.title, maxLen: 120)
                // The density hint rides along for Wellness only — the one category the client made
                // schedule-dependent. Adding it elsewhere would invite the model to mention
                // busyness in a Deep Work or Deadline line, where the rule says point at the first
                // step / steady the nerves and nothing else.
                let densityHint = Self.densityHint(for: event)
                return "\(index + 1). [category \(event.category.rawValue)\(densityHint)] \(title)"
            }
            .joined(separator: "\n")
        let userPrompt = KirolePromptSpec.render(
            Self.promptTemplate(tool.userPromptTemplates, named: "default"),
            values: ["numberedEvents": numberedList]
        )
        return (
            systemPrompt: PromptSanitizer.systemPrompt(
                containingUserContent: tool.systemPromptTemplate
            ),
            userPrompt: "<user_content>\(userPrompt)</user_content>"
        )
    }

    /// `, packed day` / `, open day` for Wellness; empty for every other category.
    ///
    /// Wellness is the only category whose client rule reads the schedule. Rest is about granting
    /// permission regardless of how the day went, so handing it a density hint would invite
    /// unrequested "the day has been full" wording — scope the App does not get to widen.
    ///
    /// Kept as a static helper so the Studio's TypeScript builder can mirror it exactly — the
    /// cross-runtime golden fixtures compare the compiled prompt byte for byte.
    static func densityHint(for event: EventSupportTextInput) -> String {
        switch event.category {
        case .wellness:
            return event.isDayPacked ? ", packed day" : ", open day"
        case .unknown, .deepWork, .meetings, .admin, .deadline, .rest:
            return ""
        }
    }

    func compileEventSupportTextPromptForFixture(
        events: [EventSupportTextInput]
    ) -> (systemPrompt: String, userPrompt: String) {
        compileEventSupportTextPrompt(events: events)
    }

    /// Parses the strict `N|line` reply. Throws `malformedResponse` unless every index 1...n is
    /// present exactly once with non-empty text — a partial reply must fall back wholesale rather
    /// than silently pair a line with the wrong event.
    static func parseSupportTextReply(_ reply: String, expectedCount: Int) throws -> [String] {
        var byIndex: [Int: String] = [:]
        for rawLine in reply.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            guard let separator = line.firstIndex(of: "|") else {
                throw OpenAIError.malformedResponse
            }
            guard let index = Int(line[line.startIndex..<separator]
                .trimmingCharacters(in: .whitespaces)),
                (1...expectedCount).contains(index),
                byIndex[index] == nil else { throw OpenAIError.malformedResponse }
            let text = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw OpenAIError.malformedResponse }
            byIndex[index] = text
        }
        guard byIndex.count == expectedCount else { throw OpenAIError.malformedResponse }
        return try (1...expectedCount).map {
            guard let text = byIndex[$0] else { throw OpenAIError.malformedResponse }
            return text
        }
    }
}
