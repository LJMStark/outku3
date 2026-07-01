import Foundation
import Testing
@testable import KiroleFeature

/// Verifies that `String.asciiSanitizedForEInk()` (the single outbound choke point wired into
/// `Data.appendString`) maps every realistic non-ASCII source — LLM typography, user keyboard
/// input, calendar-sync titles — into printable ASCII (0x20–0x7E) so the E-ink panel never draws
/// a tofu box. See the BLE ASCII audit for the full character-class inventory.
@Suite("String ASCII Wire Sanitizer")
struct StringASCIIWireSanitizerTests {

    // MARK: - The reported bug

    @Test("Curly apostrophe U+2019 becomes ASCII apostrophe (the reported daySummary tofu)")
    func reportedCurlyApostrophe() {
        // U+2019 RIGHT SINGLE QUOTATION MARK — UTF-8 E2 80 99 — is what the LLM emitted for "it's".
        #expect("it\u{2019}s working".asciiSanitizedForEInk() == "it's working")
    }

    @Test("Mixed LLM typography folds to ASCII end to end")
    func mixedTypography() {
        let input = "You\u{2019}ve got 2 events \u{2014} don\u{2019}t skip lunch\u{2026}"
        #expect(input.asciiSanitizedForEInk() == "You've got 2 events - don't skip lunch...")
    }

    // MARK: - Punctuation classes

    @Test("Smart double quotes become straight quotes")
    func curlyDoubleQuotes() {
        #expect("\u{201C}quiet\u{201D}".asciiSanitizedForEInk() == "\"quiet\"")
    }

    @Test("En/em dash and minus all become hyphen")
    func dashes() {
        #expect("9\u{2013}10am".asciiSanitizedForEInk() == "9-10am")
        #expect("focus\u{2014}breathe".asciiSanitizedForEInk() == "focus-breathe")
        #expect("temp \u{2212}5".asciiSanitizedForEInk() == "temp -5")
    }

    @Test("Ellipsis grows to three ASCII dots")
    func ellipsis() {
        #expect("loading\u{2026}".asciiSanitizedForEInk() == "loading...")
    }

    @Test("Bullet becomes asterisk")
    func bullet() {
        #expect("\u{2022} first".asciiSanitizedForEInk() == "* first")
    }

    @Test("Arrows and math symbols transliterate")
    func arrowsAndMath() {
        #expect("A \u{2192} B".asciiSanitizedForEInk() == "A -> B")
        #expect("3\u{00D7}4".asciiSanitizedForEInk() == "3x4")
        #expect("6\u{00F7}2".asciiSanitizedForEInk() == "6/2")
    }

    // MARK: - Invisible / whitespace tofu

    @Test("Non-breaking space becomes ASCII space")
    func nonBreakingSpace() {
        #expect("a\u{00A0}b".asciiSanitizedForEInk() == "a b")
    }

    @Test("Zero-width and BOM characters are dropped silently")
    func zeroWidthDropped() {
        #expect("a\u{200B}b\u{FEFF}c\u{200D}d".asciiSanitizedForEInk() == "abcd")
    }

    // MARK: - Accented Latin / ligatures

    @Test("Accented Latin is diacritic-folded to base letters")
    func accentedLatin() {
        #expect("caf\u{00E9}".asciiSanitizedForEInk() == "cafe")           // café
        #expect("na\u{00EF}ve".asciiSanitizedForEInk() == "naive")         // naïve
        #expect("r\u{00E9}sum\u{00E9}".asciiSanitizedForEInk() == "resume") // résumé
        #expect("jalape\u{00F1}o".asciiSanitizedForEInk() == "jalapeno")   // jalapeño
    }

    @Test("Non-decomposing ligatures use the explicit map")
    func ligatures() {
        #expect("stra\u{00DF}e".asciiSanitizedForEInk() == "strasse")       // straße
        #expect("\u{00E6}on".asciiSanitizedForEInk() == "aeon")            // æon
        #expect("\u{00F8}re".asciiSanitizedForEInk() == "ore")            // øre
    }

    // MARK: - Untransliterable → dropped

    @Test("Emoji are dropped, surrounding ASCII preserved")
    func emojiDropped() {
        #expect("good job \u{1F600}".asciiSanitizedForEInk() == "good job ")
        #expect("Gym \u{1F4AA} today".asciiSanitizedForEInk() == "Gym  today")
    }

    @Test("CJK is dropped, ASCII survives")
    func cjkDropped() {
        #expect("\u{4F60}\u{597D}hi".asciiSanitizedForEInk() == "hi")       // 你好hi
    }

    @Test("All-emoji string becomes empty")
    func becomesEmpty() {
        #expect("\u{1F389}\u{1F388}".asciiSanitizedForEInk() == "")
    }

