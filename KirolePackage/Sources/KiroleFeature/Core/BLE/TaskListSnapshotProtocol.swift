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

struct TaskOperationLedgerEntry: Sendable, Equatable, Codable {
    let deviceID: String
    let action: TaskListSnapshotAction
    let operationID: UInt32
    let taskID: String
    let deviceTimestamp: UInt32
    let result: TaskListSnapshotResultCode
    let state: TaskOperationLedgerState
    let recordedAt: Date

    init(
        deviceID: String,
        action: TaskListSnapshotAction,
        operationID: UInt32,
        taskID: String,
        deviceTimestamp: UInt32,
        result: TaskListSnapshotResultCode,
        state: TaskOperationLedgerState = .committed,
        recordedAt: Date
    ) {
        self.deviceID = deviceID
        self.action = action
        self.operationID = operationID
        self.taskID = taskID
        self.deviceTimestamp = deviceTimestamp
        self.result = result
        self.state = state
        self.recordedAt = recordedAt
    }

    private enum CodingKeys: String, CodingKey {
        case deviceID
        case action
        case operationID
        case taskID
        case deviceTimestamp
        case result
        case state
        case recordedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceID = try container.decode(String.self, forKey: .deviceID)
        action = try container.decode(TaskListSnapshotAction.self, forKey: .action)
        operationID = try container.decode(UInt32.self, forKey: .operationID)
        taskID = try container.decode(String.self, forKey: .taskID)
        deviceTimestamp = try container.decode(UInt32.self, forKey: .deviceTimestamp)
        result = try container.decode(TaskListSnapshotResultCode.self, forKey: .result)
        state = try container.decodeIfPresent(TaskOperationLedgerState.self, forKey: .state) ?? .committed
        recordedAt = try container.decode(Date.self, forKey: .recordedAt)
    }

    func matchesPayload(of event: EventLog) -> Bool {
        taskID == (event.taskId ?? "")
            && deviceTimestamp == UInt32(event.timestamp.timeIntervalSince1970)
    }

    func withState(_ state: TaskOperationLedgerState) -> TaskOperationLedgerEntry {
        TaskOperationLedgerEntry(
            deviceID: deviceID,
            action: action,
            operationID: operationID,
            taskID: taskID,
            deviceTimestamp: deviceTimestamp,
            result: result,
            state: state,
            recordedAt: recordedAt
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
            deviceTimestamp: deviceTimestamp,
            result: result,
            state: state,
            recordedAt: recordedAt
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
    func reserve(
        event: EventLog,
        deviceID: String,
        result: TaskListSnapshotResultCode,
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

        let entry = TaskOperationLedgerEntry(
            deviceID: deviceID,
            action: action,
            operationID: operationID,
            taskID: event.taskId ?? "",
            deviceTimestamp: UInt32(event.timestamp.timeIntervalSince1970),
            result: result,
            state: .pending,
            recordedAt: now
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
        now: Date = Date()
    ) async -> Bool {
        switch await reserve(event: event, deviceID: deviceID, result: result, now: now) {
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
    /// Acquires the same complete-message gate used by DayPack. The responder binds a durable
    /// version to the task snapshot only after this succeeds, so an older snapshot cannot wait
    /// behind and then overwrite a newer DayPack with a higher revision.
    func withTaskStateMessageGate(
        _ operation: @MainActor () async throws -> Void
    ) async throws
    /// Sends bytes that were frozen together with their StateEpoch/Revision. A retry must use the
    /// identical payload even if App tasks change while the first GATT callback is missing. The
    /// caller already owns the complete-message gate.
    func writeTaskListSnapshotAckPayload(_ payload: Data) async throws
}

protocol TaskListSnapshotVersionProviding: Sendable {
    func nextTaskListSnapshotVersion() async throws -> TaskListSnapshotVersion
}

@MainActor
enum TaskListSnapshotResponder {
    static func respond(
        to receipts: [TaskOperationReceipt],
        sender: any TaskListSnapshotSending,
        versionProvider: any TaskListSnapshotVersionProviding = LocalStorage.shared,
        tasksProvider: @escaping @MainActor () -> [TaskItem] = { AppState.shared.tasks }
    ) async {
        guard !receipts.isEmpty else { return }

        for receipt in receipts {
            do {
                try await sender.withTaskStateMessageGate {
                    // Persist the revision first, then capture App state while the task-message gate
                    // is held. Any DayPack already in flight finishes first; any later one queues
                    // behind this frozen acknowledgement and both retries.
                    let version = try await versionProvider.nextTaskListSnapshotVersion()
                    let currentTasks = DayPackGenerator.topTaskSummaries(
                        from: tasksProvider(),
                        screenSize: sender.hardwareScreenSize
                    )
                    let acknowledgement = TaskListSnapshotAck(
                        action: receipt.action,
                        operationID: receipt.operationID,
                        result: receipt.result,
                        version: version,
                        tasks: currentTasks
                    )
                    let frozenPayload = BLEDataEncoder.encodeTaskListSnapshotAck(acknowledgement)
                    await sendWithRetry(frozenPayload, sender: sender)
                }
            } catch {
                // Without a durable epoch/revision, sending a snapshot could make firmware accept
                // an ordering value the App forgets after a crash. Send nothing; firmware retries
                // the same request/operation ID.
                reportFailure(error, component: "snapshot version")
            }
        }
    }

    private static func sendWithRetry(
        _ frozenPayload: Data,
        sender: any TaskListSnapshotSending
    ) async {
        var lastError: Error?
        for attempt in 0..<2 {
            do {
                try await sender.writeTaskListSnapshotAckPayload(frozenPayload)
                return
            } catch {
                lastError = error
                if attempt == 0 {
                    do {
                        try await Task.sleep(for: .milliseconds(250))
                    } catch {
                        return
                    }
                }
            }
        }

        ErrorReporter.log(
            .sync(
                component: "BLE TaskListSnapshotAck",
                underlying: lastError?.localizedDescription ?? "write failed after 2 attempts"
            ),
            context: "TaskListSnapshotResponder.respond"
        )
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
