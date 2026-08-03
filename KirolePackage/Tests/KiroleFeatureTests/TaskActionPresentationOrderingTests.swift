import Foundation
import Testing
@testable import KiroleFeature

@Suite("Task action presentation ordering")
struct TaskActionPresentationOrderingTests {
    @Test("Complete sends the final DayPack before the acknowledgement that exits TaskIn")
    @MainActor
    func completeSendsDayPackBeforeAcknowledgement() async {
        let order = TaskActionWireOrder()
        let presentation = TaskActionPresentationCoordinatorSpy(order: order)
        let sender = TaskActionSnapshotSenderSpy(order: order)
        let versions = TaskActionSnapshotVersionProvider()

        await BLEEventHandler.respondToLiveTaskOperations(
            [TaskOperationReceipt(action: .completeTask, operationID: 42, result: .applied)],
            sender: sender,
            presentationCoordinator: presentation,
            versionProvider: versions,
            deliveryStore: nil,
            tasksProvider: { [] },
            taskStateVersionProvider: { 0 }
        )

        #expect(order.events == ["dayPack", "acknowledgement"])
        #expect(presentation.callCount == 1)
        #expect(presentation.sendDestinationIDs == [sender.taskListSnapshotDestinationID])
    }

    @Test("Task action ACK never follows a sender that switches from A to B")
    @MainActor
    func taskActionCapturesSenderDestinationOnce() async {
        let order = TaskActionWireOrder()
        let presentation = TaskActionPresentationCoordinatorSpy(order: order)
        let sender = TaskActionSnapshotSenderSpy(order: order, destinationID: "device-a")
        let versions = TaskActionSnapshotVersionProvider()
        let deliveryStore = InMemoryTaskListSnapshotDeliveryStore(versionProvider: versions)
        presentation.beforeSend = {
            sender.taskListSnapshotDestinationID = "device-b"
        }

        await BLEEventHandler.respondToLiveTaskOperations(
            [TaskOperationReceipt(action: .completeTask, operationID: 46, result: .applied)],
            sender: sender,
            presentationCoordinator: presentation,
            versionProvider: versions,
            deliveryStore: deliveryStore,
            tasksProvider: { [] },
            taskStateVersionProvider: { 0 }
        )

        #expect(presentation.sendDestinationIDs == ["device-a"])
        #expect(sender.taskListSnapshotDestinationID == "device-b")
        #expect(order.events == ["dayPack"])
        #expect(await deliveryStore.preparedDestinationIDs() == Set(["device-a"]))
        #expect(await deliveryStore.frozenResponseCount() == 0)
    }

    @Test("A task action without a destination fails closed before presentation")
    @MainActor
    func taskActionWithoutDestinationFailsClosed() async {
        let order = TaskActionWireOrder()
        let presentation = TaskActionPresentationCoordinatorSpy(order: order)
        let sender = TaskActionSnapshotSenderSpy(order: order, destinationID: "")

        await BLEEventHandler.respondToLiveTaskOperations(
            [TaskOperationReceipt(action: .completeTask, operationID: 47, result: .applied)],
            sender: sender,
            presentationCoordinator: presentation,
            versionProvider: TaskActionSnapshotVersionProvider(),
            deliveryStore: nil,
            tasksProvider: { [] },
            taskStateVersionProvider: { 0 }
        )

        #expect(order.events.isEmpty)
        #expect(presentation.callCount == 0)
        #expect(presentation.sendDestinationIDs.isEmpty)
    }

