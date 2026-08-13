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

    @Test("provider-scoped reminder IDs keep duplicate external UIDs in separate accounts and lists")
    func providerScopedReminderIdentity() throws {
        let firstReference = ProviderItemReference(
            provider: .appleReminders,
            accountID: "personal-account",
            containerID: "personal-list",
            itemID: "external:shared-uid",
            allowsContentModifications: true
        )
        let secondReference = ProviderItemReference(
            provider: .appleReminders,
            accountID: "work-account",
            containerID: "work-list",
            itemID: "external:shared-uid",
            allowsContentModifications: false
        )
        var firstLocal = makeTask(
            id: firstReference.stableLocalID,
            title: "Old personal",
            isCompleted: false,
            syncStatus: .synced,
            lastModified: .distantPast
        )
        firstLocal.appleExternalId = "shared-uid"
        firstLocal.appleReminderId = "personal-item"
        firstLocal.externalReference = firstReference
        var secondLocal = makeTask(
            id: secondReference.stableLocalID,
            title: "Old work",
            isCompleted: false,
            syncStatus: .synced,
            lastModified: .distantPast
        )
        secondLocal.appleExternalId = "shared-uid"
        secondLocal.appleReminderId = "work-item"
        secondLocal.externalReference = secondReference

        var firstRemote = firstLocal
        firstRemote.title = "Personal remote"
        firstRemote.lastModified = Date(timeIntervalSince1970: 2_000)
        var secondRemote = secondLocal
        secondRemote.title = "Work remote"
        secondRemote.lastModified = Date(timeIntervalSince1970: 3_000)

        let merged = AppleSyncEngine.mergeReminders(
            currentTasks: [firstLocal, secondLocal],
            remoteTasks: [firstRemote, secondRemote]
        )

        #expect(merged.count == 2)
        let personal = try #require(merged.first { $0.id == firstReference.stableLocalID })
        let work = try #require(merged.first { $0.id == secondReference.stableLocalID })
        #expect(personal.title == "Personal remote")
        #expect(work.title == "Work remote")
        #expect(personal.externalReference == firstReference)
        #expect(work.externalReference == secondReference)
    }

    @Test("legacy reminders match by calendar item identifier and gain provider metadata")
    func legacyReminderGetsProviderReference() throws {
        let reference = ProviderItemReference(
            provider: .appleReminders,
            accountID: "account",
            containerID: "list",
            itemID: "external:provider-uid",
            allowsContentModifications: false
        )
        var local = makeTask(
            id: "legacy-local",
            title: "Legacy",
            isCompleted: false,
            syncStatus: .synced,
            lastModified: .distantPast
        )
        local.appleExternalId = "provider-uid"
        local.appleReminderId = "calendar-item-id"
        local.externalReference = nil

        var remote = makeTask(
            id: reference.stableLocalID,
            title: "Remote",
            isCompleted: false,
            syncStatus: .synced,
            lastModified: Date(timeIntervalSince1970: 2_000)
        )
        remote.appleExternalId = "provider-uid"
        remote.appleReminderId = "calendar-item-id"
        remote.externalReference = reference

        let merged = AppleSyncEngine.mergeReminders(
            currentTasks: [local],
            remoteTasks: [remote]
        )

        let task = try #require(merged.first)
        #expect(task.title == "Remote")
        #expect(task.externalReference == reference)
    }
}
