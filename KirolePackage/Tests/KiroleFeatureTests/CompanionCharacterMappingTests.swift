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
        #expect(silasPrompt.contains("quiet presence"))
        #expect(novaPrompt.contains("signal over noise"))
        #expect(novaPrompt.contains("critical path"))
    }

    /// The customer's 2026-07-28 rewrite gave all three personas an explicit two-mode structure:
    /// Mode A (~80% everyday voice) and Mode B (~20% moment worth marking). Mode B is fulfilled
    /// differently per character — `secondaryModeStyle` in PromptSpec is the switch — so the
    /// prompt text and the style flag must not drift apart.
    @Test("Every persona declares both writing modes and matches its secondary-mode style")
    func personasDeclareTwoModesMatchingTheirStyle() throws {
        for character in CompanionCharacter.allCases {
            let spec = try #require(KirolePromptSpec.character(character.rawValue))
            let prompt = spec.personaPrompt.lowercased()

            #expect(prompt.contains("mode a"), "\(character.rawValue) is missing Mode A")
            #expect(prompt.contains("mode b"), "\(character.rawValue) is missing Mode B")
            #expect(["quote", "generative"].contains(spec.secondaryModeStyle))

            switch spec.secondaryModeStyle {
            case "quote":
                // Quote-backed Mode B is deterministic: the approved bank is the only source, so it
                // must be non-empty or a signature-quote turn would have nothing to emit.
                #expect(!spec.approvedQuotes.isEmpty,
                        "\(character.rawValue) uses quote-style Mode B but has an empty bank")
            case "generative":
                // Generative Mode B writes an original line in the character's own voice, so an
                // approved bank would be dead weight — and a non-empty bank would silently route
                // this character back through the deterministic path.
                #expect(spec.approvedQuotes.isEmpty,
                        "\(character.rawValue) uses generative Mode B and must not carry quotes")
            default:
                break
            }
        }
    }
}