    @Test("An unbound task action blocks routine sync for every destination")
    @MainActor
    func unboundTaskActionInstallsGlobalBarrier() async {
        let order = TaskActionWireOrder()
        let destination = TaskActionDestinationBox("device-b")
        let coordinator = BLESyncCoordinator.makeForTestingTaskActionPresentation(
            appState: AppState.makeForTesting(),
            sendFinalDayPack: {
                Issue.record("An unbound task action must not send a DayPack")
                return nil
            },
            runScheduledSync: { _, _ in order.events.append("unexpectedSync") },
            connectedDestinationProvider: { destination.value }
        )

        await coordinator.sendFinalDayPackBeforeAcknowledgement(destinationID: "") { _ in
            Issue.record("An unbound task action must not acknowledge")
            return .sent
        }
        await coordinator.performSync(force: true, trigger: .manual)

        #expect(order.events.isEmpty)
    }

    @Test("Skip sends the final DayPack before the acknowledgement that exits TaskIn")
    @MainActor
    func skipSendsDayPackBeforeAcknowledgement() async {
        let order = TaskActionWireOrder()
        let presentation = TaskActionPresentationCoordinatorSpy(order: order)
        let sender = TaskActionSnapshotSenderSpy(order: order)
        let versions = TaskActionSnapshotVersionProvider()

        await BLEEventHandler.respondToLiveTaskOperations(
            [TaskOperationReceipt(action: .skipTask, operationID: 44, result: .applied)],
            sender: sender,
            presentationCoordinator: presentation,
            versionProvider: versions,
            deliveryStore: nil,
            tasksProvider: { [] },
            taskStateVersionProvider: { 0 }
        )

        #expect(order.events == ["dayPack", "acknowledgement"])
        #expect(presentation.callCount == 1)
    }

    @Test("RequestRefresh acknowledgement remains immediate")
    @MainActor
    func requestRefreshDoesNotWaitForTaskActionPresentation() async {
        let order = TaskActionWireOrder()
        let presentation = TaskActionPresentationCoordinatorSpy(order: order)
        let sender = TaskActionSnapshotSenderSpy(order: order)
        let versions = TaskActionSnapshotVersionProvider()

        await BLEEventHandler.respondToLiveTaskOperations(
            [TaskOperationReceipt(action: .requestRefresh, operationID: 43, result: .applied)],
            sender: sender,
            presentationCoordinator: presentation,
            versionProvider: versions,
            deliveryStore: nil,
            tasksProvider: { [] },
            taskStateVersionProvider: { 0 }
        )

        #expect(order.events == ["acknowledgement"])
        #expect(presentation.callCount == 0)
    }

    @Test("An attempted acknowledgement retry does not cache a newer DayPack first")
    @MainActor
    func attemptedRetrySkipsNewDayPack() async throws {
        let order = TaskActionWireOrder()
        let presentation = TaskActionPresentationCoordinatorSpy(order: order)
        let sender = TaskActionSnapshotSenderSpy(order: order)
        let versions = TaskActionSnapshotVersionProvider()
        let deliveryStore = InMemoryTaskListSnapshotDeliveryStore(
            versionProvider: versions
        )
        let receipt = TaskOperationReceipt(
            action: .completeTask,
            operationID: 45,
            result: .applied
        )
        let key = TaskListSnapshotRequestKey(
            destinationID: sender.taskListSnapshotDestinationID,
            action: receipt.action,
            operationID: receipt.operationID
        )
        guard case .reserved(let version) = try await deliveryStore
            .prepareTaskListSnapshotDelivery(for: key) else {
            Issue.record("Expected a reserved first delivery")
            return
        }
        let frozen = FrozenTaskListSnapshotResponse(
            key: key,
            version: version,
            sourceTaskStateVersion: 7,
            payload: BLEDataEncoder.encodeTaskListSnapshotAck(TaskListSnapshotAck(
                action: receipt.action,
                operationID: receipt.operationID,
                result: receipt.result,
                version: version,
                tasks: []
            ))
        )
        try await deliveryStore.freezeTaskListSnapshotDelivery(frozen)
        try await deliveryStore.markTaskListSnapshotDeliveryAttempted(frozen)

        await BLEEventHandler.respondToLiveTaskOperations(
            [receipt],
            sender: sender,
            presentationCoordinator: presentation,
            versionProvider: versions,
            deliveryStore: deliveryStore,
            tasksProvider: { [] },
            taskStateVersionProvider: { 8 }
        )

        #expect(order.events == ["acknowledgement"])
        #expect(presentation.callCount == 0)
        #expect(presentation.replayCallCount == 1)
        #expect(presentation.replayDestinationIDs == [sender.taskListSnapshotDestinationID])
        #expect(await deliveryStore.frozenResponseCount() == 0)
    }

