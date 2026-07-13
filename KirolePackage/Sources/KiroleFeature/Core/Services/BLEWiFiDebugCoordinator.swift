import Foundation
import Observation

public enum BLEWiFiDebugCommand: UInt8, Sendable, Equatable {
    case disable = 0x00
    case enable = 0x01
    case query = 0x02

    public var payload: Data { Data([rawValue]) }
}

public enum BLEWiFiDebugStatus: Sendable, Equatable {
    case success
    case unsupported
    case busy
    case wifiInitializationFailed
    case invalidCommand
    case unknownError
    case unrecognized(UInt8)

    init(rawValue: UInt8) {
        self = switch rawValue {
        case 0x00: .success
        case 0x01: .unsupported
        case 0x02: .busy
        case 0x03: .wifiInitializationFailed
        case 0x04: .invalidCommand
        case 0xFF: .unknownError
        default: .unrecognized(rawValue)
        }
    }

    public var message: String {
        switch self {
        case .success:
            return "Success"
        case .unsupported:
            return "This firmware does not support Wi-Fi PC Debug."
        case .busy:
            return "The device is busy. Try again in a moment."
        case .wifiInitializationFailed:
            return "The device could not start its Wi-Fi access point."
        case .invalidCommand:
            return "The device rejected an invalid Wi-Fi debug command."
        case .unknownError:
            return "The device reported an unknown Wi-Fi error."
        case .unrecognized(let code):
            return "The device reported Wi-Fi status 0x\(String(format: "%02X", code))."
        }
    }
}

public enum BLEWiFiDebugResponseError: Error, Sendable, Equatable {
    case invalidLength(Int)
    case invalidEnabledByte(UInt8)
}

public struct BLEWiFiDebugResponse: Sendable, Equatable {
    public let isEnabled: Bool
    public let status: BLEWiFiDebugStatus

    public init(payload: Data) throws {
        guard payload.count == 2 else {
            throw BLEWiFiDebugResponseError.invalidLength(payload.count)
        }
        guard payload[0] == 0x00 || payload[0] == 0x01 else {
            throw BLEWiFiDebugResponseError.invalidEnabledByte(payload[0])
        }
        isEnabled = payload[0] == 0x01
        status = BLEWiFiDebugStatus(rawValue: payload[1])
    }
}

/// 管理 0x19 Wi-Fi PC Debug 的实时请求/应答。
/// 状态只代表当前 BLE 连接内的硬件状态；断连和硬件重启都恢复为 unknown，不落盘。
@MainActor
@Observable
public final class BLEWiFiDebugCoordinator {
    public enum State: Sendable, Equatable {
        case unknown
        case off
        case enabling
        case on
        case disabling
        case failed
    }

    public enum Failure: Sendable, Equatable {
        case deviceRejected(BLEWiFiDebugStatus)
        case invalidResponse
        case timedOut
        case writeFailed(String)
        case stateMismatch(expectedEnabled: Bool, actualEnabled: Bool)

        public var message: String {
            switch self {
            case .deviceRejected(let status):
                return status.message
            case .invalidResponse:
                return "The device returned a malformed Wi-Fi debug response."
            case .timedOut:
                return "The device did not respond within 5 seconds."
            case .writeFailed(let message):
                return "Could not send the Wi-Fi debug command: \(message)"
            case .stateMismatch(let expectedEnabled, let actualEnabled):
                let expected = expectedEnabled ? "on" : "off"
                let actual = actualEnabled ? "on" : "off"
                return "The device accepted the command but Wi-Fi debug stayed \(actual) instead of turning \(expected)."
            }
        }
    }

    public typealias SendCommand = @MainActor (BLEWiFiDebugCommand) async throws -> Void

    public static let shared = BLEWiFiDebugCoordinator()

    public private(set) var state: State = .unknown
    public private(set) var isEnabled = false
    public private(set) var isQuerying = false
    public private(set) var failure: Failure?

    public var isBusy: Bool {
        isQuerying || state == .enabling || state == .disabling
    }

    /// 开启、关闭途中或硬件已开启时，App 都不能主动释放 BLE；否则无法继续查询或关闭热点。
    public var requiresBLEConnection: Bool {
        isEnabled || isBusy
    }

