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
}
