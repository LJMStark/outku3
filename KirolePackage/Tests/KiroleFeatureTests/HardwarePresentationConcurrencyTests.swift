import Foundation
import Testing
@testable import KiroleFeature

@Suite("Hardware presentation concurrency", .serialized)
struct HardwarePresentationConcurrencyTests {
    @Test(
        "Complete and Skip finish while full sync is still preparing",
        arguments: [TaskListSnapshotAction.completeTask, .skipTask]
    )
    @MainActor
    func taskActionPreemptsSlowFullSyncPreparation(
        action: TaskListSnapshotAction
    ) async throws {
        let fixtures = ProtocolFixtures()
        let box = PresentationFirmwareBox()
        box.firmware.beginEnterTaskIn(taskID: fixtures.taskId)
        try box.firmware.receive(stream: BLEPacketizer.packetize(
            type: BLEDataType.dayPack.rawValue,
            messageId: 0x6501,
            payload: BLEDataEncoder.encodeDayPack(fixtures.dayPack, screenSize: .fourInch),
            maxChunkSize: 18
        ))
        try box.firmware.beginTaskAction(action: action, operationID: 73)
        box.firmware.clearWireLog()
        let refreshBaseline = box.firmware.refreshCount
        let appState = AppState.makeForTesting()
        let coordinator = BLESyncCoordinator.makeForTestingTaskActionPresentation(
            appState: appState,
            sendFinalDayPack: {
                do {
                    try box.firmware.receive(stream: BLEPacketizer.packetize(
                        type: BLEDataType.dayPack.rawValue,
                        messageId: 0x6502,
                        payload: BLEDataEncoder.encodeDayPack(
                            finalDayPack(),
                            screenSize: .fourInch
                        ),
                        maxChunkSize: 24
                    ))
                    return 0
                } catch {
                    box.error = error
                    return nil
                }
            }
        )
        // This is the production in-flight flag. The task action must not wait for it to clear;
        // otherwise an active sync waiting for the page gate and the action waiting for the sync
        // reproduce the reverse-lock deadlock.
        coordinator.setSyncingForTesting(true)
        let completion = TaskActionCompletionFlag()
        let taskAction = Task { @MainActor in
            await coordinator.sendFinalDayPackBeforeAcknowledgement { _ in
                do {
                    try box.firmware.receive(BLESimpleEncoder.encode(
                        type: BLEDataType.taskListSnapshotAck.rawValue,
                        payload: BLEDataEncoder.encodeTaskListSnapshotAck(TaskListSnapshotAck(
                            action: action,
                            operationID: 73,
                            result: .applied,
                            version: TaskListSnapshotVersion(epoch: 1, revision: 1),
                            tasks: []
                        ))
                    ))
                    return .sent
                } catch {
                    box.error = error
                    return .failed
                }
            }
            await completion.finish()
        }
        for _ in 0..<100 where !(await completion.isFinished) {
            await Task.yield()
        }
        let finishedBeforeSyncEnded = await completion.isFinished
        coordinator.setSyncingForTesting(false)
        await taskAction.value

        #expect(finishedBeforeSyncEnded)
        try #require(box.error == nil)
        #expect(box.firmware.logicalWireTypes == [.dayPack, .taskListSnapshotAck])
        #expect(box.firmware.page == .overview)
        #expect(box.firmware.refreshCount - refreshBaseline == 1)
    }

    private func finalDayPack() -> DayPack {
        DayPack(
            date: Date(),
            deviceMode: .interactive,
            focusChallengeEnabled: true,
            petDialogue: "Done together.",
            daySummary: "Updated overview",
            firstUp: "Nothing urgent",
            settlementReview: "Final settlement",
            settlementQuote: "One thing finished well.",
            events: [],
            topTasks: [],
            settlementData: SettlementData(
                tasksCompleted: 1,
                tasksTotal: 1,
                pointsEarned: 1,
                petMood: "happy",
                summaryMessage: "",
                encouragementMessage: "",
                totalFocusMinutes: 1,
                focusSessionCount: 1,
                longestFocusMinutes: 1,
                interruptionCount: 0,
                totalEnergyBottles: 0
            )
        )
    }
}

private actor TaskActionCompletionFlag {
    private(set) var isFinished = false

    func finish() {
        isFinished = true
    }
}