    private let responseTimeout: Duration
    private let sendCommand: SendCommand
    private var activeOperationID: UUID?
    private var activeCommand: BLEWiFiDebugCommand?
    private var responseTimeoutTask: Task<Void, Never>?

    private init(
        responseTimeout: Duration = .seconds(5),
        sendCommand: SendCommand? = nil
    ) {
        self.responseTimeout = responseTimeout
        self.sendCommand = sendCommand ?? { command in
            try await BLEService.shared.sendWiFiDebugCommand(command)
        }
    }

    static func makeForTesting(
        responseTimeout: Duration = .seconds(5),
        sendCommand: @escaping SendCommand
    ) -> BLEWiFiDebugCoordinator {
        BLEWiFiDebugCoordinator(responseTimeout: responseTimeout, sendCommand: sendCommand)
    }

    public func setEnabled(_ enabled: Bool) async {
        guard activeOperationID == nil else { return }
        if failure == nil,
           (state == .on || state == .off),
           enabled == isEnabled {
            return
        }

        failure = nil
        state = enabled ? .enabling : .disabling
        await begin(command: enabled ? .enable : .disable)
    }

    /// 查询当前硬件状态。若连接完成回调与设置页首次出现同时触发，只保留先到的一次。
    public func queryStatus() async {
        guard activeOperationID == nil else { return }
        failure = nil
        isQuerying = true
        await begin(command: .query)
    }

    public func handleResponse(payload: Data) {
        // 0x19 没有 request ID。只接收当前操作的应答，避免超时/断连后的迟到包
        // 把 failed/unknown 状态重新改成一个过期状态。
        guard let command = activeCommand, activeOperationID != nil else { return }

        let response: BLEWiFiDebugResponse
        do {
            response = try BLEWiFiDebugResponse(payload: payload)
        } catch {
            fail(.invalidResponse)
            ErrorReporter.log(
                .sync(component: "BLE WiFi Debug", underlying: "invalid 0x19 response (\(payload.count) bytes)"),
                context: "BLEWiFiDebugCoordinator.handleResponse"
            )
            return
        }

        cancelPendingOperation()
        guard response.status == .success else {
            // 即使命令失败，Enabled 仍是设备回报的当前真相；用它校正开关，避免 App 保留旧状态。
            isEnabled = response.isEnabled
            state = .failed
            failure = .deviceRejected(response.status)
            return
        }

        let expectedEnabled: Bool? = switch command {
        case .enable: true
        case .disable: false
        case .query: nil
        }
        if let expectedEnabled, expectedEnabled != response.isEnabled {
            isEnabled = response.isEnabled
            state = .failed
            failure = .stateMismatch(
                expectedEnabled: expectedEnabled,
                actualEnabled: response.isEnabled
            )
            return
        }

        isEnabled = response.isEnabled
        state = response.isEnabled ? .on : .off
        failure = nil
    }

    public func handleDisconnected() {
        cancelPendingOperation()
        state = .unknown
        isEnabled = false
        failure = nil
    }

    private func begin(command: BLEWiFiDebugCommand) async {
        let operationID = UUID()
        activeOperationID = operationID
        activeCommand = command

        do {
            try await sendCommand(command)
            // Notify 有可能早于 CoreBluetooth write ACK 到达；这种情况下应答已结束操作，
            // 不要在写调用返回后重新挂一个超时任务。
            guard activeOperationID == operationID else { return }
            scheduleTimeout(for: operationID)
        } catch {
            guard activeOperationID == operationID else { return }
            fail(.writeFailed(error.localizedDescription))
        }
    }

    private func scheduleTimeout(for operationID: UUID) {
        responseTimeoutTask?.cancel()
        responseTimeoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: self.responseTimeout)
            } catch {
                return
            }
            guard !Task.isCancelled, self.activeOperationID == operationID else { return }
            self.fail(.timedOut)
        }
    }

    private func fail(_ failure: Failure) {
        cancelPendingOperation()
        state = .failed
        self.failure = failure
    }

    private func cancelPendingOperation() {
        responseTimeoutTask?.cancel()
        responseTimeoutTask = nil
        activeOperationID = nil
        activeCommand = nil
        isQuerying = false
    }
}
