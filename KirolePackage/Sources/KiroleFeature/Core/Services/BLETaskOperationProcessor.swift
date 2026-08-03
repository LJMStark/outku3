import Foundation

/// Owns the complete write-ahead → focus/task persistence → ledger commit transaction for
/// versioned device task operations. MainActor tasks can interleave at every await, so a separate
/// gate prevents two CoreBluetooth notifications from mutating the same operation concurrently.
@MainActor
enum BLETaskOperationProcessor {
    private static let processingGate = BLEWriteGate()

    private struct AuthoritySnapshot {
        let taskID: String?
        /// Status-only generation so title/notes/date edits do not supersede Complete/Skip.
        let taskStatusMutationGeneration: UInt64?
        let focusStartGeneration: UInt64?

        @MainActor
        func isSuperseded(
            appState: AppState,
            focusService: FocusSessionService
        ) -> Bool {
            guard let taskID else { return false }
            if let taskStatusMutationGeneration,
               appState.taskStatusMutationGeneration(for: taskID) != taskStatusMutationGeneration {
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
        appState: AppState = .shared,
        hardwareTaskPersistence: (any HardwareTaskStatePersisting)? = nil,
        receivedAt: Date = Date()
    ) async -> TaskOperationReceipt {
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
            authoritySnapshot: authoritySnapshot,
            hardwareTaskPersistence: hardwareTaskPersistence
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
        authoritySnapshot: AuthoritySnapshot,
        hardwareTaskPersistence: (any HardwareTaskStatePersisting)?
    ) async -> TaskOperationReceipt {
        // App task state may change while this notification waits for the gate. Re-plan inside the
        // transaction; a resumed write-ahead entry still uses the first durable result below.
        // `log.taskId` stays the raw wire ID (e.g. h-…) so the ledger can match lost-ACK retries
        // even after the task row is gone. Domain mutations resolve to the canonical ID separately.
        let currentReceipt = BLEEventHandler.plannedTaskOperationReceipt(
            log,
            tasks: appState.tasks
        ) ?? plannedReceipt
        let wireTaskID = log.taskId ?? ""
        // Prefer the live task row; when App deleted the focused task, fall back to the active
        // focus session so Complete/Skip can still settle without resurrecting the row.
        let domainTaskID = BLEEventHandler.resolveTask(taskId: wireTaskID, in: appState.tasks)?.id
            ?? domainTaskIDMatchingActiveFocus(wireTaskID: wireTaskID, focusService: focusService)
            ?? wireTaskID
        let reservation = await operationLedger.reserve(
            event: log,
            deviceID: deviceID,
            result: currentReceipt.result,
            domainTaskID: domainTaskID,
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
                appState: appState,
                hardwareTaskPersistence: hardwareTaskPersistence,
                mutationDate: receivedAt
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
        guard let wireTaskID = log.taskId else {
            return AuthoritySnapshot(
                taskID: nil,
                taskStatusMutationGeneration: nil,
                focusStartGeneration: nil
            )
        }
        let domainTaskID = BLEEventHandler.resolveTask(taskId: wireTaskID, in: appState.tasks)?.id
            ?? domainTaskIDMatchingActiveFocus(wireTaskID: wireTaskID, focusService: focusService)
        guard let domainTaskID else {
            return AuthoritySnapshot(
                taskID: nil,
                taskStatusMutationGeneration: nil,
                focusStartGeneration: nil
            )
        }
        return AuthoritySnapshot(
            taskID: domainTaskID,
            taskStatusMutationGeneration: appState.taskStatusMutationGeneration(for: domainTaskID),
            focusStartGeneration: focusService.sessionStartGeneration(for: domainTaskID)
        )
    }

    /// When the task row is gone (App deletion), map the wire ID back through the active focus
    /// session so settlement still targets the in-flight focus identity.
    private static func domainTaskIDMatchingActiveFocus(
        wireTaskID: String,
        focusService: FocusSessionService
    ) -> String? {
        guard let active = focusService.activeSession else { return nil }
        if active.taskId == wireTaskID { return active.taskId }
        let hardwareID = TaskItem(id: active.taskId, title: active.taskTitle).hardwareIdentifier
        return hardwareID == wireTaskID ? active.taskId : nil
    }

    private static func applyDurably(
        _ log: EventLog,
        entry: TaskOperationLedgerEntry,
        expectedFocusStartGeneration: UInt64?,
        focusService: FocusSessionService,
        appState: AppState,
        hardwareTaskPersistence: (any HardwareTaskStatePersisting)?,
        mutationDate: Date
    ) async -> TaskListSnapshotResultCode {
        guard let action = TaskListSnapshotAction(eventType: log.eventType) else {
            return .invalidRequest
        }

        // Settle focus even when the task row was deleted (taskNotFound). Energy/time must still
        // commit; only the task-library mutation is skipped.
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

        if entry.result == .taskNotFound {
            return .taskNotFound
        }

        guard entry.result == .applied || entry.result == .alreadyApplied,
              let hardwareTaskID = log.taskId else {
            return entry.result
        }
        guard let task = BLEEventHandler.resolveTask(
            taskId: hardwareTaskID,
            in: appState.tasks
        ), !task.pendingDeletion else {
            return .taskNotFound
        }

        if action == .skipTask {
            let persistenceResult: HardwareTaskSkipPersistenceResult
            if let hardwareTaskPersistence {
                persistenceResult = await appState.persistHardwareTaskSkip(
                    taskID: task.id,
                    operationKey: entry.operationKey,
                    persistence: hardwareTaskPersistence
                )
            } else {
                persistenceResult = await appState.persistHardwareTaskSkip(
                    taskID: task.id,
                    operationKey: entry.operationKey
                )
            }
            switch persistenceResult {
            case .applied:
                return .applied
            case .supersededByApp:
                return .supersededByApp
            case .taskNotFound:
                return .taskNotFound
            case .persistenceFailed:
                return .internalError
            }
        }

        guard action == .completeTask else { return .invalidRequest }

        let persistenceResult: HardwareTaskCompletionPersistenceResult
        if let hardwareTaskPersistence {
            persistenceResult = await appState.persistHardwareTaskCompletion(
                taskID: task.id,
                operationKey: entry.operationKey,
                deviceTimestamp: entry.deviceTimestamp,
                reservedAt: entry.recordedAt,
                mutationDate: mutationDate,
                source: entry.timestampAuthority == .deviceClock ? .hardwareReplay : .user,
                persistence: hardwareTaskPersistence
            )
        } else {
            persistenceResult = await appState.persistHardwareTaskCompletion(
                taskID: task.id,
                operationKey: entry.operationKey,
                deviceTimestamp: entry.deviceTimestamp,
                reservedAt: entry.recordedAt,
                mutationDate: mutationDate,
                source: entry.timestampAuthority == .deviceClock ? .hardwareReplay : .user
            )
        }

        switch persistenceResult {
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
        // taskNotFound is a terminal merge outcome (deletion wins / row gone). It must still run
        // focus settlement and must not be rewritten to supersededByApp by content/status races.
        self == .applied || self == .alreadyApplied
    }
}
