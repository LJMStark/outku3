import Foundation
import Testing
@testable import KiroleFeature

// MARK: - Mode B Gating Tests

/// 客户 2026-07-28 规范：Mode B «reserved for completions, milestones, or moments worth marking»，
/// 且 «chosen externally by the system, not guessed by you»。此前实现对所有场景一律 20% 随机，
/// 早安语也可能冒出一句 Marcus Aurelius——本 suite 钉住修复后的行为。
@Suite("Companion Mode B gating")
struct CompanionModeBGatingTests {

    // MARK: Which moments may enter Mode B

    @Test("only settlement moments allow Mode B", arguments: [
        AITextType.settlementSummary,
        .settlementQuoteCelebration,
        .settlementQuoteOverloaded
    ])
    func settlementMomentsAllowSecondaryMode(type: AITextType) {
        #expect(type.allowsSecondaryMode)
    }

    @Test("everyday moments never allow Mode B", arguments: [
        AITextType.morningGreeting,
        .companionPhrase,
        .taskEncouragement,
        .scheduleReminder,
        .smartReminder,
        .dailySummary
    ])
    func everydayMomentsStayInPrimaryMode(type: AITextType) {
        // A morning greeting quoting scripture with attribution is the exact mismatch the client
        // called out; the gate — not the dice — has to prevent it.
        #expect(!type.allowsSecondaryMode)
    }

    @Test("every Mode B moment has a tone mapping in PromptSpec")
    func modeBMomentsAreMappedInSpec() {
        let mapped = Set(KirolePromptSpec.document.modeBMomentTones.keys)
        let allowed = Set(
            [
                AITextType.morningGreeting, .dailySummary, .companionPhrase, .taskEncouragement,
                .scheduleReminder, .settlementSummary, .smartReminder,
                .settlementQuoteCelebration, .settlementQuoteOverloaded
            ]
            .filter(\.allowsSecondaryMode)
            .map(\.rawValue)
        )

        // Drift guard: adding a Mode B moment without a tone list would silently fall back to the
        // whole quote bank, losing the tone matching the client asked for.
        #expect(mapped == allowed)
    }

    // MARK: Tone matching

