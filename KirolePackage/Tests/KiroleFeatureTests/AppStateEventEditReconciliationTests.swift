import Foundation
import Testing
@testable import KiroleFeature

@Suite("Event Edit Reconciliation")
struct AppStateEventEditReconciliationTests {
    @Test("A remote edit result follows its event after the local array is reordered")
    func remoteResultFollowsReorderedEvent() throws {
        let baseline = Date(timeIntervalSince1970: 1_700_000_000)
        let target = makeEvent(id: "target", title: "Before", lastModified: baseline)
        let other = makeEvent(id: "other", title: "Other", lastModified: baseline)
        let synced = makeEvent(id: "target", title: "After", lastModified: baseline.addingTimeInterval(1))

        let reconciled = try #require(AppState.replacingEvent(
            in: [other, target],
            with: synced,
            matching: target.id,
            expectedLastModified: baseline
        ))

        #expect(reconciled.map(\.id) == ["other", "target"])
        #expect(reconciled[0].title == "Other")
        #expect(reconciled[1].title == "After")
    }

    @Test("A remote edit result cannot resurrect a deleted event")
    func remoteResultDoesNotResurrectDeletedEvent() {
        let baseline = Date(timeIntervalSince1970: 1_700_000_000)
        let synced = makeEvent(id: "target", title: "After", lastModified: baseline.addingTimeInterval(1))

        let reconciled = AppState.replacingEvent(
            in: [makeEvent(id: "other", title: "Other", lastModified: baseline)],
            with: synced,
            matching: "target",
            expectedLastModified: baseline
        )

        #expect(reconciled?.count == nil)
    }

    @Test("A remote edit result cannot overwrite a newer local version")
    func remoteResultDoesNotOverwriteNewerVersion() {
        let baseline = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = makeEvent(
            id: "target",
            title: "Newer local value",
            lastModified: baseline.addingTimeInterval(2)
        )
        let synced = makeEvent(id: "target", title: "Stale remote value", lastModified: baseline.addingTimeInterval(1))

        let reconciled = AppState.replacingEvent(
            in: [newer],
            with: synced,
            matching: "target",
            expectedLastModified: baseline
        )

        #expect(reconciled?.count == nil)
    }

    private func makeEvent(id: String, title: String, lastModified: Date) -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: title,
            startTime: Date(timeIntervalSince1970: 1_700_003_600),
            endTime: Date(timeIntervalSince1970: 1_700_007_200),
            lastModified: lastModified
        )
    }
}
