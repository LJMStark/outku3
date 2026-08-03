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

/// Narrow external boundary used by the event handler. Tests inject a recorder; production uses
/// `BLEService`, which preserves the existing write gate, GATT response and secure-envelope path.
@MainActor
protocol TaskListSnapshotSending: AnyObject {
    var hardwareScreenSize: ScreenSize { get }
    var taskListSnapshotDestinationID: String { get }
    /// Acquires the same complete-message gate used by DayPack. The responder binds a durable
    /// version to the task snapshot only after this succeeds, so an older snapshot cannot wait
    /// behind and then overwrite a newer DayPack with a higher revision.
    func withTaskStateMessageGate(
        _ operation: @MainActor () async throws -> Void
    ) async throws
    /// Sends bytes that were frozen together with their StateEpoch/Revision. A retry must use the
    /// identical payload even if App tasks change while the first GATT callback is missing. The
    /// caller already owns the complete-message gate.
    func writeTaskListSnapshotAckPayload(
        _ payload: Data,
        expectedTaskStateVersion: UInt64?
    ) async throws
    /// Production invokes this callback at the last safe point before the first packet reaches
    /// CoreBluetooth. Test senders inherit the default wrapper around their in-memory write.
    func writeTaskListSnapshotAckPayload(
        _ payload: Data,
        expectedTaskStateVersion: UInt64?,
        beforeFirstWrite: @escaping @MainActor @Sendable () async throws -> Void
    ) async throws
}

extension TaskListSnapshotSending {
    var taskListSnapshotDestinationID: String { "single-active-device" }

    func writeTaskListSnapshotAckPayload(
        _ payload: Data,
        expectedTaskStateVersion: UInt64?,
        beforeFirstWrite: @escaping @MainActor @Sendable () async throws -> Void
    ) async throws {
        try await beforeFirstWrite()
        try await writeTaskListSnapshotAckPayload(
            payload,
            expectedTaskStateVersion: expectedTaskStateVersion
        )
    }
}

protocol TaskListSnapshotVersionProviding: Sendable {
    func nextTaskListSnapshotVersion() async throws -> TaskListSnapshotVersion
}

struct TaskListSnapshotRequestKey: Sendable, Hashable, Codable {
    let destinationID: String
    let action: TaskListSnapshotAction
    let operationID: UInt32
}

struct FrozenTaskListSnapshotResponse: Sendable, Equatable, Codable {
    private enum CodingKeys: String, CodingKey {
        case key
        case version
        case sourceTaskStateVersion
        case payload
    }

    let key: TaskListSnapshotRequestKey
    let version: TaskListSnapshotVersion
    /// App task generation used to build these bytes. Production captures it for every response;
    /// `nil` is retained only for decoding transitional test data.
    let sourceTaskStateVersion: UInt64?
    let payload: Data

    init(
        key: TaskListSnapshotRequestKey,
        version: TaskListSnapshotVersion,
        sourceTaskStateVersion: UInt64? = nil,
        payload: Data
    ) {
        self.key = key
        self.version = version
        self.sourceTaskStateVersion = sourceTaskStateVersion
        self.payload = payload
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(TaskListSnapshotRequestKey.self, forKey: .key)
        version = try container.decode(TaskListSnapshotVersion.self, forKey: .version)
        sourceTaskStateVersion = try container.decodeIfPresent(
            UInt64.self,
            forKey: .sourceTaskStateVersion
        )
        payload = try container.decode(Data.self, forKey: .payload)
    }
}

enum TaskListSnapshotDeliveryPreparation: Sendable, Equatable {
    /// A previous attempt may have reached the transport, or a delivered response is awaiting
    /// duplicate-request cleanup. These bytes are immutable.
    case frozen(FrozenTaskListSnapshotResponse)
    /// No transport attempt has started. The same version may be rebuilt before it is marked.
    case reserved(TaskListSnapshotVersion)
}

enum TaskListSnapshotWriteError: Error {
    /// The sender's final task-state check failed before its first packet was written.
    case staleBeforeFirstWrite
    /// This call was stale before its first packet, but an earlier attempt may already have sent
    /// part of the same frozen message. The bytes must remain immutable.
    case staleAfterUncertainWrite
}

enum TaskListSnapshotDeliveryCapabilityError: Error {
    case attemptedDeliveryQueryUnsupported
}

protocol TaskListSnapshotDeliveryStoring: Sendable {
    /// Returns whether this destination has bytes whose BLE delivery is still uncertain.
    /// Read/decode failures must be thrown so synchronization can fail closed.
    func hasAttemptedTaskListSnapshotDelivery(
        for destinationID: String
    ) async throws -> Bool

