import Foundation
import Testing
@testable import KiroleFeature

// MARK: - Event Support Text Tests

/// 支持性文字（客户 2026-07-28 六类规范）：每条日程按其类别的规则各写一句，随 DayPack
/// Events[] 下发，固件在该日程进行中时自行排版展示。
@Suite("Event Support Text")
struct EventSupportTextTests {

    // MARK: Reply parsing

    @Test("parseSupportTextReply accepts the strict numbered format")
    func parseAcceptsCleanReply() throws {
        let lines = try OpenAIService.parseSupportTextReply(
            "1|Just the first piece.\n2|A minute to gather your thoughts.",
            expectedCount: 2
        )

        #expect(lines == ["Just the first piece.", "A minute to gather your thoughts."])
    }

    @Test("parseSupportTextReply reorders out-of-order lines by their index")
    func parseReordersByIndex() throws {
        let lines = try OpenAIService.parseSupportTextReply(
            "2|second\n1|first",
            expectedCount: 2
        )

        // Pairing is by declared index, not arrival order — a swapped reply must not attach
        // the wrong line to the wrong event.
        #expect(lines == ["first", "second"])
    }

    @Test("parseSupportTextReply tolerates surrounding whitespace")
    func parseToleratesWhitespace() throws {
        let lines = try OpenAIService.parseSupportTextReply(
            "  1 | padded line  \n\n2|second\n",
            expectedCount: 2
        )

        #expect(lines == ["padded line", "second"])
    }

    @Test("parseSupportTextReply keeps a vertical bar inside the text")
    func parseKeepsInnerSeparator() throws {
        let lines = try OpenAIService.parseSupportTextReply("1|a|b", expectedCount: 1)

        // Only the FIRST bar separates index from text; later bars belong to the sentence.
        #expect(lines == ["a|b"])
    }

