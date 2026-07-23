import Foundation

// MARK: - ASCII Wire Sanitizer

extension String {
    /// Returns a copy containing only printable ASCII (`0x20`–`0x7E`), safe to send to the
    /// E-ink hardware, which renders no other bytes (anything else shows as a tofu box `□`).
    ///
    /// This is the single outbound choke point: `Data.appendString` calls it, so every
    /// length-prefixed text field on the BLE wire (LLM copy, user-typed titles, calendar-sync
    /// titles) is cleaned in one place. The classic trigger is an LLM emitting the "correct"
    /// curly apostrophe `’` (U+2019, UTF-8 `E2 80 99`) instead of ASCII `'` — three non-ASCII
    /// bytes the panel can't draw.
    ///
    /// Strategy, in order:
    /// 1. **Pass through** any scalar already in `0x20`–`0x7E` (identity — UUIDs, `HH:mm`,
    ///    SF-Symbol names stay byte-identical).
    /// 2. **Transliterate** common typographic / symbolic Unicode to ASCII (smart quotes,
    ///    dashes, ellipsis, non-breaking spaces, bullets, arrows, ×/÷, ™/©/®, fullwidth forms).
    /// 3. **Diacritic-fold** accented Latin to base letters (`café` → `cafe`), plus an explicit
    ///    map for ligatures that do not canonically decompose (`ß` → `ss`, `æ` → `ae`).
    /// 4. **Drop** anything still outside `0x20`–`0x7E` (emoji, CJK/Cyrillic/Greek/…, currency,
    ///    math, zero-width & directional-format characters). Romanization is intentionally out of
    ///    scope; hardware-visible title fields add a role-specific English fallback after this step.
    ///
    /// Must run BEFORE the `maxLength` byte truncation in `appendString`: a transform can grow
    /// (`…` → `...`) or shrink (`café` → `cafe`) the byte count, so truncation clamps the final
    /// ASCII bytes.
    func asciiSanitizedForEInk() -> String {
        // Fast path: already pure printable ASCII → byte-identical, no work.
        if isPrintableASCII { return self }

        var out = String()
        out.reserveCapacity(unicodeScalars.count)

        for scalar in unicodeScalars {
            let value = scalar.value
            if value >= 0x20, value <= 0x7E {
                out.unicodeScalars.append(scalar)                        // identity on printable ASCII
            } else if let mapped = Self.wireASCIIMap[value] {
                out += mapped                                            // transliterate (may be "")
            } else if value >= 0xFF01, value <= 0xFF5E,
                      let halfwidth = Unicode.Scalar(value - 0xFEE0) {
                out.unicodeScalars.append(halfwidth)                     // fullwidth ASCII → halfwidth
            } else if let folded = Self.diacriticFoldedToASCII(scalar) {
                out += folded                                            // café → cafe, ß → ss
            }
            // else: unmappable (emoji, CJK, currency, math, zero-width, and controls
            //       incl. DEL 0x7F — intentionally excluded as a non-printing control) → dropped
        }
        return out
    }

    /// Hardware title fields need a readable word, not punctuation left behind after CJK removal.
    func needsHardwareTitleFallback(asciiSanitized: String? = nil) -> Bool {
        let ascii = asciiSanitized ?? asciiSanitizedForEInk()
        if ascii.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }

