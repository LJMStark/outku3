import Foundation

// MARK: - Durable idempotency ledger for device task operations (0x11 / 0x12)

// Split out of `TaskListSnapshotProtocol.swift`: the wire contract and the durability
// mechanism that decides whether an operation is new, resumable or a duplicate are separate
// concerns, and only this half needs persistence and actor isolation.

enum TaskOperationLedgerState: String, Sendable, Equatable, Codable {
    /// Write-ahead marker. A retry must resume the domain mutation instead of treating it as done.
    case pending
    /// The task/focus mutation has reached durable storage and may be acknowledged as a duplicate.
    case committed
}

enum TaskOperationTimestampAuthority: String, Sendable, Equatable, Codable {
    /// A live button notification is ordered and settled by the App receipt time.
    case appReceipt
    /// An offline EventLogBatch operation is ordered by the persisted device timestamp.
    case deviceClock
}

struct TaskOperationLedgerEntry: Sendable, Equatable, Codable {
    let deviceID: String
    let action: TaskListSnapshotAction
    let operationID: UInt32
    /// Domain/focus identity. When the wire ID is a bounded hash (`h-…`), this holds the
    /// provider's canonical task ID so focus recovery can match `FocusSession.taskId`.
    let taskID: String
    /// Raw task ID bytes as delivered on the wire. Idempotency compares this value so a lost ACK
    /// can still match after the task row (and therefore the hash→canonical resolver) is gone.
    /// Absent on pre-#24 ledger rows; those fall back to comparing `taskID`.
    let wireTaskID: String?
    let deviceTimestamp: UInt32
    let result: TaskListSnapshotResultCode
    let state: TaskOperationLedgerState
    let recordedAt: Date
    let timestampAuthority: TaskOperationTimestampAuthority

    init(
        deviceID: String,
        action: TaskListSnapshotAction,
        operationID: UInt32,
        taskID: String,
        wireTaskID: String? = nil,
        deviceTimestamp: UInt32,
        result: TaskListSnapshotResultCode,
        state: TaskOperationLedgerState = .committed,
        recordedAt: Date,
        timestampAuthority: TaskOperationTimestampAuthority = .appReceipt
    ) {
        self.deviceID = deviceID
        self.action = action
        self.operationID = operationID
        self.taskID = taskID
        self.wireTaskID = wireTaskID
        self.deviceTimestamp = deviceTimestamp
        self.result = result
        self.state = state
        self.recordedAt = recordedAt
        self.timestampAuthority = timestampAuthority
    }

    private enum CodingKeys: String, CodingKey {
        case deviceID
        case action
        case operationID
        case taskID
        case wireTaskID
        case deviceTimestamp
        case result
        case state
        case recordedAt
        case timestampAuthority
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceID = try container.decode(String.self, forKey: .deviceID)
        action = try container.decode(TaskListSnapshotAction.self, forKey: .action)
        operationID = try container.decode(UInt32.self, forKey: .operationID)
        taskID = try container.decode(String.self, forKey: .taskID)
        // Pre-#24 entries only persisted the domain taskID (often already resolved). Decode
        // succeeds without wireTaskID; matchesPayload falls back to taskID for those rows.
        wireTaskID = try container.decodeIfPresent(String.self, forKey: .wireTaskID)
        deviceTimestamp = try container.decode(UInt32.self, forKey: .deviceTimestamp)
        result = try container.decode(TaskListSnapshotResultCode.self, forKey: .result)
        state = try container.decodeIfPresent(TaskOperationLedgerState.self, forKey: .state) ?? .committed
        recordedAt = try container.decode(Date.self, forKey: .recordedAt)
        // Pre-fix pending entries did not persist their first delivery carrier. Keep the
        // conservative replay ordering for that narrow upgrade case so an unknown old operation
        // cannot overwrite a newer App edit or focus session.
        timestampAuthority = try container.decodeIfPresent(
            TaskOperationTimestampAuthority.self,
            forKey: .timestampAuthority
        ) ?? .deviceClock
    }

