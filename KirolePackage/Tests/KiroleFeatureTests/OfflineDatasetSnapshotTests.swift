import Foundation
import Testing
@testable import KiroleFeature

@Suite("Offline dataset snapshot")
struct OfflineDatasetSnapshotTests {
    @Test("Snapshot freezes TaskList, Schedule and DayPack payloads from one source state")
    func freezesAllPayloads() {
        let now = Date(timeIntervalSince1970: 1_786_396_800)
        let task = TaskItem(
            id: "task-1",
            title: "Plan BLE",
            dueDate: now
        )
        let event = CalendarEvent(
            title: "Hardware sync",
            startTime: now.addingTimeInterval(3600),
            endTime: now.addingTimeInterval(5400)
        )
        let dayPack = DayPack(
            date: now,
            petDialogue: "Ready.",
            events: [EventSummary(from: event)],
            topTasks: [TaskSummary(from: task)],
            settlementData: SettlementData(
                tasksCompleted: 0,
                tasksTotal: 1,
                pointsEarned: 0,
                petMood: "Happy",
                summaryMessage: "",
                encouragementMessage: ""
            )
        )

        let snapshot = OfflineDatasetSnapshot(
            tasks: [task],
            events: [event],
            dayPack: dayPack,
            screenSize: .fourInch
        )

        #expect(snapshot.datasetMask == [.taskList, .schedule, .dayPack])
        #expect(snapshot.taskListPayload == BLEDataEncoder.encodeTaskList([task]))
        #expect(snapshot.schedulePayload == BLEDataEncoder.encodeSchedule([event]))
        #expect(snapshot.dayPackPayload == BLEDataEncoder.encodeDayPack(dayPack, screenSize: .fourInch))
    }

    @Test("Revision is stable for identical bytes and nonzero")
    func stableRevision() {
        let first = OfflineDatasetSnapshot(
            taskListPayload: Data([1, 2]),
            schedulePayload: Data([3]),
            dayPackPayload: Data([4, 5])
        )
        let second = OfflineDatasetSnapshot(
            taskListPayload: Data([1, 2]),
            schedulePayload: Data([3]),
            dayPackPayload: Data([4, 5])
        )

        #expect(first.revision == second.revision)
        #expect(first.revision != 0)
    }
}
