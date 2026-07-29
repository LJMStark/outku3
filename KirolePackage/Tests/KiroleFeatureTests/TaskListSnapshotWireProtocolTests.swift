import Foundation
import Testing
@testable import KiroleFeature

@Suite("Task-list Snapshot Wire Protocol Tests", .serialized)
struct TaskListSnapshotWireProtocolTests {
    @Test("TaskInPage sends the same hardware ID advertised by the Overview snapshot")
    @MainActor
    func taskInPageUsesOpaqueTaskHardwareID() async {
        let task = TaskItem(
            id: "provider-\(String(repeating: "任务-id-", count: 12))",
            title: "Opaque Task"
        )

        let page = await DayPackGenerator.shared.generateTaskInPage(
            task: task,
            pet: Pet()
        )

        #expect(page.taskId == task.hardwareIdentifier)
        #expect(page.taskId == TaskSummary(from: task).id)
    }

    @Test("TaskInPage uses the immediate deterministic Deep Work fallback")
    @MainActor
    func taskInPageUsesImmediateDeterministicSupportText() async {
        let task = TaskItem(id: "task-immediate-support", title: "Write release notes")
        let expected = FallbackText.eventSupportText(for: .deepWork, seed: task.title)

        let first = await DayPackGenerator.shared.generateTaskInPage(task: task, pet: Pet())
        let second = await DayPackGenerator.shared.generateTaskInPage(task: task, pet: Pet())

        #expect(first.encouragement == expected)
        #expect(second.encouragement == expected)
        #expect(!expected.isEmpty)
        #expect(expected.utf8.allSatisfy { (0x20...0x7E).contains($0) })
        #expect(expected.utf8.count <= DayPackTextBudget.taskEncouragement)
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
