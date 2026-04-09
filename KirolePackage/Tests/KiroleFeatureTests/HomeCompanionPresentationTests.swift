import Foundation
import Testing
@testable import KiroleFeature

@Suite("Home Companion Presentation", .serialized)
struct HomeCompanionPresentationTests {
    @Test("New calendar day resets home companion to daily haiku")
    @MainActor
    func newCalendarDayResetsToDailyHaiku() async throws {
        let state = AppState.makeForTesting()
        let storage = LocalStorage.shared
        let now = makeDate(year: 2026, month: 4, day: 2, hour: 9)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let cachedHaiku = Haiku(lines: [
            "Fresh start arrives",
            "A new page opens quietly",
            "Begin with calm focus"
        ])

        try await storage.clearAll()
        try await storage.cacheHaiku(cachedHaiku, for: now)
        try await storage.saveSharedCompanionDialogue(
            SharedCompanionDialogueCache(
                date: dateKey(for: now),
                fingerprint: "today-fingerprint",
                text: "*waves paw* Today's cached dialogue."
            )
        )
        await storage.saveLastHomeHaikuShownDate(dateKey(for: yesterday))

        state.currentHaiku = .placeholder
        state.currentPetDialogue = ""
        state.homeCompanionDisplayMode = .petDialogue

        await state.refreshHomeCompanionPresentation(now: now)

        #expect(state.homeCompanionDisplayMode == .dailyHaiku)
        #expect(state.currentHaiku.lines == cachedHaiku.lines)
        #expect(state.currentPetDialogue == "*waves paw* Today's cached dialogue.")
        #expect(await storage.loadLastHomeHaikuShownDate() == dateKey(for: now))
    }

    @Test("Same-day revisit stays on pet dialogue and preserves current haiku")
    @MainActor
    func sameDayRevisitStaysOnPetDialogue() async throws {
        let state = AppState.makeForTesting()
        let storage = LocalStorage.shared
        let now = makeDate(year: 2026, month: 4, day: 2, hour: 14)
        let existingHaiku = Haiku(lines: [
            "Keep this haiku",
            "It should not be replaced today",
            "Dialogue takes over"
        ])

        try await storage.clearAll()
        try await storage.saveSharedCompanionDialogue(
            SharedCompanionDialogueCache(
                date: dateKey(for: now),
                fingerprint: "same-day-fingerprint",
                text: "*leans closer* Same-day cached dialogue."
            )
        )
        await storage.saveLastHomeHaikuShownDate(dateKey(for: now))

        state.currentHaiku = existingHaiku
        state.currentPetDialogue = ""
        state.homeCompanionDisplayMode = .dailyHaiku

        await state.refreshHomeCompanionPresentation(now: now)

        #expect(state.homeCompanionDisplayMode == .petDialogue)
        #expect(state.currentHaiku.lines == existingHaiku.lines)
        #expect(state.currentPetDialogue == "*leans closer* Same-day cached dialogue.")
        #expect(await storage.loadLastHomeHaikuShownDate() == dateKey(for: now))
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = 0
        components.second = 0
        return components.date!
    }

    private func dateKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}
