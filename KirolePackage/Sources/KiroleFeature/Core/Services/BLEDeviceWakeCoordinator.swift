import Foundation
import Observation

/// 每次连接在发送任何业务帧之前完成的功耗握手（`0x25`，协议 §4.24/§5.24）。
///
/// 客户要求硬件 BLE 常开：设备进入低功耗后连接仍然可达，所以「连上了」不等于「能收数据」。
///
/// 流程（2026-08-04 硬件团队定的语义）：读状态 →（休眠则）下发唤醒 → **间隔轮询读状态** →
/// **必须读到「正常运行」才允许继续通信**。唤醒命令是 fire-and-forget，判定完全依赖后续查询。
///
/// **整个流程 fail-closed**：任一环节读不到 active——无应答、格式非法、设备拒绝、轮询用尽——
/// 都判本次连接失败并断开，与紧随其后的 `0x20` 回放屏障同一处置。轮询的意义就是「确认之后
/// 才继续」，超时后照发不误等于白轮询。
///
/// > ⚠️ 这是 flag-day 切换：**固件实现 `0x25` 之前，App 连不上任何设备**（连上就断、反复重连）。
/// > 协议 v2.18.0 已定案，固件按 §4.24 施工。
///
/// 状态只代表当前 BLE 连接内的硬件状态；断连恢复为 unknown，不落盘。
@MainActor
@Observable
public final class BLEDeviceWakeCoordinator {
    public enum State: Sendable, Equatable {
        case unknown
        case querying
        case waking
        /// 读到 `PowerState=active`——**唯一**允许继续下发业务数据的状态。
        case awake
        /// 轮询用尽仍未读到 active，或设备根本不应答 `0x25`。本次连接判失败并断开。
        case failedToWake
        /// 收到设备主动上报的低功耗（`CommandEcho=0xFF`）或 `0x31 DeviceSleep`。
        case observedSleep
    }

    public typealias SendCommand = @MainActor (BLEDevicePowerCommand) async throws -> Void
    public typealias Sleeper = @Sendable (Duration) async throws -> Void

    private struct Operation {
        let id: UUID
        let expectedEcho: UInt8
        let generation: UInt64
        /// 应答早于 `sendCommand` 的写 ACK 到达时先存这里，等 `send` 回来取。
        var received: BLEDevicePowerResponse?
        var continuation: CheckedContinuation<BLEDevicePowerResponse?, Never>?
    }

    public static let shared = BLEDeviceWakeCoordinator()

    public private(set) var state: State = .unknown

    /// 单次 `0x25` 查询的应答超时。2 秒已是典型 BLE 往返的几十倍。
    private let responseTimeout: Duration
    /// 唤醒后两次状态查询之间的间隔。
    private let pollInterval: Duration
    /// 唤醒后最多查几次状态。`pollInterval × maxPollAttempts` 就是允许设备醒来的总时长；
    /// 500ms × 10 = 5 秒，能装进 `BLESyncCoordinator.connectionTimeoutSeconds` 的 40 秒预算
    /// （connect 10 + 安全握手 5 + 唤醒 ≤5 + 回放 15 = 35）。
    private let maxPollAttempts: Int
    private let sendCommand: SendCommand
    private let sleeper: Sleeper
    private var operation: Operation?
    private var timeoutTask: Task<Void, Never>?
    private var activeGeneration: UInt64?

    private init(
        responseTimeout: Duration = .seconds(2),
        pollInterval: Duration = .milliseconds(500),
        maxPollAttempts: Int = 10,
        sendCommand: SendCommand? = nil,
        sleeper: @escaping Sleeper = { try await Task.sleep(for: $0) }
    ) {
        self.responseTimeout = responseTimeout
        self.pollInterval = pollInterval
        self.maxPollAttempts = maxPollAttempts
        self.sendCommand = sendCommand ?? { command in
            try await BLEService.shared.sendDevicePowerCommand(command)
        }
        self.sleeper = sleeper
    }

    static func makeForTesting(
        responseTimeout: Duration = .seconds(2),
        pollInterval: Duration = .milliseconds(500),
        maxPollAttempts: Int = 10,
        sendCommand: @escaping SendCommand,
        sleeper: @escaping Sleeper = { try await Task.sleep(for: $0) }
    ) -> BLEDeviceWakeCoordinator {
        BLEDeviceWakeCoordinator(
            responseTimeout: responseTimeout,
            pollInterval: pollInterval,
            maxPollAttempts: maxPollAttempts,
            sendCommand: sendCommand,
            sleeper: sleeper
        )
    }

    /// 确保设备已进入可通信状态。**返回 false 时本次连接必须判失败并断开**——读不到
    /// 「正常运行」就不允许继续下发任何业务帧（2026-08-04 硬件团队定的语义）。
    ///
    /// 流程：读状态 →（休眠则）下发唤醒 → 间隔轮询读状态 → 必须读到 active 才放行。
    /// 唤醒命令是 fire-and-forget：设备可以不回应答，回了 App 也不据此判定已醒，
    /// **一切以后续 Query 读到的状态为准**。这样固件只需如实报告当前状态，
    /// 不必承诺「在真正能收数据之后才回 active」——那是固件很难自证的东西。
    ///
    /// 换代（断连后新连接）会让在途的握手立即放弃并返回 false。
    public func ensureAwake(connectionGeneration: UInt64) async -> Bool {
        activeGeneration = connectionGeneration
        state = .querying

        guard let query = await send(
            .query,
            timeout: responseTimeout,
            generation: connectionGeneration
        ) else {
            return failClosed("no answer to the power query", generation: connectionGeneration)
        }
        guard activeGeneration == connectionGeneration else { return false }
        guard query.status == .ok else {
            return failClosed(
                "device rejected the power query (\(query.status.message))",
                generation: connectionGeneration
            )
        }
        guard query.powerState == .lowPower else {
            state = .awake
            return true
        }

        state = .waking
        await sendWakeCommand(generation: connectionGeneration)
        guard activeGeneration == connectionGeneration else { return false }

        for attempt in 1...maxPollAttempts {
            do {
                try await sleeper(pollInterval)
            } catch {
                return false
            }
            guard activeGeneration == connectionGeneration else { return false }

            // 单次轮询无应答不算失败：设备正在醒来的过程中可能来不及回。继续下一次。
            guard let poll = await send(
                .query,
                timeout: responseTimeout,
                generation: connectionGeneration
            ) else {
                continue
            }
            guard activeGeneration == connectionGeneration else { return false }
            if poll.status == .ok, poll.powerState == .active {
                state = .awake
                Log.ble.debug("Device woke after \(attempt) poll(s)")
                return true
            }
        }

        return failClosed(
            "device stayed in low power after \(maxPollAttempts) polls",
            generation: connectionGeneration
        )
    }