    // MARK: - Fullwidth & CJK punctuation

    @Test("Fullwidth ASCII forms map to halfwidth")
    func fullwidthForms() {
        // Ｔｏｄｏ！ (fullwidth) → Todo!
        #expect("\u{FF34}\u{FF4F}\u{FF44}\u{FF4F}\u{FF01}".asciiSanitizedForEInk() == "Todo!")
    }

    @Test("Ideographic period and comma become ASCII")
    func ideographicPunctuation() {
        #expect("done\u{3002}next\u{3001}".asciiSanitizedForEInk() == "done.next,")
    }

    // MARK: - Identity invariant (stable identifiers must be byte-identical)

    @Test("Pure ASCII passes through unchanged")
    func pureAsciiNoop() {
        let s = "Two events today. Take a break before noon."
        #expect(s.asciiSanitizedForEInk() == s)
    }

    @Test("UUID task id is left byte-identical")
    func uuidIdentity() {
        let uuid = "3F2504E0-4F89-41D3-9A0C-0305E82C3301"
        #expect(uuid.asciiSanitizedForEInk() == uuid)
    }

    @Test("SF-Symbol weather condition raw value is left byte-identical")
    func sfSymbolIdentity() {
        #expect("cloud.rain.fill".asciiSanitizedForEInk() == "cloud.rain.fill")
    }

    @Test("HH:mm time string is left byte-identical")
    func timeIdentity() {
        #expect("09:30".asciiSanitizedForEInk() == "09:30")
    }

    // MARK: - End-to-end through appendString (the real boundary)

    @Test("appendString emits sanitized, length-prefixed ASCII bytes for the reported case")
    func appendStringEndToEnd() {
        var data = Data()
        data.appendString("it\u{2019}s", maxLength: 180)
        // Length prefix = 4 ("it's"), payload = ASCII "it's" — no 3-byte curly-quote run on the wire.
        #expect(data[0] == 4)
        let payload = data.subdata(in: 1..<data.count)
        #expect(payload == Data("it's".utf8))
        #expect(payload.allSatisfy { $0 >= 0x20 && $0 <= 0x7E })
    }

    @Test("appendString drops CJK before truncation (existing Hi你 contract stays green)")
    func appendStringHiCJK() {
        var data = Data()
        data.appendString("Hi\u{4F60}", maxLength: 4)   // Hi你
        #expect(data[0] == 2)
        #expect(String(data: data.subdata(in: 1..<data.count), encoding: .utf8) == "Hi")
    }

    // MARK: - Hardening regression tests (pin the airtight guarantee against future edits)

    @Test("DEL and C0/C1 control chars are dropped")
    func controlCharsDropped() {
        // NUL, DEL(0x7F), NEL(0x85) are all outside 0x20-0x7E and non-printing → dropped.
        #expect("a\u{00}b\u{7F}c\u{85}d".asciiSanitizedForEInk() == "abcd")
    }

    @Test("Lone leading combining mark is dropped, base survives")
    func loneCombiningMark() {
        #expect("\u{0301}abc".asciiSanitizedForEInk() == "abc")
    }

    @Test("ZWJ / flag / skin-tone emoji sequences drop wholesale (no orphan bytes)")
    func emojiSequencesDropWholesale() {
        #expect("\u{1F9D1}\u{200D}\u{1F4BB}".asciiSanitizedForEInk() == "")   // 🧑‍💻 ZWJ
        #expect("\u{1F1FA}\u{1F1F8}".asciiSanitizedForEInk() == "")           // 🇺🇸 flag
        #expect("\u{1F44B}\u{1F3FB}".asciiSanitizedForEInk() == "")           // 👋🏻 skin tone
    }

    @Test("Keycap sequence keeps the ASCII digit, drops VS16 + enclosing mark")
    func keycapKeepsDigit() {
        #expect("1\u{FE0F}\u{20E3}".asciiSanitizedForEInk() == "1")           // 1️⃣
    }

    @Test("Compatibility-only forms drop under canonical NFD (no partial romanization)")
    func compatibilityFormsDrop() {
        // ½ ² ﬁ have COMPATIBILITY (not canonical) decompositions, so canonical NFD leaves them
        // intact → catch-all drops them. Documents the deliberate choice to NOT use NFKD.
        #expect("\u{00BD}\u{00B2}\u{FB01}".asciiSanitizedForEInk() == "")
    }

