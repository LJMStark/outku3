import Foundation
import Testing
@testable import KiroleFeature

@MainActor
@Suite("AppState WiFi Transport Router", .serialized)
struct AppStateWiFiTransportRouterTests {

    @MainActor
    final class MockTransport: WiFiAvatarTransporting {
        enum Behavior {
            case success
            case cancelled
            case cancelledThenRecoverable
            case recoverable(WiFiTransferError)
        }
        let behavior: Behavior
        private(set) var sendCount = 0
        init(_ behavior: Behavior) { self.behavior = behavior }

        func send(
            operationID: UInt32,
            avatarID: UUID,
            kriData: Data,
            onPhase: @escaping @MainActor (WiFiTransferPhase) -> Void,
            onProgress: @escaping @MainActor @Sendable (Int, Int) -> Void
        ) async throws {
            sendCount += 1
            switch behavior {
            case .success:
                return
            case .cancelled:
                throw CancellationError()
            case .cancelledThenRecoverable:
                withUnsafeCurrentTask { $0?.cancel() }
                throw WiFiTransferError.unreachable
            case .recoverable(let error):
                throw error
            }
        }
    }

    @MainActor final class CallFlag { var count = 0 }

    private func route(
        _ appState: AppState,
        bleFlag: CallFlag
    ) async throws {
        try await appState.routeCustomAvatarFrame(
            operationID: 1,
            avatarID: UUID(),
            kriData: Data([1, 2, 3]),
            progress: { _, _ in },
            bleSender: { _, _, _, _ in bleFlag.count += 1 }
        )
    }

    // MARK: - Preference routing

    @Test("wifiPreferred success uses WiFi transport, not BLE")
    func wifiSuccess() async throws {
        let appState = AppState.makeForTesting()
        let transport = MockTransport(.success)
        appState.wifiAvatarTransport = transport
        appState.avatarTransferPreference = .wifiPreferred

        let bleFlag = CallFlag()
        try await route(appState, bleFlag: bleFlag)

        #expect(transport.sendCount == 1)
        #expect(bleFlag.count == 0)
    }

    @Test("bleOnly preference uses BLE directly and never opens WiFi")
    func bleOnly() async throws {
        let appState = AppState.makeForTesting()
        let transport = MockTransport(.success)
        appState.wifiAvatarTransport = transport
        appState.avatarTransferPreference = .bleOnly

        let bleFlag = CallFlag()
        try await route(appState, bleFlag: bleFlag)

        #expect(transport.sendCount == 0)
        #expect(bleFlag.count == 1)
    }

    @Test("Recoverable WiFi failure auto-falls back to BLE without prompting")
    func recoverableFallback() async throws {
        let appState = AppState.makeForTesting()
        appState.wifiAvatarTransport = MockTransport(.recoverable(.hotspotJoinFailed(.userDenied)))
        appState.avatarTransferPreference = .wifiPreferred

        let bleFlag = CallFlag()
        try await route(appState, bleFlag: bleFlag)

        #expect(bleFlag.count == 1)
    }

    @Test("Cancellation interrupts without falling back to BLE")
    func cancellationDoesNotFallback() async {
        let appState = AppState.makeForTesting()
        appState.wifiAvatarTransport = MockTransport(.cancelled)
        appState.avatarTransferPreference = .wifiPreferred

        let bleFlag = CallFlag()
        await #expect(throws: CancellationError.self) {
            try await route(appState, bleFlag: bleFlag)
        }
        #expect(bleFlag.count == 0)
    }

    @Test("Cancellation wins when a WiFi failure arrives at the same time")
    func cancellationWinsOverRecoverableFailure() async {
        let appState = AppState.makeForTesting()
        appState.wifiAvatarTransport = MockTransport(.cancelledThenRecoverable)
        appState.avatarTransferPreference = .wifiPreferred

        let bleFlag = CallFlag()
        await #expect(throws: CancellationError.self) {
            try await route(appState, bleFlag: bleFlag)
        }
        #expect(bleFlag.count == 0)
    }

    // MARK: - Phase bridging

    @Test("applyWiFiTransferPhase bridges phases and ignores non-in-progress state")
    func phaseBridge() {
        let appState = AppState.makeForTesting()

        // Guarded: an idle operation ignores a late phase callback.
        appState.customAvatarOperationState = .idle
        appState.applyWiFiTransferPhase(.joiningHotspot)
        #expect(appState.customAvatarOperationState == .idle)

        // In-progress: joiningHotspot applies.
        appState.customAvatarOperationState = .transferring(sentBytes: 0, totalBytes: 100)
        appState.applyWiFiTransferPhase(.joiningHotspot)
        #expect(appState.customAvatarOperationState == .joiningHotspot)

        // uploading → transferring(0, fileLength ?? 0). No pending op → total 0.
        appState.applyWiFiTransferPhase(.uploading)
        #expect(appState.customAvatarOperationState == .transferring(sentBytes: 0, totalBytes: 0))
    }
}