        let containedNonASCII = unicodeScalars.contains { $0.value > 0x7E }
        guard containedNonASCII else { return false }
        return !ascii.contains { $0.isLetter || $0.isNumber }
    }

    /// True when every UTF-8 byte is printable ASCII (`0x20`–`0x7E`).
    private var isPrintableASCII: Bool {
        for byte in utf8 where byte < 0x20 || byte > 0x7E { return false }
        return true
    }

    /// Folds a single non-ASCII scalar to ASCII via canonical (NFD) decomposition, keeping only
    /// the ASCII base letter(s). Returns `nil` when nothing ASCII survives (caller drops it).
    private static func diacriticFoldedToASCII(_ scalar: Unicode.Scalar) -> String? {
        // Ligatures / stroked letters that do NOT canonically decompose need an explicit map.
        if let ligature = ligatureMap[scalar.value] { return ligature }

        var ascii = ""
        for decomposed in String(scalar).decomposedStringWithCanonicalMapping.unicodeScalars
        where decomposed.value >= 0x20 && decomposed.value <= 0x7E {
            ascii.unicodeScalars.append(decomposed)
        }
        return ascii.isEmpty ? nil : ascii
    }

    /// Letters that do not decompose under NFD, mapped to a conventional ASCII spelling.
    private static let ligatureMap: [UInt32: String] = [
        0x00DF: "ss", 0x1E9E: "SS",   // ß ẞ
        0x00E6: "ae", 0x00C6: "AE",   // æ Æ
        0x0153: "oe", 0x0152: "OE",   // œ Œ
        0x00F8: "o",  0x00D8: "O",    // ø Ø
        0x0111: "d",  0x0110: "D",    // đ Đ
        0x0142: "l",  0x0141: "L",    // ł Ł
        0x00F0: "d",  0x00D0: "D",    // ð Ð
        0x00FE: "th", 0x00DE: "Th",   // þ Þ
        0x0131: "i",                  // ı  (dotless i)
    ]

    /// Fixed transliteration table for the high-frequency non-ASCII that LLM copy, iOS smart
    /// punctuation, and calendar sync actually produce. `""` means "drop". Everything not covered
    /// here and not diacritic-foldable is dropped by the catch-all in `asciiSanitizedForEInk()`.
    private static let wireASCIIMap: [UInt32: String] = [
        // Whitespace-ish control → space (single-line display fields)
        0x09: " ", 0x0A: " ", 0x0D: " ",
        // Non-breaking & typographic spaces → ASCII space (invisible tofu is the worst kind)
        0x00A0: " ", 0x1680: " ",
        0x2000: " ", 0x2001: " ", 0x2002: " ", 0x2003: " ", 0x2004: " ",
        0x2005: " ", 0x2006: " ", 0x2007: " ", 0x2008: " ", 0x2009: " ",
        0x200A: " ", 0x202F: " ", 0x205F: " ", 0x3000: " ",
        // Zero-width & directional-format → drop
        0x200B: "", 0x200C: "", 0x200D: "", 0x2060: "", 0xFEFF: "",
        0x200E: "", 0x200F: "", 0x202A: "", 0x202B: "", 0x202C: "",
        0x202D: "", 0x202E: "", 0x2066: "", 0x2067: "", 0x2068: "", 0x2069: "",
        // Single quotes / apostrophe / prime  → '
        0x2018: "'", 0x2019: "'", 0x201A: "'", 0x201B: "'", 0x2032: "'",
        // Double quotes / double prime  → "
        0x201C: "\"", 0x201D: "\"", 0x201E: "\"", 0x201F: "\"", 0x2033: "\"",
        // Dashes / hyphens / minus  → -
        0x2010: "-", 0x2011: "-", 0x2012: "-", 0x2013: "-", 0x2014: "-", 0x2015: "-", 0x2212: "-",
        // Ellipsis  → ...
        0x2026: "...",
        // Bullets / middot  → *
        0x2022: "*", 0x00B7: "*", 0x25E6: "*", 0x2023: "*", 0x2043: "*", 0x2219: "*", 0x30FB: "*",
        // Common math  → ASCII
        0x00D7: "x", 0x00F7: "/",
        // Arrows
        0x2190: "<-", 0x2192: "->",
        // Trademark / copyright / registered
        0x2122: "(tm)", 0x00A9: "(c)", 0x00AE: "(r)",
        // Degree / temperature
        0x00B0: "", 0x2103: "C", 0x2109: "F",
        // Ideographic punctuation (CJK keyboards mix these into English text)
        0x3001: ",", 0x3002: ".",
    ]
}
