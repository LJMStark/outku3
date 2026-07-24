import Foundation
import Observation

public enum WiFiAvatarSessionError: Error, Sendable, Equatable {
    case busy
    case writeFailed(String)
    case invalidResponse
    case timedOut
    case disconnected
    case deviceRejected(WiFiAvatarSessionStatus)

    /// Whether the WiFi transport can fall back to BLE after this failure.
    /// All handshake failures are recoverable — BLE 0x15 keeps working.
    public var isRecoverableToBLE: Bool { true }

    public var message: String {
        switch self {
        case .busy:
            return "A Wi-Fi avatar session is already in progress."
        case .writeFailed(let underlying):
            return "Could not send the Wi-Fi session command: \(underlying)"
        case .invalidResponse:
            return "The device returned a malformed Wi-Fi session response."
        case .timedOut:
            return "The device did not respond to the Wi-Fi session request in time."
        case .disconnected:
            return "The device disconnected during the Wi-Fi session."
        case .deviceRejected(let status):
            return "The device declined the Wi-Fi session (status 0x\(String(format: "%02X", status.rawValue)))."
        }
    }
}

/// 管理 `0x1A WiFiAvatarSession` 的 BLE 握手请求/应答。
///
/// 与 `BLEWiFiDebugCoordinator`（fire-and-forget 的 UI 状态机）不同：`open` 是
/// **request-response**——发命令后 await 设备应答拿回 SoftAP 凭据才能继续 HTTP 上传，
/// 因此用 `CheckedContinuation` 把请求/应答折叠成一个可 await 的调用（同 AppState 等
/// `0x22` 结果的 `AvatarControlResultWaiter` 思路）。状态只代表当前 BLE 连接内的会话；
/// 断连即复位，不落盘。
@MainActor
@Observable
public final class WiFiAvatarSessionCoordinator {
    public typealias SendCommand = @MainActor (WiFiAvatarSessionRequest) async throws -> Void

    public static let shared = WiFiAvatarSessionCoordinator()

    /// SoftAP 会话进行中（`open` 成功后）或握手途中（有在途请求）时，App 不能主动释放 BLE——
    /// 否则无法再发 `close` 停热点或收 `0x22 staged`。供 `BLEService.shouldKeepConnectionOpenForDebug`。
    public var requiresBLEConnection: Bool { isSessionActive || pendingWaiter != nil }

    public private(set) var isSessionActive = false

    private let responseTimeout: Duration
    private let sendCommand: SendCommand
    private var pendingWaiter: Waiter?
    private var responseTimeoutTask: Task<Void, Never>?

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<WiFiAvatarSessionResponse, any Error>
    }

    private init(
        responseTimeout: Duration = .seconds(8),
        sendCommand: SendCommand? = nil
    ) {
        self.responseTimeout = responseTimeout
        self.sendCommand = sendCommand ?? { request in
            try await BLEService.shared.sendWiFiAvatarSessionCommand(request)
        }
    }

    static func makeForTesting(
        responseTimeout: Duration = .seconds(8),
        sendCommand: @escaping SendCommand
    ) -> WiFiAvatarSessionCoordinator {
        WiFiAvatarSessionCoordinator(responseTimeout: responseTimeout, sendCommand: sendCommand)
    }

    // MARK: - Session control

    /// 开启会话：发 `open`，await 应答，成功返回 SoftAP 凭据。
    /// 失败（设备拒绝 / 超时 / 断连 / 写失败）抛 `WiFiAvatarSessionError`，调用方回退 BLE。
    public func openSession(operationID: UInt32) async throws -> WiFiAvatarSessionCredentials {
        let response = try await sendRequest(command: .open, operationID: operationID)
        guard response.status == .ok, let credentials = response.credentials else {
            throw WiFiAvatarSessionError.deviceRejected(response.status)
        }
        isSessionActive = true
        return credentials
    }

    /// 结束会话：best-effort 只**发出** `close` 停 SoftAP，不 await 应答（清理路径不应挂起
    /// 等设备，否则要空等超时）。忽略写失败——设备侧 SoftAP 也会在 TTL 到期后自动关闭。
    public func closeSession(operationID: UInt32) async {
        isSessionActive = false
        let request = WiFiAvatarSessionRequest(command: .close, operationID: operationID)
        _ = try? await sendCommand(request)
    }

    /// 查询会话状态。
    @discardableResult
    public func queryStatus(operationID: UInt32) async throws -> WiFiAvatarSessionResponse {
        try await sendRequest(command: .query, operationID: operationID)
    }

    // MARK: - BLE inbound

    public func handleResponse(payload: Data) {
        guard pendingWaiter != nil else { return }
        do {
            let response = try WiFiAvatarSessionCodec.decodeResponse(payload)
            finish(returning: response)
        } catch {
            ErrorReporter.log(
                .sync(component: "BLE WiFi Avatar", underlying: "invalid 0x1A response (\(payload.count) bytes)"),
                context: "WiFiAvatarSessionCoordinator.handleResponse"
            )
            finish(throwing: WiFiAvatarSessionError.invalidResponse)
        }
    }

    public func handleDisconnected() {
        isSessionActive = false
        finish(throwing: WiFiAvatarSessionError.disconnected)
    }

    // MARK: - Private

    private func sendRequest(
        command: WiFiAvatarSessionCommand,
        operationID: UInt32
    ) async throws -> WiFiAvatarSessionResponse {
        guard pendingWaiter == nil else { throw WiFiAvatarSessionError.busy }
        let request = WiFiAvatarSessionRequest(command: command, operationID: operationID)
        let waiterID = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            pendingWaiter = Waiter(id: waiterID, continuation: continuation)
            Task { @MainActor in
                do {
                    try await sendCommand(request)
                    // Notify 可能早于 CoreBluetooth 写 ACK 到达；应答已结束则不再挂超时。
                    guard pendingWaiter?.id == waiterID else { return }
                    scheduleTimeout(waiterID: waiterID)
                } catch {
                    guard pendingWaiter?.id == waiterID else { return }
                    finish(throwing: WiFiAvatarSessionError.writeFailed(error.localizedDescription))
                }
            }
        }
    }

    private func scheduleTimeout(waiterID: UUID) {
        responseTimeoutTask?.cancel()
        responseTimeoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: self.responseTimeout)
            } catch {
                return
            }
            guard !Task.isCancelled, self.pendingWaiter?.id == waiterID else { return }
            self.finish(throwing: WiFiAvatarSessionError.timedOut)
        }
    }

    private func finish(returning response: WiFiAvatarSessionResponse) {
        guard let waiter = pendingWaiter else { return }
        clearPending()
        waiter.continuation.resume(returning: response)
    }

    private func finish(throwing error: any Error) {
        guard let waiter = pendingWaiter else { return }
        clearPending()
        waiter.continuation.resume(throwing: error)
    }

    private func clearPending() {
        responseTimeoutTask?.cancel()
        responseTimeoutTask = nil
        pendingWaiter = nil
    }
}