    @Test("parseSupportTextReply throws when a line is missing")
    func parseRejectsMissingLine() throws {
        #expect(throws: OpenAIError.self) {
            try OpenAIService.parseSupportTextReply("1|only one", expectedCount: 2)
        }
    }

    @Test("parseSupportTextReply throws on a duplicated index")
    func parseRejectsDuplicateIndex() throws {
        // 1,1 for a 2-event batch: accepting it would silently leave event 2 unpaired.
        #expect(throws: OpenAIError.self) {
            try OpenAIService.parseSupportTextReply("1|a\n1|b", expectedCount: 2)
        }
    }

    @Test("parseSupportTextReply throws on an out-of-range index")
    func parseRejectsOutOfRangeIndex() throws {
        #expect(throws: OpenAIError.self) {
            try OpenAIService.parseSupportTextReply("1|a\n3|c", expectedCount: 2)
        }
    }

    @Test("parseSupportTextReply rejects any extra malformed nonempty line")
    func parseRejectsMalformedExtrasEvenWhenExpectedLinesExist() throws {
        #expect(throws: OpenAIError.self) {
            try OpenAIService.parseSupportTextReply("1|a\n1|dup\n2|b", expectedCount: 2)
        }
        #expect(throws: OpenAIError.self) {
            try OpenAIService.parseSupportTextReply("preamble\n1|a\n2|b", expectedCount: 2)
        }
        #expect(throws: OpenAIError.self) {
            try OpenAIService.parseSupportTextReply("1|a\n2|b\n3|extra", expectedCount: 2)
        }
    }

    @Test("parseSupportTextReply throws on empty text and on prose without indices")
    func parseRejectsUnusableReplies() throws {
        #expect(throws: OpenAIError.self) {
            try OpenAIService.parseSupportTextReply("1|", expectedCount: 1)
        }
        #expect(throws: OpenAIError.self) {
            try OpenAIService.parseSupportTextReply("Here are your lines!", expectedCount: 1)
        }
    }

    // MARK: Fallback pools

    @Test("every category has a nonempty ASCII fallback line", arguments: [
        EventCategory.deepWork, .meetings, .admin, .deadline, .wellness, .rest
    ])
    func fallbackCoversEveryCategory(category: EventCategory) {
        let line = FallbackText.eventSupportText(for: category, seed: "calendar-item")
        let isPrintableASCII = line.utf8.allSatisfy { (0x20...0x7E).contains($0) }

        // Empty would mean the hardware renders nothing — the feature silently disappears.
        #expect(!line.isEmpty)
        // Wire is ASCII-only (0x20-0x7E); non-ASCII shows as tofu on the E-ink panel.
        #expect(isPrintableASCII)
        #expect(Data(line.utf8).count <= DayPackTextBudget.eventSupportText)
    }

    @Test("the same category and seed always choose the same fallback")
    func fallbackIsDeterministic() {
        let first = FallbackText.eventSupportText(for: .meetings, seed: "weekly-sync")

        for _ in 0..<20 {
            #expect(FallbackText.eventSupportText(for: .meetings, seed: "weekly-sync") == first)
        }
    }

    @Test("stable seeds cover every candidate in each category", arguments: [
        EventCategory.deepWork, .meetings, .admin, .deadline, .wellness, .rest
    ])
    func fallbackSeedCoversPool(category: EventCategory) {
        let lines = Set((0..<100).map {
            FallbackText.eventSupportText(for: category, seed: "event-\($0)")
        })

        #expect(lines.count == 3)
    }

    @Test("each fallback is one complete sentence", arguments: [
        EventCategory.deepWork, .meetings, .admin, .deadline, .wellness, .rest
    ])
    func fallbackIsOneSentence(category: EventCategory) {
        for seed in (0..<100).map({ "event-\($0)" }) {
            let line = FallbackText.eventSupportText(for: category, seed: seed)
            let sentenceEndCount = line.filter { ".!?".contains($0) }.count

            #expect(sentenceEndCount == 1)
            #expect(line.last.map { ".!?".contains($0) } == true)
        }
    }

    @Test("deadline fallback makes no progress or urgency claim")
    func deadlineFallbackAvoidsInventedStatus() {
        let forbiddenClaims = ["on track", "time's tight", "running out", "almost", "closer", "behind"]
        let lines = Set((0..<100).map {
            FallbackText.eventSupportText(for: .deadline, seed: "deadline-\($0)")
                .lowercased()
        })

        #expect(lines.count == 3)
        for line in lines {
            #expect(!forbiddenClaims.contains(where: line.contains))
        }
    }

    @Test("unknown category still yields a usable line instead of an empty string")
    func fallbackHandlesUnknownCategory() {
        let line = FallbackText.eventSupportText(for: .unknown, seed: "unknown-event")
        let isASCII = line.allSatisfy { $0.isASCII }

        #expect(!line.isEmpty)
        #expect(isASCII)
    }

    @Test("task fallback stays inside the tighter TaskInPage budget")
    func taskFallbackFitsTaskInPageBudget() {
        // TaskInPage Encouragement is 80B, narrower than the 120B event field.
        for seed in (0..<100).map({ "task-\($0)" }) {
            let line = FallbackText.eventSupportText(for: .deepWork, seed: seed)
            #expect(Data(line.utf8).count <= DayPackTextBudget.taskSupportText)
        }
    }

    // MARK: Cooldown

    @Test("AI failure cooldown blocks retries for ten minutes")
    func aiFailureCooldownBlocksRetries() {
        let failedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let retryAfter = failedAt.addingTimeInterval(EventSupportTextService.aiFailureCooldown)

        #expect(!EventSupportTextService.isAIRetryAllowed(
            retryAfter: retryAfter,
            now: failedAt.addingTimeInterval(599)
        ))
        #expect(EventSupportTextService.isAIRetryAllowed(
            retryAfter: retryAfter,
            now: failedAt.addingTimeInterval(600)
        ))
    }

    @Test("generation is allowed before any failure")
    func generationAllowedWithoutFailure() {
        #expect(EventSupportTextService.isAIRetryAllowed(retryAfter: nil, now: Date()))
    }

    @Test("accepted model text is wire-safe before byte truncation")
    func aiAcceptanceSanitizesBeforeBudgeting() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let raw = String(repeating: "a", count: DayPackTextBudget.eventSupportText - 1) + "…"
        let result = EventSupportTextService.evaluateAIReply(
            [raw], expectedCount: 1, maxBytes: DayPackTextBudget.eventSupportText, now: now
        )

        #expect(result.acceptedLines == [String(repeating: "a", count: DayPackTextBudget.eventSupportText - 1) + "."])
        #expect(result.retryAfter == nil)
    }

    @Test("CJK emoji error markers and sanitized-empty lines are rejected and start cooldown")
    func invalidAIItemsStartCooldown() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let result = EventSupportTextService.evaluateAIReply(
            // Escapes, not literals: these are the inputs the policy must REJECT, so they have to
            // stay in the test, but AGENTS.md bans emoji glyphs in source. U+1F525 fire,
            // U+1F389 party popper.
            ["Keep going.", "你好", "Good start \u{1F525}", "[Error] upstream", "\u{1F389}"],
            expectedCount: 5,
            maxBytes: DayPackTextBudget.eventSupportText,
            now: now
        )

        #expect(result.acceptedLines == ["Keep going.", nil, nil, nil, nil])
        #expect(result.retryAfter == now.addingTimeInterval(EventSupportTextService.aiFailureCooldown))
    }

    @Test("sanitized punctuation without an ASCII letter or digit is rejected")
    func punctuationOnlySanitizedOutputIsRejected() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let result = EventSupportTextService.evaluateAIReply(
            ["Привет."],
            expectedCount: 1,
            maxBytes: DayPackTextBudget.eventSupportText,
            now: now
        )

        #expect(result.acceptedLines == [nil])
        #expect(result.retryAfter == now.addingTimeInterval(EventSupportTextService.aiFailureCooldown))
    }

    @Test("a partially invalid batch keeps valid lines while cooling down failed lines")
    func partialAIResultPreservesSuccesses() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let result = EventSupportTextService.evaluateAIReply(
            // U+1F4A5 collision — escaped for the same reason as above.
            ["Open one small piece.", "\u{1F4A5}"],
            expectedCount: 2,
            maxBytes: DayPackTextBudget.eventSupportText,
            now: now
        )

        #expect(result.acceptedLines == ["Open one small piece.", nil])
        #expect(result.retryAfter != nil)
    }

    @Test("a quote-wrapped line is rejected but inner apostrophes are kept")
    func quoteWrappedLineIsRejectedApostrophesSurvive() {
        let result = EventSupportTextService.evaluateAIReply(
            [
                // Wrapped in quotes: support text is the App speaking plainly, never a quotation.
                "\"Just the first piece.\"",
                "'Just the first piece.'",
                // Apostrophes inside words are ordinary English — both are client example lines.
                "Bet you can't clear this before your coffee gets cold.",
                "What's the one part of this you already know how to start?"
            ],
            expectedCount: 4,
            maxBytes: DayPackTextBudget.eventSupportText,
            now: Date()
        )

        #expect(result.acceptedLines[0] == nil)
        #expect(result.acceptedLines[1] == nil)
        #expect(result.acceptedLines[2] != nil)
        #expect(result.acceptedLines[3] != nil)
    }

    @Test("model support text must be exactly one complete sentence")
    func aiAcceptanceRejectsMultipleOrIncompleteSentences() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let result = EventSupportTextService.evaluateAIReply(
            ["Start here. Then do that.", "Start here", "Pause..."],
            expectedCount: 3,
            maxBytes: DayPackTextBudget.eventSupportText,
            now: now
        )

        #expect(result.acceptedLines == [nil, nil, "Pause..."])
        #expect(result.retryAfter != nil)
    }

    // MARK: Prompt compilation

    @Test("compiled prompt carries the category number for each event")
    func compiledPromptCarriesCategories() async {
        let compiled = await OpenAIService.shared.compileEventSupportTextPromptForFixture(events: [
            OpenAIService.EventSupportTextInput(title: "Ship the release", category: .deadline),
            OpenAIService.EventSupportTextInput(title: "Nap", category: .rest)
        ])

        #expect(compiled.systemPrompt.hasPrefix(PromptSanitizer.securityInstruction))
        // The category number is what selects the writing rule — without it the model would
        // have to guess which of the six angles applies.
        #expect(compiled.userPrompt.contains("1. [category 4] Ship the release"))
        // Rest does NOT carry the density hint — the client wrote that rule for Wellness only.
        #expect(compiled.userPrompt.contains("2. [category 6] Nap"))
        #expect(compiled.userPrompt.contains("<user_content>"))
    }

    @Test("the packed-day wellness fallback claims no more than isDayBusy can prove")
    func packedWellnessFallbackClaimsOnlyWhatIsProven() {
        // isDayBusy proves exactly one thing: somewhere today there is a busy stretch. It does NOT
        // establish when (the crowding may still be ahead), how much of the day is occupied (one
        // sub-hour gap between two events flips it), or where relative to this event (the tight pair
        // can sit hours away). Each banned phrase below would assert one of those.
        let lines = Set((0..<60).map {
            FallbackText.eventSupportText(for: .wellness, seed: "seed-\($0)", isDayPacked: true)
        })
        let overreach = [
            "has been", "have been", "was ", "were ", "so far",   // tense: already happened
            "full day", "all day", "every hour", "back-to-back",  // scope: whole-day occupancy
            "around this", "right after", "just before", "nearby" // position: adjacency to this event
        ]

        #expect(!lines.isEmpty)
        for line in lines {
            let lowered = line.lowercased()
            for phrase in overreach {
                #expect(!lowered.contains(phrase), "packed-day line overreaches (\(phrase)): \(line)")
            }
        }
    }

    @Test("isDayBusy flips on a single sub-hour gap, which is why the copy stays scope-free")
    func isDayBusyFiresOnOneTightGapBetweenTwoEvents() {
        // The concrete counterexample the copy has to survive: 90 minutes of events across a
        // 1440-minute day still counts as busy, so "full day" would be false.
        let twoTightEvents = [
            EventSummary(time: "09:00", endTime: "10:00", title: "A", description: ""),
            EventSummary(time: "10:30", endTime: "11:00", title: "B", description: "")
        ]
        let twoLooseEvents = [
            EventSummary(time: "09:00", endTime: "10:00", title: "A", description: ""),
            EventSummary(time: "16:00", endTime: "17:00", title: "B", description: "")
        ]

        #expect(FallbackText.isDayBusy(twoTightEvents))
        #expect(!FallbackText.isDayBusy(twoLooseEvents))
        // A lone event is never busy — hasTightGap alone would wrongly say true here, having no
        // second span to measure against. That mismatch is why isDayBusy exists.
        #expect(!FallbackText.isDayBusy([twoLooseEvents[0]]))
    }

    @Test("isDayBusy does not infer busyness from an unparseable all-day event")
    func isDayBusyRejectsUnprovableAllDayDensity() {
        let events = [
            EventSummary(time: "", endTime: "", title: "All-day note", description: ""),
            EventSummary(time: "18:00", endTime: "18:30", title: "Stretch", description: "")
        ]

        #expect(!FallbackText.isDayBusy(events))
    }

    @Test("packed and open wellness fallbacks are different copy")
    func packedAndOpenWellnessFallbacksDiffer() {
        // The client rule for a packed day is "acknowledge the busy stretch FIRST, then nudge".
        // If both states drew from one pool the acknowledgement would silently vanish on busy days.
        let packed = Set((0..<40).map {
            FallbackText.eventSupportText(for: .wellness, seed: "s\($0)", isDayPacked: true)
        })
        let open = Set((0..<40).map {
            FallbackText.eventSupportText(for: .wellness, seed: "s\($0)", isDayPacked: false)
        })

        #expect(packed.isDisjoint(with: open))
        // Non-Wellness categories ignore the flag entirely (client scoped the rule to Wellness).
        for category in [EventCategory.deepWork, .meetings, .admin, .deadline, .rest] {
            #expect(
                FallbackText.eventSupportText(for: category, seed: "k", isDayPacked: true)
                    == FallbackText.eventSupportText(for: category, seed: "k", isDayPacked: false)
            )
        }
    }

    @Test("the day-density hint reaches only Wellness, not Rest or other categories")
    func densityHintOnlyOnWellness() async {
        let packed = await OpenAIService.shared.compileEventSupportTextPromptForFixture(events: [
            OpenAIService.EventSupportTextInput(
                title: "Deep work block", category: .deepWork, isDayPacked: true
            ),
            OpenAIService.EventSupportTextInput(
                title: "Stretch break", category: .wellness, isDayPacked: true
            ),
            OpenAIService.EventSupportTextInput(
                title: "Lunch", category: .rest, isDayPacked: true
            )
        ])

        // Only Wellness gets the density hint. Deep Work and Rest never should: Deep Work must
        // name the smallest first step regardless of the day's fullness, and Rest grants permission
        // unconditionally.
        #expect(packed.userPrompt.contains("1. [category 1] Deep work block"))
        #expect(packed.userPrompt.contains("2. [category 5, packed day] Stretch break"))
        #expect(packed.userPrompt.contains("3. [category 6] Lunch"))
    }

    @Test("an open day flips the hint rather than dropping it")
    func densityHintDistinguishesOpenFromPacked() async {
        let open = await OpenAIService.shared.compileEventSupportTextPromptForFixture(events: [
            OpenAIService.EventSupportTextInput(
                title: "Stretch break", category: .wellness, isDayPacked: false
            )
        ])

        // Both states are stated explicitly: the prompt tells the model to SKIP the busyness
        // remark on an open day, which it can only do if it can tell the two apart.
        #expect(open.userPrompt.contains("1. [category 5, open day] Stretch break"))
        #expect(!open.userPrompt.contains("packed day"))
    }

    // MARK: Task support line (0x11 Encouragement)

    @Test("the task prompt asks the model for a Deep Work line about this title")
    func taskPromptUsesDeepWorkCategoryAndTitle() async {
        let compiled = await OpenAIService.shared.compileEventSupportTextPromptForFixture(events: [
            OpenAIService.EventSupportTextInput(title: "Draft the Q3 report", category: .deepWork)
        ])

        // The client's Deep Work rule is "name the concrete first step when the title implies
        // one" — only reachable by sending the title to the model. A title-seeded template pick
        // can never satisfy it, so the title and category 1 must both be in the prompt.
        #expect(compiled.userPrompt.contains("1. [category 1] Draft the Q3 report"))
    }

    @Test("the 0x11 read never awaits the network and never returns empty")
    @MainActor
    func taskSupportTextReadIsNonBlocking() {
        // The device is already parked on the task detail page waiting for 0x11. With no notes,
        // taskOverview returns immediately, so an awaiting support line would be the ONLY wait —
        // up to model.requestTimeoutSeconds (60s) of blank screen. This accessor is therefore
        // synchronous by contract: cache hit, else deterministic template.
        let line = EventSupportTextService.shared.cachedOrFallbackTaskSupportText(
            taskTitle: "Draft the Q3 report"
        )

        #expect(!line.isEmpty)
        #expect(Data(line.utf8).count <= DayPackTextBudget.taskSupportText)
        // Same title must give the same bytes, so an unchanged task does not churn the frame.
        #expect(line == EventSupportTextService.shared.cachedOrFallbackTaskSupportText(
            taskTitle: "Draft the Q3 report"
        ))
    }

    @Test("task lines are held to the tighter 80-byte TaskInPage budget")
    func taskLineUsesTaskInPageBudget() {
        let long = String(repeating: "word ", count: 40) + "end."
        let asEvent = EventSupportTextService.evaluateAIReply(
            [long], expectedCount: 1, maxBytes: DayPackTextBudget.eventSupportText, now: Date()
        )
        let asTask = EventSupportTextService.evaluateAIReply(
            [long], expectedCount: 1, maxBytes: DayPackTextBudget.taskSupportText, now: Date()
        )

        // Same reply, two fields, two budgets: 120B for Events[] vs 80B for TaskInPage.
        #expect(DayPackTextBudget.taskSupportText < DayPackTextBudget.eventSupportText)
        for line in (asEvent.acceptedLines + asTask.acceptedLines).compactMap({ $0 }) {
            #expect(Data(line.utf8).count <= DayPackTextBudget.eventSupportText)
        }
        for line in asTask.acceptedLines.compactMap({ $0 }) {
            #expect(Data(line.utf8).count <= DayPackTextBudget.taskSupportText)
        }
    }

    @Test("the admin fallback keeps the client's self-contest framing")
    func adminFallbackKeepsContestFraming() {
        // Client rule for Administrative & Routine is a wager against your own speed / accuracy /
        // record — never drudgery, never a neutral "calm round". Sweep seeds to cover the pool.
        let lines = Set((0..<60).map {
            FallbackText.eventSupportText(for: .admin, seed: "seed-\($0)")
        })
        let contestWords = ["beat", "pace", "clean pass", "accuracy", "first attempt"]

        #expect(!lines.isEmpty)
        for line in lines {
            let lowered = line.lowercased()
            #expect(
                contestWords.contains { lowered.contains($0) },
                "admin fallback lost the self-contest framing: \(line)"
            )
        }
    }

    @Test("all six category rules are stated in the system prompt")
    func systemPromptStatesEverySixRule() {
        let template = OpenAIService.promptTool("eventSupportText").systemPromptTemplate

        #expect(template.contains("1 = Deep Work"))
        #expect(template.contains("2 = Meetings and Synced"))
        #expect(template.contains("3 = Administrative and Routine"))
        #expect(template.contains("4 = Critical Deadlines"))
        #expect(template.contains("5 = Bio-Habits and Wellness"))
        #expect(template.contains("6 = Rest and Recharge"))
        // Client's universal rule: never fabricate specifics the event data does not contain.
        #expect(template.lowercased().contains("never invent"))
    }
}
