import Foundation
import Testing
@testable import KiroleFeature

@Suite("BLE DayPack task version", .serialized)
struct BLEDayPackTaskVersionTests {
    @Test("DayPack is rejected before transmission when its task version is stale")
    @MainActor
    func staleTaskVersionIsRejectedBeforeTransmission() async {
        await SharedPersistenceTestLock.shared.withLock {
            let state = AppState.shared
            await state.ensureInitialLoadComplete()
            let originalTasks = state.tasks
            defer { state.tasks = originalTasks }

            let sourceVersion = state.taskStateVersion
            state.tasks = originalTasks + [
                TaskItem(
                    id: "task-version-test-\(UUID().uuidString)",
                    title: "Newer task state",
                    dueDate: Date()
                )
            ]
            #expect(state.taskStateVersion != sourceVersion)

            let stalePack = DayPack(
                petDialogue: "Dialogue generated for the previous task version.",
                settlementData: SettlementData(
                    tasksCompleted: 0,
                    tasksTotal: 0,
                    pointsEarned: 0,
                    petMood: "happy",
                    summaryMessage: "",
                    encouragementMessage: ""
                )
            )

            do {
                try await BLEService.shared.sendDayPack(
                    stalePack,
                    expectedTaskStateVersion: sourceVersion
                )
                Issue.record("A stale DayPack reached the BLE write path")
            } catch let error as BLEError {
                guard case .staleTaskSnapshot = error else {
                    Issue.record("Expected staleTaskSnapshot, got \(error)")
                    return
                }
            } catch {
                Issue.record("Expected BLEError.staleTaskSnapshot, got \(error)")
            }
        }
    }
}