    func prepareTaskListSnapshotDelivery(
        for key: TaskListSnapshotRequestKey
    ) async throws -> TaskListSnapshotDeliveryPreparation

    func freezeTaskListSnapshotDelivery(
        _ response: FrozenTaskListSnapshotResponse
    ) async throws

    /// Atomically marks that the responder is allowed to enter the BLE writer. Once this marker
    /// survives a crash, later attempts must replay the exact frozen bytes.
    func markTaskListSnapshotDeliveryAttempted(
        _ response: FrozenTaskListSnapshotResponse
    ) async throws

    /// The caller has proved that no complete-message write was started. Restore the same durable
    /// version as a reservation so current task bytes can be frozen without consuming a revision.
    func rewindUnwrittenTaskListSnapshotDelivery(
        _ response: FrozenTaskListSnapshotResponse
    ) async throws

    /// Records that the complete acknowledgement was accepted by the BLE transport. Persistent
    /// stores must make this durable before best-effort cleanup so a cleanup failure cannot leave
    /// a confirmed delivery looking like an uncertain write.
    func markTaskListSnapshotDeliveryDelivered(
        _ response: FrozenTaskListSnapshotResponse
    ) async throws

    func completeTaskListSnapshotDelivery(
        _ response: FrozenTaskListSnapshotResponse
    ) async throws
}

extension TaskListSnapshotDeliveryStoring {
    /// Unknown stores must not silently report "no attempted delivery". Callers treat this error
    /// as a reason to keep ordinary task-state messages blocked.
    func hasAttemptedTaskListSnapshotDelivery(
        for destinationID: String
    ) async throws -> Bool {
        throw TaskListSnapshotDeliveryCapabilityError.attemptedDeliveryQueryUnsupported
    }

    /// Ephemeral stores do not need a cleanup tombstone. Removing the response at the durable
    /// confirmation point preserves their existing behavior; persistent stores override this.
    func markTaskListSnapshotDeliveryDelivered(
        _ response: FrozenTaskListSnapshotResponse
    ) async throws {
        try await completeTaskListSnapshotDelivery(response)
    }
}

@MainActor
enum TaskListSnapshotResponder {
    enum Outcome: Equatable {
        case sent
        case staleTaskState
        case failed
    }

