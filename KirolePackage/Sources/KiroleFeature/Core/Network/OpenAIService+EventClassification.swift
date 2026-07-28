import Foundation

// MARK: - Event Classification

extension OpenAIService {
    /// Classifies calendar events into the six customer-defined categories (§4.7 Category byte,
    /// v2.5.27). One batched call: numbered event list in, one line of category digits out —
    /// classification is a lookup, not prose, so the reply is machine-parsed and misalignment
    /// throws (caller falls back to the keyword heuristic).
    public func classifyEventCategories(events: [String]) async throws -> [EventCategory] {
        guard !events.isEmpty else { return [] }
        let compiled = compileEventClassificationPrompt(events: events)
        guard let tool = KirolePromptSpec.tool("eventClassification") else {
            preconditionFailure("PromptSpec is missing eventClassification")
        }
        let content = try await chatCompletion(
            systemPrompt: compiled.systemPrompt,
            userPrompt: compiled.userPrompt,
            temperature: tool.parameters.temperature,
            maxTokens: tool.parameters.maxTokens
        )
        return try Self.parseCategoryReply(content, expectedCount: events.count)
    }

    private func compileEventClassificationPrompt(
        events: [String]
    ) -> (systemPrompt: String, userPrompt: String) {
        guard let tool = KirolePromptSpec.tool("eventClassification") else {
            preconditionFailure("PromptSpec is missing eventClassification")
        }
        let systemPrompt = PromptSanitizer.systemPrompt(
            containingUserContent: KirolePromptSpec.render(
                tool.systemPromptTemplate,
                values: [
                    "categoryDefinitions": KirolePromptSpec.document.eventCategoryDefinitions
                ]
            )
        )
        let numberedList = events.enumerated()
            .map { "\($0.offset + 1). \(PromptSanitizer.sanitize($0.element, maxLen: 120))" }
            .joined(separator: "\n")
        guard let userTemplate = tool.userPromptTemplates["default"] else {
            preconditionFailure("PromptSpec is missing eventClassification.default")
        }
        let userPrompt = KirolePromptSpec.render(
            userTemplate,
            values: ["numberedEvents": numberedList]
        )
        return (
            systemPrompt: systemPrompt,
            userPrompt: "<user_content>\(userPrompt)</user_content>"
        )
    }

    func compileEventClassificationPromptForFixture(
        events: [String]
    ) -> (systemPrompt: String, userPrompt: String) {
        compileEventClassificationPrompt(events: events)
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
