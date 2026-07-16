import Foundation
import Testing
@testable import KiroleFeature

@Suite("Task Edit Reconciliation")
struct AppStateTaskEditReconciliationTests {
    @Test("A remote edit result follows its task after the local array is reordered")
    func remoteResultFollowsReorderedTask() throws {
        let baseline = Date(timeIntervalSince1970: 1_700_000_000)
        let target = makeTask(id: "target", title: "Before", lastModified: baseline)
        let other = makeTask(id: "other", title: "Other", lastModified: baseline)
        let synced = makeTask(
            id: "target",
            title: "After",
            lastModified: baseline.addingTimeInterval(1)
        )

        let reconciled = try #require(AppState.replacingTask(
            in: [other, target],
            with: synced,
            matching: target.id,
            baseline: target
        ))

        #expect(reconciled.map(\.id) == ["other", "target"])
        #expect(reconciled[0].title == "Other")
        #expect(reconciled[1].title == "After")
    }

    @Test("A remote edit result is ignored after the task was deleted")
    func remoteResultDoesNotRestoreDeletedTask() {
        let baseline = Date(timeIntervalSince1970: 1_700_000_000)
        let synced = makeTask(
            id: "target",
            title: "After",
            lastModified: baseline.addingTimeInterval(1)
        )

        let baselineTask = makeTask(id: "target", title: "Before", lastModified: baseline)
        let reconciled = AppState.replacingTask(
            in: [makeTask(id: "other", title: "Other", lastModified: baseline)],
            with: synced,
            matching: "target",
            baseline: baselineTask
        )

        #expect(reconciled == nil)
    }

    @Test("A stale remote edit cannot overwrite a newer local task version")
    func remoteResultDoesNotOverwriteNewerVersion() {
        let baseline = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = makeTask(
            id: "target",
            title: "Newer local value",
            lastModified: baseline.addingTimeInterval(2)
        )
        let synced = makeTask(
            id: "target",
            title: "Stale remote value",
            lastModified: baseline.addingTimeInterval(1)
        )

        let reconciled = AppState.replacingTask(
            in: [newer],
            with: synced,
            matching: "target",
            baseline: makeTask(id: "target", title: "Before", lastModified: baseline)
        )

        #expect(reconciled == nil)
    }

    @Test("A concurrent completion toggle is preserved while task content is reconciled")
    func remoteContentEditPreservesConcurrentCompletion() throws {
        let baselineDate = Date(timeIntervalSince1970: 1_700_000_000)
        let baseline = makeTask(id: "target", title: "Before", lastModified: baselineDate)
        var completed = baseline
        completed.isCompleted = true
        completed.syncStatus = .pending
        completed.lastModified = baselineDate.addingTimeInterval(2)
        let synced = makeTask(
            id: "target",
            title: "Edited title",
            lastModified: baselineDate.addingTimeInterval(1)
        )

        let reconciled = try #require(AppState.replacingTask(
            in: [completed],
            with: synced,
            matching: "target",
            baseline: baseline
        ))

        #expect(reconciled[0].title == "Edited title")
        #expect(reconciled[0].isCompleted)
        #expect(reconciled[0].syncStatus == .pending)
        #expect(reconciled[0].lastModified == completed.lastModified)
    }

    @Test("A remote content edit preserves a concurrent Show Today choice")
    func remoteContentEditPreservesTodayDisplayDate() throws {
        let baselineDate = Date(timeIntervalSince1970: 1_700_000_000)
        let displayDate = baselineDate.addingTimeInterval(60)
        let baseline = makeTask(id: "target", title: "Before", lastModified: baselineDate)
        var displayedToday = baseline
        displayedToday.todayDisplayDate = displayDate
        let synced = makeTask(
            id: "target",
            title: "Edited title",
            lastModified: baselineDate.addingTimeInterval(1)
        )

        let reconciled = try #require(AppState.replacingTask(
            in: [displayedToday],
            with: synced,
            matching: "target",
            baseline: baseline
        ))

        #expect(reconciled[0].title == "Edited title")
        #expect(reconciled[0].todayDisplayDate == displayDate)
    }

    private func makeTask(id: String, title: String, lastModified: Date) -> TaskItem {
        TaskItem(id: id, title: title, lastModified: lastModified)
    }
}