    @Test("Attempted ACK replay stays on A when the sender switches to B")
    @MainActor
    func attemptedReplayRejectsDestinationSwitch() async throws {
        let order = TaskActionWireOrder()
        let presentation = TaskActionPresentationCoordinatorSpy(order: order)
        let sender = TaskActionSnapshotSenderSpy(order: order, destinationID: "device-a")
        let versions = TaskActionSnapshotVersionProvider()
        let deliveryStore = InMemoryTaskListSnapshotDeliveryStore(versionProvider: versions)
        let receipt = TaskOperationReceipt(
            action: .completeTask,
            operationID: 48,
            result: .applied
        )
        let key = TaskListSnapshotRequestKey(
            destinationID: "device-a",
            action: receipt.action,
            operationID: receipt.operationID
        )
        guard case .reserved(let version) = try await deliveryStore
            .prepareTaskListSnapshotDelivery(for: key) else {
            Issue.record("Expected a reserved first delivery")
            return
        }
        let frozen = FrozenTaskListSnapshotResponse(
            key: key,
            version: version,
            sourceTaskStateVersion: 7,
            payload: BLEDataEncoder.encodeTaskListSnapshotAck(TaskListSnapshotAck(
                action: receipt.action,
                operationID: receipt.operationID,
                result: receipt.result,
                version: version,
                tasks: []
            ))
        )
        try await deliveryStore.freezeTaskListSnapshotDelivery(frozen)
        try await deliveryStore.markTaskListSnapshotDeliveryAttempted(frozen)
        presentation.beforeReplay = {
            sender.taskListSnapshotDestinationID = "device-b"
        }

        await BLEEventHandler.respondToLiveTaskOperations(
            [receipt],
            sender: sender,
            presentationCoordinator: presentation,
            versionProvider: versions,
            deliveryStore: deliveryStore,
            tasksProvider: { [] },
            taskStateVersionProvider: { 8 }
        )

        #expect(order.events.isEmpty)
        #expect(presentation.replayDestinationIDs == ["device-a"])
        #expect(await deliveryStore.preparedDestinationIDs() == Set(["device-a"]))
        #expect(await deliveryStore.frozenResponseCount() == 1)
    }

