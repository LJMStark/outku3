import Foundation
import CoreGraphics

#if canImport(UIKit)
import UIKit
private typealias PlatformFont = UIFont
#elseif canImport(AppKit)
import AppKit
private typealias PlatformFont = NSFont
#endif

enum CompanionDialogueDisplayPolicy {
    static let fontSize: CGFloat = 15
    static let maxWidth: CGFloat = 240
    static let maxLines: Int = 3
    static let reservedHeight: CGFloat = 68

    static func normalized(_ text: String) -> String {
        text
            .replacingOccurrences(
                of: #"\s*\n+\s*"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\s{2,}"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Counts whitespace-separated words. Mirrors `wordCount` in prompt-studio's
    /// `prompt-engine.ts` so the App's gate and the Studio's validator agree on the number.
    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    /// - Parameters:
    ///   - expectedApprovedQuote: the deterministic Mode B string, when one applies. Such lines
    ///     end in a source (`- Isaiah 30:15`) rather than punctuation, so they are exempt from the
    ///     terminal-punctuation rule; they are also pre-vetted, so they skip the word budget.
    ///   - wordLimit: the active character's limit for the current writing mode (PromptSpec
    ///     `characters[].wordLimits`). The limit is stated in the prompt, but a model can exceed
    ///     it — without this check an over-long line passes on bytes alone and reaches hardware.
    static func isValidForDisplay(
        _ text: String,
        expectedApprovedQuote: String? = nil,
        wordLimit: Int? = nil
    ) -> Bool {
        let normalizedText = normalized(text)
        guard !normalizedText.isEmpty else { return false }
        guard !normalizedText.hasPrefix("[Error]") else { return false }
        // English-only product: reject any AI output that slipped into CJK (the model mirrors the
        // language of Chinese task/event titles injected into the prompt). Rejecting here makes the
        // dialogue retry loop regenerate and, failing that, fall back to English FallbackText —
        // Chinese must never reach the App UI or the DayPack pushed to hardware. See CLAUDE.md
        // Interaction Rule 4 (English-only UI).
        guard !containsCJKScript(normalizedText) else { return false }
        let isExpectedApprovedQuote = expectedApprovedQuote
            .map(normalized) == normalizedText
        guard isExpectedApprovedQuote || hasTerminalPunctuation(normalizedText) else { return false }
        // Approved quotes are fixed, pre-vetted text — the client chose them, so their length is
        // not the model's to answer for. Everything else must respect the persona word budget.
        if !isExpectedApprovedQuote, let wordLimit {
            guard wordCount(normalizedText) <= wordLimit else { return false }
        }
        return renderedLineCount(for: normalizedText) <= maxLines
    }

    /// True when `text` contains any Han ideograph, Japanese kana, Korean hangul, or CJK/fullwidth
    /// punctuation. Deliberately narrow: Latin-1 accents, em-dashes, and curly quotes are NOT
    /// flagged (they are legitimate in English AI prose and handled separately at the BLE wire
    /// layer), so this only trips on genuinely non-English scripts.
    static func containsCJKScript(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3000...0x303F,   // CJK symbols & punctuation (、。「」etc.)
                 0x3040...0x30FF,   // Hiragana + Katakana
                 0x3400...0x4DBF,   // CJK Unified Ideographs Extension A
                 0x4E00...0x9FFF,   // CJK Unified Ideographs
                 0xAC00...0xD7AF,   // Hangul syllables
                 0xF900...0xFAFF,   // CJK compatibility ideographs
                 0xFF00...0xFFEF:   // Fullwidth/halfwidth forms (！？，：fullwidth punctuation)
                return true
            default:
                continue
            }
        }
        return false
    }

    static func hasTerminalPunctuation(_ text: String) -> Bool {
        guard let scalar = text.unicodeScalars.last else { return false }
        return CharacterSet(charactersIn: ".!?…。！？").contains(scalar)
    }

    static func renderedLineCount(for text: String) -> Int {
        #if canImport(UIKit) || canImport(AppKit)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineBreakStrategy = .pushOut

        let attributes: [NSAttributedString.Key: Any] = [
            .font: measurementFont(),
            .paragraphStyle: paragraphStyle
        ]

        let bounds = NSAttributedString(string: text, attributes: attributes).boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )

        let lineHeight = measurementLineHeight()
        return max(1, Int(ceil(bounds.height / lineHeight)))
        #else
        return 1
        #endif
    }

    #if canImport(UIKit) || canImport(AppKit)
    private static func measurementFont() -> PlatformFont {
        #if canImport(UIKit)
        let baseDescriptor = UIFont.systemFont(ofSize: fontSize, weight: .regular).fontDescriptor
        let serifDescriptor = baseDescriptor.withDesign(.serif) ?? baseDescriptor
        let italicDescriptor = serifDescriptor.withSymbolicTraits([.traitItalic]) ?? serifDescriptor
        return UIFont(descriptor: italicDescriptor, size: fontSize)
        #else
        return NSFont.systemFont(ofSize: fontSize)
        #endif
    }

    private static func measurementLineHeight() -> CGFloat {
        #if canImport(UIKit)
        measurementFont().lineHeight
        #else
        NSLayoutManager().defaultLineHeight(for: measurementFont())
        #endif
    }
    #endif
}
