import Testing
import Foundation
@testable import KiroleFeature

// Tests for CustomCompanion Kindroid step 1:
// - New fields decode with defaults from pre-Kindroid JSON
// - OpenAIService.customCompanionPersonaPrompt includes all dimensions
// - levelDescription maps threshold ranges correctly

@Suite("CustomCompanionPersonaTests")
struct CustomCompanionPersonaTests {

    private func makeCompanion(
        curiosity: Double = 0.5,
        humor: Double = 0.5,
        strictness: Double = 0.3,
        backstory: String = "",
        sensitiveBoundary: String = "",
        roastMode: Bool = false
    ) -> CustomCompanion {
        CustomCompanion(
            name: "Mochi",
            relationship: .pet,
            personaVoice: .companion,
            curiosityLevel: curiosity,
            humorLevel: humor,
            strictnessLevel: strictness,
            backstory: backstory,
            sensitiveBoundary: sensitiveBoundary,
            roastModeEnabled: roastMode,
            avatarPreviewFileName: "test-preview.png",
            avatarPixelsFileName: "test-pixels.bin"
        )
    }

    // MARK: - Backward-compatible decoding

    @Test("given pre-Kindroid JSON without new fields, decoding uses defaults")
    func givenPreKindroidJSON_decodesWithDefaults() throws {
        let json = """
        {
            "id": "00000000-0000-0000-0000-000000000001",
            "name": "Legacy",
            "relationship": "Friend",
            "personaVoice": "Companion",
            "roastModeEnabled": false,
            "avatarPreviewFileName": "prev.png",
            "avatarPixelsFileName": "pix.bin",
            "createdAt": 0
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let companion = try decoder.decode(CustomCompanion.self, from: json)

        #expect(companion.curiosityLevel == 0.5)
        #expect(companion.humorLevel == 0.5)
        #expect(companion.strictnessLevel == 0.3)
        #expect(companion.backstory == "")
        #expect(companion.sensitiveBoundary == "")
    }

    // MARK: - Prompt includes all dimensions

    @Test("given companion with default levels, prompt contains all three dimension labels")
    func givenDefaultLevels_promptContainsDimensionLabels() {
        let companion = makeCompanion()
        let prompt = OpenAIService.customCompanionPersonaPrompt(companion)

        #expect(prompt.contains("Curiosity:"))
        #expect(prompt.contains("Humor:"))
        #expect(prompt.contains("Accountability:"))
    }

    @Test("given companion with backstory, prompt includes backstory content")
    func givenBackstory_promptIncludesIt() {
        let companion = makeCompanion(backstory: "A wise cat who loves philosophy.")
        let prompt = OpenAIService.customCompanionPersonaPrompt(companion)

        #expect(prompt.contains("Backstory:"))
        #expect(prompt.contains("philosophy"))
    }

    @Test("given empty backstory, prompt does not contain Backstory label")
    func givenEmptyBackstory_promptExcludesLabel() {
        let companion = makeCompanion(backstory: "")
        let prompt = OpenAIService.customCompanionPersonaPrompt(companion)

        #expect(!prompt.contains("Backstory:"))
    }

    @Test("given sensitiveBoundary set, prompt uses boundary text instead of roast clause")
    func givenSensitiveBoundary_promptUsesBoundary() {
        let companion = makeCompanion(sensitiveBoundary: "No work stress please.", roastMode: true)
        let prompt = OpenAIService.customCompanionPersonaPrompt(companion)

        #expect(prompt.contains("Topic boundary set by user:"))
        #expect(prompt.contains("No work stress please."))
        // Roast Mode clause should NOT appear when boundary overrides it
        #expect(!prompt.contains("Roast Mode:"))
    }

    @Test("given roastMode true and no boundary, prompt uses roast clause")
    func givenRoastModeTrue_noBoundary_promptUsesRoastClause() {
        let companion = makeCompanion(sensitiveBoundary: "", roastMode: true)
        let prompt = OpenAIService.customCompanionPersonaPrompt(companion)

        #expect(prompt.contains("Roast Mode:"))
        #expect(!prompt.contains("Topic boundary set by user:"))
    }

    @Test("given roastMode false and no boundary, prompt uses warm supportive clause")
    func givenRoastModeFalse_noBoundary_promptIsWarm() {
        let companion = makeCompanion(sensitiveBoundary: "", roastMode: false)
        let prompt = OpenAIService.customCompanionPersonaPrompt(companion)

        #expect(prompt.contains("warm and supportive"))
    }

    // MARK: - Level description thresholds

    @Test("given low curiosity (0.2), prompt contains low-curiosity description")
    func givenLowCuriosity_lowDescription() {
        let companion = makeCompanion(curiosity: 0.2)
        let prompt = OpenAIService.customCompanionPersonaPrompt(companion)

        #expect(prompt.contains("rarely asks questions"))
    }

    @Test("given mid curiosity (0.5), prompt contains mid-curiosity description")
    func givenMidCuriosity_midDescription() {
        let companion = makeCompanion(curiosity: 0.5)
        let prompt = OpenAIService.customCompanionPersonaPrompt(companion)

        #expect(prompt.contains("occasionally curious"))
    }

    @Test("given high curiosity (0.9), prompt contains high-curiosity description")
    func givenHighCuriosity_highDescription() {
        let companion = makeCompanion(curiosity: 0.9)
        let prompt = OpenAIService.customCompanionPersonaPrompt(companion)

        #expect(prompt.contains("deeply curious"))
    }

    @Test("given high strictness (0.8), prompt contains firm accountability description")
    func givenHighStrictness_firmAccountability() {
        let companion = makeCompanion(strictness: 0.8)
        let prompt = OpenAIService.customCompanionPersonaPrompt(companion)

        #expect(prompt.contains("firm standards"))
    }
}