    @Test("Attempted acknowledgement replay defers ordinary sync until ACK cleanup finishes")
    @MainActor
    func attemptedReplayDefersOrdinarySyncUntilCleanup() async {
        let order = TaskActionWireOrder()
        let barrier = TaskActionReplayBarrier()
        let coordinator = BLESyncCoordinator.makeForTestingTaskActionPresentation(
            appState: AppState.makeForTesting(),
            sendFinalDayPack: {
                Issue.record("Attempted acknowledgement replay must not generate a new DayPack")
                return nil
            },
            runScheduledSync: { force, trigger in
                #expect(force)
                #expect(trigger == .manual)
                order.events.append("latestSync")
            }
        )

        await coordinator.replayAttemptedAcknowledgement(destinationID: "device-a") {
            order.events.append("failedAcknowledgement")
            return .failed
        }
        await coordinator.performSync(force: true, trigger: .manual)
        #expect(order.events == ["failedAcknowledgement"])

        let replay = Task { @MainActor in
            await coordinator.replayAttemptedAcknowledgement(destinationID: "device-a") {
                order.events.append("acknowledgement")
                await barrier.waitForRelease()
                order.events.append("cleanup")
                return .sent
            }
        }
        await barrier.waitUntilStarted()

        #expect(order.events == ["failedAcknowledgement", "acknowledgement"])

        await barrier.release()
        await replay.value

        #expect(order.events == [
            "failedAcknowledgement",
            "acknowledgement",
            "cleanup",
            "latestSync"
        ])
    }

    @Test("A restarted coordinator blocks an already-connected sync on durable attempted ACK")
    @MainActor
    func restartedCoordinatorRestoresAttemptedACKBarrierAtEntry() async {
        let order = TaskActionWireOrder()
        let destination = TaskActionDestinationBox("restarted-device")
        let attemptedChecker = TaskActionAttemptedDeliveryChecker(.attempted)
        let coordinator = BLESyncCoordinator.makeForTestingTaskActionPresentation(
            appState: AppState.makeForTesting(),
            sendFinalDayPack: {
                Issue.record("Durable attempted ACK must block new DayPack generation")
                return nil
            },
            runScheduledSync: { force, trigger in
                #expect(force)
                #expect(trigger == .manual)
                order.events.append("latestSync")
            },
            attemptedDeliveryChecker: { destinationID in
                try await attemptedChecker.check(destinationID)
            },
            connectedDestinationProvider: { destination.value }
        )

        await coordinator.performSync(force: true, trigger: .manual)

        #expect(order.events.isEmpty)
        #expect(await attemptedChecker.destinations == ["restarted-device"])

        await attemptedChecker.setResult(.clear)
        await coordinator.replayAttemptedAcknowledgement(destinationID: "restarted-device") {
            order.events.append("cleanup")
            return .sent
        }

        #expect(order.events == ["cleanup", "latestSync"])
    }

    @Test("A destination discovered after connect is checked before ordinary sync continues")
    @MainActor
    func postConnectAttemptedACKCheckFailsClosed() async {
        let order = TaskActionWireOrder()
        let destination = TaskActionDestinationBox(nil)
        let attemptedChecker = TaskActionAttemptedDeliveryChecker(.attempted)
        let coordinator = BLESyncCoordinator.makeForTestingTaskActionPresentation(
            appState: AppState.makeForTesting(),
            sendFinalDayPack: { nil },
            runScheduledSync: { force, trigger in
                #expect(force)
                #expect(trigger == .manual)
                order.events.append("latestSync")
            },
            attemptedDeliveryChecker: { destinationID in
                try await attemptedChecker.check(destinationID)
            },
            connectedDestinationProvider: { destination.value }
        )

        coordinator.setSyncingForTesting(true)
        #expect(!(await coordinator.shouldDeferForPersistedAttemptedDeliveryForTesting(
            force: true,
            trigger: .manual
        )))
        #expect(await attemptedChecker.destinations.isEmpty)

        destination.value = "connected-device"
        #expect(await coordinator.shouldDeferForPersistedAttemptedDeliveryForTesting(
            force: true,
            trigger: .manual
        ))
        coordinator.setSyncingForTesting(false)
        #expect(order.events.isEmpty)

        await attemptedChecker.setResult(.clear)
        coordinator.setSyncingForTesting(true)
        #expect(!(await coordinator.shouldDeferForPersistedAttemptedDeliveryForTesting(
            force: false,
            trigger: .automatic
        )))
        coordinator.setSyncingForTesting(false)

        #expect(await attemptedChecker.destinations == [
            "connected-device",
            "connected-device"
        ])
        #expect(order.events == ["latestSync"])
    }

    @Test("An in-flight sync rechecks durable attempted ACK immediately before DayPack write")
    @MainActor
    func inFlightSyncChecksDurableAttemptedACKBeforeWrite() async {
        let order = TaskActionWireOrder()
        let destination = TaskActionDestinationBox("wire-device")
        let attemptedChecker = TaskActionAttemptedDeliveryChecker(.clear)
        let coordinator = BLESyncCoordinator.makeForTestingTaskActionPresentation(
            appState: AppState.makeForTesting(),
            sendFinalDayPack: { nil },
            runScheduledSync: { force, trigger in
                #expect(force)
                #expect(trigger == .manual)
                order.events.append("latestSync")
            },
            attemptedDeliveryChecker: { destinationID in
                try await attemptedChecker.check(destinationID)
            },
            connectedDestinationProvider: { destination.value }
        )

        coordinator.setSyncingForTesting(true)
        #expect(!(await coordinator.shouldDeferForPersistedAttemptedDeliveryForTesting(
            force: true,
            trigger: .manual
        )))
        await attemptedChecker.setResult(.attempted)

        #expect(await coordinator.shouldDeferRoutineDayPackWriteForTesting(
            force: true,
            trigger: .manual
        ))
        coordinator.setSyncingForTesting(false)
        #expect(order.events.isEmpty)

        await attemptedChecker.setResult(.clear)
        coordinator.setSyncingForTesting(true)
        #expect(!(await coordinator.shouldDeferForPersistedAttemptedDeliveryForTesting(
            force: false,
            trigger: .automatic
        )))
        coordinator.setSyncingForTesting(false)

        #expect(await attemptedChecker.destinations == ["wire-device", "wire-device", "wire-device"])
        #expect(order.events == ["latestSync"])
    }

    @Test("An attempted-delivery lookup error blocks sync until a later check succeeds")
    @MainActor
    func attemptedACKLookupErrorFailsClosed() async {
        let order = TaskActionWireOrder()
        let destination = TaskActionDestinationBox("error-device")
        let attemptedChecker = TaskActionAttemptedDeliveryChecker(.failure)
        let coordinator = BLESyncCoordinator.makeForTestingTaskActionPresentation(
            appState: AppState.makeForTesting(),
            sendFinalDayPack: { nil },
            runScheduledSync: { force, trigger in
                #expect(force)
                #expect(trigger == .manual)
                order.events.append("latestSync")
            },
            attemptedDeliveryChecker: { destinationID in
                try await attemptedChecker.check(destinationID)
            },
            connectedDestinationProvider: { destination.value }
        )

        coordinator.setSyncingForTesting(true)
        #expect(await coordinator.shouldDeferForPersistedAttemptedDeliveryForTesting(
            force: true,
            trigger: .manual
        ))
        coordinator.setSyncingForTesting(false)
        #expect(order.events.isEmpty)

        await attemptedChecker.setResult(.clear)
        coordinator.setSyncingForTesting(true)
        #expect(!(await coordinator.shouldDeferForPersistedAttemptedDeliveryForTesting(
            force: false,
            trigger: .automatic
        )))
        coordinator.setSyncingForTesting(false)

        #expect(await attemptedChecker.destinations == ["error-device", "error-device"])
        #expect(order.events == ["latestSync"])
    }

    @Test("Device A pending ACK does not block routine sync after switching to clear device B")
    @MainActor
    func pendingACKIsScopedToItsDestination() async {
        let order = TaskActionWireOrder()
        let destination = TaskActionDestinationBox("device-a")
        let attemptedChecker = TaskActionAttemptedDeliveryChecker(.attempted)
        let coordinator = BLESyncCoordinator.makeForTestingTaskActionPresentation(
            appState: AppState.makeForTesting(),
            sendFinalDayPack: { nil },
            runScheduledSync: { force, trigger in
                #expect(force)
                #expect(trigger == .manual)
                order.events.append("deviceBSync")
            },
            attemptedDeliveryChecker: { destinationID in
                try await attemptedChecker.check(destinationID)
            },
            connectedDestinationProvider: { destination.value }
        )

        await coordinator.replayAttemptedAcknowledgement(destinationID: "device-a") {
            .failed
        }
        await coordinator.performSync(force: true, trigger: .manual)
        #expect(order.events.isEmpty)

        destination.value = "device-b"
        await attemptedChecker.setResult(.clear)
        coordinator.setSyncingForTesting(true)
        #expect(!(await coordinator.shouldDeferForPersistedAttemptedDeliveryForTesting(
            force: false,
            trigger: .automatic
        )))
        #expect(!(await coordinator.shouldDeferRoutineDayPackWriteForTesting(
            force: false,
            trigger: .automatic
        )))
        coordinator.setSyncingForTesting(false)

        #expect(order.events == ["deviceBSync"])
        #expect(await attemptedChecker.destinations == ["device-a", "device-b", "device-b"])
    }

    @Test("A failed replay releases queued routine sync when the connection changes to B")
    @MainActor
    func failedReplayResumesClearCurrentDestination() async {
        let order = TaskActionWireOrder()
        let destination = TaskActionDestinationBox("device-a")
        let coordinator = BLESyncCoordinator.makeForTestingTaskActionPresentation(
            appState: AppState.makeForTesting(),
            sendFinalDayPack: { nil },
            runScheduledSync: { force, trigger in
                #expect(force)
                #expect(trigger == .manual)
                order.events.append("deviceBSync")
            },
            connectedDestinationProvider: { destination.value }
        )

        await coordinator.replayAttemptedAcknowledgement(destinationID: "device-a") {
            await coordinator.performSync(force: true, trigger: .manual)
            destination.value = "device-b"
            return .failed
        }

        #expect(order.events == ["deviceBSync"])
    }

    @Test("Device B durable attempted ACK still blocks B after switching away from A")
    @MainActor
    func switchedDestinationStillHonorsItsOwnAttemptedACK() async {
        let order = TaskActionWireOrder()
        let destination = TaskActionDestinationBox("device-a")
        let attemptedChecker = TaskActionAttemptedDeliveryChecker(.attempted)
        let coordinator = BLESyncCoordinator.makeForTestingTaskActionPresentation(
            appState: AppState.makeForTesting(),
            sendFinalDayPack: { nil },
            runScheduledSync: { _, _ in order.events.append("unexpectedSync") },
            attemptedDeliveryChecker: { destinationID in
                try await attemptedChecker.check(destinationID)
            },
            connectedDestinationProvider: { destination.value }
        )

        await coordinator.replayAttemptedAcknowledgement(destinationID: "device-a") {
            .failed
        }
        destination.value = "device-b"
        coordinator.setSyncingForTesting(true)

        #expect(await coordinator.shouldDeferForPersistedAttemptedDeliveryForTesting(
            force: true,
            trigger: .manual
        ))
        coordinator.setSyncingForTesting(false)

        #expect(order.events.isEmpty)
        #expect(await attemptedChecker.destinations == ["device-b"])
    }

    @Test("A late sent result for device A cannot clear device B pending ACK")
    @MainActor
    func lateSentResultOnlyClearsItsOwnDestination() async {
        let order = TaskActionWireOrder()
        let destination = TaskActionDestinationBox("device-a")
        let attemptedChecker = TaskActionAttemptedDeliveryChecker(.clear)
        let coordinator = BLESyncCoordinator.makeForTestingTaskActionPresentation(
            appState: AppState.makeForTesting(),
            sendFinalDayPack: { nil },
            runScheduledSync: { _, _ in order.events.append("unexpectedSync") },
            attemptedDeliveryChecker: { destinationID in
                try await attemptedChecker.check(destinationID)
            },
            connectedDestinationProvider: { destination.value }
        )

        await coordinator.replayAttemptedAcknowledgement(destinationID: "device-a") {
            .failed
        }
        destination.value = "device-b"
        await coordinator.replayAttemptedAcknowledgement(destinationID: "device-b") {
            .failed
        }

        coordinator.setSyncingForTesting(true)
        #expect(await coordinator.shouldDeferRoutineDayPackWriteForTesting(
            force: true,
            trigger: .manual
        ))
        coordinator.setSyncingForTesting(false)

        await coordinator.replayAttemptedAcknowledgement(destinationID: "device-a") {
            .sent
        }

        #expect(order.events.isEmpty)
        #expect(await attemptedChecker.destinations.isEmpty)
    }

    @Test("An in-flight ordinary sync yields its prepared DayPack to a queued ACK retry")
    @MainActor
    func inFlightSyncRechecksBeforeWritingPreparedDayPack() async {
        let order = TaskActionWireOrder()
        let syncPreparation = TaskActionReplayBarrier()
        let hardwareGate = HardwarePagePresentationGate()
        let coordinator = BLESyncCoordinator.makeForTestingTaskActionPresentation(
            appState: AppState.makeForTesting(),
            sendFinalDayPack: {
                Issue.record("Attempted acknowledgement replay must not generate a new DayPack")
                return nil
            },
            runScheduledSync: { force, trigger in
                #expect(force)
                #expect(trigger == .manual)
                order.events.append("latestSync")
            },
            hardwarePagePresentationGate: hardwareGate
        )

        // Model performSync after it has set isSyncing and acquired the presentation gate, but
        // while an awaited preparation step still separates it from the actual DayPack write.
        coordinator.setSyncingForTesting(true)
        let inFlightSync = Task { @MainActor in
            _ = try? await hardwareGate.performPresentationWrite(
                droppingIfPageTransactionIntervened: false
            ) {
                order.events.append("syncPrepared")
                await syncPreparation.waitForRelease()
                if !(await coordinator.shouldDeferRoutineDayPackWriteForTesting(
                    force: true,
                    trigger: .manual
                )) {
                    order.events.append("newDayPack")
                }
            }
        }
        await syncPreparation.waitUntilStarted()

        let retry = Task { @MainActor in
            await hardwareGate.performPageTransaction {
                await coordinator.replayAttemptedAcknowledgement(destinationID: "device-a") {
                    order.events.append("acknowledgement")
                    order.events.append("cleanup")
                    return .sent
                }
            }
        }
        for _ in 0..<100 where !hardwareGate.hasPageTransactionDemand {
            await Task.yield()
        }
        #expect(hardwareGate.hasPageTransactionDemand)

        await syncPreparation.release()
        await inFlightSync.value
        await retry.value
        coordinator.setSyncingForTesting(false)

        #expect(order.events == [
            "syncPrepared",
            "acknowledgement",
            "cleanup",
            "latestSync"
        ])
    }

    @Test("A failed final DayPack never releases the TaskIn acknowledgement")
    @MainActor
    func failedDayPackDoesNotAcknowledge() async {
        var acknowledgementCount = 0

        let completed = await BLESyncCoordinator.completeTaskActionPresentation(
            sendFinalDayPack: { nil },
            acknowledge: { _ in
                acknowledgementCount += 1
                return .sent
            }
        )

        #expect(!completed)
        #expect(acknowledgementCount == 0)
    }

    @Test("A stale acknowledgement regenerates DayPack for the newer task version")
    @MainActor
    func staleAcknowledgementRegeneratesDayPack() async {
        var versions: [UInt64] = [7, 8]
        var acknowledgedVersions: [UInt64] = []

        let completed = await BLESyncCoordinator.completeTaskActionPresentation(
            sendFinalDayPack: { versions.isEmpty ? nil : versions.removeFirst() },
            acknowledge: { version in
                acknowledgedVersions.append(version)
                return version == 7 ? .staleTaskState : .sent
            }
        )

        #expect(completed)
        #expect(acknowledgedVersions == [7, 8])
        #expect(versions.isEmpty)
    }
}

