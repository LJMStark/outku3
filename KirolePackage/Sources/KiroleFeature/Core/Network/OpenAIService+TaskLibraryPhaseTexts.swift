import Foundation

extension OpenAIService {
    func generateTaskLibraryPhaseTexts(
        task: TaskItem,
        userProfile: UserProfile,
        customCompanion: CustomCompanion?
    ) async throws -> TaskLibraryPhaseTexts {
        let tool = Self.promptTool("taskLibraryPhaseText")
        let compiled = await compileTaskLibraryPhasePrompt(
            task: task,
            userProfile: userProfile,
            customCompanion: customCompanion
        )
        let content = try await chatCompletion(
            systemPrompt: compiled.systemPrompt,
            userPrompt: compiled.userPrompt,
            temperature: tool.parameters.temperature,
            maxTokens: tool.parameters.maxTokens
        )
        let lines = try Self.parseSupportTextReply(content, expectedCount: 3)
        return TaskLibraryPhaseTexts(
            starting: lines[0],
            building: lines[1],
            deep: lines[2]
        )
    }

    func compileTaskLibraryPhasePromptForFixture(
        task: TaskItem,
        userProfile: UserProfile
    ) async -> (systemPrompt: String, userPrompt: String) {
        await compileTaskLibraryPhasePrompt(
            task: task,
            userProfile: userProfile,
            customCompanion: nil
        )
    }

    private func compileTaskLibraryPhasePrompt(
        task: TaskItem,
        userProfile: UserProfile,
        customCompanion: CustomCompanion?
    ) async -> (systemPrompt: String, userPrompt: String) {
        let tool = Self.promptTool("taskLibraryPhaseText")
        let persona: String
        if let customCompanion {
            persona = Self.customCompanionPersonaPrompt(customCompanion)
        } else {
            persona = """
                \(Self.characterPrompt(for: userProfile.companionCharacter))
                \(Self.intimacyPrompt(for: userProfile.intimacyStage))
                \(Self.defaultPrompt(for: userProfile.companionStyle))
                """
        }
        let systemPrompt = PromptSanitizer.systemPrompt(
            containingUserContent: "\(persona)\n\n\(tool.systemPromptTemplate)"
        )
        return (
            systemPrompt: systemPrompt,
            userPrompt: Self.compileTaskLibraryPhaseUserPrompt(task: task)
        )
    }

    static func compileTaskLibraryPhaseUserPrompt(task: TaskItem) -> String {
        let tool = promptTool("taskLibraryPhaseText")
        return KirolePromptSpec.render(
            promptTemplate(tool.userPromptTemplates, named: "default"),
            values: [
                "taskTitle": PromptSanitizer.userContent(task.title, maxLen: 120),
                "taskNotes": PromptSanitizer.userContent(task.notes ?? "", maxLen: 300)
            ]
        )
    }
}
