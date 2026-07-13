import Foundation
import Testing
@testable import KiroleFeature

@Suite("Remote Merge Preservation Tests")
struct RemoteMergePreservationTests {
    @Test("Taskade sparse remote keeps local metadata fields")
    func taskadeSparseRemoteKeepsLocalMetadata() {
        let preservedLocalId = UUID()
        let preservedDueDate = Date(timeIntervalSince1970: 1_700_000_000)
        let preservedTodayDisplayDate = Date(timeIntervalSince1970: 1_700_010_000)

        let local = TaskItem(
            id: "task-1",
            localId: preservedLocalId,
            taskadeTaskId: "task-1",
            taskadeProjectId: "project-1",
            title: "Local title",
            isCompleted: false,
            dueDate: preservedDueDate,
            source: .taskade,
            priority: .high,
            syncStatus: .synced,
            lastModified: Date(timeIntervalSince1970: 100),
            remoteUpdatedAt: Date(timeIntervalSince1970: 100),
            notes: "local note",
            todayDisplayDate: preservedTodayDisplayDate
        )
        let remote = TaskItem(
            id: "task-1",
            taskadeTaskId: "task-1",
            taskadeProjectId: "project-1",
            title: "Remote title",
            isCompleted: true,
            dueDate: nil,
            source: .taskade,
            priority: .medium,
            syncStatus: .synced,
            lastModified: Date(timeIntervalSince1970: 200),
            remoteUpdatedAt: Date(timeIntervalSince1970: 200),
            notes: nil
        )

        let merged = TaskadeSyncEngine.mergeRemoteTaskPreservingLocalFields(local: local, remote: remote)

        #expect(merged.title == "Remote title")
        #expect(merged.isCompleted)
        #expect(merged.localId == preservedLocalId)
        #expect(merged.dueDate == preservedDueDate)
        #expect(merged.priority == .high)
        #expect(merged.notes == "local note")
        #expect(merged.todayDisplayDate == preservedTodayDisplayDate)
    }

    @Test("Notion sparse remote keeps local metadata fields")
    func notionSparseRemoteKeepsLocalMetadata() {
        let preservedLocalId = UUID()
        let preservedDueDate = Date(timeIntervalSince1970: 1_700_000_100)
        let preservedTodayDisplayDate = Date(timeIntervalSince1970: 1_700_010_100)

        let local = TaskItem(
            id: "page-1",
            localId: preservedLocalId,
            notionPageId: "page-1",
            notionDatabaseId: "db-1",
            title: "Local title",
            isCompleted: false,
            dueDate: preservedDueDate,
            source: .notion,
            priority: .low,
            syncStatus: .synced,
            lastModified: Date(timeIntervalSince1970: 100),
            remoteUpdatedAt: Date(timeIntervalSince1970: 100),
            notes: "local note",
            todayDisplayDate: preservedTodayDisplayDate
        )
        let remote = TaskItem(
            id: "page-1",
            notionPageId: "page-1",
            notionDatabaseId: "db-1",
            title: "Remote title",
            isCompleted: true,
            dueDate: nil,
            source: .notion,
            priority: .medium,
            syncStatus: .synced,
            lastModified: Date(timeIntervalSince1970: 200),
            remoteUpdatedAt: Date(timeIntervalSince1970: 200),
            notes: nil
        )

        let merged = NotionSyncEngine.mergeRemoteTaskPreservingLocalFields(local: local, remote: remote)

        #expect(merged.title == "Remote title")
        #expect(merged.isCompleted)
        #expect(merged.localId == preservedLocalId)
        #expect(merged.dueDate == preservedDueDate)
        #expect(merged.priority == .low)
        #expect(merged.notes == "local note")
        #expect(merged.todayDisplayDate == preservedTodayDisplayDate)
    }

    @Test("Notion merge honors explicit remote metadata when provided")
    func notionMergeHonorsExplicitRemoteMetadata() {
        let local = TaskItem(
            id: "page-2",
            notionPageId: "page-2",
            notionDatabaseId: "db-1",
            title: "Local title",
            isCompleted: false,
            dueDate: Date(timeIntervalSince1970: 1_700_000_200),
            source: .notion,
            priority: .low,
            syncStatus: .synced,
            lastModified: Date(timeIntervalSince1970: 100),
            notes: "local note"
        )
        let remoteDueDate = Date(timeIntervalSince1970: 1_700_000_300)
        let remote = TaskItem(
            id: "page-2",
            notionPageId: "page-2",
            notionDatabaseId: "db-1",
            title: "Remote title",
            isCompleted: true,
            dueDate: remoteDueDate,
            source: .notion,
            priority: .high,
            syncStatus: .synced,
            lastModified: Date(timeIntervalSince1970: 200),
            remoteUpdatedAt: Date(timeIntervalSince1970: 200),
            notes: "remote note"
        )

        let merged = NotionSyncEngine.mergeRemoteTaskPreservingLocalFields(local: local, remote: remote)

        #expect(merged.dueDate == remoteDueDate)
        #expect(merged.priority == .high)
        #expect(merged.notes == "remote note")
    }

    @Test("Google remote refresh keeps local today display selection")
    func googleRemoteKeepsLocalTodayDisplaySelection() {
        let selectedDate = Date(timeIntervalSince1970: 1_700_020_000)
        let local = TaskItem(
            id: "google-1",
            googleTaskId: "google-1",
            googleTaskListId: "list-1",
            title: "Local",
            source: .google,
            todayDisplayDate: selectedDate
        )
        let remote = TaskItem(
            id: "google-1",
            googleTaskId: "google-1",
            googleTaskListId: "list-1",
            title: "Remote",
            source: .google
        )

        let merged = GoogleSyncEngine.mergeRemoteTaskPreservingLocalFields(
            local: local,
            remote: remote
        )

        #expect(merged.title == "Remote")
        #expect(merged.todayDisplayDate == selectedDate)
        #expect(merged.localId == local.localId)
    }
}