    /// Payload identity for idempotency: raw wire task ID + device timestamp.
    /// Identity scope remains (deviceID, action, operationID); this only guards against a
    /// conflicting reuse of the same operationID with different payload bytes.
    func matchesPayload(of event: EventLog) -> Bool {
        let eventTaskID = event.taskId ?? ""
        let expectedTaskID = wireTaskID ?? taskID
        return expectedTaskID == eventTaskID
            && deviceTimestamp == UInt32(event.timestamp.timeIntervalSince1970)
    }

    func withState(_ state: TaskOperationLedgerState) -> TaskOperationLedgerEntry {
        TaskOperationLedgerEntry(
            deviceID: deviceID,
            action: action,
            operationID: operationID,
            taskID: taskID,
            wireTaskID: wireTaskID,
            deviceTimestamp: deviceTimestamp,
            result: result,
            state: state,
            recordedAt: recordedAt,
            timestampAuthority: timestampAuthority
        )
    }

    func withState(
        _ state: TaskOperationLedgerState,
        result: TaskListSnapshotResultCode
    ) -> TaskOperationLedgerEntry {
        TaskOperationLedgerEntry(
            deviceID: deviceID,
            action: action,
            operationID: operationID,
            taskID: taskID,
            wireTaskID: wireTaskID,
            deviceTimestamp: deviceTimestamp,
            result: result,
            state: state,
            recordedAt: recordedAt,
            timestampAuthority: timestampAuthority
        )
    }

    var operationKey: String {
        "\(deviceID)|\(action.rawValue)|\(operationID)"
    }
}

enum TaskOperationLedgerDecision: Sendable, Equatable {
    case new
    case resume(TaskListSnapshotResultCode)
    case duplicate(TaskListSnapshotResultCode)
    case conflict
    case unavailable
}

enum TaskOperationLedgerReservation: Sendable, Equatable {
    case new(TaskOperationLedgerEntry)
    case resume(TaskOperationLedgerEntry)
    case duplicate(TaskListSnapshotResultCode)
    case conflict
    case unavailable
}

enum TaskOperationLedgerPendingLookup: Sendable, Equatable {
    case found(TaskOperationLedgerEntry)
    case none
    case unavailable
}

protocol TaskOperationLedgerPersisting: Sendable {
    func loadTaskOperationLedger() async throws -> [TaskOperationLedgerEntry]?
    func saveTaskOperationLedger(_ entries: [TaskOperationLedgerEntry]) async throws
}

private struct LocalTaskOperationLedgerPersistence: TaskOperationLedgerPersisting {
    func loadTaskOperationLedger() async throws -> [TaskOperationLedgerEntry]? {
        try await LocalStorage.shared.loadTaskOperationLedger()
    }

    func saveTaskOperationLedger(_ entries: [TaskOperationLedgerEntry]) async throws {
        try await LocalStorage.shared.saveTaskOperationLedger(entries)
    }
}

