import Foundation

/// Owns the complete write-ahead → focus/task persistence → ledger commit transaction for
/// versioned device task operations. MainActor tasks can interleave at every await, so a separate
/// gate prevents two CoreBluetooth notifications from mutating the same operation concurrently.
@MainActor
enum BLETaskOperationProcessor {
    private static let processingGate = BLEWriteGate()

    private struct AuthoritySnapshot {
        let taskID: String?
        let taskMutationGeneration: UInt64?
        let focusStartGeneration: UInt64?

        @MainActor
        func isSuperseded(
            appState: AppState,
            focusService: FocusSessionService
        ) -> Bool {
            guard let taskID else { return false }
            if let taskMutationGeneration,
               appState.taskMutationGeneration(for: taskID) != taskMutationGeneration {
                return true
            }
            if let focusStartGeneration,
               focusService.sessionStartGeneration(for: taskID) != focusStartGeneration {
                return true
            }
            return false
        }
    }

    static func process(
        _ log: EventLog,
        plannedReceipt: TaskOperationReceipt,
        deviceID: String,
        focusService: FocusSessionService,
        isReplay: Bool,
        operationLedger: TaskOperationLedger,
        appState: AppState = .shared
    ) async -> TaskOperationReceipt {
        let receivedAt = Date()
        let authoritySnapshot = makeAuthoritySnapshot(
            for: log,
            appState: appState,
            focusService: focusService
        )
        do {
            try await processingGate.acquire()
        } catch {
            return plannedReceipt.withResult(.internalError)
        }
        let receipt = await processWhileHoldingGate(
            log,
            plannedReceipt: plannedReceipt,
            deviceID: deviceID,
            focusService: focusService,
            isReplay: isReplay,
            operationLedger: operationLedger,
            appState: appState,
            receivedAt: receivedAt,
            authoritySnapshot: authoritySnapshot
        )
        await processingGate.release()
        return receipt
    }

    private static func processWhileHoldingGate(
        _ log: EventLog,
        plannedReceipt: TaskOperationReceipt,
        deviceID: String,
        focusService: FocusSessionService,
        isReplay: Bool,
        operationLedger: TaskOperationLedger,
        appState: AppState,
        receivedAt: Date,
        authoritySnapshot: AuthoritySnapshot
    ) async -> TaskOperationReceipt {
        // App task state may change while this notification waits for the gate. Re-plan inside the
        // transaction; a resumed write-ahead entry still uses the first durable result below.
        let currentReceipt = BLEEventHandler.plannedTaskOperationReceipt(
            log,
            tasks: appState.tasks
        ) ?? plannedReceipt
        let reservation = await operationLedger.reserve(
            event: log,
            deviceID: deviceID,
            result: currentReceipt.result,
            timestampAuthority: isReplay ? .deviceClock : .appReceipt,
            now: receivedAt
        )

        let entry: TaskOperationLedgerEntry
        switch reservation {
        case .new(let reserved), .resume(let reserved):
            entry = reserved
        case .duplicate(let cachedResult):
            return currentReceipt.withResult(cachedResult)
        case .conflict:
            return currentReceipt.withResult(.invalidRequest)
        case .unavailable:
            return currentReceipt.withResult(.internalError)
        }

        var finalResult: TaskListSnapshotResultCode
        if currentReceipt.result.canBeSupersededByApp,
           authoritySnapshot.isSuperseded(appState: appState, focusService: focusService) {
            finalResult = .supersededByApp
        } else {
            finalResult = await applyDurably(
                log,
                entry: entry,
                expectedFocusStartGeneration: authoritySnapshot.focusStartGeneration,
                focusService: focusService,
                appState: appState
            )
        }
        if finalResult.canBeSupersededByApp,
           authoritySnapshot.isSuperseded(appState: appState, focusService: focusService) {
            finalResult = .supersededByApp
        }
        guard finalResult != .internalError,
              await operationLedger.commit(
                event: log,
                deviceID: deviceID,
                result: finalResult
        ) else {
            return currentReceipt.withResult(.internalError)
        }

        // `commit` performs file I/O and therefore yields MainActor. Recheck immediately after it
        // returns, with no intervening suspension. If an App edit/undo or newer same-task focus
        // start landed in that window, revise the durable receipt before sending the 0x1B ACK.
        if finalResult.canBeSupersededByApp,
           authoritySnapshot.isSuperseded(appState: appState, focusService: focusService) {
            guard await operationLedger.reviseCommittedResult(
                event: log,
                deviceID: deviceID,
                result: .supersededByApp
            ) else {
                return currentReceipt.withResult(.internalError)
            }
            finalResult = .supersededByApp
        }
        return currentReceipt.withResult(finalResult)
    }

    private static func makeAuthoritySnapshot(
        for log: EventLog,
        appState: AppState,
        focusService: FocusSessionService
    ) -> AuthoritySnapshot {
        guard let wireTaskID = log.taskId,
              let task = BLEEventHandler.resolveTask(taskId: wireTaskID, in: appState.tasks) else {
            return AuthoritySnapshot(
                taskID: nil,
                taskMutationGeneration: nil,
                focusStartGeneration: nil
            )
        }
        return AuthoritySnapshot(
            taskID: task.id,
            taskMutationGeneration: appState.taskMutationGeneration(for: task.id),
            focusStartGeneration: focusService.sessionStartGeneration(for: task.id)
        )
    }

    private static func applyDurably(
        _ log: EventLog,
        entry: TaskOperationLedgerEntry,
        expectedFocusStartGeneration: UInt64?,
        focusService: FocusSessionService,
        appState: AppState
    ) async -> TaskListSnapshotResultCode {
        guard let action = TaskListSnapshotAction(eventType: log.eventType) else {
            return .invalidRequest
        }

        if entry.result != .invalidRequest {
            switch await focusService.settleHardwareTaskOperation(
                entry,
                expectedSessionStartGeneration: expectedFocusStartGeneration
            ) {
            case .durable:
                break
            case .supersededByApp:
                return .supersededByApp
            case .persistenceFailed:
                return .internalError
            }
        }

        guard action == .completeTask,
              entry.result == .applied || entry.result == .alreadyApplied,
              let hardwareTaskID = log.taskId else {
            return entry.result
        }
        guard let task = BLEEventHandler.resolveTask(
            taskId: hardwareTaskID,
            in: appState.tasks
        ) else {
            return .taskNotFound
        }

        switch await appState.persistHardwareTaskCompletion(
            taskID: task.id,
            operationKey: entry.operationKey,
            deviceTimestamp: entry.deviceTimestamp,
            reservedAt: entry.recordedAt,
            source: entry.timestampAuthority == .deviceClock ? .hardwareReplay : .user
        ) {
        case .applied:
            return .applied
        case .alreadyApplied:
            return .alreadyApplied
        case .supersededByApp:
            return .supersededByApp
        case .taskNotFound:
            return .taskNotFound
        case .persistenceFailed:
            return .internalError
        }
    }
}

private extension TaskListSnapshotResultCode {
    var canBeSupersededByApp: Bool {
        self == .applied || self == .alreadyApplied || self == .taskNotFound
    }
}
