import Foundation
import Testing
@testable import KiroleFeature

// MARK: - Event Category Tests

@Suite("Event Category")
struct EventCategoryTests {

    // MARK: Heuristic fallback

    @Test("heuristic maps obvious keywords to the customer's six categories")
    func heuristicMapsObviousKeywords() {
        #expect(EventCategory.heuristic(for: "Weekly ops sync") == .meetings)
        #expect(EventCategory.heuristic(for: "Contract signing deadline") == .deadline)
        #expect(EventCategory.heuristic(for: "Stretch break") == .wellness)
        #expect(EventCategory.heuristic(for: "Lunch with Sam") == .rest)
        #expect(EventCategory.heuristic(for: "Inbox zero — clear email") == .admin)
        #expect(EventCategory.heuristic(for: "Deep work: coding session") == .deepWork)
    }

    @Test("heuristic returns unknown rather than guessing on ambiguous titles")
    func heuristicReturnsUnknownWhenAmbiguous() {
        #expect(EventCategory.heuristic(for: "Dentist") == .unknown)
        #expect(EventCategory.heuristic(for: "Q3") == .unknown)
        #expect(EventCategory.heuristic(for: "") == .unknown)
    }

    @Test("AI failure cooldown blocks retries for ten minutes")
    func aiFailureCooldownBlocksRetries() {
        let failedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let retryAfter = failedAt.addingTimeInterval(EventCategoryService.aiFailureCooldown)

        #expect(!EventCategoryService.isAIRetryAllowed(
            retryAfter: retryAfter,
            now: failedAt.addingTimeInterval(599)
        ))
        #expect(EventCategoryService.isAIRetryAllowed(
            retryAfter: retryAfter,
            now: failedAt.addingTimeInterval(600)
        ))
    }

    @Test("AI classification is allowed before any failure")
    func aiClassificationAllowedWithoutFailure() {
        #expect(EventCategoryService.isAIRetryAllowed(retryAfter: nil, now: Date()))
    }

    // MARK: Classifier reply parsing

    @Test("parseCategoryReply accepts a clean comma-separated digit line")
    func parseAcceptsCleanReply() throws {
        let categories = try OpenAIService.parseCategoryReply("2,5,1", expectedCount: 3)
        #expect(categories == [.meetings, .wellness, .deepWork])
    }

    @Test("parseCategoryReply tolerates spaces and newlines")
    func parseToleratesNoise() throws {
        let categories = try OpenAIService.parseCategoryReply(" 4 ,\n6 ", expectedCount: 2)
        #expect(categories == [.deadline, .rest])
    }

    @Test("parseCategoryReply throws when the count does not match the input")
    func parseRejectsMisalignedCount() {
        #expect(throws: OpenAIError.self) {
            _ = try OpenAIService.parseCategoryReply("1,2", expectedCount: 3)
        }
        #expect(throws: OpenAIError.self) {
            _ = try OpenAIService.parseCategoryReply("No events to classify.", expectedCount: 1)
        }
    }

    @Test("parseCategoryReply rejects digits outside 1-6, including 0/unknown")
    func parseRejectsOutOfRangeDigits() {
        #expect(throws: OpenAIError.self) {
            _ = try OpenAIService.parseCategoryReply("0,3", expectedCount: 2)
        }
        #expect(throws: OpenAIError.self) {
            _ = try OpenAIService.parseCategoryReply("7", expectedCount: 1)
        }
    }

    // MARK: Model integration

    @Test("withCategory returns a copy that only swaps the category")
    func withCategorySwapsOnlyCategory() {
        let original = EventSummary(time: "09:30", title: "HW Sync", description: "Bring the logic analyzer.")
        let tagged = original.withCategory(.meetings)
        #expect(original.category == .unknown)
        #expect(tagged.category == .meetings)
        #expect(tagged.time == original.time)
        #expect(tagged.title == original.title)
        #expect(tagged.description == original.description)
    }

    @Test("DayPackGenerator tags events via the heuristic when AI is unavailable")
    @MainActor
    func generatorTagsEventsWithoutAI() async {
        let calendar = Calendar.current
        let today = Date()
        let events = [
            CalendarEvent(
                id: "cat-sync", title: "Weekly ops sync",
                startTime: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today)!,
                endTime: calendar.date(bySettingHour: 9, minute: 30, second: 0, of: today)!
            ),
            CalendarEvent(
                id: "cat-stretch", title: "Stretch break",
                startTime: calendar.date(bySettingHour: 15, minute: 0, second: 0, of: today)!,
                endTime: calendar.date(bySettingHour: 15, minute: 10, second: 0, of: today)!
            )
        ]

        let dayPack = await DayPackGenerator.shared.generateDayPack(
            pet: Pet(), tasks: [], events: events,
            weather: Weather(), deviceMode: .interactive,
            petDialogue: "Ready"
        )

        // No API key in the test environment → the batched AI call is skipped and the
        // keyword heuristic fills the categories deterministically.
        #expect(dayPack.events.map(\.category) == [.meetings, .wellness])
    }

    @Test("DayPack fingerprint changes when only an event category changes")
    func fingerprintTracksCategory() {
        let settlement = SettlementData(
            tasksCompleted: 0, tasksTotal: 0, pointsEarned: 0,
            petMood: "happy", summaryMessage: "", encouragementMessage: ""
        )
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let untagged = DayPack(
            date: date, petDialogue: "hi",
            events: [EventSummary(time: "09:00", title: "Sync", description: "team")],
            settlementData: settlement
        )
        let tagged = DayPack(
            date: date, petDialogue: "hi",
            events: [EventSummary(time: "09:00", title: "Sync", description: "team", category: .meetings)],
            settlementData: settlement
        )
        #expect(untagged.stableFingerprint() != tagged.stableFingerprint())
    }
}
