import Foundation
import Testing
@testable import KiroleFeature

@Suite("Task-list Snapshot Wire Protocol Tests", .serialized)
struct TaskListSnapshotWireProtocolTests {
    @Test("The Overview snapshot advertises the opaque hardware ID, not the provider ID")
    @MainActor
    func overviewSnapshotUsesOpaqueTaskHardwareID() {
        // v2.16.0: the old `0x11 TaskInPage` leg of this invariant is gone (Issue #29). What still
        // must hold is that every hardware-facing surface names a task by `hardwareIdentifier`,
        // so a long/non-ASCII provider ID cannot leak onto the wire or split one task into two.
        let task = TaskItem(
            id: "provider-\(String(repeating: "任务-id-", count: 12))",
            title: "Opaque Task"
        )

        #expect(TaskSummary(from: task).id == task.hardwareIdentifier)
        #expect(task.hardwareIdentifier.utf8.allSatisfy { (0x20...0x7E).contains($0) })
    }

    @Test("Snapshot version increments monotonically and changes epoch on overflow")
    func snapshotVersionAdvancement() {
        let first = TaskListSnapshotVersion.advanced(from: nil, newEpoch: 11)
        let next = TaskListSnapshotVersion.advanced(from: first, newEpoch: 99)
        let overflow = TaskListSnapshotVersion.advanced(
            from: TaskListSnapshotVersion(epoch: 11, revision: .max),
            newEpoch: 99
        )

        #expect(first == TaskListSnapshotVersion(epoch: 11, revision: 1))
        #expect(next == TaskListSnapshotVersion(epoch: 11, revision: 2))
        #expect(overflow == TaskListSnapshotVersion(epoch: 99, revision: 1))
    }

    @Test("Operation ID is the deduplication identity for versioned task operations")
    func operationIDDeduplication() {
        let first = EventLog(
            eventType: .completeTask,
            taskId: "task-a",
            operationID: 42,
            timestamp: Date(timeIntervalSince1970: 100),
            hasDeviceTimestamp: true
        )
        let retry = EventLog(
            eventType: .completeTask,
            taskId: "task-a",
            operationID: 42,
            timestamp: Date(timeIntervalSince1970: 100),
            hasDeviceTimestamp: true
        )

        #expect(BLEEventHandler.sortAndDedup([first, retry]).count == 1)
    }
}