    static func respond(
        to receipts: [TaskOperationReceipt],
        sender: any TaskListSnapshotSending,
        versionProvider: any TaskListSnapshotVersionProviding = LocalStorage.shared,
        deliveryStore: (any TaskListSnapshotDeliveryStoring)? = nil,
        tasksProvider: @escaping @MainActor () -> [TaskItem] = { AppState.shared.tasks },
        nowProvider: @escaping @MainActor () -> Date = { Date() },
        retrySleeper: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        },
        deliveryConfirmationAttempts: Int = 2,
        deliveryConfirmationRetrySleeper: @escaping @Sendable (Duration) async throws -> Void = {
            duration in
            try await Task.sleep(for: duration)
        },
        expectedTaskStateVersion: UInt64? = nil,
        taskStateVersionProvider: @escaping @MainActor () -> UInt64 = {
            AppState.shared.taskStateVersion
        }
    ) async -> Outcome {
        guard !receipts.isEmpty else { return .sent }

        var outcome: Outcome = .sent
        for receipt in receipts {
            do {
                try await sender.withTaskStateMessageGate {
                    let requestedTaskStateVersion = expectedTaskStateVersion
                        ?? taskStateVersionProvider()
                    try validateTaskState(
                        requestedTaskStateVersion,
                        taskStateVersionProvider: taskStateVersionProvider
                    )
                    let destinationID = sender.taskListSnapshotDestinationID
                    guard !destinationID.isEmpty else { throw BLEError.notConnected }
                    let key = TaskListSnapshotRequestKey(
                        destinationID: destinationID,
                        action: receipt.action,
                        operationID: receipt.operationID
                    )
                    let response: FrozenTaskListSnapshotResponse
                    let isAttemptedReplay: Bool
                    if let deliveryStore {
                        let preparation = try await deliveryStore
                            .prepareTaskListSnapshotDelivery(for: key)
                        switch preparation {
                        case .frozen(let frozen):
                            response = frozen
                            isAttemptedReplay = true
                        case .reserved(let version):
                            response = try await freezeResponse(
                                for: receipt,
                                key: key,
                                version: version,
                                sender: sender,
                                deliveryStore: deliveryStore,
                                tasksProvider: tasksProvider,
                                nowProvider: nowProvider,
                                expectedTaskStateVersion: requestedTaskStateVersion,
                                taskStateVersionProvider: taskStateVersionProvider
                            )
                            isAttemptedReplay = false
                        }
                    } else {
                        let version = try await versionProvider.nextTaskListSnapshotVersion()
                        response = try makeResponse(
                            for: receipt,
                            key: key,
                            version: version,
                            sender: sender,
                            tasksProvider: tasksProvider,
                            nowProvider: nowProvider,
                            expectedTaskStateVersion: requestedTaskStateVersion,
                            taskStateVersionProvider: taskStateVersionProvider
                        )
                        isAttemptedReplay = false
                    }
                    // A caller without an expected generation has not sent a paired DayPack in
                    // this transaction (RequestRefresh, offline replay, or a live retry preflight).
                    // An attempted response must therefore finish with its original bytes before
                    // any newer task presentation is allowed to start.
                    let responseTaskStateVersion: UInt64?
                    if isAttemptedReplay, expectedTaskStateVersion == nil {
                        responseTaskStateVersion = nil
                    } else {
                        responseTaskStateVersion = response.sourceTaskStateVersion
                            ?? requestedTaskStateVersion
                    }
                    do {
                        try validateTaskState(
                            responseTaskStateVersion,
                            taskStateVersionProvider: taskStateVersionProvider
                        )
                    } catch {
                        if let deliveryStore,
                           !isAttemptedReplay,
                           isStaleTaskStateError(error) {
                            try await deliveryStore
                                .rewindUnwrittenTaskListSnapshotDelivery(response)
                        }
                        throw error
                    }
                    do {
                        try await sendWithRetry(
                            response.payload,
                            sender: sender,
                            expectedTaskStateVersion: responseTaskStateVersion,
                            hasPriorAttempt: isAttemptedReplay,
                            beforeFirstWrite: {
                                if let deliveryStore, !isAttemptedReplay {
                                    try await deliveryStore
                                        .markTaskListSnapshotDeliveryAttempted(response)
                                }
                                do {
                                    try validateTaskState(
                                        responseTaskStateVersion,
                                        taskStateVersionProvider: taskStateVersionProvider
                                    )
                                } catch {
                                    if isStaleTaskStateError(error) {
                                        throw TaskListSnapshotWriteError.staleBeforeFirstWrite
                                    }
                                    throw error
                                }
                            },
                            retrySleeper: retrySleeper
                        )
                    } catch TaskListSnapshotWriteError.staleBeforeFirstWrite {
                        if let deliveryStore, !isAttemptedReplay {
                            try await deliveryStore
                                .rewindUnwrittenTaskListSnapshotDelivery(response)
                        }
                        throw BLEError.staleTaskSnapshot
                    } catch TaskListSnapshotWriteError.staleAfterUncertainWrite {
                        throw TaskListSnapshotWriteError.staleAfterUncertainWrite
                    }
                    if let deliveryStore {
                        try await markDeliveryConfirmedWithRetry(
                            response,
                            deliveryStore: deliveryStore,
                            maxAttempts: deliveryConfirmationAttempts,
                            retrySleeper: deliveryConfirmationRetrySleeper
                        )
                        do {
                            try await deliveryStore.completeTaskListSnapshotDelivery(response)
                        } catch {
                            // Delivery is already durably distinguished from an uncertain write.
                            // A duplicate request can replay the same bytes, while a newer operation
                            // can atomically discard this cleanup tombstone and advance.
                            reportFailure(error, component: "cleanup")
                        }
                    }
                }
            } catch {
                if let bleError = error as? BLEError,
                   case .staleTaskSnapshot = bleError {
                    return .staleTaskState
                }
                // A durable version or complete write is required before firmware can close the
                // pending operation. Send nothing; firmware retries the same request/operation ID.
                reportFailure(error, component: "response")
                outcome = .failed
            }
        }

        return outcome
    }

    private static func markDeliveryConfirmedWithRetry(
        _ response: FrozenTaskListSnapshotResponse,
        deliveryStore: any TaskListSnapshotDeliveryStoring,
        maxAttempts: Int,
        retrySleeper: @escaping @Sendable (Duration) async throws -> Void
    ) async throws {
        // Task OperationID/RequestID is only a nonzero idempotency key in the current wire
        // contract; firmware does not promise a globally monotonic counter, and offline batches
        // may contain multiple pending records. A larger number therefore cannot supersede an
        // attempted response. Retry only the durable confirmation write, never the BLE bytes.
        let attemptCount = max(1, maxAttempts)
        for attempt in 0..<attemptCount {
            do {
                try await deliveryStore.markTaskListSnapshotDeliveryDelivered(response)
                return
            } catch let error as CancellationError {
                throw error
            } catch {
                guard attempt + 1 < attemptCount else { throw error }
                try await retrySleeper(.milliseconds(250))
            }
        }
    }

    private static func freezeResponse(
        for receipt: TaskOperationReceipt,
        key: TaskListSnapshotRequestKey,
        version: TaskListSnapshotVersion,
        sender: any TaskListSnapshotSending,
        deliveryStore: any TaskListSnapshotDeliveryStoring,
        tasksProvider: @escaping @MainActor () -> [TaskItem],
        nowProvider: @escaping @MainActor () -> Date,
        expectedTaskStateVersion: UInt64?,
        taskStateVersionProvider: @escaping @MainActor () -> UInt64
    ) async throws -> FrozenTaskListSnapshotResponse {
        let response = try makeResponse(
            for: receipt,
            key: key,
            version: version,
            sender: sender,
            tasksProvider: tasksProvider,
            nowProvider: nowProvider,
            expectedTaskStateVersion: expectedTaskStateVersion,
            taskStateVersionProvider: taskStateVersionProvider
        )
        try await deliveryStore.freezeTaskListSnapshotDelivery(response)
        return response
    }

    private static func makeResponse(
        for receipt: TaskOperationReceipt,
        key: TaskListSnapshotRequestKey,
        version: TaskListSnapshotVersion,
        sender: any TaskListSnapshotSending,
        tasksProvider: @escaping @MainActor () -> [TaskItem],
        nowProvider: @escaping @MainActor () -> Date,
        expectedTaskStateVersion: UInt64?,
        taskStateVersionProvider: @escaping @MainActor () -> UInt64
    ) throws -> FrozenTaskListSnapshotResponse {
        try validateTaskState(
            expectedTaskStateVersion,
            taskStateVersionProvider: taskStateVersionProvider
        )
        let currentTasks = DayPackGenerator.topTaskSummaries(
            from: tasksProvider(),
            screenSize: sender.hardwareScreenSize,
            on: nowProvider()
        )
        try validateTaskState(
            expectedTaskStateVersion,
            taskStateVersionProvider: taskStateVersionProvider
        )
        let acknowledgement = TaskListSnapshotAck(
            action: receipt.action,
            operationID: receipt.operationID,
            result: receipt.result,
            version: version,
            tasks: currentTasks
        )
        return FrozenTaskListSnapshotResponse(
            key: key,
            version: version,
            sourceTaskStateVersion: expectedTaskStateVersion,
            payload: BLEDataEncoder.encodeTaskListSnapshotAck(acknowledgement)
        )
    }

    private static func sendWithRetry(
        _ frozenPayload: Data,
        sender: any TaskListSnapshotSending,
        expectedTaskStateVersion: UInt64?,
        hasPriorAttempt: Bool,
        beforeFirstWrite: @escaping @MainActor @Sendable () async throws -> Void,
        retrySleeper: @escaping @Sendable (Duration) async throws -> Void
    ) async throws {
        var lastError: Error?
        var hasUncertainWrite = hasPriorAttempt
        for attempt in 0..<2 {
            do {
                try await sender.writeTaskListSnapshotAckPayload(
                    frozenPayload,
                    expectedTaskStateVersion: expectedTaskStateVersion,
                    beforeFirstWrite: beforeFirstWrite
                )
                return
            } catch {
                if let writeError = error as? TaskListSnapshotWriteError,
                   case .staleBeforeFirstWrite = writeError {
                    throw hasUncertainWrite
                        ? TaskListSnapshotWriteError.staleAfterUncertainWrite
                        : error
                }
                if let bleError = error as? BLEError,
                   case .staleTaskSnapshot = bleError {
                    throw TaskListSnapshotWriteError.staleAfterUncertainWrite
                }
                hasUncertainWrite = true
                lastError = error
                if attempt == 0 {
                    try await retrySleeper(.milliseconds(250))
                }
            }
        }

        throw lastError ?? BLEError.writeFailed(nil)
    }

    private static func isStaleTaskStateError(_ error: Error) -> Bool {
        guard let bleError = error as? BLEError else { return false }
        if case .staleTaskSnapshot = bleError { return true }
        return false
    }

    private static func validateTaskState(
        _ expectedTaskStateVersion: UInt64?,
        taskStateVersionProvider: @MainActor () -> UInt64
    ) throws {
        guard let expectedTaskStateVersion else { return }
        guard taskStateVersionProvider() == expectedTaskStateVersion else {
            throw BLEError.staleTaskSnapshot
        }
    }

    private static func reportFailure(_ error: Error, component: String) {
        ErrorReporter.log(
            .sync(
                component: "BLE TaskListSnapshotAck \(component)",
                underlying: error.localizedDescription
            ),
            context: "TaskListSnapshotResponder.respond"
        )
    }
}
