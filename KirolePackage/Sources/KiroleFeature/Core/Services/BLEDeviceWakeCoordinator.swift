import Foundation
import Observation

/// 每次连接在发送任何业务帧之前完成的功耗握手（`0x25`，协议 §4.24/§5.24）。
///
/// 客户要求硬件 BLE 常开：设备进入低功耗后连接仍然可达，所以「连上了」不等于「能收数据」。
/// App 先 query，若设备回 lowPower 再发 wake 并等它回到 active。
///
/// **整个流程 fail-open**：超时、写失败、老固件静默丢弃、设备明确拒绝，一律记 `ErrorReporter`
/// 后当作设备醒着继续。这与紧随其后的 `0x20` 回放屏障（fail-closed，15 秒判连接失败并断开）
/// 方向相反，是刻意的——丢失离线动作会造成数据错乱，而「查不到功耗状态」的正确降级就是继续
/// （设备至少已经能维持 BLE 连接）。若这里也 fail-closed，不认识 `0x25` 的现役固件会当场全部
/// 连不上。
///
/// 状态只代表当前 BLE 连接内的硬件状态；断连恢复为 unknown，不落盘。
@MainActor
@Observable
public final class BLEDeviceWakeCoordinator {
    public enum State: Sendable, Equatable {
        case unknown
        case querying
        case waking
        /// 设备明确回了 `PowerState=active`。
        case awake
        /// fail-open 的结果：超时 / 老固件无应答 / 写失败 / 设备拒绝。
        /// 语义上等同 `awake`（后续照常发数据），分开是为了让日志和硬件面板能区分
        /// 「确认醒着」与「猜它醒着」。
        case assumedAwake
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

    /// 查询超时。这是**老固件每次连接都要付的固定税**——不认识 `0x25` 的固件不会回任何东西，
    /// 必然吃满这段等待（随后 fail-open 跳过 wake，不会再吃第二次）。2 秒已是典型 BLE 往返的
    /// 几十倍。
    private let queryTimeout: Duration
    /// 唤醒超时。设备只要还能回 BLE 就不在 deep sleep（那种情况连接本身就没了，走重连路径），
    /// 所以这里等的是任务调度延迟而非重启，3 秒有充足余量。
    private let wakeTimeout: Duration
    private let sendCommand: SendCommand
    private let sleeper: Sleeper
    private var operation: Operation?
    private var timeoutTask: Task<Void, Never>?
    private var activeGeneration: UInt64?

    private init(
        queryTimeout: Duration = .seconds(2),
        wakeTimeout: Duration = .seconds(3),
        sendCommand: SendCommand? = nil,
        sleeper: @escaping Sleeper = { try await Task.sleep(for: $0) }
    ) {
        self.queryTimeout = queryTimeout
        self.wakeTimeout = wakeTimeout
        self.sendCommand = sendCommand ?? { command in
            try await BLEService.shared.sendDevicePowerCommand(command)
        }
        self.sleeper = sleeper
    }

    static func makeForTesting(
        queryTimeout: Duration = .seconds(2),
        wakeTimeout: Duration = .seconds(3),
        sendCommand: @escaping SendCommand,
        sleeper: @escaping Sleeper = { try await Task.sleep(for: $0) }
    ) -> BLEDeviceWakeCoordinator {
        BLEDeviceWakeCoordinator(
            queryTimeout: queryTimeout,
            wakeTimeout: wakeTimeout,
            sendCommand: sendCommand,
            sleeper: sleeper
        )
    }

    /// 确保设备能接收业务帧。无返回值——fail-open 意味着调用方没有需要分支的失败。
    ///
    /// 换代（断连后新连接）会让在途的握手静默放弃：本代次之外的应答不改状态，也不重挂超时。
    public func ensureAwake(connectionGeneration: UInt64) async {
        activeGeneration = connectionGeneration
        state = .querying

        guard let query = await send(
            .query,
            timeout: queryTimeout,
            generation: connectionGeneration
        ) else {
            failOpen("no answer to the power query", generation: connectionGeneration)
            return
        }
        guard activeGeneration == connectionGeneration else { return }
        guard query.status == .ok else {
            failOpen(
                "device rejected the power query (\(query.status.message))",
                generation: connectionGeneration
            )
            return
        }
        guard query.powerState == .lowPower else {
            state = .awake
            return
        }

        state = .waking
        guard let wake = await send(
            .wake,
            timeout: wakeTimeout,
            generation: connectionGeneration
        ) else {
            failOpen("no answer to the wake command", generation: connectionGeneration)
            return
        }
        guard activeGeneration == connectionGeneration else { return }
        guard wake.status == .ok, wake.powerState == .active else {
            failOpen(
                "device stayed in low power after wake (\(wake.status.message))",
                generation: connectionGeneration
            )
            return
        }
        state = .awake
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

    private func failOpen(_ reason: String, generation: UInt64) {
        guard activeGeneration == generation else { return }
        ErrorReporter.log(
            .sync(component: "BLE Device Wake", underlying: "assuming awake — \(reason)"),
            context: "BLEDeviceWakeCoordinator.ensureAwake"
        )
        state = .assumedAwake
    }
}