    @Test("Closure property: output is always within printable ASCII 0x20-0x7E", arguments: [
        "it\u{2019}s \u{2014} a test\u{2026}",
        "caf\u{00E9} \u{2615} \u{4F60}\u{597D} \u{1F600}",
        "\u{1F1FA}\u{1F1F8}\u{1F9D1}\u{200D}\u{1F4BB}",
        "\u{0301}\u{200B}\u{FEFF}\u{202E}\u{2066}",
        "\u{00BD}\u{00B2}\u{00B3} \u{2122}\u{00A9}\u{00AE} \u{20AC}\u{00A3}\u{00A5} \u{2260}\u{2264}\u{2265} \u{2192} \u{00D7}\u{00F7}",
        "\u{00}\u{07}\u{7F}\u{85}\u{9F}",
        "\u{FF26}\u{FF55}\u{FF4C}\u{FF4C}\u{FF01}\u{FF1F}",
        "\u{03A9}\u{2248}\u{00E7}\u{221A}\u{222B} \u{00E5}\u{00DF}\u{2202} \u{0439}\u{0451}",
    ])
    func closureProperty(_ input: String) {
        let output = input.asciiSanitizedForEInk()
        #expect(output.utf8.allSatisfy { $0 >= 0x20 && $0 <= 0x7E })
    }

    // MARK: - Realistic content verification (>=10 cases through the real production sanitizer)

    /// Runs the exact kind of text the LLM (daySummary/petDialogue/encouragement/quote), the user
    /// keyboard (task/pet names), and calendar sync (event titles) actually produce — through the
    /// real asciiSanitizedForEInk() — and proves every output is printable ASCII (0x20-0x7E).
    @Test("Realistic LLM / user / calendar field text is cleaned to printable ASCII")
    func realisticContentIsAsciiClean() {
        let cases: [(label: String, input: String, expected: String)] = [
            ("daySummary curly+em-dash", "You\u{2019}ve got a light day ahead \u{2014} enjoy it.",   "You've got a light day ahead - enjoy it."),
            ("petDialogue ellipsis",     "No rush today\u{2026} take it slow.",                       "No rush today... take it slow."),
            ("quote curly doubles",      "\u{201C}Focus time\u{201D} starts at 9.",                  "\"Focus time\" starts at 9."),
            ("encouragement emoji",      "Great job! \u{1F525} Keep going \u{1F4AA}",                "Great job!  Keep going "),
            ("calendar accented name",   "Lunch with Jos\u{00E9} at the caf\u{00E9}",                "Lunch with Jose at the cafe"),
            ("currency + degree",        "Pay \u{20AC}200 rent; high of 32\u{00B0}C today",          "Pay 200 rent; high of 32C today"),
            ("inline bullets",           "Today: \u{2022} gym \u{2022} groceries \u{2022} mom",      "Today: * gym * groceries * mom"),
            ("user CJK + em-dash",       "\u{4EFB}\u{52A1} done \u{2014} nice work",                 " done - nice work"),
            ("arrows + multiply",        "9\u{2192}10 review, then 2\u{00D7}focus blocks",           "9->10 review, then 2xfocus blocks"),
            ("fullwidth punctuation",    "Done\u{FF01}Next\u{FF1F}",                                 "Done!Next?"),
            ("trademark",                "Watch the Nike\u{2122} ad later",                          "Watch the Nike(tm) ad later"),
            ("two accents",              "Meet Zo\u{00EB} re: r\u{00E9}sum\u{00E9}",                 "Meet Zoe re: resume"),
            ("non-breaking space",       "See you at 3\u{00A0}PM sharp",                             "See you at 3 PM sharp"),
            ("curly singles + en-dash",  "Reflect \u{2018}quietly\u{2019} \u{2013} you earned it",   "Reflect 'quietly' - you earned it"),
            ("pure ASCII identity",      "Two events today. Take a break before noon.",              "Two events today. Take a break before noon."),
        ]

        print("\n──────── ASCII wire-sanitizer verification: \(cases.count) realistic cases ────────")
        var asciiClean = 0
        for (i, c) in cases.enumerated() {
            let out = c.input.asciiSanitizedForEInk()
            let isAscii = out.utf8.allSatisfy { $0 >= 0x20 && $0 <= 0x7E }
            if isAscii { asciiClean += 1 }
            let n = String(format: "%2d", i + 1)
            print("\(n). [\(c.label)]  ascii=\(isAscii ? "PASS" : "FAIL")  matches-expected=\(out == c.expected ? "PASS" : "FAIL")")
            print("    in : \(c.input)")
            print("    out: \(out)")
            #expect(isAscii, "case \(i + 1) leaked non-ASCII byte on the wire: \(out)")
            #expect(out == c.expected, "case \(i + 1): got \"\(out)\", expected \"\(c.expected)\"")
        }
        print("──────── \(asciiClean)/\(cases.count) outputs are pure printable ASCII (0x20-0x7E) ────────\n")
        #expect(asciiClean == cases.count)
    }
}
