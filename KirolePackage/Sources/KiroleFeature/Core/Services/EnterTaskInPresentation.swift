import Foundation

/// Serializes complete hardware-page transactions with every other presentation write.
///
/// TaskIn and task-action frames are multi-write transactions. The lower BLE write gate only
/// protects one GATT packet, so it cannot stop a focus/scene frame from landing between chunks or
/// between the final DayPack and 0x1B. This gate owns that wider boundary.
@MainActor
final class HardwarePagePresentationGate {
    static let shared = HardwarePagePresentationGate()

    private let gate = BLEWriteGate()
    private var pageTransactionGeneration: UInt64 = 0
    private var isPageTransactionActive = false
    /// Includes both the active owner and callers waiting behind a presentation write. A queued
    /// task-action retry must be visible before it acquires the gate so an in-flight full sync can
    /// stand down before writing a newer DayPack.
    private var pageTransactionDemandCount = 0

    var hasPageTransactionDemand: Bool {
        pageTransactionDemandCount > 0
    }

    func performPageTransaction(
        _ operation: @MainActor () async -> Void
    ) async {
        pageTransactionDemandCount += 1
        do {
            try await gate.acquire()
        } catch {
            pageTransactionDemandCount -= 1
            return
        }

        pageTransactionGeneration &+= 1
        isPageTransactionActive = true
        await operation()
        isPageTransactionActive = false
        pageTransactionDemandCount -= 1
        await gate.release()
    }

    /// Runs a non-page presentation only when no complete page transaction owns the wire.
    /// Focus/scene updates are obsolete if a page transaction ran while they waited, whereas a
    /// full identity sync must set `droppingIfPageTransactionIntervened` to false and resample the
    /// latest App state after the transaction.
    @discardableResult
    func performPresentationWrite(
        droppingIfPageTransactionIntervened: Bool,
        _ operation: @MainActor () async throws -> Void
    ) async throws -> Bool {
        let observedGeneration = pageTransactionGeneration
        let transactionWasActive = isPageTransactionActive
        try await gate.acquire()

        if droppingIfPageTransactionIntervened,
           transactionWasActive || pageTransactionGeneration != observedGeneration {
            await gate.release()
            return false
        }

        do {
            try await operation()
        } catch {
            await gate.release()
            throw error
        }
        await gate.release()
        return true
    }
}

@MainActor
protocol TaskActionPresentationCoordinating: AnyObject {
    /// Sends the final task/dialogue DayPack while the device is still on TaskIn, then performs
    /// the acknowledgement that lets firmware enter Overview and render that cached DayPack.
    func sendFinalDayPackBeforeAcknowledgement(
        _ acknowledgement: @MainActor @Sendable (
            _ expectedTaskStateVersion: UInt64
        ) async -> TaskListSnapshotResponder.Outcome
    ) async

    /// Binds the presentation transaction to the sender that raised the operation. The explicit
    /// destination survives connection changes while the DayPack and acknowledgement are awaited.
    func sendFinalDayPackBeforeAcknowledgement(
        destinationID: String,
        _ acknowledgement: @MainActor @Sendable (
            _ expectedTaskStateVersion: UInt64
        ) async -> TaskListSnapshotResponder.Outcome
    ) async

    /// Replays an acknowledgement whose matching final DayPack was already sent. The coordinator
    /// still owns the presentation window so routine sync cannot publish a newer DayPack until the
    /// frozen acknowledgement write and its delivery-state cleanup have both completed.
    func replayAttemptedAcknowledgement(
        _ acknowledgement: @MainActor @Sendable () async -> TaskListSnapshotResponder.Outcome
    ) async

    func replayAttemptedAcknowledgement(
        destinationID: String,
        _ acknowledgement: @MainActor @Sendable () async -> TaskListSnapshotResponder.Outcome
    ) async
}

extension TaskActionPresentationCoordinating {
    func sendFinalDayPackBeforeAcknowledgement(
        destinationID: String,
        _ acknowledgement: @MainActor @Sendable (
            _ expectedTaskStateVersion: UInt64
        ) async -> TaskListSnapshotResponder.Outcome
    ) async {
        guard !destinationID.isEmpty else { return }
        await sendFinalDayPackBeforeAcknowledgement(acknowledgement)
    }

    func replayAttemptedAcknowledgement(
        _ acknowledgement: @MainActor @Sendable () async -> TaskListSnapshotResponder.Outcome
    ) async {
        _ = await acknowledgement()
    }

