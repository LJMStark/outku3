import Foundation
import CryptoKit
import Testing
@testable import KiroleFeature

@Suite("PromptSpec single source")
struct PromptSpecConsistencyTests {
    private struct CompanionFixture: Decodable {
        let characterId: String
        let scenarioId: String
        let writingMode: CompanionWritingMode
        let quoteIndex: Int?
        let expectedSystemSHA256: String
        let expectedUserSHA256: String
    }

    private struct ToolFixture: Decodable {
        let scenarioId: String
        let expectedSystemSHA256: String
        let expectedUserSHA256: String
    }

    @Test("Generated Swift embeds the canonical website JSON byte for byte")
    func generatedSwiftMatchesCanonicalJSON() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot
            .appendingPathComponent("prompt-studio/lib/prompt-spec.json")
        let sourceData = try Data(contentsOf: sourceURL)

        #expect(sourceData == KirolePromptSpec.sourceJSONData)
    }

    @Test("Canonical spec covers all built-in characters and intimacy stages")
    func canonicalIdentityCoverage() {
        let document = KirolePromptSpec.document

        #expect(Set(document.characters.map(\.id)) == Set(["joy", "silas", "nova"]))
        #expect(Set(document.intimacyStages.map(\.id)) == Set([
            "acquaintance", "familiar", "closeFriend"
        ]))
        #expect(document.characters.allSatisfy { !$0.personaPrompt.isEmpty })
        #expect(document.characters.allSatisfy { !$0.characterPrompt.isEmpty })
        // v2.10.0: Mode B is per-character. "quote" characters must carry an approved bank;
        // "generative" ones (joy — writes its own quotable line) must carry none, so an
        // attributed quotation can never leak into a voice the client wants unattributed.
        for character in document.characters {
            switch character.secondaryModeStyle {
            case "quote":
                #expect(character.approvedQuotes.count >= 3)
            case "generative":
                #expect(character.approvedQuotes.isEmpty)
            default:
                Issue.record("Unknown secondaryModeStyle \(character.secondaryModeStyle)")
            }
        }
    }

    @Test("Writing mode assignment is exactly 80 percent normal and 20 percent signature quote")
    func writingModeAssignment() {
        let modes = (0..<100).map(CompanionWritingModeSelector.mode(forPercentile:))

        #expect(modes.filter { $0 == .normal }.count == 80)
        #expect(modes.filter { $0 == .signatureQuote }.count == 20)
        #expect(CompanionWritingModeSelector.mode(forPercentile: 19) == .signatureQuote)
        #expect(CompanionWritingModeSelector.mode(forPercentile: 20) == .normal)
    }

    @Test("Signature quote selection comes from the approved character quote bank")
    func approvedQuoteSelection() async throws {
        let selection = try #require(CompanionWritingModeSelector.selection(
            for: .silas,
            percentile: 7,
            quoteIndex: 1
        ))

        let quote = try #require(KirolePromptSpec.character("silas")?.approvedQuotes[1])
        #expect(selection.mode == .signatureQuote)
        #expect(selection.quote == quote)
        // Derived from the spec, not pinned to one quote: the bank grows as the client adds
        // approved sources, and only the *format* is the contract. Client format (2026-07-28):
        // "[exact line]" - [Source] — ASCII hyphen, no trailing period, no parentheses.
        #expect(selection.deterministicOutput == "\"\(quote.text)\" - \(quote.source)")
        #expect(CompanionWritingSelection.normal.deterministicOutput == nil)
        let generated = try await OpenAIService.shared.generateCompanionText(
            type: .companionPhrase,
            context: AIContext(companionCharacter: .silas, intimacyStage: .familiar),
            writingSelection: selection
        )
        #expect(generated == selection.deterministicOutput)
    }

    @Test("Canonical spec lists the eight active persona scenes exactly")
    func activePersonaSceneCoverage() {
        let expected = Set([
            "morningGreeting",
            "companionPhrase",
            "taskEncouragement",
            "scheduleReminder",
            "settlementSummary",
            "smartReminder",
            "settlementQuoteCelebration",
            "settlementQuoteOverloaded"
        ])

        #expect(Set(KirolePromptSpec.document.personaScenes.map(\.id)) == expected)
        #expect(KirolePromptSpec.document.personaScenes.allSatisfy { $0.status == "active" })
    }

    @Test("Canonical spec covers every independent model prompt")
    func toolPromptCoverage() {
        let expected = Set([
            "haiku",
            "screensaver",
            "taskOverview",
            "daySummary",
            // v2.10.0: per-event support line, one writing rule per customer category.
            "eventSupportText",
            "taskLibraryPhaseText",
            "settlementReview",
            "eventClassification",
            "translation"
        ])

        let tools = KirolePromptSpec.document.toolPrompts
        #expect(Set(tools.map(\.id)) == expected)
        #expect(tools.allSatisfy { !$0.systemPromptTemplate.isEmpty })
        #expect(KirolePromptSpec.tool("screensaver")?.userPromptTemplates["resting"] != nil)
        #expect(KirolePromptSpec.tool("screensaver")?.userPromptTemplates["postcard"] != nil)
        #expect(KirolePromptSpec.tool("daySummary")?.userPromptTemplates["empty"] != nil)
        #expect(KirolePromptSpec.tool("daySummary")?.userPromptTemplates["events"] != nil)
        #expect(tools.filter { !["screensaver", "daySummary"].contains($0.id) }
            .allSatisfy { $0.userPromptTemplates["default"] != nil })
        #expect(KirolePromptSpec.document.eventCategoryDefinitions == EventCategory.promptDefinitions)
    }

    @Test("Legacy and non-model paths are visibly separated from active scenes")
    func legacyCoverage() {
        let legacyIDs = Set(KirolePromptSpec.document.nonActivePaths.map(\.id))

        #expect(legacyIDs.contains("dailySummaryPersonaEnum"))
        #expect(legacyIDs.contains("fallbackTextPools"))
        #expect(legacyIDs.contains("focusLocalPhrases"))
        #expect(legacyIDs.contains("settlementEncouragementMessage"))
        #expect(legacyIDs.isDisjoint(with: Set(KirolePromptSpec.document.personaScenes.map(\.id))))
    }

    @Test("Model behavior preserves production OpenRouter settings")
    func productionModelSettings() {
        let model = KirolePromptSpec.document.model

        #expect(model.fallbackModel == "openai/gpt-oss-120b:free")
        #expect(model.reasoning.effort == "low")
        #expect(model.reasoning.exclude)
        #expect(model.requireParameters)
        #expect(model.reasoningTokenHeadroom == 220)
        #expect(model.requestTimeoutSeconds == 60)
        #expect(KirolePromptSpec.parameters(for: "companionPhrase")?.temperature == 0.9)
        #expect(KirolePromptSpec.parameters(for: "eventClassification")?.maxTokens == 60)
    }

    @Test("Hardware byte budgets come from PromptSpec")
    func hardwareByteBudgets() {
        #expect(KirolePromptSpec.scene("companionPhrase")?.outputMaxBytes == 120)
        #expect(KirolePromptSpec.tool("screensaver")?.outputMaxBytes == 180)
        #expect(KirolePromptSpec.tool("taskOverview")?.outputMaxBytes == 100)
        #expect(KirolePromptSpec.tool("daySummary")?.outputMaxBytes == 180)
        #expect(KirolePromptSpec.tool("settlementReview")?.outputMaxBytes == 180)
        #expect(DayPackTextBudget.petDialogue == 120)
        #expect(DayPackTextBudget.taskDescription == 100)
        #expect(DayPackTextBudget.daySummary == 180)
        #expect(DayPackTextBudget.settlementReview == 180)
        #expect(DayPackTextBudget.settlementQuote == 120)
    }

    @Test("App prompt accessors resolve from PromptSpec")
    func appAccessorsResolveFromSpec() {
        #expect(OpenAIService.companionPromptVersion == KirolePromptSpec.document.version)
        #expect(OpenAIService.defaultPrompt(for: .joy) == KirolePromptSpec.character("joy")?.personaPrompt)
        #expect(OpenAIService.characterPrompt(for: .silas) == KirolePromptSpec.character("silas")?.characterPrompt)
        #expect(OpenAIService.intimacyPrompt(for: .closeFriend) == KirolePromptSpec.intimacy("closeFriend")?.prompt)
    }

    @Test("Template rendering never recursively expands inserted user content")
    func templateRenderingIsSinglePass() {
        let rendered = KirolePromptSpec.render(
            "First={{first}}; second={{second}}",
            values: [
                "first": "{{second}}",
                "second": "safe"
            ]
        )

        #expect(rendered == "First={{second}}; second=safe")
    }

    @Test("App exposes the final prompt pair used by cross-runtime fixtures")
    @MainActor
    func appPromptCompilationSeam() async {
        let context = AIContext(
            companionCharacter: .joy,
            intimacyStage: .familiar,
            petName: "Kirole",
            recentTexts: ["One clear step is enough."],
            nextAgendaItem: "15:00 · Client demo",
            activeTaskTitle: "Finish demo",
            topTaskTitles: ["Finish demo", "Reply to email"]
        )

        let compiled = await OpenAIService.shared.compilePromptForFixture(
            type: .taskEncouragement,
            context: context
        )

        #expect(compiled.systemPrompt.hasPrefix(PromptSanitizer.securityInstruction))
        #expect(compiled.userPrompt.contains(
            "ALREADY SAID (never repeat): <user_content>One clear step is enough.</user_content>"
        ))
        #expect(compiled.userPrompt.contains("<user_content>Finish demo</user_content>"))
    }

    @Test("Compiled companion prompts make the selected writing mode explicit")
    @MainActor
    func companionWritingModePrompt() async throws {
        let context = AIContext(companionCharacter: .nova, intimacyStage: .familiar)
        let quote = try #require(KirolePromptSpec.character("nova")?.approvedQuotes.first)

        let normal = await OpenAIService.shared.compilePromptForFixture(
            type: .companionPhrase,
            context: context,
            writingSelection: .normal
        )
        let signature = await OpenAIService.shared.compilePromptForFixture(
            type: .companionPhrase,
            context: context,
            writingSelection: CompanionWritingSelection(mode: .signatureQuote, quote: quote)
        )

        #expect(normal.systemPrompt.contains("MODE: NORMAL"))
        #expect(normal.systemPrompt.contains("Do not use an attributed quotation"))
        #expect(signature.systemPrompt.contains("MODE: SIGNATURE QUOTE"))
        #expect(signature.systemPrompt.contains(quote.text))
        #expect(signature.systemPrompt.contains(quote.source))
        #expect(KirolePromptSpec.writingMode("normal")?.temperatureOverride == nil)
        #expect(KirolePromptSpec.writingMode("signatureQuote")?.temperatureOverride == 0)
    }

    @Test("Haiku fixture seam returns the production prompt pair")
    func haikuPromptCompilationSeam() async {
        let context = HaikuContext(
            currentTime: Date(timeIntervalSince1970: 43_200),
            tasksCompletedToday: 2,
            totalTasksToday: 5,
            petMood: .focused,
            currentSceneName: "Forest"
        )
        let compiled = await OpenAIService.shared.compileHaikuPromptForFixture(context: context)

        #expect(compiled.systemPrompt.hasPrefix(PromptSanitizer.securityInstruction))
        #expect(compiled.userPrompt.hasPrefix("<user_content>"))
        #expect(compiled.userPrompt.contains("3 task(s) remaining"))
    }

    @Test("Screensaver fixture seam returns the production prompt pair")
    func screensaverPromptCompilationSeam() async {
        let compiled = await OpenAIService.shared.compileScreensaverPromptForFixture(
            isPostcard: true,
            usageDays: 21,
            workContext: "Launch prep",
            profileContext: "Calm companion"
        )

        #expect(compiled.systemPrompt.hasPrefix(PromptSanitizer.securityInstruction))
        #expect(compiled.userPrompt.contains("reached 21 consecutive usage days"))
    }

    @Test("Task overview fixture seam returns the production prompt pair")
    func taskOverviewPromptCompilationSeam() async {
        let compiled = await OpenAIService.shared.compileTaskOverviewPromptForFixture(
            notes: "Ship the final demo"
        )

        #expect(compiled.systemPrompt.hasPrefix(PromptSanitizer.securityInstruction))
        #expect(compiled.userPrompt == "<user_content>Ship the final demo</user_content>")
    }

    @Test("Translation fixture seam returns the production prompt pair")
    func translationPromptCompilationSeam() async {
        let compiled = await OpenAIService.shared.compileTranslationPromptForFixture(
            text: "Protect the quiet hour."
        )

        #expect(compiled.systemPrompt.hasPrefix(PromptSanitizer.securityInstruction))
        #expect(compiled.userPrompt == "<user_content>Protect the quiet hour.</user_content>")
    }

    @Test("Day summary fixture seam returns the production prompt pair")
    func daySummaryPromptCompilationSeam() async {
        let compiled = await OpenAIService.shared.compileDaySummaryPromptForFixture(
            eventDigest: ["09:00 Product sync", "10:00 Client demo"]
        )

        #expect(compiled.systemPrompt.hasPrefix(PromptSanitizer.securityInstruction))
        #expect(compiled.userPrompt.contains("Today's events: 09:00 Product sync; 10:00 Client demo"))
    }

    @Test("Settlement review fixture seam returns the production prompt pair")
    func settlementReviewPromptCompilationSeam() async {
        let compiled = await OpenAIService.shared.compileSettlementReviewPromptForFixture(
            eventDigest: ["15:00 Client demo"],
            deadlineTitles: ["Client demo"],
            focusMinutes: 240,
            tasksCompleted: 3,
            tasksTotal: 6
        )

        #expect(compiled.systemPrompt.contains("MUST state the total focus time"))
        #expect(compiled.userPrompt.contains("Total focus time: 4h."))
    }

    @Test("Event classification fixture seam returns the production prompt pair")
    func eventClassificationPromptCompilationSeam() async {
        let compiled = await OpenAIService.shared.compileEventClassificationPromptForFixture(
            events: ["Product sync", "Client deadline"]
        )

        #expect(compiled.systemPrompt.hasPrefix(PromptSanitizer.securityInstruction))
        #expect(compiled.userPrompt == "<user_content>1. Product sync\n2. Client deadline</user_content>")
    }

    @Test("Every companion scene matches the shared cross-runtime golden fixtures")
    @MainActor
    func companionPromptGoldenFixtures() async throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureURL = repositoryRoot
            .appendingPathComponent("prompt-studio/tests/fixtures/companion-prompts.json")
        let fixtures = try JSONDecoder().decode(
            [CompanionFixture].self,
            from: Data(contentsOf: fixtureURL)
        )
        #expect(fixtures.count == 48)
        for fixture in fixtures {
            let character = try #require(CompanionCharacter(rawValue: fixture.characterId))
            let type = try #require(AITextType(rawValue: fixture.scenarioId))
            let context = AIContext(
                companionCharacter: character,
                intimacyStage: .familiar,
                petName: "Kirole",
                recentTexts: ["One clear step is enough."],
                nextAgendaItem: "Now · Client demo",
                activeTaskTitle: "Finish demo",
                topTaskTitles: ["Finish demo", "Reply to email"]
            )
            let compiled = await OpenAIService.shared.compilePromptForFixture(
                type: type,
                context: context,
                writingSelection: try CompanionWritingModeSelector.forcedSelection(
                    mode: fixture.writingMode,
                    character: character,
                    quoteIndex: fixture.quoteIndex ?? 0
                )
            )
            #expect(Self.sha256(compiled.systemPrompt) == fixture.expectedSystemSHA256)
            #expect(Self.sha256(compiled.userPrompt) == fixture.expectedUserSHA256)
        }
    }

    @Test("Every tool prompt matches the shared cross-runtime golden fixtures")
    func toolPromptGoldenFixtures() async throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fixtureURL = repositoryRoot
            .appendingPathComponent("prompt-studio/tests/fixtures/tool-prompts.json")
        let fixtures = try JSONDecoder().decode(
            [ToolFixture].self,
            from: Data(contentsOf: fixtureURL)
        )

        #expect(fixtures.count == 9)
        for fixture in fixtures {
            let compiled = try await compilationForToolFixture(fixture.scenarioId)
            #expect(Self.sha256(compiled.systemPrompt) == fixture.expectedSystemSHA256)
            #expect(Self.sha256(compiled.userPrompt) == fixture.expectedUserSHA256)
        }
    }

    private func compilationForToolFixture(
        _ scenarioId: String
    ) async throws -> (systemPrompt: String, userPrompt: String) {
        switch scenarioId {
        case "haiku":
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            let date = try #require(calendar.date(from: DateComponents(
                year: 2026, month: 7, day: 28, hour: 14
            )))
            return await OpenAIService.shared.compileHaikuPromptForFixture(
                context: HaikuContext(
                    currentTime: date,
                    tasksCompletedToday: 2,
                    totalTasksToday: 5,
                    petMood: .focused,
                    currentSceneName: "Forest"
                )
            )
        case "screensaver":
            return await OpenAIService.shared.compileScreensaverPromptForFixture(
                isPostcard: true,
                usageDays: 21,
                workContext: "Launch prep",
                profileContext: "Calm companion"
            )
        case "taskOverview":
            return await OpenAIService.shared.compileTaskOverviewPromptForFixture(
                notes: "Ship the final demo"
            )
        case "daySummary":
            return await OpenAIService.shared.compileDaySummaryPromptForFixture(
                eventDigest: ["09:00 Product sync", "10:00 Client demo"]
            )
        case "settlementReview":
            return await OpenAIService.shared.compileSettlementReviewPromptForFixture(
                eventDigest: ["15:00 Client demo"],
                deadlineTitles: ["Client demo"],
                focusMinutes: 240,
                tasksCompleted: 3,
                tasksTotal: 6
            )
        case "eventClassification":
            return await OpenAIService.shared.compileEventClassificationPromptForFixture(
                events: ["Product sync", "Client deadline"]
            )
        case "eventSupportText":
            // The third event is Wellness with isDayPacked: true so the golden fixture covers the
            // day-density hint — categories 1-4 never carry it, so a two-event fixture would let
            // the Swift and TypeScript hint builders drift apart unnoticed.
            return await OpenAIService.shared.compileEventSupportTextPromptForFixture(
                events: [
                    OpenAIService.EventSupportTextInput(title: "Product sync", category: .meetings),
                    OpenAIService.EventSupportTextInput(title: "Client deadline", category: .deadline),
                    OpenAIService.EventSupportTextInput(
                        title: "Stretch break", category: .wellness, isDayPacked: true
                    )
                ]
            )
        case "taskLibraryPhaseText":
            return await OpenAIService.shared.compileTaskLibraryPhasePromptForFixture(
                task: TaskItem(
                    id: "phase-fixture",
                    title: "Finish demo",
                    notes: "Keep the customer facts accurate."
                ),
                userProfile: UserProfile(
                    companionCharacter: .joy,
                    intimacyStage: .familiar
                )
            )
        case "translation":
            return await OpenAIService.shared.compileTranslationPromptForFixture(
                text: "Protect the quiet hour."
            )
        default:
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
