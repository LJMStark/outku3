import Foundation
@testable import KiroleFeature

enum ScenarioDevicePage: Codable, Equatable, Sendable {
    case overview
    case focus(taskID: String)
    case dailySummary
    case screensaver
}

struct ScenarioDeviceFocus: Codable, Equatable, Sendable {
    let taskID: String
    let startedAt: Date
}

enum ScenarioDeviceEventCodec {
    static func taskOperationRecord(
        action: TaskListSnapshotAction,
        taskID: String,
        operationID: UInt32,
        timestamp: Date
    ) throws -> Data {
        let taskIDBytes = Data(taskID.utf8)
        let seconds = timestamp.timeIntervalSince1970.rounded(.down)
        guard action == .completeTask || action == .skipTask,
              operationID != 0,
              (1...36).contains(taskIDBytes.count),
              seconds >= 0,
              seconds <= TimeInterval(UInt32.max) else {
            throw AppDeviceScenarioError.invalidOfflineTaskAction
        }

        var record = Data([action.rawValue, 0x01])
        record.appendBigEndian(operationID)
        record.append(UInt8(taskIDBytes.count))
        record.append(taskIDBytes)
        record.appendBigEndian(UInt32(seconds))
        return record
    }
}

extension Array {
    func chunked(maxCount: Int) -> [[Element]] {
        guard maxCount > 0 else { return [] }
        return stride(from: 0, to: count, by: maxCount).map { start in
            Array(self[start..<Swift.min(start + maxCount, count)])
        }
    }
}