    func replayAttemptedAcknowledgement(
        destinationID: String,
        _ acknowledgement: @MainActor @Sendable () async -> TaskListSnapshotResponder.Outcome
    ) async {
        guard !destinationID.isEmpty else { return }
        await replayAttemptedAcknowledgement(acknowledgement)
    }
}

/// Freezes the logical destination used to build durable ACK keys and rejects the write if the
/// underlying sender moves to another device while any responder/storage operation is suspended.
@MainActor
private final class DestinationBoundTaskListSnapshotSender: TaskListSnapshotSending {
    private let sender: any TaskListSnapshotSending
    let taskListSnapshotDestinationID: String

    var hardwareScreenSize: ScreenSize {
        sender.hardwareScreenSize
    }

    init(sender: any TaskListSnapshotSending, destinationID: String) {
        self.sender = sender
        taskListSnapshotDestinationID = destinationID
    }

    func withTaskStateMessageGate(
        _ operation: @MainActor () async throws -> Void
    ) async throws {
        try validateDestination()
        try await sender.withTaskStateMessageGate {
            try self.validateDestination()
            try await operation()
        }
    }

    func writeTaskListSnapshotAckPayload(
        _ payload: Data,
        expectedTaskStateVersion: UInt64?
    ) async throws {
        try await writeTaskListSnapshotAckPayload(
            payload,
            expectedTaskStateVersion: expectedTaskStateVersion,
            beforeFirstWrite: {}
        )
    }

    func writeTaskListSnapshotAckPayload(
        _ payload: Data,
        expectedTaskStateVersion: UInt64?,
        beforeFirstWrite: @escaping @MainActor @Sendable () async throws -> Void
    ) async throws {
        try validateDestination()
        try await sender.writeTaskListSnapshotAckPayload(
            payload,
            expectedTaskStateVersion: expectedTaskStateVersion,
            beforeFirstWrite: {
                try self.validateDestination()
                try await beforeFirstWrite()
                // The attempted marker can suspend. Validate again at the last point before the
                // underlying sender hands the first 0x1B packet to its transport.
                try self.validateDestination()
            }
        )
    }

    private func validateDestination() throws {
        guard sender.taskListSnapshotDestinationID == taskListSnapshotDestinationID else {
            throw BLEPresentationDestinationError.changed
        }
    }
}

enum EnterTaskInRoute {
    case sendTaskIn(TaskItem)
    case recoverInteractive
}

enum EnterTaskInPresentationResult: Equatable {
    case presented
    case pageWriteFailed
    case focusStartFailed
}

// MARK: - EnterTaskIn page transaction

extension BLEEventHandler {
    /// Production seam for the EnterTaskIn page transaction. The complete 0x11 page is the first
    /// committed hardware state; only a successful write may start the App focus session. Keeping
    /// both operations in one awaited function also makes the real wire-to-page order testable.
    @discardableResult
    static func performEnterTaskInPresentation(
        task: TaskItem,
        pet: Pet,
        userProfile: UserProfile,
        sendTaskInPage: @MainActor (TaskInPageData) async throws -> Void,
        startFocus: @MainActor () async -> Bool
    ) async -> EnterTaskInPresentationResult {
        let taskInPage = DayPackGenerator.shared.generateTaskInPage(
            task: task,
            pet: pet,
            userProfile: userProfile
        )
        do {
            try await sendTaskInPage(taskInPage)
        } catch {
            ErrorReporter.log(
                .sync(component: "BLE TaskInPage", underlying: error.localizedDescription),
                context: "BLEEventHandler.performEnterTaskInPresentation"
            )
            return .pageWriteFailed
        }
        guard await startFocus() else {
            ErrorReporter.log(
                .sync(
                    component: "BLE EnterTaskIn",
                    underlying: "TaskInPage arrived but the App focus session did not start"
                ),
                context: "BLEEventHandler.performEnterTaskInPresentation"
            )
            return .focusStartFailed
        }
        return .presented
    }

    static func enterTaskInRoute(
        for eventLog: EventLog,
        tasks: [TaskItem]
    ) -> EnterTaskInRoute {
        guard let taskID = eventLog.taskId,
              let task = resolveTask(taskId: taskID, in: tasks) else {
            return .recoverInteractive
        }
        return .sendTaskIn(task)
    }

