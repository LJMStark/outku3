import Foundation
import Testing
@testable import KiroleFeature

// 联审 2026-07-16 F7 回归防线：主动断开（Settings 断连按钮 / clearTrustedDevices / 同步超时）
// 走 BLEService.disconnect() → cleanup() 先清空 connectedPeripheral，随后到达的合法
// didDisconnect 被 shouldProcessCallback 身份门拒绝——回调内的 handleDeviceDisconnected
// 不会执行。因此 disconnect() 必须在意图点直接结束活跃专注会话，本测试钉住这条接线。
// 使用真单例（先例：ResilienceAndIsolationTests.FocusSessionPersistenceTests），.serialized
// 防止套件内并行在 await 点互踩共享单例状态。
@Suite("BLEService Manual Disconnect", .serialized)
struct BLEServiceManualDisconnectTests {
    @Test("Manual disconnect ends the active focus session at the intent point")
    @MainActor
    func manualDisconnectEndsActiveFocusSession() async {
        let focusService = FocusSessionService.shared
        let baseline = focusService.todaySessions.count

        await focusService.startSession(
            taskId: "manual-disconnect-\(UUID().uuidString)",
            taskTitle: "Manual Disconnect Task"
        )
        #expect(focusService.activeSession != nil)

        BLEService.shared.disconnect()

        #expect(focusService.activeSession == nil)
        #expect(focusService.todaySessions.count >= baseline + 1)
        #expect(focusService.todaySessions.last?.endReason == .disconnected)
    }

    @Test("Manual disconnect without an active session is a no-op for focus state")
    @MainActor
    func manualDisconnectWithoutSessionIsNoOp() async {
        let focusService = FocusSessionService.shared
        #expect(focusService.activeSession == nil)
        let baseline = focusService.todaySessions.count

        BLEService.shared.disconnect()

        #expect(focusService.activeSession == nil)
        #expect(focusService.todaySessions.count == baseline)
    }
}
