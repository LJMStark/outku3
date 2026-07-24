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
            case wifiDisabled
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
            case .wifiDisabled:
                throw WiFiTransferError.wifiDisabled
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
        #expect(!appState.isWiFiEnablePromptPresented)
    }

    // MARK: - WiFi-off prompt

    @Test("wifiDisabled prompts, then Send over Bluetooth falls back to BLE")
    func wifiDisabledUseBluetooth() async throws {
        let appState = AppState.makeForTesting()
        appState.wifiAvatarTransport = MockTransport(.wifiDisabled)
        appState.avatarTransferPreference = .wifiPreferred

        let bleFlag = CallFlag()
        let task = Task { try await self.route(appState, bleFlag: bleFlag) }
        while !appState.isWiFiEnablePromptPresented { await Task.yield() }
        appState.resolveWiFiEnablePrompt(.useBluetooth)
        try await task.value

        #expect(bleFlag.count == 1)
        #expect(!appState.isWiFiEnablePromptPresented)
    }

    @Test("wifiDisabled Cancel interrupts (CancellationError) without BLE fallback")
    func wifiDisabledCancel() async {
        let appState = AppState.makeForTesting()
        appState.wifiAvatarTransport = MockTransport(.wifiDisabled)
        appState.avatarTransferPreference = .wifiPreferred

        let bleFlag = CallFlag()
        let task = Task { try await self.route(appState, bleFlag: bleFlag) }
        while !appState.isWiFiEnablePromptPresented { await Task.yield() }
        appState.resolveWiFiEnablePrompt(.cancel)

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(bleFlag.count == 0)
        #expect(!appState.isWiFiEnablePromptPresented)
    }

    @Test("resolveWiFiEnablePrompt with no pending prompt is a no-op")
    func resolveNoPending() {
        let appState = AppState.makeForTesting()
        appState.resolveWiFiEnablePrompt(.cancel)
        #expect(!appState.isWiFiEnablePromptPresented)
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
