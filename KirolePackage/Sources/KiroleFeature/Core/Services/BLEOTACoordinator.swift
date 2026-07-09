import Foundation
import Observation

// MARK: - BLE OTA Coordinator

/// App-side state machine for the 0x18 OTA upgrade trigger flow (§4.17 / §5.17).
///
/// State transitions:
///   idle → (requestReboot) → sending
///   sending → (0x00 response OR pre-response disconnect) → awaitingReboot
///   sending → (non-0x00 response) → failed(.deviceRejected)
///   sending → (3 timeouts, connection alive throughout) → failed(.noResponse)
///   awaitingReboot → (DeviceWake 0x30) → idle  (success)
///   awaitingReboot → (~90s timeout, no DeviceWake) → failed(.timedOutWaitingForReboot)
@MainActor
@Observable
public final class BLEOTACoordinator {

    // MARK: - Types

    public enum State: Equatable {
        case idle
        case sending
        case awaitingReboot
        case failed(Failure)
    }

    public enum Failure: Equatable {
        case deviceRejected(UInt8)
        case noResponse
        case timedOutWaitingForReboot
    }

    // MARK: - Constants

    private static let maxAttempts = 3
    private static let responseTimeoutSeconds: TimeInterval = 5
    private static let rebootTimeoutSeconds: TimeInterval = 90

    // MARK: - Shared

    public static let shared = BLEOTACoordinator()

    // MARK: - Observed State

    public private(set) var state: State = .idle

    // MARK: - Private

    private let bleService: BLEService
    private var attemptCount = 0
    private var responseTimeoutTask: Task<Void, Never>?
    private var rebootTimeoutTask: Task<Void, Never>?

    private init(bleService: BLEService = .shared) {
        self.bleService = bleService
    }

    /// Factory for unit tests only — not for production call sites.
    static func makeForTesting(bleService: BLEService = .shared) -> BLEOTACoordinator {
        BLEOTACoordinator(bleService: bleService)
    }

    // MARK: - Public API

    /// Initiates the OTA upgrade trigger. No-op if already in a non-idle state.
    public func requestReboot() async {
        guard state == .idle else { return }
        attemptCount = 0
        await sendAttempt()
    }

    /// Called by BLEEventHandler when a 0x18 OTAResult notify arrives.
    public func handleOTAResult(statusCode: UInt8) {
        guard state == .sending else { return }
        cancelResponseTimeout()
        if statusCode == 0x00 {
            enterAwaitingReboot()
        } else {
            bleService.isPendingOTAReboot = false
            state = .failed(.deviceRejected(statusCode))
        }
    }

    /// Called by BLEService.didDisconnectPeripheral when isPendingOTAReboot is true.
    /// Per §4.17: a pre-response disconnect means the device likely started upgrading.
    public func handleExpectedDisconnect() {
        guard state == .sending || state == .awaitingReboot else { return }
        cancelResponseTimeout()
        if state == .sending { enterAwaitingReboot() }
    }

    /// Called by BLEEventHandler when DeviceWake(0x30) arrives.
    /// Confirms the device completed its reboot cycle — upgrade flow is done.
    public func handleDeviceWake() {
        guard state == .awaitingReboot else { return }
        cancelRebootTimeout()
        bleService.isPendingOTAReboot = false
        state = .idle
    }

    /// Cancels all pending timers and returns to idle. Safe to call from any state.
    public func reset() {
        cancelResponseTimeout()
        cancelRebootTimeout()
        bleService.isPendingOTAReboot = false
        state = .idle
        attemptCount = 0
    }

    // MARK: - Private

    private func sendAttempt() async {
        guard attemptCount < Self.maxAttempts else {
            state = .failed(.noResponse)
            return
        }
        attemptCount += 1
        state = .sending
        // Write errors are non-fatal: the response timeout will retry or give up.
        try? await bleService.sendOTAReboot()
        scheduleResponseTimeout()
    }

    private func scheduleResponseTimeout() {
        cancelResponseTimeout()
        responseTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(BLEOTACoordinator.responseTimeoutSeconds))
            guard !Task.isCancelled, let self, self.state == .sending else { return }
            // If still connected after 5s with no response, retry.
            if self.bleService.connectionState.isConnected {
                await self.sendAttempt()
            }
            // If disconnected, handleExpectedDisconnect() was already called by BLEService.
        }
    }

    private func enterAwaitingReboot() {
        bleService.isPendingOTAReboot = true
        state = .awaitingReboot
        scheduleRebootTimeout()
    }

    private func scheduleRebootTimeout() {
        cancelRebootTimeout()
        rebootTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(BLEOTACoordinator.rebootTimeoutSeconds))
            guard !Task.isCancelled, let self, self.state == .awaitingReboot else { return }
            self.bleService.isPendingOTAReboot = false
            self.state = .failed(.timedOutWaitingForReboot)
        }
    }

    private func cancelResponseTimeout() {
        responseTimeoutTask?.cancel()
        responseTimeoutTask = nil
    }

    private func cancelRebootTimeout() {
        rebootTimeoutTask?.cancel()
        rebootTimeoutTask = nil
    }
}