    @Test("celebration and consolation moments draw disjoint-enough tone sets")
    func oppositeMomentsDoNotShareEveryTone() throws {
        let tones = KirolePromptSpec.document.modeBMomentTones
        let celebration = Set(try #require(tones["settlementQuoteCelebration"]))
        let overloaded = Set(try #require(tones["settlementQuoteOverloaded"]))

        // They may overlap (grace fits both), but must not be identical — otherwise the filter
        // does nothing and a fully-completed day can draw a consolation line.
        #expect(celebration != overloaded)
    }

    @Test("tone filter narrows the bank for a quote-style character", arguments: [
        CompanionCharacter.silas, .nova
    ])
    func toneFilterNarrowsBank(character: CompanionCharacter) throws {
        let quotes = try #require(KirolePromptSpec.character(character.rawValue)?.approvedQuotes)
        let celebration = CompanionWritingModeSelector.quotesMatchingTone(
            of: .settlementQuoteCelebration, from: quotes
        )

        #expect(!celebration.isEmpty)
        #expect(celebration.count <= quotes.count)
        // Every survivor genuinely carries a tone the moment asked for.
        let wanted = Set(KirolePromptSpec.document.modeBMomentTones["settlementQuoteCelebration"] ?? [])
        #expect(celebration.allSatisfy { !Set($0.tones).isDisjoint(with: wanted) })
    }

    @Test("an unknown moment falls back to the whole bank rather than returning nothing")
    func unknownMomentKeepsEveryCandidate() throws {
        let quotes = try #require(KirolePromptSpec.character("silas")?.approvedQuotes)

        // nil moment (and any moment absent from the map) must not strand Mode B with an empty
        // pool — an off-tone approved quote still beats shipping no line at all.
        #expect(CompanionWritingModeSelector.quotesMatchingTone(of: nil, from: quotes).count == quotes.count)
        #expect(
            CompanionWritingModeSelector
                .quotesMatchingTone(of: .morningGreeting, from: quotes)
                .count == quotes.count
        )
    }

    @Test("random selection in a settlement moment stays inside that moment's tones")
    func randomSelectionRespectsMomentTones() {
        let wanted = Set(KirolePromptSpec.document.modeBMomentTones["settlementQuoteOverloaded"] ?? [])
        var offToneHits = 0

        // Sweep enough seeds to cover the 20% Mode B window many times over.
        for seed in UInt64(0)..<400 {
            var generator = SeededGenerator(seed: seed)
            let selection = CompanionWritingModeSelector.randomSelection(
                for: .silas, moment: .settlementQuoteOverloaded, using: &generator
            )
            guard let quote = selection.quote else { continue }
            if Set(quote.tones).isDisjoint(with: wanted) { offToneHits += 1 }
        }

        #expect(offToneHits == 0)
    }

    // MARK: Word budget

    @Test("a custom companion is exempt from the built-in word budgets")
    func customCompanionHasNoWordBudget() {
        let custom = CustomCompanion(
            name: "Kip",
            relationship: .pet,
            personaVoice: .companion,
            avatarPreviewFileName: "preview.png",
            avatarPixelsFileName: "pixels.bin"
        )
        // AIContext always carries a built-in companionCharacter (default .joy) even when a custom
        // persona is active, so resolving the limit from that field alone would impose joy's 25
        // words on a persona the client never set a budget for — and reject valid user-authored copy.
        let customContext = AIContext(
            companionCharacter: .joy, intimacyStage: .familiar, customCompanion: custom
        )
        let builtInContext = AIContext(companionCharacter: .joy, intimacyStage: .familiar)

        #expect(CompanionWritingModeSelector.wordLimit(for: customContext, mode: .normal) == nil)
        #expect(CompanionWritingModeSelector.wordLimit(for: builtInContext, mode: .normal) == 25)
    }

    @Test("word limits resolve per character and per mode")
    func wordLimitsResolvePerCharacterAndMode() {
        // Client 2026-07-28: joy 25 both modes; silas 15 everyday / 20 in Mode B;
        // nova 20 everyday / 25 in Mode B (including attribution).
        #expect(CompanionWritingModeSelector.wordLimit(for: .joy, mode: .normal) == 25)
        #expect(CompanionWritingModeSelector.wordLimit(for: .silas, mode: .normal) == 15)
        #expect(CompanionWritingModeSelector.wordLimit(for: .silas, mode: .signatureQuote) == 20)
        #expect(CompanionWritingModeSelector.wordLimit(for: .nova, mode: .normal) == 20)
        #expect(CompanionWritingModeSelector.wordLimit(for: .nova, mode: .signatureQuote) == 25)
    }

    @Test("an over-length model line is rejected for display")
    func overLongLineIsRejected() {
        let sixteenWords = "One two three four five six seven eight nine ten "
            + "eleven twelve thirteen fourteen fifteen sixteen."

        // Silas everyday budget is 15 words. Byte/punctuation/line gates all pass here, so
        // without the word check this would reach hardware at the wrong length.
        #expect(CompanionDialogueDisplayPolicy.wordCount(sixteenWords) == 16)
        #expect(!CompanionDialogueDisplayPolicy.isValidForDisplay(sixteenWords, wordLimit: 15))
        #expect(CompanionDialogueDisplayPolicy.isValidForDisplay(sixteenWords, wordLimit: 16))
    }

    @Test("omitting the limit leaves existing callers unchanged")
    func absentLimitSkipsTheWordCheck() {
        let long = "One two three four five six seven eight nine ten eleven twelve."

        // Cached-dialogue re-validation and our own fallback copy pass no limit on purpose:
        // tightening a budget must not retroactively invalidate them.
        #expect(CompanionDialogueDisplayPolicy.isValidForDisplay(long))
    }

    @Test("an approved quote is exempt from the word budget")
    func approvedQuoteIsExemptFromWordBudget() throws {
        let quote = try #require(
            KirolePromptSpec.character("nova")?.approvedQuotes
                .first { $0.text == "Nothing happens to any man which he is not formed by nature to bear." }
        )
        let rendered = CompanionWritingSelection(mode: .signatureQuote, quote: quote)
            .deterministicOutput
        let output = try #require(rendered)

        // 16 words, over nova's 25-word Mode B budget only if counted with attribution — the point
        // is that a client-chosen fixed line is never the model's length to answer for, and it
        // also ends in a source rather than punctuation.
        #expect(CompanionDialogueDisplayPolicy.isValidForDisplay(
            output,
            expectedApprovedQuote: output,
            wordLimit: 3
        ))
        // Same text arriving as free-form model output stays subject to the budget.
        #expect(!CompanionDialogueDisplayPolicy.isValidForDisplay(output, wordLimit: 3))
    }

    @Test("word count matches the prompt-studio validator on padded and multiline input")
    func wordCountMatchesStudioSemantics() {
        // prompt-studio: text.trim().split(/\s+/).length — collapsed whitespace, no empty token.
        #expect(CompanionDialogueDisplayPolicy.wordCount("  two  words  ") == 2)
        #expect(CompanionDialogueDisplayPolicy.wordCount("line\nbreak here") == 3)
        #expect(CompanionDialogueDisplayPolicy.wordCount("") == 0)
        #expect(CompanionDialogueDisplayPolicy.wordCount("   ") == 0)
    }

    @Test("generative characters ignore the tone filter and carry no quote")
    func generativeCharacterHasNoQuote() {
        var sawSecondary = false
        for seed in UInt64(0)..<200 {
            var generator = SeededGenerator(seed: seed)
            let selection = CompanionWritingModeSelector.randomSelection(
                for: .joy, moment: .settlementQuoteCelebration, using: &generator
            )
            if selection.mode == .signatureQuote {
                sawSecondary = true
                // joy writes its own line: a quote here would route it back through the
                // deterministic path and emit an attribution the client explicitly forbade.
                #expect(selection.quote == nil)
            }
        }
        #expect(sawSecondary)
    }
}

/// Deterministic generator so Mode B sweeps are reproducible across runs and machines.
/// SplitMix64 — small, well-distributed, and fixed regardless of Swift's per-process seed.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