    /// 唤醒是 fire-and-forget：不等应答，写失败也只记日志继续轮询——设备可能已经在醒了。
    private func sendWakeCommand(generation: UInt64) async {
        do {
            try await sendCommand(.wake)
        } catch {
            ErrorReporter.log(
                .sync(
                    component: "BLE Device Wake",
                    underlying: "0x25 wake write failed: \(error.localizedDescription)"
                ),
                context: "BLEDeviceWakeCoordinator.sendWakeCommand"
            )
        }
    }

    public func handleResponse(payload: Data) {
        let response: BLEDevicePowerResponse
        do {
            response = try BLEDevicePowerResponse(payload: payload)
        } catch {
            ErrorReporter.log(
                .sync(
                    component: "BLE Device Wake",
                    underlying: "invalid 0x25 response (\(payload.count) bytes)"
                ),
                context: "BLEDeviceWakeCoordinator.handleResponse"
            )
            resolveActiveOperation(with: nil)
            return
        }

        guard !response.isUnsolicited else {
            // 设备主动上报，不属于任何在途操作：只更新状态，不释放等待中的握手。
            state = response.powerState == .lowPower ? .observedSleep : .awake
            return
        }

        // 回显不匹配 = 上一条命令的迟到应答。必须丢弃，否则 query 的迟到包会释放 wake 的等待、
        // 让 App 误以为设备已醒。
        guard let current = operation, current.expectedEcho == response.commandEcho else { return }
        resolve(operationID: current.id, with: response)
    }

    /// 收到 `0x31 DeviceSleep` 时调用：设备在活链路上主动进入低功耗。
    ///
    /// 目前只记录状态，`performSync` 尚未据此重发唤醒——那一路的 `requestEventLogsIfNeeded()`
    /// 因屏障已 resolved 而不写任何字节，加了是空操作。真要补是在 presentation 写入之前，
    /// 且只在本状态为 `.observedSleep` 时才发帧，避免 keep-alive 下每轮同步变成 `0x25` 心跳风暴。
    public func handleObservedSleep() {
        state = .observedSleep
    }

    public func handleDisconnected() {
        activeGeneration = nil
        resolveActiveOperation(with: nil)
        state = .unknown
    }

    private func send(
        _ command: BLEDevicePowerCommand,
        timeout: Duration,
        generation: UInt64
    ) async -> BLEDevicePowerResponse? {
        let operationID = UUID()
        operation = Operation(
            id: operationID,
            expectedEcho: command.rawValue,
            generation: generation
        )

        do {
            try await sendCommand(command)
        } catch {
            ErrorReporter.log(
                .sync(
                    component: "BLE Device Wake",
                    underlying: "0x25 \(command) write failed: \(error.localizedDescription)"
                ),
                context: "BLEDeviceWakeCoordinator.send"
            )
            clearOperation(operationID)
            return nil
        }

        // 写 ACK 期间可能已换代，或 Notify 已经先到。
        guard var current = operation, current.id == operationID else { return nil }
        guard current.generation == generation, activeGeneration == generation else {
            clearOperation(operationID)
            return nil
        }
        if let received = current.received {
            clearOperation(operationID)
            return received
        }

        return await withCheckedContinuation { continuation in
            current.continuation = continuation
            operation = current
            scheduleTimeout(for: operationID, after: timeout)
        }
    }

    private func scheduleTimeout(for operationID: UUID, after timeout: Duration) {
        timeoutTask?.cancel()
        let sleeper = sleeper
        timeoutTask = Task { @MainActor [weak self] in
            do {
                try await sleeper(timeout)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.resolve(operationID: operationID, with: nil)
        }
    }

    private func resolve(operationID: UUID, with response: BLEDevicePowerResponse?) {
        guard let current = operation, current.id == operationID else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        operation = nil
        if let continuation = current.continuation {
            continuation.resume(returning: response)
        } else if let response {
            // 应答早于写 ACK 到达：还没有人在等，先存住让 send 回来取。
            var pending = current
            pending.received = response
            operation = pending
        }
    }

    private func resolveActiveOperation(with response: BLEDevicePowerResponse?) {
        guard let current = operation else { return }
        resolve(operationID: current.id, with: response)
    }

    private func clearOperation(_ operationID: UUID) {
        guard let current = operation, current.id == operationID else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        operation = nil
    }

    @discardableResult
    private func failClosed(_ reason: String, generation: UInt64) -> Bool {
        guard activeGeneration == generation else { return false }
        ErrorReporter.log(
            .sync(component: "BLE Device Wake", underlying: "device not ready — \(reason)"),
            context: "BLEDeviceWakeCoordinator.ensureAwake"
        )
        state = .failedToWake
        return false
    }
}
