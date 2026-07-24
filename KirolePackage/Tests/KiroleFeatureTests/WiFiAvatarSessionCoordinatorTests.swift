import Foundation
import Testing
@testable import KiroleFeature

@MainActor
@Suite("WiFi Avatar Session Coordinator (0x1A)", .serialized)
struct WiFiAvatarSessionCoordinatorTests {

    @MainActor
    final class RequestRecorder {
        var requests: [WiFiAvatarSessionRequest] = []
        func record(_ request: WiFiAvatarSessionRequest) { requests.append(request) }
    }

    private static let sampleCredentials = WiFiAvatarSessionCredentials(
        ssid: "Kirole-TEST",
        passphrase: "p@ssw0rd",
        gateway: IPv4Address(192, 168, 4, 1),
        port: 8080,
        path: "/avatar",
        token: "tok_test",
        ttlSeconds: 120
    )

    /// Spins the cooperative executor until the coordinator has an in-flight request.
    private func waitForInFlightRequest(_ coordinator: WiFiAvatarSessionCoordinator) async {
        while !coordinator.requiresBLEConnection { await Task.yield() }
    }

    @Test("openSession returns credentials and activates on OK response")
    func openSucceeds() async throws {
        let recorder = RequestRecorder()
        let coordinator = WiFiAvatarSessionCoordinator.makeForTesting { recorder.record($0) }

        async let credentials = coordinator.openSession(operationID: 0x1234_5678)
        await waitForInFlightRequest(coordinator)
        coordinator.handleResponse(
            payload: WiFiAvatarSessionCodec.encodeResponse(
                WiFiAvatarSessionResponse(status: .ok, credentials: Self.sampleCredentials)
            )
        )

        let result = try await credentials
        #expect(result == Self.sampleCredentials)
        #expect(coordinator.isSessionActive)
        #expect(recorder.requests == [WiFiAvatarSessionRequest(command: .open, operationID: 0x1234_5678)])
    }

    @Test("openSession throws deviceRejected and stays inactive on a non-OK status")
    func openRejected() async throws {
        let coordinator = WiFiAvatarSessionCoordinator.makeForTesting { _ in }

        let task = Task { try await coordinator.openSession(operationID: 1) }
        await waitForInFlightRequest(coordinator)
        coordinator.handleResponse(
            payload: WiFiAvatarSessionCodec.encodeResponse(
                WiFiAvatarSessionResponse(status: .busy, credentials: nil)
            )
        )

        await #expect(throws: WiFiAvatarSessionError.deviceRejected(.busy)) {
            _ = try await task.value
        }
        #expect(!coordinator.isSessionActive)
    }

    @Test("openSession times out when the device never answers")
    func openTimesOut() async {
        let coordinator = WiFiAvatarSessionCoordinator.makeForTesting(
            responseTimeout: .milliseconds(40)
        ) { _ in }

        await #expect(throws: WiFiAvatarSessionError.timedOut) {
            _ = try await coordinator.openSession(operationID: 1)
        }
        #expect(!coordinator.isSessionActive)
    }

    @Test("openSession throws disconnected when the link drops mid-handshake")
    func openDisconnects() async {
        let coordinator = WiFiAvatarSessionCoordinator.makeForTesting { _ in }

        let task = Task { try await coordinator.openSession(operationID: 1) }
        await waitForInFlightRequest(coordinator)
        coordinator.handleDisconnected()

        await #expect(throws: WiFiAvatarSessionError.disconnected) {
            _ = try await task.value
        }
        #expect(!coordinator.isSessionActive)
    }

    @Test("openSession surfaces a write failure")
    func openWriteFails() async {
        struct SendFailure: Error {}
        let coordinator = WiFiAvatarSessionCoordinator.makeForTesting { _ in throw SendFailure() }

        await #expect(throws: WiFiAvatarSessionError.self) {
            _ = try await coordinator.openSession(operationID: 1)
        }
        #expect(!coordinator.isSessionActive)
    }

    @Test("A second request while one is in flight is rejected as busy")
    func concurrentRequestRejected() async throws {
        let coordinator = WiFiAvatarSessionCoordinator.makeForTesting { _ in }

        async let first = coordinator.openSession(operationID: 1)
        await waitForInFlightRequest(coordinator)

        await #expect(throws: WiFiAvatarSessionError.busy) {
            _ = try await coordinator.openSession(operationID: 2)
        }

        coordinator.handleDisconnected() // release the first waiter
        _ = try? await first
    }

    @Test("closeSession emits a close command and deactivates without awaiting a response")
    func closeEmitsCommand() async throws {
        let recorder = RequestRecorder()
        let coordinator = WiFiAvatarSessionCoordinator.makeForTesting { recorder.record($0) }

        // Bring the session up first.
        async let credentials = coordinator.openSession(operationID: 7)
        await waitForInFlightRequest(coordinator)
        coordinator.handleResponse(
            payload: WiFiAvatarSessionCodec.encodeResponse(
                WiFiAvatarSessionResponse(status: .ok, credentials: Self.sampleCredentials)
            )
        )
        _ = try await credentials
        #expect(coordinator.isSessionActive)

        await coordinator.closeSession(operationID: 7)
        #expect(!coordinator.isSessionActive)
        #expect(recorder.requests.last == WiFiAvatarSessionRequest(command: .close, operationID: 7))
    }

    @Test("A response with no in-flight request is ignored")
    func lateResponseIgnored() {
        let coordinator = WiFiAvatarSessionCoordinator.makeForTesting { _ in }
        // Must not crash or flip state.
        coordinator.handleResponse(
            payload: WiFiAvatarSessionCodec.encodeResponse(
                WiFiAvatarSessionResponse(status: .ok, credentials: Self.sampleCredentials)
            )
        )
        #expect(!coordinator.isSessionActive)
        #expect(!coordinator.requiresBLEConnection)
    }

    @Test("requiresBLEConnection tracks the handshake lifecycle")
    func keepAliveLifecycle() async throws {
        let coordinator = WiFiAvatarSessionCoordinator.makeForTesting { _ in }
        #expect(!coordinator.requiresBLEConnection)

        async let credentials = coordinator.openSession(operationID: 9)
        await waitForInFlightRequest(coordinator)
        #expect(coordinator.requiresBLEConnection) // in-flight

        coordinator.handleResponse(
            payload: WiFiAvatarSessionCodec.encodeResponse(
                WiFiAvatarSessionResponse(status: .ok, credentials: Self.sampleCredentials)
            )
        )
        _ = try await credentials
        #expect(coordinator.requiresBLEConnection) // active session

        coordinator.handleDisconnected()
        #expect(!coordinator.requiresBLEConnection)
    }
}
