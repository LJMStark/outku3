import Foundation
import Testing
@testable import KiroleFeature

@MainActor
private final class DisconnectContinuityFocusGuardService: FocusGuardService {
    var authorizationStatus: FocusAuthorizationStatus = .approved
    var isDeepFocusFeatureEnabled = true
    var isDeepFocusCapable = true
    var canShowDeepFocusEntry = true
    var selectedApplicationCount = 0
    var isPickerPresented = false

    func refreshAuthorizationStatus() async {}
    func requestAuthorization() async -> FocusAuthorizationStatus { authorizationStatus }
    func presentAppPicker() {}
    func applyShield(selection: FocusAppSelection) throws {}
    func clearShield() {}
    func currentSelection() -> FocusAppSelection? { nil }
}

// Issue #23：BLE 只是屏幕传输通道，断连不是专注结束事件。
// 使用真单例覆盖 BLEService.disconnect() 的主动断连入口；共享锁避免
// 其他套件在 await 点改动 FocusSessionService.shared。
@Suite("BLEService Manual Disconnect", .serialized)
struct BLEServiceManualDisconnectTests {
    @Test("Manual disconnect preserves the active focus session and creates no disconnected history")
    @MainActor
    func manualDisconnectPreservesActiveFocusSession() async {
        await SharedPersistenceTestLock.shared.withLock {
            let focusService = FocusSessionService.shared
            let taskId = "manual-disconnect-\(UUID().uuidString)"
            if focusService.activeSession != nil {
                focusService.endSession(reason: .completed)
                await focusService.waitForPendingPersistenceForTesting()
            }

            await focusService.startSession(taskId: taskId, taskTitle: "Manual Disconnect Task")
            let sessionID = focusService.activeSession?.id

            BLEService.shared.disconnect()
            await focusService.waitForPendingPersistenceForTesting()

            #expect(focusService.activeSession?.id == sessionID)
            #expect(!focusService.todaySessions.contains {
                $0.taskId == taskId && $0.endReason == .disconnected
            })

            focusService.endSession(reason: .completed)
            await focusService.waitForPendingPersistenceForTesting()
        }
    }

    @Test("Manual disconnect without an active session is a no-op for focus state")
    @MainActor
    func manualDisconnectWithoutSessionIsNoOp() async {
        await SharedPersistenceTestLock.shared.withLock {
            let focusService = FocusSessionService.shared
            if focusService.activeSession != nil {
                focusService.endSession(reason: .completed)
                await focusService.waitForPendingPersistenceForTesting()
            }
            let baseline = focusService.todaySessions.count

            BLEService.shared.disconnect()

            #expect(focusService.activeSession == nil)
            #expect(focusService.todaySessions.count == baseline)
        }
    }

    @Test("Passive disconnect and repeated reconnect event preserve session identity and progress")
    @MainActor
    func passiveDisconnectAndReconnectPreserveSession() async throws {
        let service = FocusSessionService.makeForTesting(
            focusGuardService: DisconnectContinuityFocusGuardService(),
            persistenceEnabled: false
        )
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        await service.startSession(
            taskId: "passive-disconnect",
            taskTitle: "Continuous Focus",
            startTime: start
        )
        let original = try #require(service.activeSession)
        #expect(service.progressSnapshot(now: start.addingTimeInterval(10)).elapsedSeconds == 10)

        service.handleDeviceDisconnected()

        #expect(service.activeSession?.id == original.id)
        #expect(service.todaySessions.isEmpty)
        #expect(service.progressSnapshot(now: start.addingTimeInterval(70)).elapsedSeconds == 70)

        let reconnectResult = await service.startSession(
            taskId: original.taskId,
            taskTitle: original.taskTitle,
            startTime: start.addingTimeInterval(70)
        )
        guard case .alreadyActive(let reconnected) = reconnectResult else {
            Issue.record("Expected reconnect delivery to reuse the active focus session")
            return
        }
        #expect(reconnected.id == original.id)
        #expect(reconnected.startTime == start)
        #expect(service.activeSession?.id == original.id)
        #expect(service.todaySessions.isEmpty)
        #expect(service.progressSnapshot(now: start.addingTimeInterval(120)).elapsedSeconds == 120)
    }

    @Test("Disconnected end reason remains decodable for historical sessions")
    func disconnectedEndReasonRemainsCodable() throws {
        let encoded = try JSONEncoder().encode(FocusEndReason.disconnected)
        let decoded = try JSONDecoder().decode(FocusEndReason.self, from: encoded)

        #expect(decoded == .disconnected)
    }
}
