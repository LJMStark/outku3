import Foundation
import Testing
@_spi(KiroleInternal) @testable import KiroleFeature
@_spi(KiroleInternal) @testable import KiroleInternalBLE

@MainActor
@Suite("BLE WiFi PC Debug", .serialized)
struct BLEWiFiDebugCoordinatorTests {
    @Test("WiFi debug commands use the 0x19 wire format")
    func commandWireFormat() {
        #expect(BLEDataType.wifiDebugMode.rawValue == 0x19)
        #expect(BLEWiFiDebugCommand.disable.payload == Data([0x00]))
        #expect(BLEWiFiDebugCommand.enable.payload == Data([0x01]))
        #expect(BLEWiFiDebugCommand.query.payload == Data([0x02]))
        #expect(BLESimpleEncoder.encode(
            type: BLEDataType.wifiDebugMode.rawValue,
            payload: BLEWiFiDebugCommand.disable.payload
        ) == Data([0x19, 0x00, 0x01, 0x00]))
        #expect(BLESimpleEncoder.encode(
            type: BLEDataType.wifiDebugMode.rawValue,
            payload: BLEWiFiDebugCommand.enable.payload
        ) == Data([0x19, 0x00, 0x01, 0x01]))
        #expect(BLESimpleEncoder.encode(
            type: BLEDataType.wifiDebugMode.rawValue,
            payload: BLEWiFiDebugCommand.query.payload
        ) == Data([0x19, 0x00, 0x01, 0x02]))
    }

    @Test("Two-byte device responses parse enabled and every documented status")
    func responseParsing() throws {
        let success = try BLEWiFiDebugResponse(payload: Data([0x01, 0x00]))
        #expect(success.isEnabled)
        #expect(success.status == .success)

        let statuses: [(UInt8, BLEWiFiDebugStatus)] = [
            (0x01, .unsupported),
            (0x02, .busy),
            (0x03, .wifiInitializationFailed),
            (0x04, .invalidCommand),
            (0xFF, .unknownError),
        ]
        for (rawValue, expected) in statuses {
            let response = try BLEWiFiDebugResponse(payload: Data([0x00, rawValue]))
            #expect(response.status == expected)
        }
    }

    @Test("Malformed device response is rejected instead of treated as success", arguments: [
        Data(), Data([0x01]), Data([0x01, 0x00, 0x00]), Data([0x02, 0x00]),
    ])
    func malformedResponseRejected(payload: Data) {
        #expect(throws: BLEWiFiDebugResponseError.self) {
            _ = try BLEWiFiDebugResponse(payload: payload)
        }
    }

    @Test("Enable waits for a successful device response before becoming on")
    func enableRequiresAcknowledgement() async {
        let recorder = CommandRecorder()
        let coordinator = BLEWiFiDebugCoordinator.makeForTesting { command in
            recorder.commands.append(command)
        }

        await coordinator.setEnabled(true)
        #expect(recorder.commands == [.enable])
        #expect(coordinator.state == .enabling)
        #expect(!coordinator.isEnabled)

        coordinator.handleResponse(payload: Data([0x01, 0x00]))
        #expect(coordinator.state == .on)
        #expect(coordinator.isEnabled)
        #expect(coordinator.failure == nil)
    }

    @Test("A rejected command still uses the device Enabled byte as the actual state")
    func rejectedCommandUsesDeviceState() async {
        let coordinator = BLEWiFiDebugCoordinator.makeForTesting { _ in }
        await coordinator.queryStatus()
        coordinator.handleResponse(payload: Data([0x01, 0x00]))
        #expect(coordinator.isEnabled)

        await coordinator.setEnabled(false)
        #expect(coordinator.state == .disabling)
        coordinator.handleResponse(payload: Data([0x00, 0x02]))

        #expect(coordinator.state == .failed)
        #expect(coordinator.failure == .deviceRejected(.busy))
        #expect(!coordinator.isEnabled)
    }

    @Test("A successful response that contradicts the command becomes a visible failure")
    func successfulResponseMustMatchCommand() async {
        let coordinator = BLEWiFiDebugCoordinator.makeForTesting { _ in }

        await coordinator.setEnabled(true)
        coordinator.handleResponse(payload: Data([0x00, 0x00]))

        #expect(coordinator.state == .failed)
        #expect(coordinator.failure == .stateMismatch(expectedEnabled: true, actualEnabled: false))
        #expect(!coordinator.isEnabled)
    }

    @Test("A five-second response timeout fails and rolls back")
    func responseTimeoutRollsBack() async throws {
        let coordinator = BLEWiFiDebugCoordinator.makeForTesting(
            responseTimeout: .milliseconds(20)
        ) { _ in }

        await coordinator.setEnabled(true)
        try await waitForFailure(.timedOut, from: coordinator)

        #expect(coordinator.state == .failed)
        #expect(coordinator.failure == .timedOut)
        #expect(!coordinator.isEnabled)
    }

    @Test("The response timeout starts after the BLE write finishes")
    func responseTimeoutStartsAfterWrite() async throws {
        let coordinator = BLEWiFiDebugCoordinator.makeForTesting(
            responseTimeout: .milliseconds(20)
        ) { _ in
            try await Task.sleep(for: .milliseconds(40))
        }

        await coordinator.setEnabled(true)
        #expect(coordinator.state == .enabling)
        #expect(coordinator.failure == nil)

        try await waitForFailure(.timedOut, from: coordinator)
        #expect(coordinator.failure == .timedOut)
    }

    @Test("Concurrent status queries are coalesced")
    func queryIsCoalesced() async {
        let recorder = CommandRecorder()
        let coordinator = BLEWiFiDebugCoordinator.makeForTesting { command in
            recorder.commands.append(command)
            try await Task.sleep(for: .milliseconds(20))
        }

        async let first: Void = coordinator.queryStatus()
        async let second: Void = coordinator.queryStatus()
        _ = await (first, second)

        #expect(recorder.commands == [.query])
        #expect(coordinator.isQuerying)
        coordinator.handleResponse(payload: Data([0x00, 0x00]))
        #expect(coordinator.state == .off)
        #expect(!coordinator.isQuerying)
    }

    @Test("Disconnect cancels pending work and resets state to unknown")
    func disconnectResetsState() async {
        let coordinator = BLEWiFiDebugCoordinator.makeForTesting { _ in }
        await coordinator.setEnabled(true)
        #expect(coordinator.state == .enabling)

        coordinator.handleDisconnected()

        #expect(coordinator.state == .unknown)
        #expect(!coordinator.isEnabled)
        #expect(!coordinator.isQuerying)
        #expect(coordinator.failure == nil)
    }

    @Test("BLE must stay connected while WiFi debug is changing or enabled")
    func wifiDebugRequiresBLEConnection() async {
        let coordinator = BLEWiFiDebugCoordinator.makeForTesting { _ in }
        #expect(!coordinator.requiresBLEConnection)

        await coordinator.setEnabled(true)
        #expect(coordinator.requiresBLEConnection)

        coordinator.handleResponse(payload: Data([0x01, 0x00]))
        #expect(coordinator.requiresBLEConnection)

        await coordinator.setEnabled(false)
        #expect(coordinator.requiresBLEConnection)

        coordinator.handleResponse(payload: Data([0x00, 0x00]))
        #expect(!coordinator.requiresBLEConnection)
    }

    @Test("Only 0x1C bypasses the shipping-mode write block")
    func onlyShippingModeCommandBypassesShippingModeBlock() async {
        let shippingCoordinator = BLEShippingModeCoordinator.makeForTesting(
            disconnectTimeout: .seconds(1),
            setPendingDisconnect: { _ in },
            sendCommand: { armExpectedDisconnect in armExpectedDisconnect() }
        )
        await shippingCoordinator.enable()
        #expect(shippingCoordinator.blocksAutomaticBLEWork)

        let wifiCoordinator = BLEWiFiDebugCoordinator.makeForTesting { _ in }
        InternalBLEToolsController.installForTesting(
            wifiDebugCoordinator: wifiCoordinator,
            shippingModeCoordinator: shippingCoordinator
        )
        defer { InternalBLEToolsController.uninstallForTesting() }

        do {
            try await BLEService.shared.sendInternalToolCommand(
                type: .wifiDebugMode,
                data: BLEWiFiDebugCommand.query.payload
            )
            Issue.record("Expected 0x19 to remain blocked while shipping mode owns the connection")
        } catch let error as BLEError {
            guard case .shippingModeActive = error else {
                Issue.record("Expected shippingModeActive for 0x19, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected BLEError.shippingModeActive for 0x19, got \(error)")
        }

        do {
            try await BLEService.shared.sendInternalToolCommand(
                type: .shippingMode,
                data: BLEShippingModeCommand.enable.payload
            )
            Issue.record("Expected the disconnected test service to reject 0x1C after the block")
        } catch let error as BLEError {
            guard case .notConnected = error else {
                Issue.record("Expected 0x1C to reach the connection guard, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected BLEError.notConnected for 0x1C, got \(error)")
        }
    }

    @Test("0x19 is routed as a live response and never parsed as an EventLog")
    func eventHandlerRoutesLiveResponse() async throws {
        let coordinator = BLEWiFiDebugCoordinator.makeForTesting { _ in }
        await coordinator.queryStatus()
        InternalBLEToolsController.installForTesting(wifiDebugCoordinator: coordinator)
        defer { InternalBLEToolsController.uninstallForTesting() }
        let decoded = try #require(BLESimpleDecoder.decode(Data([0x19, 0x02, 0x01, 0x00])))
        await BLEEventHandler.handleReceivedPayload(
            decoded,
            service: .shared
        )

        #expect(coordinator.state == .on)
        #expect(coordinator.isEnabled)
    }

    @Test("Malformed 0x19 live response becomes a visible failure")
    func malformedLiveResponseFails() async {
        let coordinator = BLEWiFiDebugCoordinator.makeForTesting { _ in }
        await coordinator.queryStatus()
        InternalBLEToolsController.installForTesting(wifiDebugCoordinator: coordinator)
        defer { InternalBLEToolsController.uninstallForTesting() }
        await BLEEventHandler.handleReceivedPayload(
            BLEReceivedMessage(type: 0x19, payload: Data([0x01])),
            service: .shared
        )

        #expect(coordinator.state == .failed)
        #expect(coordinator.failure == .invalidResponse)
    }

    @Test("0x19 is rejected if firmware incorrectly puts it inside an offline batch")
    func wifiDebugRecordIsRejectedFromEventLogBatch() {
        let batch = Data([0x01, 0x19, 0x01, 0x00])
        #expect(BLEEventHandler.parseEventLogBatchPayload(batch).isEmpty)
    }

    @Test("A late response after timeout or disconnect is ignored")
    func staleResponseIsIgnored() async {
        let coordinator = BLEWiFiDebugCoordinator.makeForTesting { _ in }
        coordinator.handleResponse(payload: Data([0x01, 0x00]))
        #expect(coordinator.state == .unknown)
        #expect(!coordinator.isEnabled)
    }

    private func waitForFailure(
        _ expectedFailure: BLEWiFiDebugCoordinator.Failure,
        from coordinator: BLEWiFiDebugCoordinator,
        timeout: Duration = .seconds(1)
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while coordinator.failure != expectedFailure, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

}

@MainActor
private final class CommandRecorder {
    var commands: [BLEWiFiDebugCommand] = []
}
