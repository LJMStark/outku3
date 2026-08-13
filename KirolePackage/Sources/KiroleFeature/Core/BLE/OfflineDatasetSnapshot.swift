import CryptoKit
import Foundation

/// One immutable set of bytes for a single OfflineSync transaction. The three payloads are
/// encoded before BEGIN, so an App edit cannot mix old and new task/calendar data in one commit.
public struct OfflineDatasetSnapshot: Sendable, Equatable {
    public let datasetMask: OfflineSyncDatasetMask
    public let taskListPayload: Data
    public let schedulePayload: Data
    public let dayPackPayload: Data
    public let revision: UInt32

    public init(
        taskListPayload: Data,
        schedulePayload: Data,
        dayPackPayload: Data
    ) {
        self.datasetMask = [.taskList, .schedule, .dayPack]
        self.taskListPayload = taskListPayload
        self.schedulePayload = schedulePayload
        self.dayPackPayload = dayPackPayload

        var bytes = Data([datasetMask.rawValue])
        for payload in [taskListPayload, schedulePayload, dayPackPayload] {
            bytes.appendBigEndian(UInt32(clamping: payload.count))
            bytes.append(payload)
        }
        let digest = SHA256.hash(data: bytes)
        let candidate = digest.prefix(4).reduce(UInt32(0)) { value, byte in
            (value << 8) | UInt32(byte)
        }
        revision = candidate == 0 ? 1 : candidate
    }

    public init(
        tasks: [TaskItem],
        events: [CalendarEvent],
        dayPack: DayPack,
        screenSize: ScreenSize
    ) {
        self.init(
            taskListPayload: BLEDataEncoder.encodeTaskList(tasks),
            schedulePayload: BLEDataEncoder.encodeSchedule(events),
            dayPackPayload: BLEDataEncoder.encodeDayPack(dayPack, screenSize: screenSize)
        )
    }
}
