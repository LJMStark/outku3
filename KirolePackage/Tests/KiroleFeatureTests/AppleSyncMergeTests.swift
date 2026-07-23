import Testing
import Foundation
import EventKit
@testable import KiroleFeature

@Suite("Apple Sync Merge (B16)")
struct AppleSyncMergeTests {

    @Test("Apple reference events are excluded without dropping useful subscriptions")
    func systemReferenceEventsAreExcluded() {
        #expect(EventKitService.shouldSyncEvent(
            title: "大暑",
            calendarType: .subscription,
            isSubscribed: true,
            calendarTitle: "中国大陆节假日"
        ) == false)
        #expect(EventKitService.shouldSyncEvent(
            title: "Birthday",
            calendarType: .birthday,
            isSubscribed: false,
            calendarTitle: "Birthdays"
        ) == false)
        #expect(EventKitService.shouldSyncEvent(
            title: "Team practice",
            calendarType: .subscription,
            isSubscribed: true,
            calendarTitle: "Team Schedule"
        ))
        #expect(EventKitService.shouldSyncEvent(
            title: "League match",
            calendarType: .calDAV,
            isSubscribed: true,
            calendarTitle: "League Matches"
        ))
        #expect(EventKitService.shouldSyncEvent(
            title: "Campaign review",
            calendarType: .subscription,
            isSubscribed: true,
            calendarTitle: "Working Holiday Team Schedule"
        ))
        #expect(EventKitService.shouldSyncEvent(
            title: "大暑",
            calendarType: .subscription,
            isSubscribed: true,
            calendarTitle: "Team Schedule"
        ) == false)
        #expect(EventKitService.shouldSyncEvent(
            title: "大暑项目复盘",
            calendarType: .local,
            isSubscribed: false,
            calendarTitle: "Work"
        ))
    }

    private func makeTask(
        id: String,
        title: String,
        isCompleted: Bool,
        syncStatus: SyncStatus,
        lastModified: Date,
        remoteUpdatedAt: Date? = nil
    ) -> TaskItem {
        var task = TaskItem(id: id, title: title, source: .apple)
        task.isCompleted = isCompleted
        task.syncStatus = syncStatus
        task.lastModified = lastModified
        task.remoteUpdatedAt = remoteUpdatedAt
        task.appleReminderId = "rem-\(id)"
        return task
    }

    @Test("dirty local newer than remote is preserved (hardware completion not rolled back)")
    func dirtyLocalNewerIsPreserved() {
        // Hardware pushed a completion locally (marked .error because the EventKit push failed),
        // newer than the stale remote snapshot. The merge must keep the local completion.
        let local = makeTask(id: "1", title: "Task", isCompleted: true,
                             syncStatus: .error, lastModified: Date(timeIntervalSince1970: 2000))
        let remote = makeTask(id: "1", title: "Task", isCompleted: false,
                              syncStatus: .synced, lastModified: Date(timeIntervalSince1970: 1000),
                              remoteUpdatedAt: Date(timeIntervalSince1970: 1000))

        let merged = AppleSyncEngine.mergeLocalWithRemote(local: local, remote: remote)

        #expect(merged.isCompleted == true)
    }

    @Test("synced local takes remote values")
    func syncedLocalTakesRemote() {
        var local = makeTask(id: "1", title: "Old", isCompleted: false,
                             syncStatus: .synced, lastModified: Date(timeIntervalSince1970: 1000))
        let todayDisplayDate = Date(timeIntervalSince1970: 1500)
        local.todayDisplayDate = todayDisplayDate
        let remote = makeTask(id: "1", title: "New", isCompleted: true,
                              syncStatus: .synced, lastModified: Date(timeIntervalSince1970: 2000),
                              remoteUpdatedAt: Date(timeIntervalSince1970: 2000))

        let merged = AppleSyncEngine.mergeLocalWithRemote(local: local, remote: remote)

        #expect(merged.isCompleted == true)
        #expect(merged.title == "New")
        #expect(merged.todayDisplayDate == todayDisplayDate)
    }

    @Test("dirty local older than remote yields to remote (last-writer-wins)")
    func dirtyLocalOlderYieldsToRemote() {
        let local = makeTask(id: "1", title: "Local", isCompleted: false,
                             syncStatus: .pending, lastModified: Date(timeIntervalSince1970: 1000))
        let remote = makeTask(id: "1", title: "Remote", isCompleted: true,
                              syncStatus: .synced, lastModified: Date(timeIntervalSince1970: 3000),
                              remoteUpdatedAt: Date(timeIntervalSince1970: 3000))

        let merged = AppleSyncEngine.mergeLocalWithRemote(local: local, remote: remote)

        #expect(merged.isCompleted == true)
        #expect(merged.title == "Remote")
        // Adopting remote must also converge the sync status, not leave the local .pending dirty flag.
        #expect(merged.syncStatus == .synced)
    }
}
