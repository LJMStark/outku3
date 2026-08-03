import Foundation
@testable import KiroleFeature

/// Minimal firmware mirror for the 0x23 expand phase. Pending bytes never replace committed data;
/// only a completely decoded transaction with a valid CRC becomes visible.
struct SimulatedTaskLibraryFirmware {
    private(set) var pendingVersion: TaskLibraryVersion?
    private(set) var committedVersion: TaskLibraryVersion?
    private(set) var committedRecords: [TaskLibraryRecord] = []

    mutating func begin(version: TaskLibraryVersion) throws {
        try validate(version: version)
        pendingVersion = version
    }

    mutating func apply(payload: Data) throws -> TaskLibraryCommitAcknowledgement {
        let transaction = try TaskLibraryCodec.decodeTransaction(payload)
        guard pendingVersion == transaction.version else {
            throw SimulationError.taskLibraryPendingMismatch
        }
        try validate(version: transaction.version)

        committedRecords = transaction.records
        committedVersion = transaction.version
        pendingVersion = nil
        return TaskLibraryCommitAcknowledgement(
            version: transaction.version,
            result: .committed,
            contentCRC32: payload.bigEndianUInt32(at: payload.count - 4)
        )
    }

    mutating func simulatePowerCycle() {
        pendingVersion = nil
    }

    func record(taskID: String) throws -> TaskLibraryRecord {
        guard let record = committedRecords.first(where: { $0.taskID == taskID }) else {
            throw SimulationError.taskLibraryTaskNotFound
        }
        return record
    }

    private func validate(version: TaskLibraryVersion) throws {
        guard version.epoch != 0, version.revision != 0 else {
            throw SimulationError.taskLibraryVersionRejected
        }
    }
}
