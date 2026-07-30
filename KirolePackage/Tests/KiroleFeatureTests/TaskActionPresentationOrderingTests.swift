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
            tasksProvider: { [] },
            taskStateVersionProvider: { 0 }
        )

        #expect(order.events == ["dayPack", "acknowledgement"])
        #expect(presentation.callCount == 1)
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
            tasksProvider: { [] },
            taskStateVersionProvider: { 0 }
        )

        #expect(order.events == ["acknowledgement"])
        #expect(presentation.callCount == 0)
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
}

@MainActor
private final class TaskActionSnapshotSenderSpy: TaskListSnapshotSending {
    let hardwareScreenSize: ScreenSize = .fourInch
    private let order: TaskActionWireOrder

    init(order: TaskActionWireOrder) {
        self.order = order
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
