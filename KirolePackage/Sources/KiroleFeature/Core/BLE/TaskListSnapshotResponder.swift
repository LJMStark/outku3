import Foundation

// MARK: - 0x1B acknowledgement delivery (freeze, send, confirm)

// Split out of `TaskListSnapshotProtocol.swift`: everything below is about *getting* an
// acknowledgement to the device exactly once — freezing bytes against a task generation,
// surviving a crash mid-write, and confirming delivery — not about what the bytes mean.

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
