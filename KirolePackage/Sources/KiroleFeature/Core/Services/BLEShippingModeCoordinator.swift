import Foundation
import Observation

// MARK: - BLE Shipping Mode Coordinator

/// 管理工厂 ShippingMode (0x1C) 的单向流程。
///
/// 协议没有业务 ACK：App 先写出 `01`，随后只把设备主动断开 BLE 视为成功。
/// 等待期间会暂时禁止自动重连，避免运输模式刚生效就被 App 重新连接。
@MainActor
@Observable
public final class BLEShippingModeCoordinator {
    public enum State: Equatable {
        case idle
        case sending
        case awaitingDisconnect
        case activated
        case failed(Failure)
    }

    public enum Failure: Equatable {
        case sendFailed
        case didNotDisconnect
        case activationUnconfirmed
        case conflictingDeviceOperation
    }

    public typealias ArmExpectedDisconnect = @MainActor () -> Void
    public typealias SendCommand = @MainActor (@escaping ArmExpectedDisconnect) async throws -> Void
    public typealias CanStart = @MainActor () -> Bool
    public typealias SetPendingDisconnect = @MainActor (Bool) -> Void

    public static let shared = BLEShippingModeCoordinator()

    public private(set) var state: State = .idle

    /// 发送开始后停止普通同步和自动连接；只有明确的手动重连才解除。
    public var blocksAutomaticBLEWork: Bool {
        if expectedDisconnectArmed { return true }
        switch state {
        case .sending, .awaitingDisconnect, .activated:
            return true
        case .idle, .failed:
            return false
        }
    }

    /// 普通同步、看门狗和后台任务不能在命令发送与设备主动断连之间关闭 BLE。
    public var requiresCurrentConnection: Bool {
        expectedDisconnectArmed || state == .sending || state == .awaitingDisconnect
    }

    private let disconnectTimeout: Duration
    private let lateDisconnectGrace: Duration
    private let canStart: CanStart
    private let setPendingDisconnect: SetPendingDisconnect
    private let sendCommand: SendCommand
    private var expectedDisconnectArmed = false
    private var timeoutTask: Task<Void, Never>?
    private var lateDisconnectTask: Task<Void, Never>?

    private init(
        disconnectTimeout: Duration = .seconds(10),
        lateDisconnectGrace: Duration = .seconds(2),
        canStart: CanStart? = nil,
        setPendingDisconnect: SetPendingDisconnect? = nil,
        sendCommand: SendCommand? = nil
    ) {
        self.disconnectTimeout = disconnectTimeout
        self.lateDisconnectGrace = lateDisconnectGrace
        self.canStart = canStart ?? {
            !BLEOTACoordinator.shared.isBusy
                && FocusSessionService.shared.activeSession == nil
                && !FocusSessionService.shared.isStartingSession
        }
        self.setPendingDisconnect = setPendingDisconnect ?? { isPending in
            BLEService.shared.isPendingShippingModeActivation = isPending
        }
        self.sendCommand = sendCommand ?? { armExpectedDisconnect in
            try await BLEService.shared.sendShippingModeCommand(
                onWillWrite: armExpectedDisconnect
            )
        }
    }

    static func makeForTesting(
        disconnectTimeout: Duration,
        lateDisconnectGrace: Duration = .seconds(2),
        canStart: @escaping CanStart = { true },
        setPendingDisconnect: @escaping SetPendingDisconnect,
        sendCommand: @escaping SendCommand
    ) -> BLEShippingModeCoordinator {
        BLEShippingModeCoordinator(
            disconnectTimeout: disconnectTimeout,
            lateDisconnectGrace: lateDisconnectGrace,
            canStart: canStart,
            setPendingDisconnect: setPendingDisconnect,
            sendCommand: sendCommand
        )
    }

    /// 发送一次运输模式命令。重复点击不会叠加并行请求。
    public func enable() async {
        guard state != .sending, state != .awaitingDisconnect else { return }
        guard canStart() else {
            state = .failed(.conflictingDeviceOperation)
            return
        }

        cancelPendingTimers()
        clearExpectedDisconnect()
        state = .sending

        do {
            try await sendCommand { [weak self] in
                guard let self, self.state == .sending else { return }
                self.expectedDisconnectArmed = true
                self.setPendingDisconnect(true)
            }
            // 设备可能在 CoreBluetooth 写完成前已经断开；这种情况下断连回调已将状态置为成功。
            guard state == .sending else { return }
            guard expectedDisconnectArmed else {
                state = .failed(.sendFailed)
                return
            }
            state = .awaitingDisconnect
            scheduleTimeout()
        } catch {
            guard state != .activated else { return }
            guard expectedDisconnectArmed else {
                state = .failed(.sendFailed)
                return
            }
            // CoreBluetooth may report the write error before delivering the device's disconnect.
            // Once writeValue was reached, keep the disconnect route armed and let the device's
            // disconnect remain authoritative instead of misreporting failure and reconnecting.
            state = .awaitingDisconnect
            scheduleTimeout()
        }
    }

    /// 由 BLEService 在 0x1C 发送后的预期断连中调用。
    public func handleExpectedDisconnect() {
        guard expectedDisconnectArmed else { return }
        cancelPendingTimers()
        clearExpectedDisconnect()
        state = .activated
    }

    /// App 主动断开不能冒充设备的生效信号。
    public func handleUnconfirmedDisconnect() {
        guard expectedDisconnectArmed else { return }
        cancelPendingTimers()
        clearExpectedDisconnect()
        state = .failed(.activationUnconfirmed)
    }

    /// 运输模式唤醒后会由固件自动关闭；设备重新连上时，App 也回到可再次操作的初始状态。
    public func handleDeviceReconnected() {
        guard state == .activated else { return }
        state = .idle
    }

    public func reset() {
        cancelPendingTimers()
        clearExpectedDisconnect()
        state = .idle
    }

    private func scheduleTimeout() {
        cancelTimeout()
        timeoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: disconnectTimeout)
            guard !Task.isCancelled, state == .awaitingDisconnect else { return }
            // Keep the one-shot disconnect route armed. A device can disconnect just after this
            // UI timeout; that late signal must still suppress auto-reconnect and confirm success.
            state = .failed(.didNotDisconnect)
            scheduleLateDisconnectGrace()
        }
    }

    private func scheduleLateDisconnectGrace() {
        lateDisconnectTask?.cancel()
        lateDisconnectTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: lateDisconnectGrace)
            guard !Task.isCancelled,
                  state == .failed(.didNotDisconnect) else { return }
            clearExpectedDisconnect()
        }
    }

    private func clearExpectedDisconnect() {
        guard expectedDisconnectArmed else { return }
        expectedDisconnectArmed = false
        setPendingDisconnect(false)
    }

    private func cancelTimeout() {
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    private func cancelPendingTimers() {
        cancelTimeout()
        lateDisconnectTask?.cancel()
        lateDisconnectTask = nil
    }
}
