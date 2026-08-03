import Foundation
@testable import KiroleFeature

/// Minimal firmware mirror for the 0x23 expand phase. Pending bytes never replace committed data;
/// only a completely decoded transaction with a valid CRC becomes visible.
struct SimulatedTaskLibraryFirmware {
    private(set) var pendingVersion: TaskLibraryVersion?
    private(set) var committedVersion: TaskLibraryVersion?
    private(set) var committedRecords: [TaskLibraryRecord] = []
    private(set) var committedState: TaskLibraryCommittedState?
    private var maximumRecords: Int?

    var localDefaultDialogue: String {
        TaskLibraryPhaseTexts.localFallback.starting
    }

    mutating func setMaximumRecords(_ maximumRecords: Int?) {
        self.maximumRecords = maximumRecords
    }

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
        let transactionState = try TaskLibraryCodec.committedState(for: transaction)
        let nextRecords: [TaskLibraryRecord]
        switch transaction.kind {
        case .full:
            nextRecords = transaction.records
        case .incremental:
            guard transaction.baseState == committedState else {
                pendingVersion = nil
                return TaskLibraryCommitAcknowledgement(
                    version: transaction.version,
                    result: .baseMismatch,
                    contentCRC32: transactionState.contentCRC32
                )
            }
            var recordsByID: [String: TaskLibraryRecord] = [:]
            for record in committedRecords where recordsByID[record.taskID] == nil {
                recordsByID[record.taskID] = record
            }
            for taskID in transaction.deletedTaskIDs {
                recordsByID.removeValue(forKey: taskID)
            }
            for record in transaction.records {
                recordsByID[record.taskID] = record
            }
            nextRecords = recordsByID.values.sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.taskID < $1.taskID
            }
        }
        if let maximumRecords, nextRecords.count > maximumRecords {
            pendingVersion = nil
            return TaskLibraryCommitAcknowledgement(
                version: transaction.version,
                result: .capacityExceeded,
                contentCRC32: transactionState.contentCRC32
            )
        }

        committedRecords = nextRecords
        committedVersion = transaction.version
        committedState = transactionState
        pendingVersion = nil
        return TaskLibraryCommitAcknowledgement(
            version: transaction.version,
            result: .committed,
            contentCRC32: transactionState.contentCRC32
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

    func phaseText(taskID: String, elapsedMinutes: Int) throws -> String {
        try record(taskID: taskID).phaseTexts.text(atElapsedMinutes: elapsedMinutes)
    }

    private func validate(version: TaskLibraryVersion) throws {
        guard version.epoch != 0, version.revision != 0 else {
            throw SimulationError.taskLibraryVersionRejected
        }
    }
}