@MainActor
private final class TaskActionWireOrder {
    var events: [String] = []
}

@MainActor
private final class TaskActionPresentationCoordinatorSpy: TaskActionPresentationCoordinating {
    private let order: TaskActionWireOrder
    private(set) var callCount = 0
    private(set) var replayCallCount = 0
    private(set) var sendDestinationIDs: [String] = []
    private(set) var replayDestinationIDs: [String] = []
    var beforeSend: (() -> Void)?
    var beforeReplay: (() -> Void)?

    init(order: TaskActionWireOrder) {
        self.order = order
    }

    func sendFinalDayPackBeforeAcknowledgement(
        _ acknowledgement: @MainActor @Sendable (
            _ expectedTaskStateVersion: UInt64
        ) async -> TaskListSnapshotResponder.Outcome
    ) async {
        callCount += 1
        order.events.append("dayPack")
        _ = await acknowledgement(0)
    }

    func sendFinalDayPackBeforeAcknowledgement(
        destinationID: String,
        _ acknowledgement: @MainActor @Sendable (
            _ expectedTaskStateVersion: UInt64
        ) async -> TaskListSnapshotResponder.Outcome
    ) async {
        guard !destinationID.isEmpty else { return }
        sendDestinationIDs.append(destinationID)
        beforeSend?()
        await sendFinalDayPackBeforeAcknowledgement(acknowledgement)
    }

