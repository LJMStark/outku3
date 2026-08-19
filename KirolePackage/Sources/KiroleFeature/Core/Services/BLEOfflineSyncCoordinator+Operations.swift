import Foundation

extension BLEOfflineSyncCoordinator {
    func drainOperations(
        state: OfflineSyncState,
        runID: UUID
    ) async throws -> Int {
        let expectedCount = Int(state.pendingCount)
        guard expectedCount > 0 else { return 0 }

        var acceptedRecords: [UInt32: OfflineSyncOperationRecord] = [:]
        var lastProcessedID: UInt32?

        while acceptedRecords.count < expectedCount {
            let inbound = try await waitForMessage(
                expecting: .operationBatch(bootSessionID: state.bootSessionID),
                runID: runID
            )
            guard case .operationBatch(let batch) = inbound else {
                throw BLEOfflineSyncCoordinatorError.invalidInbound
            }
            guard !batch.records.isEmpty else {
                throw BLEOfflineSyncCoordinatorError.emptyOperationBatch
            }

            let newRecords = try validate(
                batch.records,
                acceptedRecords: acceptedRecords,
                lastProcessedID: lastProcessedID,
                expectedCount: expectedCount
            )

            do {
                for record in newRecords {
                    try ensureRunIsActive(runID)
                    if let lastProcessedID, record.operationID != lastProcessedID + 1 {
                        throw BLEOfflineSyncCoordinatorError.operationIDGap(
                            previous: lastProcessedID,
                            current: record.operationID
                        )
                    }
                    try await dependencies.processOperation(state.bootSessionID, record)
                    try ensureRunIsActive(runID)
                    acceptedRecords[record.operationID] = record
                    lastProcessedID = record.operationID
                }
            } catch {
                if let lastProcessedID {
                    try? await dependencies.sendCommand(
                        .opAck(
                            OfflineSyncOperationAck(
                                bootSessionID: state.bootSessionID,
                                ackOperationID: lastProcessedID
                            )
                        )
                    )
                }
                throw error
            }

            guard let cumulativeAckID = lastProcessedID else {
                throw BLEOfflineSyncCoordinatorError.emptyOperationBatch
            }
            try await sendCommand(
                .opAck(
                    OfflineSyncOperationAck(
                        bootSessionID: state.bootSessionID,
                        ackOperationID: cumulativeAckID
                    )
                ),
                runID: runID
            )
        }

        return acceptedRecords.count
    }

    func recoverOpenTransactionIfNeeded(
        _ state: OfflineSyncState,
        runID: UUID
    ) async throws -> OfflineSyncState {
        guard state.stateFlags.contains(.transactionOpen) else { return state }
        guard state.currentSyncID != 0 else {
            throw BLEOfflineSyncCoordinatorError.inconsistentOpenTransaction
        }

        try await sendCommand(.abort(syncID: state.currentSyncID), runID: runID)
        // The second QUERY defines a fresh STATE/OP_BATCH boundary. Do not let batches or results
        // emitted for the abandoned transaction satisfy the refreshed state.
        expectedBootSessionID = nil
        mailbox.removeAll(keepingCapacity: true)
        let refreshedMessage = try await request(
            .query,
            expecting: .state,
            runID: runID
        )
        guard case .state(let refreshed) = refreshedMessage else {
            throw BLEOfflineSyncCoordinatorError.invalidInbound
        }
        guard !refreshed.stateFlags.contains(.transactionOpen),
              refreshed.currentSyncID == 0 else {
            throw BLEOfflineSyncCoordinatorError.transactionRecoveryFailed(
                refreshed.currentSyncID
            )
        }
        return refreshed
    }

    func validate(
        _ records: [OfflineSyncOperationRecord],
        acceptedRecords: [UInt32: OfflineSyncOperationRecord],
        lastProcessedID: UInt32?,
        expectedCount: Int
    ) throws -> [OfflineSyncOperationRecord] {
        var newRecords: [OfflineSyncOperationRecord] = []
        var candidateLastID = lastProcessedID

        for record in records {
            guard record.operationID != 0 else {
                throw BLEOfflineSyncCoordinatorError.invalidOperationID
            }
            if let previous = acceptedRecords[record.operationID] {
                guard previous == record else {
                    throw BLEOfflineSyncCoordinatorError.conflictingDuplicateOperation(
                        record.operationID
                    )
                }
                continue
            }
            if let duplicateInBatch = newRecords.first(where: {
                $0.operationID == record.operationID
            }) {
                guard duplicateInBatch == record else {
                    throw BLEOfflineSyncCoordinatorError.conflictingDuplicateOperation(
                        record.operationID
                    )
                }
                continue
            }
            if let candidateLastID, record.operationID <= candidateLastID {
                throw BLEOfflineSyncCoordinatorError.nonIncreasingOperationID(
                    previous: candidateLastID,
                    current: record.operationID
                )
            }
            newRecords.append(record)
            candidateLastID = record.operationID
        }

        let resultingCount = acceptedRecords.count + newRecords.count
        guard resultingCount <= expectedCount else {
            throw BLEOfflineSyncCoordinatorError.operationCountExceeded(
                expected: expectedCount,
                actual: resultingCount
            )
        }
        return newRecords
    }

}
