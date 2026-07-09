import Testing
import Foundation
@testable import KiroleFeature

@MainActor
@Suite("BLEOTACoordinator state machine")
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
}
