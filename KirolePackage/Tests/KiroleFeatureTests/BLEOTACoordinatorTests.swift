import Testing
import Foundation
@testable import KiroleFeature

// .serialized：下方防卡死回归用例断言共享的 BLEService.shared.isPendingOTAReboot，
// 并行执行时其他用例的置位/清零会在 await 悬挂点插进来造成 flake。
@MainActor
@Suite("BLEOTACoordinator state machine", .serialized)
struct BLEOTACoordinatorTests {

    @Test("Initial state is idle")
    func initialStateIsIdle() async {
        let c = BLEOTACoordinator.makeForTesting()
        #expect(c.state == .idle)
    }

    @Test("0x00 response transitions to awaitingReboot")
    func successResponseEntersAwaitingReboot() async {
        let c = BLEOTACoordinator.makeForTesting()
        await c.requestReboot()
        c.handleOTAResult(statusCode: 0x00)
        #expect(c.state == .awaitingReboot)
    }

    @Test("Non-zero response transitions to failed(deviceRejected)")
    func errorResponseFails() async {
        let c = BLEOTACoordinator.makeForTesting()
        await c.requestReboot()
        c.handleOTAResult(statusCode: 0x01)
        #expect(c.state == .failed(.deviceRejected(0x01)))
    }

    @Test("Disconnect during sending transitions to awaitingReboot")
    func disconnectDuringSendingEntersAwaitingReboot() async {
        let c = BLEOTACoordinator.makeForTesting()
        await c.requestReboot()
        c.handleExpectedDisconnect()
        #expect(c.state == .awaitingReboot)
    }

    @Test("DeviceWake during awaitingReboot returns to idle")
    func deviceWakeCompletesUpgrade() async {
        let c = BLEOTACoordinator.makeForTesting()
        await c.requestReboot()
        c.handleOTAResult(statusCode: 0x00)
        c.handleDeviceWake()
        #expect(c.state == .idle)
    }

    @Test("reset() returns to idle from awaitingReboot")
    func resetFromAwaitingReboot() async {
        let c = BLEOTACoordinator.makeForTesting()
        await c.requestReboot()
        c.handleOTAResult(statusCode: 0x00)
        c.reset()
        #expect(c.state == .idle)
    }

    @Test("handleDeviceWake is no-op when state is idle")
    func deviceWakeIgnoredWhenIdle() async {
        let c = BLEOTACoordinator.makeForTesting()
        c.handleDeviceWake()
        #expect(c.state == .idle)
    }

    @Test("handleOTAResult is no-op when state is idle")
    func otaResultIgnoredWhenIdle() async {
        let c = BLEOTACoordinator.makeForTesting()
        c.handleOTAResult(statusCode: 0x00)
        #expect(c.state == .idle)
    }

    // MARK: - Upgrade outcome via firmware version (v2.5.19)

    @Test("Version changed after reboot → confirmed outcome with from/to")
    func upgradeOutcomeConfirmed() async {
        let c = BLEOTACoordinator.makeForTesting()
        // Baseline wake while idle records the pre-upgrade version.
        c.handleDeviceWake(reportedVersion: FirmwareVersion(major: 1, minor: 2, patch: 3))
        await c.requestReboot()
        c.handleOTAResult(statusCode: 0x00)
        c.handleDeviceWake(reportedVersion: FirmwareVersion(major: 1, minor: 2, patch: 4))
        #expect(c.state == .idle)
        #expect(c.lastOutcome == .confirmed(
            from: FirmwareVersion(major: 1, minor: 2, patch: 3),
            to: FirmwareVersion(major: 1, minor: 2, patch: 4)
        ))
    }

    @Test("Same version after reboot → sameVersion outcome (possible rollback)")
    func upgradeOutcomeSameVersion() async {
        let c = BLEOTACoordinator.makeForTesting()
        let v = FirmwareVersion(major: 1, minor: 2, patch: 3)
        c.handleDeviceWake(reportedVersion: v)
        await c.requestReboot()
        c.handleOTAResult(statusCode: 0x00)
        c.handleDeviceWake(reportedVersion: v)
        #expect(c.state == .idle)
        #expect(c.lastOutcome == .sameVersion(v))
    }

    @Test("No version reported after reboot → versionUnknown outcome")
    func upgradeOutcomeVersionUnknown() async {
        let c = BLEOTACoordinator.makeForTesting()
        await c.requestReboot()
        c.handleOTAResult(statusCode: 0x00)
        c.handleDeviceWake()
        #expect(c.state == .idle)
        #expect(c.lastOutcome == .versionUnknown)
    }

    @Test("Version reported but no baseline → confirmed(from: nil)")
    func upgradeOutcomeNoBaseline() async {
        let c = BLEOTACoordinator.makeForTesting()
        await c.requestReboot()
        c.handleOTAResult(statusCode: 0x00)
        let v = FirmwareVersion(major: 2, minor: 0, patch: 0)
        c.handleDeviceWake(reportedVersion: v)
        #expect(c.lastOutcome == .confirmed(from: nil, to: v))
    }

    @Test("requestReboot clears previous outcome")
    func requestRebootClearsOutcome() async {
        let c = BLEOTACoordinator.makeForTesting()
        await c.requestReboot()
        c.handleOTAResult(statusCode: 0x00)
        c.handleDeviceWake(reportedVersion: FirmwareVersion(major: 2, minor: 0, patch: 0))
        #expect(c.lastOutcome != nil)
        await c.requestReboot()
        #expect(c.lastOutcome == nil)
    }

    // MARK: - Stuck-sending regressions（2026-07-12：应答前断连 / 离线点击卡死修复）

    @Test("sending arms isPendingOTAReboot so a pre-response disconnect reaches the coordinator")
    func sendingArmsPendingOTARebootFlag() async {
        let c = BLEOTACoordinator.makeForTesting()
        await c.requestReboot()
        #expect(c.state == .sending)
        // 生产断连路由的门闩：didDisconnectPeripheral 只在该标志为 true 时才通知
        // 协调器。此前它到 awaitingReboot 才置位，sending 期间断连永远进不来。
        #expect(BLEService.shared.isPendingOTAReboot == true)
        c.reset()
        #expect(BLEService.shared.isPendingOTAReboot == false)
    }

    @Test("Response timeout while disconnected fails instead of hanging in sending")
    func responseTimeoutWhileDisconnectedFails() async {
        let c = BLEOTACoordinator.makeForTesting()
        await c.requestReboot()
        #expect(c.state == .sending)
        // 测试环境没有 BLE 连接（写入失败被吞）：超时兜底必须给 sending 一个出口。
        await c.handleResponseTimeout()
        #expect(c.state == .failed(.noResponse))
        #expect(BLEService.shared.isPendingOTAReboot == false)
    }

    @Test("Response timeout is a no-op outside sending")
    func responseTimeoutIgnoredOutsideSending() async {
        let c = BLEOTACoordinator.makeForTesting()
        await c.requestReboot()
        c.handleOTAResult(statusCode: 0x00)
        #expect(c.state == .awaitingReboot)
        await c.handleResponseTimeout()
        #expect(c.state == .awaitingReboot)
        c.reset()
    }
}
