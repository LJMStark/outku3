import Foundation

public enum CompanionWritingMode: String, Codable, Sendable {
    case normal
    case signatureQuote
}

public struct CompanionWritingSelection: Sendable, Equatable {
    public let mode: CompanionWritingMode
    public let quote: PromptQuoteSpec?

    public init(mode: CompanionWritingMode, quote: PromptQuoteSpec? = nil) {
        self.mode = mode
        self.quote = quote
    }

    public static let normal = CompanionWritingSelection(mode: .normal)

    public var deterministicOutput: String? {
        // Generative secondary mode (joy): quote is nil by design — caller uses LLM instead.
        guard mode == .signatureQuote, let quote else { return nil }
        // Wire-safe ASCII: "text" - source  (plain hyphen-minus, no trailing period).
        return "\"\(quote.text)\" - \(quote.source)"
    }
}

enum CompanionWritingModeSelectionError: Error {
    case missingQuote(CompanionCharacter)
    case invalidQuoteIndex(Int)
}

/// How a character fulfils Mode B (the ~20% "quotable moment"), per PromptSpec
/// `characters[].secondaryModeStyle`. The client spec asks for two different things:
/// Silas/Nova cite a REAL public-domain line (deterministic whitelist, no LLM call), while Joy
/// writes an ORIGINAL line in the style of Wilde / The Little Prince (generative, LLM call).
enum CompanionSecondaryModeStyle: String {
    case quote
    case generative

    static func resolved(for character: CompanionCharacter) -> CompanionSecondaryModeStyle {
        guard let raw = KirolePromptSpec.character(character.rawValue)?.secondaryModeStyle,
              let style = CompanionSecondaryModeStyle(rawValue: raw) else {
            preconditionFailure("PromptSpec is missing secondaryModeStyle for \(character.rawValue)")
        }
        return style
    }
}

public enum CompanionWritingModeSelector {
    public static let signatureQuotePercent = 20

    public static func mode(forPercentile percentile: Int) -> CompanionWritingMode {
        precondition((0..<100).contains(percentile), "Percentile must be between 0 and 99")
        return percentile < signatureQuotePercent ? .signatureQuote : .normal
    }

    public static func selection(
        for character: CompanionCharacter,
        percentile: Int,
        quoteIndex: Int
    ) -> CompanionWritingSelection? {
        let selectedMode = mode(forPercentile: percentile)
        guard selectedMode == .signatureQuote else { return .normal }
        // Generative Mode B carries no quote — the LLM writes an original line.
        guard CompanionSecondaryModeStyle.resolved(for: character) == .quote else {
            return CompanionWritingSelection(mode: .signatureQuote, quote: nil)
        }
        guard let quotes = KirolePromptSpec.character(character.rawValue)?.approvedQuotes,
              quotes.indices.contains(quoteIndex) else { return nil }
        return CompanionWritingSelection(mode: .signatureQuote, quote: quotes[quoteIndex])
    }

    static func forcedSelection(
        mode: CompanionWritingMode,
        character: CompanionCharacter,
        quoteIndex: Int
    ) throws -> CompanionWritingSelection {
        guard mode == .signatureQuote else { return .normal }
        guard CompanionSecondaryModeStyle.resolved(for: character) == .quote else {
            return CompanionWritingSelection(mode: .signatureQuote, quote: nil)
        }
        guard let quotes = KirolePromptSpec.character(character.rawValue)?.approvedQuotes,
              !quotes.isEmpty else {
            throw CompanionWritingModeSelectionError.missingQuote(character)
        }
        guard quotes.indices.contains(quoteIndex) else {
            throw CompanionWritingModeSelectionError.invalidQuoteIndex(quoteIndex)
        }
        return CompanionWritingSelection(mode: .signatureQuote, quote: quotes[quoteIndex])
    }

    public static func randomSelection<R: RandomNumberGenerator>(
        for character: CompanionCharacter,
        moment: AITextType? = nil,
        using generator: inout R
    ) -> CompanionWritingSelection {
        let percentile = Int.random(in: 0..<100, using: &generator)
        guard mode(forPercentile: percentile) == .signatureQuote else { return .normal }
        // Joy: generative Mode B — no quote bank to draw from, the LLM writes the line.
        guard CompanionSecondaryModeStyle.resolved(for: character) == .quote else {
            return CompanionWritingSelection(mode: .signatureQuote, quote: nil)
        }
        guard let quotes = KirolePromptSpec.character(character.rawValue)?.approvedQuotes,
              !quotes.isEmpty else {
            preconditionFailure("PromptSpec is missing approved quotes for \(character.rawValue)")
        }
        let candidates = quotesMatchingTone(of: moment, from: quotes)
        let quote = candidates.randomElement(using: &generator) ?? quotes[0]
        return CompanionWritingSelection(mode: .signatureQuote, quote: quote)
    }

