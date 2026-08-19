import Foundation
import Testing
@testable import KiroleFeature

// v2.13: 断连不再结束专注。disconnect() 仍调用 handleDeviceDisconnected，但该方法是空操作。
@Suite("BLEService Manual Disconnect", .serialized)
struct BLEServiceManualDisconnectTests {
    @Test("Manual disconnect keeps the active focus session and shield")
    @MainActor
    func manualDisconnectKeepsActiveFocusSession() async {
        await SharedPersistenceTestLock.shared.withLock {
            let focusService = FocusSessionService.shared
            let taskId = "manual-disconnect-\(UUID().uuidString)"

            await focusService.startSession(taskId: taskId, taskTitle: "Manual Disconnect Task")
            #expect(focusService.activeSession != nil)

            BLEService.shared.disconnect()

            #expect(focusService.activeSession?.taskId == taskId)
            #expect(focusService.todaySessions.contains { $0.taskId == taskId && $0.endReason == .disconnected } == false)
            focusService.endSession(reason: .completed)
        }
    }

    @Test("Manual disconnect without an active session is a no-op for focus state")
    @MainActor
    func manualDisconnectWithoutSessionIsNoOp() async {
        await SharedPersistenceTestLock.shared.withLock {
            let focusService = FocusSessionService.shared
            if focusService.activeSession != nil {
                focusService.endSession(reason: .completed)
            }
            let baseline = focusService.todaySessions.count

            BLEService.shared.disconnect()

            #expect(focusService.activeSession == nil)
            #expect(focusService.todaySessions.count == baseline)
        }
    }
}
