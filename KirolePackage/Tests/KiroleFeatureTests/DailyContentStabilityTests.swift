import Foundation
import Testing
@testable import KiroleFeature

@Suite("Daily content stability window")
struct DailyContentStabilityTests {
    @MainActor
    @Test("The App shows edits immediately while hardware keeps the prior schedule until the deadline")
    func appAndHardwareUseDifferentProjectionsDuringWindow() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let old = makeStabilityEvent(id: "event", title: "Before", start: now)
        var edited = old
        edited.title = "After"
        let state = AppState.makeForTesting()
        state.dailyContentNowProvider = { now }
        state.suppressesDailyContentChangeTracking = true
        state.events = [old]
        state.suppressesDailyContentChangeTracking = false

        state.events = [edited]

        #expect(state.events.first?.title == "After")
        #expect(state.dailyContentPresentationSnapshot().events.first?.title == "Before")

        state.dailyContentNowProvider = { now.addingTimeInterval(180) }
        let ready = state.dailyContentPresentationSnapshot()
        #expect(ready.events.first?.title == "After")
        #expect(ready.readyGeneration == state.dailyContentStabilityState.generation)
    }

    @Test("A current-day edit becomes ready three minutes after the last change")
    func currentDayEditUsesLastChangeDeadline() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let start = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 3, hour: 9
        )))
        let event = makeStabilityEvent(id: "event", title: "First", start: start)
        var changed = event
        changed.title = "Second"
        var changedAgain = changed
        changedAgain.title = "Final"
        var state = DailyContentStabilityState()

        let recordedFirst = state.recordChanges(
            from: [event], to: [changed], at: start, calendar: calendar
        )
        #expect(recordedFirst)
        #expect(state.readyGeneration(at: start.addingTimeInterval(179)) == nil)

        let secondEdit = start.addingTimeInterval(120)
        let recordedSecond = state.recordChanges(
            from: [changed], to: [changedAgain], at: secondEdit, calendar: calendar
        )
        #expect(recordedSecond)
        #expect(state.readyGeneration(at: start.addingTimeInterval(299)) == nil)
        #expect(state.readyGeneration(at: start.addingTimeInterval(300)) == state.generation)
    }

    @Test("Changing only a future event does not start the daily-content window")
    func futureEventDoesNotStartWindow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 3, hour: 9
        )))
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: now))
        let event = makeStabilityEvent(id: "future", title: "Original", start: tomorrow)
        var changed = event
        changed.title = "Updated"
        var state = DailyContentStabilityState()

        let recorded = state.recordChanges(
            from: [event], to: [changed], at: now, calendar: calendar
        )
        #expect(!recorded)
        #expect(state.deadline == nil)
        #expect(state.changedEventIDs.isEmpty)
    }

    @Test("A successful commit clears only the captured generation")
    func commitIsGenerationBound() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let event = makeStabilityEvent(id: "event", title: "Original", start: now)
        var first = event
        first.title = "First"
        var second = first
        second.title = "Second"
        var state = DailyContentStabilityState()
        let recordedFirst = state.recordChanges(from: [event], to: [first], at: now)
        #expect(recordedFirst)
        let firstGeneration = state.generation
        let recordedSecond = state.recordChanges(
            from: [first], to: [second], at: now.addingTimeInterval(30)
        )
        #expect(recordedSecond)

        state.markCommitted(capturedGeneration: firstGeneration)
        #expect(!state.changedEventIDs.isEmpty)

        state.markCommitted(capturedGeneration: state.generation)
        #expect(state.changedEventIDs.isEmpty)
        #expect(state.deadline == nil)
    }
}

private func makeStabilityEvent(id: String, title: String, start: Date) -> CalendarEvent {
    CalendarEvent(
        id: id,
        title: title,
        startTime: start,
        endTime: start.addingTimeInterval(1_800)
    )
}
