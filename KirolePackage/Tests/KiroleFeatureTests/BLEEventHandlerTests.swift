import Testing
import Foundation
@testable import KiroleFeature

@Suite("BLEEventHandlerTests")
struct BLEEventHandlerTests {

    // MARK: - filterAndSortForMutation

    @Test("given events older than or equal to lastTimestamp, when filtered, then they are dropped")
    func givenOldEvents_whenFiltered_thenDropped() {
        let logs = [
            EventLog(eventType: .completeTask, taskId: "a", timestamp: Date(timeIntervalSince1970: 100)),
            EventLog(eventType: .completeTask, taskId: "b", timestamp: Date(timeIntervalSince1970: 200)),
        ]

        let result = BLEEventHandler.filterAndSortForMutation(logs, since: 100)

        #expect(result.count == 1)
        #expect(result[0].taskId == "b")
    }

    @Test("given lastTimestamp is zero, when filtered, then all events are returned")
    func givenZeroLastTimestamp_whenFiltered_thenAllReturned() {
        let logs = [
            EventLog(eventType: .completeTask, taskId: "x", timestamp: Date(timeIntervalSince1970: 1)),
            EventLog(eventType: .completeTask, taskId: "y", timestamp: Date(timeIntervalSince1970: 2)),
        ]

        let result = BLEEventHandler.filterAndSortForMutation(logs, since: 0)

        #expect(result.count == 2)
    }

    @Test("given out-of-order events, when sorted, then timestamps are ascending")
    func givenOutOfOrderEvents_whenSorted_thenAscendingTimestamps() {
        let logs = [
            EventLog(eventType: .completeTask, taskId: "late",  timestamp: Date(timeIntervalSince1970: 300)),
            EventLog(eventType: .completeTask, taskId: "early", timestamp: Date(timeIntervalSince1970: 100)),
            EventLog(eventType: .completeTask, taskId: "mid",   timestamp: Date(timeIntervalSince1970: 200)),
        ]

        let result = BLEEventHandler.filterAndSortForMutation(logs, since: 0)

        #expect(result.map(\.taskId) == ["early", "mid", "late"])
    }

    @Test("given duplicate events with identical content triplet, when deduplicated, then only one is kept")
    func givenDuplicateContentTriplet_whenDeduplicated_thenOnlyOneKept() {
        let ts = Date(timeIntervalSince1970: 500)
        let logs = [
            EventLog(eventType: .completeTask, taskId: "dup", timestamp: ts),
            EventLog(eventType: .completeTask, taskId: "dup", timestamp: ts),
        ]

        let result = BLEEventHandler.filterAndSortForMutation(logs, since: 0)

        #expect(result.count == 1)
    }

    @Test("given same eventType and timestamp but different taskIds, when deduplicated, then both are kept")
    func givenSameTypeAndTimestampDifferentTaskIds_whenDeduplicated_thenBothKept() {
        let ts = Date(timeIntervalSince1970: 500)
        let logs = [
            EventLog(eventType: .completeTask, taskId: "task-1", timestamp: ts),
            EventLog(eventType: .completeTask, taskId: "task-2", timestamp: ts),
        ]

        let result = BLEEventHandler.filterAndSortForMutation(logs, since: 0)

        #expect(result.count == 2)
    }

    @Test("given same taskId completed at different times, when deduplicated, then both are kept")
    func givenSameTaskIdDifferentTimestamps_whenDeduplicated_thenBothKept() {
        let logs = [
            EventLog(eventType: .completeTask, taskId: "t", timestamp: Date(timeIntervalSince1970: 100)),
            EventLog(eventType: .completeTask, taskId: "t", timestamp: Date(timeIntervalSince1970: 200)),
        ]

        let result = BLEEventHandler.filterAndSortForMutation(logs, since: 0)

        #expect(result.count == 2)
    }

    // MARK: - eventContentKey

    @Test("given two EventLogs with identical content but different UUIDs, when keyed, then keys are equal")
    func givenSameContentDifferentUUID_whenKeyed_thenKeysEqual() {
        let ts = Date(timeIntervalSince1970: 999)
        let log1 = EventLog(eventType: .completeTask, taskId: "abc", timestamp: ts)
        let log2 = EventLog(eventType: .completeTask, taskId: "abc", timestamp: ts)

        #expect(log1.id != log2.id)
        #expect(BLEEventHandler.eventContentKey(log1) == BLEEventHandler.eventContentKey(log2))
    }
}
