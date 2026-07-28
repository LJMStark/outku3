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
        guard mode == .signatureQuote, let quote else { return nil }
        return "\"\(quote.text)\" (\(quote.source))."
    }
}

enum CompanionWritingModeSelectionError: Error {
    case missingQuote(CompanionCharacter)
    case invalidQuoteIndex(Int)
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
        using generator: inout R
    ) -> CompanionWritingSelection {
        let percentile = Int.random(in: 0..<100, using: &generator)
        guard mode(forPercentile: percentile) == .signatureQuote else { return .normal }
        guard let quotes = KirolePromptSpec.character(character.rawValue)?.approvedQuotes,
              !quotes.isEmpty else {
            preconditionFailure("PromptSpec is missing approved quotes for \(character.rawValue)")
        }
        let quote = quotes.randomElement(using: &generator) ?? quotes[0]
        return CompanionWritingSelection(mode: .signatureQuote, quote: quote)
    }

    public static func randomSelection(for character: CompanionCharacter) -> CompanionWritingSelection {
        var generator = SystemRandomNumberGenerator()
        return randomSelection(for: character, using: &generator)
    }
}
