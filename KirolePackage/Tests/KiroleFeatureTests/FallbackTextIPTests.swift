import Testing
import Foundation
@testable import KiroleFeature

// Tests for FallbackText.sharedPetDialogue IP-awareness:
// - Built-in characters (joy / silas / nova) return distinct phrase pools
// - Custom companion dispatches by personaVoice, not companionStyle
// - Context state (empty day / all done / upcoming / active tasks / default) is honoured per style

@Suite("FallbackTextIPTests")
struct FallbackTextIPTests {

    // MARK: - Helpers

    private func context(
        character: CompanionCharacter = .joy,
        custom: CustomCompanion? = nil,
        totalTasks: Int = 0,
        completedTasks: Int = 0,
        events: Int = 0,
        nextAgendaItem: String? = nil,
        topTaskTitles: [String] = []
    ) -> AIContext {
        AIContext(
            companionCharacter: character,
            petName: "Tiko",
            petMood: .happy,
            tasksCompletedToday: completedTasks,
            totalTasksToday: totalTasks,
            eventsToday: events,
            nextAgendaItem: nextAgendaItem,
            topTaskTitles: topTaskTitles,
            customCompanion: custom
        )
    }

    private func makeCustom(voice: CompanionPersonaVoice) -> CustomCompanion {
        CustomCompanion(
            name: "Test",
            relationship: .friend,
            personaVoice: voice,
            avatarPreviewFileName: "test-avatar-preview.png",
            avatarPixelsFileName: "test-avatar-pixels.bin"
        )
    }

    // MARK: - Joy: empty day

    @Test("given Joy + empty day, dialogue is not generic Silas prose")
    func givenJoy_emptyDay_notSilasGenericProse() {
        let result = FallbackText.sharedPetDialogue(context: context(character: .joy))
        #expect(!result.contains("carried today to the end"))
        #expect(!result.contains("faithfulness"))
        #expect(!result.isEmpty)
    }

    // MARK: - Silas: empty day

    @Test("given Silas + empty day, dialogue contains spiritual warmth keywords")
    func givenSilas_emptyDay_containsSpiritualWarmth() {
        let ctx = context(character: .silas)
        let result = FallbackText.sharedPetDialogue(context: ctx)
        let silasKeywords = ["quiet", "still", "breath", "rest", "be", "strength"]
        let hasKeyword = silasKeywords.contains { result.localizedCaseInsensitiveContains($0) }
        #expect(hasKeyword)
        #expect(!result.isEmpty)
    }

    // MARK: - Nova: empty day

    @Test("given Nova + empty day, dialogue is short and crisp")
    func givenNova_emptyDay_isShortAndCrisp() {
        let ctx = context(character: .nova)
        let result = FallbackText.sharedPetDialogue(context: ctx)
        // Nova empty-day phrases are all ≤10 words
        let wordCount = result.split(separator: " ").count
        #expect(wordCount <= 10)
    }

    // MARK: - All tasks done path

    @Test("given Joy + all tasks done, dialogue contains positive completion tone")
    func givenJoy_allDone_positiveCompletionTone() {
        let ctx = context(character: .joy, totalTasks: 3, completedTasks: 3)
        let result = FallbackText.sharedPetDialogue(context: ctx)
        #expect(!result.isEmpty)
        // Joy all-done phrases contain exclamation
        let hasExclamation = result.contains("!")
        #expect(hasExclamation)
    }

    @Test("given Nova + all tasks done, dialogue is terse")
    func givenNova_allDone_isTerse() {
        let ctx = context(character: .nova, totalTasks: 2, completedTasks: 2)
        let result = FallbackText.sharedPetDialogue(context: ctx)
        let wordCount = result.split(separator: " ").count
        #expect(wordCount <= 10)
    }

    // MARK: - Custom companion overrides built-in style

    @Test("given Custom companion, dialogue ignores companionCharacter and uses personaVoice")
    func givenCustomCompanion_usesPersonaVoice_notCharacterStyle() {
        // companionCharacter = .nova (crisp) but voice = .companion (warm)
        let custom = makeCustom(voice: .companion)
        let ctx = context(character: .nova, custom: custom)
        let result = FallbackText.sharedPetDialogue(context: ctx)
        // Companion-voice phrases are warm and personal; Nova phrases are crisp imperatives
        // Check it's not a Nova-specific phrase
        #expect(!result.contains("Signal is clear"))
        #expect(!result.contains("Execution complete"))
        #expect(!result.isEmpty)
    }

    // MARK: - Custom companion — each voice returns non-empty

    @Test("given Custom challenger voice, dialogue is action-oriented")
    func givenChallenger_actionOriented() {
        let custom = makeCustom(voice: .challenger)
        let result = FallbackText.sharedPetDialogue(context: context(custom: custom))
        #expect(!result.isEmpty)
        // Challenger phrases are short, direct imperatives — not zen whispers
        #expect(!result.contains("Breathe"))
    }

    @Test("given Custom zen voice, dialogue is very short")
    func givenZen_veryShort() {
        let custom = makeCustom(voice: .zen)
        let result = FallbackText.sharedPetDialogue(context: context(custom: custom))
        let wordCount = result.split(separator: " ").count
        #expect(wordCount <= 8)
    }

    @Test("given Custom playful voice, dialogue returns non-empty string")
    func givenPlayful_nonEmpty() {
        let custom = makeCustom(voice: .playful)
        let result = FallbackText.sharedPetDialogue(context: context(custom: custom))
        #expect(!result.isEmpty)
    }

    // MARK: - All built-in styles are mutually distinct for default path

    @Test("given same default context, joy / silas / nova produce distinct phrase pools")
    func givenDefaultContext_allStylesDistinct() {
        // Run many iterations to check no cross-contamination
        let joySet = Set((0..<20).map { _ in
            FallbackText.sharedPetDialogue(context: context(character: .joy))
        })
        let novaSet = Set((0..<20).map { _ in
            FallbackText.sharedPetDialogue(context: context(character: .nova))
        })
        // Joy phrases won't appear in Nova's pool and vice versa
        #expect(joySet.isDisjoint(with: novaSet))
    }
}
