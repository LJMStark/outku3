import Foundation
import Testing
@testable import KiroleFeature

@MainActor
@Suite("Daily content package generator")
struct DailyContentPackageGeneratorTests {
    @Test("A failed first preparation is retried once and the successful whole package wins")
    func retriesFirstFailureOnce() async {
        let expected = generatedPackage(marker: "retry")
        let preparer = ScriptedDailyContentPreparer(results: [
            .failure(TestPreparationError.failed),
            .success(expected),
        ])
        let generator = DailyContentPackageGenerator(preparer: preparer)

        let result = await generator.generate(input: generationInput(eventCount: 3))

        #expect(result == expected)
        #expect(preparer.attemptCount == 2)
    }

    @Test("Two failures use complete local templates for every daily slot and event")
    func secondFailureUsesCompleteFallback() async {
        let preparer = ScriptedDailyContentPreparer(results: [
            .failure(TestPreparationError.failed),
            .failure(TestPreparationError.failed),
        ])
        let input = generationInput(eventCount: 13)
        let generator = DailyContentPackageGenerator(preparer: preparer)

        let result = await generator.generate(input: input)

        #expect(preparer.attemptCount == 2)
        #expect(result.events.count == 13)
        #expect(!result.morningDialogue.isEmpty)
        #expect(!result.idleDialogue.isEmpty)
        #expect(!result.closingDialogue.isEmpty)
        #expect(!result.daySummary.isEmpty)
        #expect(!result.screensaverQuote.isEmpty)
        #expect(!result.screensaverAuthor.isEmpty)
        #expect(!result.settlementReview.isEmpty)
        #expect(!result.settlementQuote.isEmpty)
        #expect(result.settlementQuote != FallbackText.settlementQuoteFullSchedule())
        #expect(result.events.allSatisfy { !$0.companionDialogue.isEmpty })
        #expect(result.events.allSatisfy { !$0.supportText.isEmpty })
    }

    @Test("The fallback package excludes future events without truncating today")
    func fallbackUsesOnlyTodayWithoutLimit() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 3, hour: 8
        )))
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: now))
        let todayEvents = (0..<20).map { index in
            CalendarEvent(
                id: "today-\(index)",
                title: "Today \(index)",
                startTime: now.addingTimeInterval(Double(index * 600)),
                endTime: now.addingTimeInterval(Double(index * 600 + 300))
            )
        }
        let future = CalendarEvent(
            id: "future",
            title: "Future",
            startTime: tomorrow,
            endTime: tomorrow.addingTimeInterval(1_800)
        )
        let input = DailyContentGenerationInput(
            now: now,
            calendar: calendar,
            events: todayEvents + [future],
            tasks: [],
            pet: Pet(),
            userProfile: .default,
            customCompanions: [],
            usageDays: 1,
            sceneID: "harbor"
        )
        let preparer = ScriptedDailyContentPreparer(results: [
            .failure(TestPreparationError.failed),
            .failure(TestPreparationError.failed),
        ])

        let result = await DailyContentPackageGenerator(preparer: preparer).generate(input: input)

        #expect(result.events.count == 20)
        #expect(!result.events.contains { $0.eventID == "future" })
    }

    @Test("Every input that can change packaged text changes the package source fingerprint")
    func packageSourceFingerprintTracksTextInputs() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let profile = UserProfile.default
        let baseTask = TaskItem(id: "task", title: "Plan")
        let base = DailyContentSource.packageSourceFingerprint(
            events: [], tasks: [baseTask], pet: Pet(), usageDays: 1,
            sceneID: "harbor", focusMinutes: 0, at: now,
            userProfile: profile, customCompanions: []
        )
        var changedTask = baseTask
        changedTask.title = "Ship"
        var changedPet = Pet()
        changedPet.mood = .focused

        let variants = [
            DailyContentSource.packageSourceFingerprint(
                events: [], tasks: [changedTask], pet: Pet(), usageDays: 1,
                sceneID: "harbor", focusMinutes: 0, at: now,
                userProfile: profile, customCompanions: []
            ),
            DailyContentSource.packageSourceFingerprint(
                events: [], tasks: [baseTask], pet: changedPet, usageDays: 1,
                sceneID: "harbor", focusMinutes: 0, at: now,
                userProfile: profile, customCompanions: []
            ),
            DailyContentSource.packageSourceFingerprint(
                events: [], tasks: [baseTask], pet: Pet(), usageDays: 2,
                sceneID: "forest", focusMinutes: 30, at: now,
                userProfile: profile, customCompanions: []
            ),
        ]

        #expect(variants.allSatisfy { $0 != base })
    }

    @Test("A changed event title invalidates the reusable screensaver copy")
    func staticCopyFingerprintTracksEventTitles() {
        let base = DailyContentSource.staticCopyFingerprint(
            eventTitles: ["Planning"],
            tasks: [],
            pet: Pet(),
            usageDays: 1,
            sceneID: "harbor",
            userProfile: .default,
            customCompanions: []
        )
        let changed = DailyContentSource.staticCopyFingerprint(
            eventTitles: ["Review"],
            tasks: [],
            pet: Pet(),
            usageDays: 1,
            sceneID: "harbor",
            userProfile: .default,
            customCompanions: []
        )

        #expect(changed != base)
    }

    @Test("Custom-companion copy is invalidated when the intimacy stage changes")
    func customPersonaFingerprintTracksIntimacyStage() {
        var profile = UserProfile.default
        profile.customCompanionId = UUID(uuidString: "00000000-0000-0000-0000-000000000020")
        let base = DailyContentSource.personaFingerprint(
            userProfile: profile,
            customCompanions: []
        )
        profile.intimacyStage = .closeFriend

        let changed = DailyContentSource.personaFingerprint(
            userProfile: profile,
            customCompanions: []
        )

        #expect(changed != base)
    }
}

@MainActor
private final class ScriptedDailyContentPreparer: DailyContentPackagePreparing {
    private var results: [Result<DailyContentPackage, Error>]
    private(set) var attemptCount = 0

    init(results: [Result<DailyContentPackage, Error>]) {
        self.results = results
    }

    func prepare(input: DailyContentGenerationInput) async throws -> DailyContentPackage {
        attemptCount += 1
        return try results.removeFirst().get()
    }
}

private enum TestPreparationError: Error {
    case failed
}

private func generationInput(eventCount: Int) -> DailyContentGenerationInput {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    return DailyContentGenerationInput(
        now: now,
        events: (0..<eventCount).map { index in
            CalendarEvent(
                id: "event-\(index)",
                title: "Event \(index)",
                startTime: now.addingTimeInterval(Double(index * 900)),
                endTime: now.addingTimeInterval(Double(index * 900 + 600))
            )
        },
        tasks: [],
        pet: Pet(),
        userProfile: .default,
        customCompanions: [],
        usageDays: 1,
        sceneID: "harbor"
    )
}

private func generatedPackage(marker: String) -> DailyContentPackage {
    DailyContentPackage(
        localDate: DailyContentDate(year: 2026, month: 8, day: 3),
        morningDialogue: "morning-\(marker)",
        idleDialogue: "idle-\(marker)",
        closingDialogue: "closing-\(marker)",
        daySummary: "summary-\(marker)",
        screensaverQuote: "screen-\(marker)",
        screensaverAuthor: "Joy",
        settlementReview: "review-\(marker)",
        settlementQuote: "quote-\(marker)",
        events: []
    )
}
