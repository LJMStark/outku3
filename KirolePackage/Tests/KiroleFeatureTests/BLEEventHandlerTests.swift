import Testing
import Foundation
@testable import KiroleFeature

@Suite("BLEEventHandlerTests")
struct BLEEventHandlerTests {

    // MARK: - filterAndSortForMutation

    @Test("drops logs at or before lastTimestamp")
    func dropsOldLogs() {
        let t100 = Date(timeIntervalSince1970: 100)
        let t200 = Date(timeIntervalSince1970: 200)
        let logs = [
            EventLog(eventType: .completeTask, taskId: "a", timestamp: t100),
            EventLog(eventType: .completeTask, taskId: "b", timestamp: t200),
        ]
        let result = BLEEventHandler.filterAndSortForMutation(logs, since: 100)
        #expect(result.count == 1)
        #expect(result[0].taskId == "b")
    }

    @Test("returns all logs when lastTimestamp is zero")
    func allowsAllWhenTimestampIsZero() {
        let logs = [
            EventLog(eventType: .completeTask, taskId: "x", timestamp: Date(timeIntervalSince1970: 1)),
            EventLog(eventType: .completeTask, taskId: "y", timestamp: Date(timeIntervalSince1970: 2)),
        ]
        let result = BLEEventHandler.filterAndSortForMutation(logs, since: 0)
        #expect(result.count == 2)
    }

    @Test("sorts ascending by timestamp")
    func sortsAscendingByTimestamp() {
        let logs = [
            EventLog(eventType: .completeTask, taskId: "late",  timestamp: Date(timeIntervalSince1970: 300)),
            EventLog(eventType: .completeTask, taskId: "early", timestamp: Date(timeIntervalSince1970: 100)),
            EventLog(eventType: .completeTask, taskId: "mid",   timestamp: Date(timeIntervalSince1970: 200)),
        ]
        let result = BLEEventHandler.filterAndSortForMutation(logs, since: 0)
        #expect(result.map(\.taskId) == ["early", "mid", "late"])
    }

    @Test("deduplicates same (eventType, taskId, timestamp)")
    func deduplicatesIdenticalContent() {
        let ts = Date(timeIntervalSince1970: 500)
        let logs = [
            EventLog(eventType: .completeTask, taskId: "dup", timestamp: ts),
            EventLog(eventType: .completeTask, taskId: "dup", timestamp: ts),
        ]
        let result = BLEEventHandler.filterAndSortForMutation(logs, since: 0)
        #expect(result.count == 1)
    }

    @Test("keeps different taskIds despite same eventType and timestamp")
    func keepsDifferentTaskIds() {
        let ts = Date(timeIntervalSince1970: 500)
        let logs = [
            EventLog(eventType: .completeTask, taskId: "task-1", timestamp: ts),
            EventLog(eventType: .completeTask, taskId: "task-2", timestamp: ts),
        ]
        let result = BLEEventHandler.filterAndSortForMutation(logs, since: 0)
        #expect(result.count == 2)
    }

    @Test("keeps same taskId with different timestamps")
    func keepsSameTaskDifferentTimestamps() {
        let logs = [
            EventLog(eventType: .completeTask, taskId: "t", timestamp: Date(timeIntervalSince1970: 100)),
            EventLog(eventType: .completeTask, taskId: "t", timestamp: Date(timeIntervalSince1970: 200)),
        ]
        let result = BLEEventHandler.filterAndSortForMutation(logs, since: 0)
        #expect(result.count == 2)
    }

    // MARK: - eventContentKey

    @Test("eventContentKey is stable across reparsed EventLog with new UUID")
    func eventContentKeyIsStable() {
        let ts = Date(timeIntervalSince1970: 999)
        let log1 = EventLog(eventType: .completeTask, taskId: "abc", timestamp: ts)
        let log2 = EventLog(eventType: .completeTask, taskId: "abc", timestamp: ts)
        #expect(log1.id != log2.id)
        #expect(BLEEventHandler.eventContentKey(log1) == BLEEventHandler.eventContentKey(log2))
    }
}
