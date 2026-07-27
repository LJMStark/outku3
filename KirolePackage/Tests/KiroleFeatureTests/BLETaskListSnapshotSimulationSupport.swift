import Foundation
@testable import KiroleFeature

struct SimulatedTaskListSnapshotAck: Equatable {
    struct Task: Equatable {
        let id: String
        let title: String
        let isCompleted: Bool
        let priority: UInt8
    }

    let action: TaskListSnapshotAction
    let operationID: UInt32
    let result: TaskListSnapshotResultCode
    let epoch: UInt32
    let revision: UInt32
    let tasks: [Task]
}

/// Small firmware-state mirror for the 0x1B contract. Validation finishes before assignment, so a
/// rejected packet cannot partially replace the current Overview list.
struct SimulatedTaskListSnapshotFirmware {
    private(set) var pendingAction: TaskListSnapshotAction?
    private(set) var pendingOperationID: UInt32?
    private(set) var version: TaskListSnapshotVersion?
    private(set) var tasks: [SimulatedTaskListSnapshotAck.Task] = []
    private var lastAppliedAcknowledgement: SimulatedTaskListSnapshotAck?

    mutating func beginPending(action: TaskListSnapshotAction, operationID: UInt32) throws {
        guard operationID != 0 else { throw SimulationError.invalidSnapshotState }
        pendingAction = action
        pendingOperationID = operationID
    }

    mutating func apply(
        _ acknowledgement: SimulatedTaskListSnapshotAck,
        screenSize: ScreenSize
    ) throws {
        guard acknowledgement.tasks.count <= screenSize.maxTasks else {
            throw SimulationError.snapshotTaskCountExceeded
        }
        if acknowledgement == lastAppliedAcknowledgement {
            return
        }
        guard pendingAction == acknowledgement.action,
              pendingOperationID == acknowledgement.operationID else {
            throw SimulationError.snapshotPendingMismatch
        }
        if acknowledgement.result == .internalError {
            return
        }

        let incomingVersion = TaskListSnapshotVersion(
            epoch: acknowledgement.epoch,
            revision: acknowledgement.revision
        )
        guard incomingVersion.epoch != 0, incomingVersion.revision != 0 else {
            throw SimulationError.snapshotVersionRejected
        }
        if let version {
            if version.epoch == incomingVersion.epoch {
                guard incomingVersion.revision > version.revision else {
                    throw SimulationError.snapshotVersionRejected
                }
            } else {
                guard incomingVersion.revision == 1 else {
                    throw SimulationError.snapshotVersionRejected
                }
            }
        } else {
            guard incomingVersion.revision == 1 else {
                throw SimulationError.snapshotVersionRejected
            }
        }

        let replacement = acknowledgement.tasks
        tasks = replacement
        version = incomingVersion
        lastAppliedAcknowledgement = acknowledgement
        pendingAction = nil
        pendingOperationID = nil
    }
}

enum SimulationError: Error, Equatable {
    case truncatedPacket
    case truncatedPayload
    case lengthMismatch(expected: Int, actual: Int)
    case incompleteChunkedMessage
    case trailingBytes
    case invalidUTF8
    case invalidEnumValue
    case invalidSnapshotState
    case snapshotPendingMismatch
    case snapshotTaskCountExceeded
    case snapshotVersionRejected
    case developmentDisplayCommandNotStandard
    case invalidSecureHandshake
    case unexpectedType(expected: UInt8, actual: UInt8)
    case chunkCRCMismatch
    case chunkHeaderMismatch
    case avatarOperationRejected
}