    func replayAttemptedAcknowledgement(
        _ acknowledgement: @MainActor @Sendable () async -> TaskListSnapshotResponder.Outcome
    ) async {
        replayCallCount += 1
        _ = await acknowledgement()
    }

    func replayAttemptedAcknowledgement(
        destinationID: String,
        _ acknowledgement: @MainActor @Sendable () async -> TaskListSnapshotResponder.Outcome
    ) async {
        beforeReplay?()
        replayDestinationIDs.append(destinationID)
        await replayAttemptedAcknowledgement(acknowledgement)
    }
}

@MainActor
private final class TaskActionSnapshotSenderSpy: TaskListSnapshotSending {
    let hardwareScreenSize: ScreenSize = .fourInch
    var taskListSnapshotDestinationID: String
    private let order: TaskActionWireOrder

    init(order: TaskActionWireOrder, destinationID: String = "single-active-device") {
        self.order = order
        taskListSnapshotDestinationID = destinationID
    }

    func withTaskStateMessageGate(
        _ operation: @MainActor () async throws -> Void
    ) async throws {
        try await operation()
    }

    func writeTaskListSnapshotAckPayload(
        _ payload: Data,
        expectedTaskStateVersion: UInt64?
    ) async throws {
        order.events.append("acknowledgement")
    }
}