/// Durable idempotency ledger. Entries are not evicted until the protocol gains an explicit device
/// apply acknowledgement; otherwise an arbitrarily delayed retry could be mistaken for new work.
actor TaskOperationLedger {
    static let shared = TaskOperationLedger()

    private let persistenceEnabled: Bool
    private let persistence: any TaskOperationLedgerPersisting
    private var entries: [TaskOperationLedgerEntry]?
    private var loadingTask: Task<[TaskOperationLedgerEntry], any Error>?
    private var pendingPersistenceTask: Task<Void, Error>?

    init(
        persistenceEnabled: Bool = true,
        initialEntries: [TaskOperationLedgerEntry]? = nil,
        persistence: any TaskOperationLedgerPersisting = LocalTaskOperationLedgerPersistence()
    ) {
        self.persistenceEnabled = persistenceEnabled
        self.entries = initialEntries
        self.persistence = persistence
    }

    func decision(
        for event: EventLog,
        deviceID: String
    ) async -> TaskOperationLedgerDecision {
        guard let action = TaskListSnapshotAction(eventType: event.eventType),
              action == .completeTask || action == .skipTask,
              let operationID = event.operationID,
              operationID != 0 else {
            return .new
        }
        guard await loadIfNeeded() else { return .unavailable }

        guard let existing = entries?.last(where: {
            $0.deviceID == deviceID
                && $0.action == action
                && $0.operationID == operationID
        }) else {
            return .new
        }
        guard existing.matchesPayload(of: event) else { return .conflict }
        return existing.state == .committed
            ? .duplicate(existing.result)
            : .resume(existing.result)
    }

    /// Used during launch recovery to preserve the semantic end reason when the App terminated
    /// after writing the pending WAL but before settling the active focus session.
    func latestPendingOperation(for taskID: String) async -> TaskOperationLedgerPendingLookup {
        guard await loadIfNeeded() else { return .unavailable }
        let pending = (entries ?? [])
            .filter {
                $0.state == .pending
                    && $0.taskID == taskID
                    && ($0.action == .completeTask || $0.action == .skipTask)
            }
        guard let entry = pending.max(by: { $0.recordedAt < $1.recordedAt }) else {
            return .none
        }
        return .found(entry)
    }

    /// Atomically checks and persists a new operation receipt. Production calls this before any
    /// focus or task mutation, so concurrent copies of one notification cannot both pass a
    /// separate lookup and then execute twice.
    ///
    /// - Parameters:
    ///   - event: Wire payload. `event.taskId` is the raw hardware ID used for payload matching.
    ///   - domainTaskID: Canonical provider task ID for focus/task recovery. Defaults to the wire
    ///     ID when the caller has not resolved a longer provider identity.
    func reserve(
        event: EventLog,
        deviceID: String,
        result: TaskListSnapshotResultCode,
        domainTaskID: String? = nil,
        timestampAuthority: TaskOperationTimestampAuthority = .appReceipt,
        now: Date = Date()
    ) async -> TaskOperationLedgerReservation {
        guard let action = TaskListSnapshotAction(eventType: event.eventType),
              action == .completeTask || action == .skipTask,
              let operationID = event.operationID,
              operationID != 0 else {
            return .conflict
        }
        guard await loadIfNeeded() else { return .unavailable }

        if let existing = entries?.last(where: {
            $0.deviceID == deviceID
                && $0.action == action
                && $0.operationID == operationID
        }) {
            guard existing.matchesPayload(of: event) else { return .conflict }
            if existing.state == .committed {
                return .duplicate(existing.result)
            }
            do {
                try await persistCurrentEntriesIfNeeded()
                return .resume(existing)
            } catch {
                reportPersistenceFailure(error, operation: "resume")
                return .unavailable
            }
        }

        let wireTaskID = event.taskId ?? ""
        let entry = TaskOperationLedgerEntry(
            deviceID: deviceID,
            action: action,
            operationID: operationID,
            taskID: domainTaskID ?? wireTaskID,
            wireTaskID: wireTaskID,
            deviceTimestamp: UInt32(event.timestamp.timeIntervalSince1970),
            result: result,
            state: .pending,
            recordedAt: now,
            timestampAuthority: timestampAuthority
        )
        var updated = entries ?? []
        updated.append(entry)

        // Publish the pending marker in memory before suspension. A second actor call can now only
        // resume/duplicate/conflict; it cannot pass the same stale lookup as another first writer.
        entries = updated
        do {
            try await persistCurrentEntriesIfNeeded()
        } catch {
            // Keep the pending marker in memory. The sender receives internalError and its exact
            // retry will attempt to persist/resume it; no domain mutation has run yet.
            reportPersistenceFailure(error, operation: "reserve")
            return .unavailable
        }
        return .new(entry)
    }

    /// Marks an operation committed only after its task/focus effects have reached durable storage.
    /// A crash while this write is pending leaves the on-disk marker as `.pending`, so firmware's
    /// exact retry resumes an idempotent mutation instead of losing the action.
    func commit(
        event: EventLog,
        deviceID: String,
        result: TaskListSnapshotResultCode? = nil
    ) async -> Bool {
        guard let action = TaskListSnapshotAction(eventType: event.eventType),
              let operationID = event.operationID,
              operationID != 0,
              await loadIfNeeded(),
              let index = entries?.lastIndex(where: {
                  $0.deviceID == deviceID
                      && $0.action == action
                      && $0.operationID == operationID
              }),
              let existing = entries?[index],
              existing.matchesPayload(of: event) else {
            return false
        }
        guard existing.state != .committed else { return true }

        let committed = existing.withState(
            .committed,
            result: result ?? existing.result
        )
        entries?[index] = committed
        do {
            try await persistCurrentEntriesIfNeeded()
            return true
        } catch {
            // The durable copy is still pending. Restore the same in-memory state so an exact
            // retry in this process also resumes and flushes the receipt instead of reporting a
            // duplicate that only exists in memory.
            if entries?[index] == committed {
                entries?[index] = existing
            }
            reportPersistenceFailure(error, operation: "commit")
            return false
        }
    }

    /// Revises a result after the first committed write when the MainActor detects that an App
    /// task edit or newer focus session landed while that write was suspended. The revised result
    /// must itself reach durable storage before BLE acknowledges it.
    func reviseCommittedResult(
        event: EventLog,
        deviceID: String,
        result: TaskListSnapshotResultCode
    ) async -> Bool {
        guard let action = TaskListSnapshotAction(eventType: event.eventType),
              let operationID = event.operationID,
              operationID != 0,
              await loadIfNeeded(),
              let index = entries?.lastIndex(where: {
                  $0.deviceID == deviceID
                      && $0.action == action
                      && $0.operationID == operationID
              }),
              let existing = entries?[index],
              existing.matchesPayload(of: event),
              existing.state == .committed else {
            return false
        }
        guard existing.result != result else { return true }

        let revised = existing.withState(.committed, result: result)
        entries?[index] = revised
        do {
            try await persistCurrentEntriesIfNeeded()
            return true
        } catch {
            // Do not expose the stale committed result to another notification in this process.
            // Its exact retry will resume and durably flush the newer authoritative result.
            if entries?[index] == revised {
                entries?[index] = existing.withState(.pending, result: result)
            }
            reportPersistenceFailure(error, operation: "revise")
            return false
        }
    }

    @discardableResult
    func record(
        event: EventLog,
        deviceID: String,
        result: TaskListSnapshotResultCode,
        timestampAuthority: TaskOperationTimestampAuthority = .appReceipt,
        now: Date = Date()
    ) async -> Bool {
        switch await reserve(
            event: event,
            deviceID: deviceID,
            result: result,
            timestampAuthority: timestampAuthority,
            now: now
        ) {
        case .new, .resume:
            return await commit(event: event, deviceID: deviceID)
        case .duplicate:
            return true
        case .conflict, .unavailable:
            return false
        }
    }

    private func loadIfNeeded() async -> Bool {
        if entries != nil { return true }
        guard persistenceEnabled else {
            entries = []
            return true
        }
        let task: Task<[TaskOperationLedgerEntry], any Error>
        if let loadingTask {
            task = loadingTask
        } else {
            let persistence = self.persistence
            task = Task {
                try await persistence.loadTaskOperationLedger() ?? []
            }
            loadingTask = task
        }
        do {
            let loaded = try await task.value
            // Another waiter may already have published this load and then reserved an entry while
            // this actor call was suspended. Never replace that newer in-memory snapshot.
            if entries == nil {
                entries = loaded
            }
            loadingTask = nil
            return true
        } catch {
            loadingTask = nil
            ErrorReporter.log(
                .persistence(
                    operation: "load",
                    target: "task_operation_ledger.json",
                    underlying: error.localizedDescription
                ),
                context: "TaskOperationLedger.load"
            )
            return false
        }
    }

    private func persistCurrentEntriesIfNeeded() async throws {
        guard persistenceEnabled else { return }
        let snapshot = entries ?? []
        let predecessor = pendingPersistenceTask
        let persistence = self.persistence
        let task = Task {
            if let predecessor {
                _ = await predecessor.result
            }
            try await persistence.saveTaskOperationLedger(snapshot)
        }
        pendingPersistenceTask = task
        try await task.value
    }

    private func reportPersistenceFailure(_ error: Error, operation: String) {
        ErrorReporter.log(
            .persistence(
                operation: "save",
                target: "task_operation_ledger.json",
                underlying: error.localizedDescription
            ),
            context: "TaskOperationLedger.\(operation)"
        )
    }
}
