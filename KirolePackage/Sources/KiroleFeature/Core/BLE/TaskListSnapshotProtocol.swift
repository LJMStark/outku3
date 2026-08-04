import Foundation

// MARK: - Task-list business acknowledgement (0x1B)

/// The device action whose result is being acknowledged by `TaskListSnapshotAck`.
/// Raw values intentionally match the corresponding Device→App event bytes.
public enum TaskListSnapshotAction: UInt8, Sendable, Equatable, Codable {
    case completeTask = 0x11
    case skipTask = 0x12
    case requestRefresh = 0x20

    init?(eventType: EventLogType) {
        switch eventType {
        case .completeTask: self = .completeTask
        case .skipTask: self = .skipTask
        case .requestRefresh: self = .requestRefresh
        default: return nil
        }
    }
}

/// Business result, separate from the GATT write acknowledgement.
public enum TaskListSnapshotResultCode: UInt8, Sendable, Equatable, Codable {
    case applied = 0x00
    case alreadyApplied = 0x01
    case taskNotFound = 0x02
    case invalidRequest = 0x03
    /// The App changed the task or started a newer session after this device operation was
    /// reserved. The request is closed without overwriting the newer App-authoritative state.
    case supersededByApp = 0x04
    case internalError = 0xFF
}

/// Monotonic within one epoch. A new epoch tells firmware to accept revision 1 after an
/// App reset/reinstall instead of comparing it with a revision from an unrelated state history.
public struct TaskListSnapshotVersion: Sendable, Equatable, Codable {
    public let epoch: UInt32
    public let revision: UInt32

    public init(epoch: UInt32, revision: UInt32) {
        self.epoch = epoch
        self.revision = revision
    }

    static func advanced(
        from current: TaskListSnapshotVersion?,
        newEpoch: UInt32
    ) -> TaskListSnapshotVersion {
        guard let current else {
            return TaskListSnapshotVersion(epoch: normalizedEpoch(newEpoch), revision: 1)
        }
        guard current.revision < UInt32.max else {
            return TaskListSnapshotVersion(epoch: normalizedEpoch(newEpoch), revision: 1)
        }
        return TaskListSnapshotVersion(epoch: current.epoch, revision: current.revision + 1)
    }

    private static func normalizedEpoch(_ value: UInt32) -> UInt32 {
        value == 0 ? 1 : value
    }
}

/// App→Device `0x1B` payload. It confirms one semantic operation and carries the complete
/// current Overview task list, so firmware replaces its list instead of applying its own delta.
public struct TaskListSnapshotAck: Sendable {
    public static let subVersion: UInt8 = 0x01

    public let action: TaskListSnapshotAction
    public let operationID: UInt32
    public let result: TaskListSnapshotResultCode
    public let version: TaskListSnapshotVersion
    public let tasks: [TaskSummary]

    public init(
        action: TaskListSnapshotAction,
        operationID: UInt32,
        result: TaskListSnapshotResultCode,
        version: TaskListSnapshotVersion,
        tasks: [TaskSummary]
    ) {
        self.action = action
        self.operationID = operationID
        self.result = result
        self.version = version
        self.tasks = tasks
    }

}

/// Compares the fields that firmware renders for each Overview row. DayPack freshness checks use
/// this before the first chunk is written, preventing an older generated pack from arriving after
/// a newer `0x1B` acknowledgement and resurrecting a completed task.
enum TaskListSnapshotContent {
    nonisolated static func isEquivalent(_ lhs: [TaskSummary], _ rhs: [TaskSummary]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { left, right in
            left.id == right.id
                && left.title == right.title
                && left.isCompleted == right.isCompleted
                && left.priority == right.priority
        }
    }
}

struct TaskOperationReceipt: Sendable, Equatable {
    let action: TaskListSnapshotAction
    let operationID: UInt32
    let result: TaskListSnapshotResultCode

    func withResult(_ result: TaskListSnapshotResultCode) -> TaskOperationReceipt {
        TaskOperationReceipt(action: action, operationID: operationID, result: result)
    }
}
