import Testing
@testable import KiroleFeature

@Suite("Companion Character Mapping")
struct CompanionCharacterMappingTests {
    @Test("CompanionCharacter allCases are exactly the three product IPs")
    func allCasesAreProductIPs() {
        #expect(CompanionCharacter.allCases == [.joy, .silas, .nova])
    }

    @Test("CompanionCharacter resolved styles match each product IP")
    func resolvedStyleMappingForProductIPs() {
        #expect(CompanionCharacter.joy.resolvedStyle == .joy)
        #expect(CompanionCharacter.silas.resolvedStyle == .silas)
        #expect(CompanionCharacter.nova.resolvedStyle == .nova)
    }

    @Test("CompanionCharacter names stay stable for storage and UI")
    func displayNameAndRawValueStability() {
        #expect(CompanionCharacter.joy.rawValue == "joy")
        #expect(CompanionCharacter.joy.displayName == "Joy")
        #expect(CompanionCharacter.silas.rawValue == "silas")
        #expect(CompanionCharacter.silas.displayName == "Silas")
        #expect(CompanionCharacter.nova.rawValue == "nova")
        #expect(CompanionCharacter.nova.displayName == "Nova")
    }

    @Test("Profile variant uses dedicated <character>-profile asset names")
    func profileHeroAssetNames() {
        #expect(CompanionCharacter.joy.heroAssetName(variant: .profile) == "joy-profile")
        #expect(CompanionCharacter.silas.heroAssetName(variant: .profile) == "silas-profile")
        #expect(CompanionCharacter.nova.heroAssetName(variant: .profile) == "nova-profile")
    }

    @Test("Character prompts contain distinct persona anchors")
    func characterPromptsContainExpectedPersonaAnchors() {
        let joyPrompt = OpenAIService.characterPrompt(for: .joy).lowercased()
        let silasPrompt = OpenAIService.characterPrompt(for: .silas).lowercased()
        let novaPrompt = OpenAIService.characterPrompt(for: .nova).lowercased()

        #expect(joyPrompt.contains("joy"))
        #expect(joyPrompt.contains("gladness"))
        #expect(silasPrompt.contains("silas"))
        #expect(silasPrompt.contains("spiritual"))
        #expect(novaPrompt.contains("nova"))
        #expect(novaPrompt.contains("discipline"))
    }

    @Test("Default prompts contain distinct voice anchors")
    func defaultPromptsContainExpectedVoiceAnchors() {
        let joyPrompt = OpenAIService.defaultPrompt(for: .joy).lowercased()
        let silasPrompt = OpenAIService.defaultPrompt(for: .silas).lowercased()
        let novaPrompt = OpenAIService.defaultPrompt(for: .nova).lowercased()

        #expect(joyPrompt.contains("two-second scan"))
        #expect(joyPrompt.contains("haiku reward"))
        #expect(silasPrompt.contains("quiet presence"))
        #expect(silasPrompt.contains("soulful reframing"))
        #expect(novaPrompt.contains("signal over noise"))
        #expect(novaPrompt.contains("critical path"))
    }
}
