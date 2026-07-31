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

    func performPageTransaction(
        _ operation: @MainActor () async -> Void
    ) async {
        do {
            try await gate.acquire()
        } catch {
            return
        }

        pageTransactionGeneration &+= 1
        isPageTransactionActive = true
        await operation()
        isPageTransactionActive = false
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
        tasksProvider: @escaping @MainActor () -> [TaskItem] = { AppState.shared.tasks },
        taskStateVersionProvider: @escaping @MainActor () -> UInt64 = {
            AppState.shared.taskStateVersion
        }
    ) async {
        let acknowledge: @MainActor @Sendable (
            UInt64
        ) async -> TaskListSnapshotResponder.Outcome = { expectedTaskStateVersion in
            await TaskListSnapshotResponder.respond(
                to: receipts,
                sender: sender,
                versionProvider: versionProvider,
                tasksProvider: tasksProvider,
                expectedTaskStateVersion: expectedTaskStateVersion,
                taskStateVersionProvider: taskStateVersionProvider
            )
        }
        guard receipts.contains(where: {
            $0.action == .completeTask || $0.action == .skipTask
        }) else {
            _ = await TaskListSnapshotResponder.respond(
                to: receipts,
                sender: sender,
                versionProvider: versionProvider,
                tasksProvider: tasksProvider,
                taskStateVersionProvider: taskStateVersionProvider
            )
            return
        }

        await presentationCoordinator.sendFinalDayPackBeforeAcknowledgement(acknowledge)
    }

    /// Offline `0x21` replay has no live TaskIn presentation to commit. Preserve record order and
    /// acknowledge every recovered operation directly; inserting one shared DayPack before a
    /// batch of acknowledgements would not form a valid per-operation presentation transaction.
    @discardableResult
    static func respondToReplayedTaskOperations(
        _ receipts: [TaskOperationReceipt],
        sender: any TaskListSnapshotSending,
        versionProvider: any TaskListSnapshotVersionProviding = LocalStorage.shared,
        tasksProvider: @escaping @MainActor () -> [TaskItem] = { AppState.shared.tasks },
        taskStateVersionProvider: @escaping @MainActor () -> UInt64 = {
            AppState.shared.taskStateVersion
        }
    ) async -> TaskListSnapshotResponder.Outcome {
        await TaskListSnapshotResponder.respond(
            to: receipts,
            sender: sender,
            versionProvider: versionProvider,
            tasksProvider: tasksProvider,
            taskStateVersionProvider: taskStateVersionProvider
        )
    }
}
