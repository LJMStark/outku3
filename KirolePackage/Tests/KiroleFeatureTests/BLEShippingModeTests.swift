import Foundation
import Testing
@testable import KiroleFeature
@testable import KiroleInternalBLE

@MainActor
@Suite("BLE Shipping Mode", .serialized)
struct BLEShippingModeTests {
    @Test("Shipping mode uses the documented 0x1C frame")
    func commandWireFormat() {
        #expect(BLEDataType.shippingMode.rawValue == 0x1C)
        #expect(BLEShippingModeCommand.enable.payload == Data([0x01]))
        #expect(BLESimpleEncoder.encode(
            type: BLEDataType.shippingMode.rawValue,
            payload: BLEShippingModeCommand.enable.payload
        ) == Data([0x1C, 0x00, 0x01, 0x01]))
    }

    @Test("A disconnect after sending is the only success signal")
    func disconnectConfirmsActivation() async {
        var sendCount = 0
        var pendingValues: [Bool] = []
        let coordinator = BLEShippingModeCoordinator.makeForTesting(
            disconnectTimeout: .seconds(1),
            setPendingDisconnect: { pendingValues.append($0) },
            sendCommand: { armExpectedDisconnect in
                sendCount += 1
                armExpectedDisconnect()
            }
        )

        await coordinator.enable()

        #expect(sendCount == 1)
        #expect(coordinator.state == .awaitingDisconnect)
        #expect(coordinator.blocksAutomaticBLEWork)
        #expect(pendingValues == [true])

        coordinator.handleExpectedDisconnect()

        #expect(coordinator.state == .activated)
        #expect(coordinator.blocksAutomaticBLEWork)
        #expect(pendingValues == [true, false])

        coordinator.handleDeviceReconnected()
        #expect(coordinator.state == .idle)
        #expect(!coordinator.blocksAutomaticBLEWork)
    }

    @Test("An App-initiated disconnect never claims activation")
    func intentionalDisconnectIsUnconfirmed() async {
        var pendingValues: [Bool] = []
        let coordinator = BLEShippingModeCoordinator.makeForTesting(
            disconnectTimeout: .seconds(1),
            setPendingDisconnect: { pendingValues.append($0) },
            sendCommand: { armExpectedDisconnect in armExpectedDisconnect() }
        )

        await coordinator.enable()
        coordinator.handleUnconfirmedDisconnect()

        #expect(coordinator.state == .failed(.activationUnconfirmed))
        #expect(!coordinator.blocksAutomaticBLEWork)
        #expect(pendingValues == [true, false])
    }

    @Test("A BLE write failure does not claim shipping mode is active")
    func writeFailureIsVisible() async {
        var pendingValues: [Bool] = []
        let coordinator = BLEShippingModeCoordinator.makeForTesting(
            disconnectTimeout: .seconds(1),
            setPendingDisconnect: { pendingValues.append($0) },
            sendCommand: { _ in throw TestFailure.expected }
        )

        await coordinator.enable()

        #expect(coordinator.state == .failed(.sendFailed))
        #expect(pendingValues.isEmpty)
    }

    @Test("A write error after the CoreBluetooth boundary still accepts a late device disconnect")
    func armedWriteFailureWaitsForDisconnect() async {
        var pendingValues: [Bool] = []
        let coordinator = BLEShippingModeCoordinator.makeForTesting(
            disconnectTimeout: .seconds(1),
            setPendingDisconnect: { pendingValues.append($0) },
            sendCommand: { armExpectedDisconnect in
                armExpectedDisconnect()
                throw TestFailure.expected
            }
        )

        await coordinator.enable()

        #expect(coordinator.state == .awaitingDisconnect)
        #expect(coordinator.blocksAutomaticBLEWork)
        #expect(coordinator.requiresCurrentConnection)
        #expect(pendingValues == [true])

        coordinator.handleExpectedDisconnect()

        #expect(coordinator.state == .activated)
        #expect(pendingValues == [true, false])
    }

    @Test("A send that never reaches CoreBluetooth cannot arm disconnect success")
    func missingWriteBoundaryFailsWithoutArming() async {
        var pendingValues: [Bool] = []
        let coordinator = BLEShippingModeCoordinator.makeForTesting(
            disconnectTimeout: .seconds(1),
            setPendingDisconnect: { pendingValues.append($0) },
            sendCommand: { _ in }
        )

        await coordinator.enable()

        #expect(coordinator.state == .failed(.sendFailed))
        #expect(pendingValues.isEmpty)
    }

    @Test("OTA in progress blocks shipping mode before it sends")
    func otaBlocksShippingMode() async {
        var sendCount = 0
        var pendingValues: [Bool] = []
        let coordinator = BLEShippingModeCoordinator.makeForTesting(
            disconnectTimeout: .seconds(1),
            canStart: { false },
            setPendingDisconnect: { pendingValues.append($0) },
            sendCommand: { _ in sendCount += 1 }
        )

        await coordinator.enable()

        #expect(coordinator.state == .failed(.conflictingDeviceOperation))
        #expect(sendCount == 0)
        #expect(pendingValues.isEmpty)
    }

    @Test("A late disconnect after timeout still suppresses reconnect and confirms activation")
    func lateDisconnectAfterTimeoutConfirmsActivation() async throws {
        var pendingValues: [Bool] = []
        let coordinator = BLEShippingModeCoordinator.makeForTesting(
            disconnectTimeout: .milliseconds(20),
            setPendingDisconnect: { pendingValues.append($0) },
            sendCommand: { armExpectedDisconnect in armExpectedDisconnect() }
        )

        await coordinator.enable()
        try await waitForState(.failed(.didNotDisconnect), from: coordinator)

        #expect(coordinator.blocksAutomaticBLEWork)
        #expect(coordinator.requiresCurrentConnection)
        #expect(pendingValues == [true])

        coordinator.handleExpectedDisconnect()

        #expect(coordinator.state == .activated)
        #expect(pendingValues == [true, false])
    }

    @Test("A manual retry after timeout replaces the old disconnect route")
    func retryAfterTimeoutRearmsDisconnect() async throws {
        var pendingValues: [Bool] = []
        let coordinator = BLEShippingModeCoordinator.makeForTesting(
            disconnectTimeout: .milliseconds(20),
            setPendingDisconnect: { pendingValues.append($0) },
            sendCommand: { armExpectedDisconnect in armExpectedDisconnect() }
        )

        await coordinator.enable()
        try await waitForState(.failed(.didNotDisconnect), from: coordinator)
        await coordinator.enable()

        #expect(coordinator.state == .awaitingDisconnect)
        #expect(pendingValues == [true, false, true])
    }

    @Test("The late-disconnect grace eventually releases ordinary BLE work")
    func lateDisconnectGraceExpires() async throws {
        var pendingValues: [Bool] = []
        let coordinator = BLEShippingModeCoordinator.makeForTesting(
            disconnectTimeout: .milliseconds(20),
            lateDisconnectGrace: .milliseconds(20),
            setPendingDisconnect: { pendingValues.append($0) },
            sendCommand: { armExpectedDisconnect in armExpectedDisconnect() }
        )

        await coordinator.enable()
        try await waitForAutomaticBLEWorkToResume(from: coordinator)

        #expect(coordinator.state == .failed(.didNotDisconnect))
        #expect(!coordinator.blocksAutomaticBLEWork)
        #expect(!coordinator.requiresCurrentConnection)
        #expect(pendingValues == [true, false])

        coordinator.handleExpectedDisconnect()
        #expect(coordinator.state == .failed(.didNotDisconnect))
    }

    private func waitForState(
        _ expected: BLEShippingModeCoordinator.State,
        from coordinator: BLEShippingModeCoordinator
    ) async throws {
        for _ in 0..<100 where coordinator.state != expected {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(coordinator.state == expected)
    }

    private func waitForAutomaticBLEWorkToResume(
        from coordinator: BLEShippingModeCoordinator
    ) async throws {
        for _ in 0..<100 where coordinator.blocksAutomaticBLEWork {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(!coordinator.blocksAutomaticBLEWork)
    }
}

private enum TestFailure: Error {
    case expected
}