private actor TaskActionSnapshotVersionProvider: TaskListSnapshotVersionProviding {
    func nextTaskListSnapshotVersion() async throws -> TaskListSnapshotVersion {
        TaskListSnapshotVersion(epoch: 1, revision: 1)
    }
}

private actor TaskActionReplayBarrier {
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var isStarted = false
    private var isReleased = false

    func waitForRelease() async {
        isStarted = true
        startedContinuation?.resume()
        startedContinuation = nil
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard !isStarted else { return }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func release() {
        isReleased = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@MainActor
private final class TaskActionDestinationBox {
    var value: String?

    init(_ value: String?) {
        self.value = value
    }
}

private enum TaskActionAttemptedDeliveryResult: Sendable {
    case clear
    case attempted
    case failure
}

private enum TaskActionAttemptedDeliveryError: Error {
    case unavailable
}

private actor TaskActionAttemptedDeliveryChecker {
    private var result: TaskActionAttemptedDeliveryResult
    private(set) var destinations: [String] = []

    init(_ result: TaskActionAttemptedDeliveryResult) {
        self.result = result
    }

    func setResult(_ result: TaskActionAttemptedDeliveryResult) {
        self.result = result
    }

    func check(_ destinationID: String) throws -> Bool {
        destinations.append(destinationID)
        switch result {
        case .clear:
            return false
        case .attempted:
            return true
        case .failure:
            throw TaskActionAttemptedDeliveryError.unavailable
        }
    }
}
