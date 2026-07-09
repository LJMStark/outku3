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

    /// 升级完成后的结果判定（基于 DeviceWake 携带的固件版本对比，协议 v2.5.19）。
    public enum UpgradeOutcome: Equatable {
        /// 版本发生变化（或此前版本未知）——升级已生效。
        case confirmed(from: FirmwareVersion?, to: FirmwareVersion)
        /// 重启后仍为同一版本——更新可能未生效（回滚与同版本重刷在 App 侧不可分）。
        case sameVersion(FirmwareVersion)
        /// 重启后的 DeviceWake 未携带版本（旧固件）——无法判定。
        case versionUnknown
    }

    // MARK: - Constants

    private static let maxAttempts = 3
    private static let responseTimeoutSeconds: TimeInterval = 5
    private static let rebootTimeoutSeconds: TimeInterval = 90

    // MARK: - Shared

    public static let shared = BLEOTACoordinator()

    // MARK: - Observed State

    public private(set) var state: State = .idle
    /// 最近一次升级流程的结果；`requestReboot()` / `reset()` 时清空。
    public private(set) var lastOutcome: UpgradeOutcome?

    // MARK: - Private

    private let bleService: BLEService
    private var attemptCount = 0
    private var responseTimeoutTask: Task<Void, Never>?
    private var rebootTimeoutTask: Task<Void, Never>?
    /// 任意 DeviceWake 都会刷新（不限状态），作为升级前版本快照的来源。
    private var lastKnownFirmwareVersion: FirmwareVersion?
    /// 进入 awaitingReboot 时的版本快照，用于与重启后版本对比。
    private var versionBeforeUpgrade: FirmwareVersion?

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
        lastOutcome = nil
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
    /// `reportedVersion` 是本次 wake 帧携带的固件版本（v2.5.19+；旧固件为 nil），
    /// 任意状态下都会刷新已知版本，仅 awaitingReboot 态触发结果判定。
    public func handleDeviceWake(reportedVersion: FirmwareVersion? = nil) {
        if let reportedVersion { lastKnownFirmwareVersion = reportedVersion }
        guard state == .awaitingReboot else { return }
        cancelRebootTimeout()
        bleService.isPendingOTAReboot = false
        if let after = reportedVersion {
            if let before = versionBeforeUpgrade, before == after {
                lastOutcome = .sameVersion(after)
            } else {
                lastOutcome = .confirmed(from: versionBeforeUpgrade, to: after)
            }
        } else {
            lastOutcome = .versionUnknown
        }
        state = .idle
    }

    /// Cancels all pending timers and returns to idle. Safe to call from any state.
    public func reset() {
        cancelResponseTimeout()
        cancelRebootTimeout()
        bleService.isPendingOTAReboot = false
        state = .idle
        attemptCount = 0
        lastOutcome = nil
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
        versionBeforeUpgrade = lastKnownFirmwareVersion
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