    public static func randomSelection(
        for character: CompanionCharacter,
        moment: AITextType? = nil
    ) -> CompanionWritingSelection {
        var generator = SystemRandomNumberGenerator()
        return randomSelection(for: character, moment: moment, using: &generator)
    }

    /// The single place that decides which writing mode a generation uses.
    ///
    /// Two gates, both from the client's 2026-07-28 spec:
    /// 1. Mode B is «reserved for completions, milestones, or moments worth marking» — only
    ///    `AITextType.allowsSecondaryMode` moments may roll for it.
    /// 2. A custom companion has no client-authored Mode B (no approved bank, no generative
    ///    template), so it stays in Mode A.
    ///
    /// Callers must reuse the returned selection for BOTH the model call and any post-generation
    /// validation. Rolling once here and re-deriving the mode later is what let a 21-word nova
    /// Mode B line get judged against the 20-word Mode A budget.
    static func selectionForGeneration(
        context: AIContext,
        type: AITextType
    ) -> CompanionWritingSelection {
        guard context.customCompanion == nil, type.allowsSecondaryMode else { return .normal }
        return randomSelection(for: context.companionCharacter, moment: type)
    }

    /// The word budget for `character` in `mode` (PromptSpec `characters[].wordLimits`).
    ///
    /// Client 2026-07-28 sets these per character (joy 25 / silas 15 everyday, 20 in Mode B /
    /// nova 20 everyday, 25 in Mode B including attribution). The limit is stated in the prompt,
    /// but a model can overrun it and the App's other gates (bytes, punctuation, rendered lines)
    /// would not catch it: 120 bytes comfortably holds far more than 15 short words.
    ///
    public static func wordLimit(
        for character: CompanionCharacter,
        mode: CompanionWritingMode
    ) -> Int? {
        guard let limits = KirolePromptSpec.character(character.rawValue)?.wordLimits else {
            return nil
        }
        return mode == .signatureQuote ? limits.secondaryMode : limits.primaryMode
    }

    /// Context-aware budget for a generated line.
    ///
    /// Returns nil when a custom companion is active: `AIContext` always carries a built-in
    /// `companionCharacter` (defaulting to `.joy`) even for a user-authored persona, so resolving
    /// the limit from that field alone would impose joy's 25 words on a persona the client never
    /// set a budget for — rejecting legitimate output. Custom personas keep only the byte budget.
    static func wordLimit(for context: AIContext, mode: CompanionWritingMode) -> Int? {
        guard context.customCompanion == nil else { return nil }
        return wordLimit(for: context.companionCharacter, mode: mode)
    }

    /// Narrows the approved bank to the lines whose tone fits `moment`.
    ///
    /// The client asks Silas to pick "a line matching the emotional tone of the moment" and Nova
    /// to "match the quote to the moment's theme". Quote-style Mode B never reaches the LLM
    /// (`deterministicOutput` short-circuits at temperature 0), so the App is the only place that
    /// can honour it — a bare `randomElement()` would let a fully-completed day draw a
    /// consolation verse, or an overloaded day draw a triumphant one.
    ///
    /// Falls back to the whole bank when the moment is unknown or nothing matches: shipping a
    /// slightly off-tone approved quote beats shipping nothing. `PromptSpec` validation already
    /// guarantees each quote-style character has ≥1 candidate per moment, so the fallback is a
    /// safety net rather than a routine path.
    static func quotesMatchingTone(
        of moment: AITextType?,
        from quotes: [PromptQuoteSpec]
    ) -> [PromptQuoteSpec] {
        guard let moment,
              let wanted = KirolePromptSpec.document.modeBMomentTones[moment.rawValue],
              !wanted.isEmpty else { return quotes }
        let wantedSet = Set(wanted)
        let matches = quotes.filter { !wantedSet.isDisjoint(with: Set($0.tones)) }
        return matches.isEmpty ? quotes : matches
    }
}
