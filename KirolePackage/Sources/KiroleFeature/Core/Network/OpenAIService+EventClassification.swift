import Foundation

// MARK: - Event Classification

extension OpenAIService {
    /// Classifies calendar events into the six customer-defined categories (§4.7 Category byte,
    /// v2.5.27). One batched call: numbered event list in, one line of category digits out —
    /// classification is a lookup, not prose, so the reply is machine-parsed and misalignment
    /// throws (caller falls back to the keyword heuristic).
    public func classifyEventCategories(events: [String]) async throws -> [EventCategory] {
        guard !events.isEmpty else { return [] }
        let systemPrompt = PromptSanitizer.systemPrompt(containingUserContent: """
            Classify each numbered calendar event inside <user_content> into exactly ONE category:
            \(EventCategory.promptDefinitions)
            Reply with ONLY the category numbers in input order, comma-separated, one per event \
            (example for 3 events: 2,5,1). No words, no explanation.
            """)
        let numberedList = events.enumerated()
            .map { "\($0.offset + 1). \(PromptSanitizer.sanitize($0.element, maxLen: 120))" }
            .joined(separator: "\n")
        let content = try await chatCompletion(
            systemPrompt: systemPrompt,
            userPrompt: "<user_content>\(numberedList)</user_content>",
            temperature: 0.0,
            maxTokens: 60
        )
        return try Self.parseCategoryReply(content, expectedCount: events.count)
    }

    /// Parses a strict category-only reply ("2,5,1", with optional whitespace/newlines).
    /// Throws `malformedResponse` when the digit count does not match the input count or any
    /// digit is outside 1-6 (0/unknown is never a valid model answer).
    static func parseCategoryReply(_ reply: String, expectedCount: Int) throws -> [EventCategory] {
        let digits = reply
            .components(separatedBy: CharacterSet.decimalDigits.inverted)
            .filter { !$0.isEmpty }
        guard digits.count == expectedCount else { throw OpenAIError.malformedResponse }
        return try digits.map {
            guard let value = UInt8($0),
                  let category = EventCategory(rawValue: value),
                  category != .unknown else {
                throw OpenAIError.malformedResponse
            }
            return category
        }
    }
}
