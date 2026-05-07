import Observation

/// Production preference for which OpenRouter/OpenAI model is used to generate
/// companion dialogue. Read by `OpenAIService.generateCompanionText` at request time.
///
/// Currently the value is only mutated via the debug-only PromptDebugger UI.
/// Release builds use the default model id. When a production model-selection UI
/// ships, it should write this same singleton.
@Observable
@MainActor
public final class CompanionModelPreference {
    public static let shared = CompanionModelPreference()
    public var modelID: String = OpenAIService.defaultChatModelID
    private init() {}
}