    static func respondToLiveTaskOperations(
        _ receipts: [TaskOperationReceipt],
        sender: any TaskListSnapshotSending,
        presentationCoordinator: any TaskActionPresentationCoordinating,
        versionProvider: any TaskListSnapshotVersionProviding = LocalStorage.shared,
        deliveryStore: (any TaskListSnapshotDeliveryStoring)? = LocalStorage.shared,
        tasksProvider: @escaping @MainActor () -> [TaskItem] = { AppState.shared.tasks },
        taskStateVersionProvider: @escaping @MainActor () -> UInt64 = {
            AppState.shared.taskStateVersion
        }
    ) async {
        // Capture once before any awaited work. A reconnect must not move this operation's
        // coordinator barrier from its originating device to whichever device is current later.
        let destinationID = sender.taskListSnapshotDestinationID
        guard receipts.contains(where: {
            $0.action == .completeTask || $0.action == .skipTask
        }) else {
            _ = await TaskListSnapshotResponder.respond(
                to: receipts,
                sender: sender,
                versionProvider: versionProvider,
                deliveryStore: deliveryStore,
                tasksProvider: tasksProvider,
                taskStateVersionProvider: taskStateVersionProvider
            )
            return
        }
        guard !destinationID.isEmpty else {
            // Let the production coordinator install an unbound fail-closed barrier. It must not
            // infer a later connection's destination for this already-received operation.
            await presentationCoordinator.sendFinalDayPackBeforeAcknowledgement(
                destinationID: destinationID,
                { _ in .failed }
            )
            ErrorReporter.log(
                .sync(
                    component: "BLE Task Action Presentation",
                    underlying: "task action sender has no snapshot destination ID"
                ),
                context: "BLEEventHandler.respondToLiveTaskOperations"
            )
            return
        }
        let destinationBoundSender = DestinationBoundTaskListSnapshotSender(
            sender: sender,
            destinationID: destinationID
        )
        let acknowledge: @MainActor @Sendable (
            UInt64
        ) async -> TaskListSnapshotResponder.Outcome = { expectedTaskStateVersion in
            await TaskListSnapshotResponder.respond(
                to: receipts,
                sender: destinationBoundSender,
                versionProvider: versionProvider,
                deliveryStore: deliveryStore,
                tasksProvider: tasksProvider,
                expectedTaskStateVersion: expectedTaskStateVersion,
                taskStateVersionProvider: taskStateVersionProvider
            )
        }

        // A failed 0x1B attempt already has the matching final DayPack cached on the device.
        // Finish that frozen acknowledgement before generating another DayPack; otherwise a
        // newer pack could be paired with an older immutable Overview response.
        if let deliveryStore {
            do {
                for receipt in receipts where receipt.action == .completeTask
                    || receipt.action == .skipTask {
                    let key = TaskListSnapshotRequestKey(
                        destinationID: destinationID,
                        action: receipt.action,
                        operationID: receipt.operationID
                    )
                    if case .frozen = try await deliveryStore
                        .prepareTaskListSnapshotDelivery(for: key) {
                        await presentationCoordinator.replayAttemptedAcknowledgement(
                            destinationID: destinationID
                        ) {
                            await TaskListSnapshotResponder.respond(
                                to: [receipt],
                                sender: destinationBoundSender,
                                versionProvider: versionProvider,
                                deliveryStore: deliveryStore,
                                tasksProvider: tasksProvider,
                                taskStateVersionProvider: taskStateVersionProvider
                            )
                        }
                        return
                    }
                }
            } catch {
                ErrorReporter.log(
                    .sync(
                        component: "BLE Task Action retry preflight",
                        underlying: error.localizedDescription
                    ),
                    context: "BLEEventHandler.respondToLiveTaskOperations"
                )
                return
            }
        }

        await presentationCoordinator.sendFinalDayPackBeforeAcknowledgement(
            destinationID: destinationID,
            acknowledge
        )
    }

    /// Offline `0x21` replay has no live TaskIn presentation to commit. Preserve record order and
    /// acknowledge every recovered operation directly; inserting one shared DayPack before a
    /// batch of acknowledgements would not form a valid per-operation presentation transaction.
    @discardableResult
    static func respondToReplayedTaskOperations(
        _ receipts: [TaskOperationReceipt],
        sender: any TaskListSnapshotSending,
        versionProvider: any TaskListSnapshotVersionProviding = LocalStorage.shared,
        deliveryStore: (any TaskListSnapshotDeliveryStoring)? = LocalStorage.shared,
        tasksProvider: @escaping @MainActor () -> [TaskItem] = { AppState.shared.tasks },
        taskStateVersionProvider: @escaping @MainActor () -> UInt64 = {
            AppState.shared.taskStateVersion
        }
    ) async -> TaskListSnapshotResponder.Outcome {
        await TaskListSnapshotResponder.respond(
            to: receipts,
            sender: sender,
            versionProvider: versionProvider,
            deliveryStore: deliveryStore,
            tasksProvider: tasksProvider,
            taskStateVersionProvider: taskStateVersionProvider
        )
    }
}
