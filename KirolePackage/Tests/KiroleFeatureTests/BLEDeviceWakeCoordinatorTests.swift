import Foundation
import Testing
@testable import KiroleFeature

@MainActor
@Suite("Device power handshake (0x25)", .serialized)
struct BLEDeviceWakeCoordinatorTests {
    private static func response(
        echo: UInt8,
        state: BLEDevicePowerState,
        status: UInt8 = 0x00
    ) -> Data {
        Data([echo, state.rawValue, status])
    }

    @Test("The power control frame uses byte 0x25 with a single command byte")
    func commandWireFormat() {
        #expect(BLEDataType.devicePowerControl.rawValue == 0x25)
        #expect(BLEDevicePowerCommand.query.payload == Data([0x00]))
        #expect(BLEDevicePowerCommand.wake.payload == Data([0x01]))
        #expect(
            BLESimpleEncoder.encode(
                type: BLEDataType.devicePowerControl.rawValue,
                payload: BLEDevicePowerCommand.wake.payload
            ).contains(0x25)
        )
    }

    @Test("A three-byte response carries the echo, power state and status")
    func responseParsing() throws {
        let active = try BLEDevicePowerResponse(payload: Self.response(echo: 0x00, state: .active))
        #expect(active.commandEcho == 0x00)
        #expect(active.powerState == .active)
        #expect(active.status == .ok)
        #expect(!active.isUnsolicited)

        let sleeping = try BLEDevicePowerResponse(
            payload: Self.response(echo: 0xFF, state: .lowPower)
        )
        #expect(sleeping.isUnsolicited)
        #expect(sleeping.powerState == .lowPower)

        let rejected = try BLEDevicePowerResponse(
            payload: Self.response(echo: 0x01, state: .lowPower, status: 0x01)
        )
        #expect(rejected.status == .unsupported)
    }

    @Test(
        "Malformed power responses are rejected",
        arguments: [
            Data(),
            Data([0x00, 0x00]),
            Data([0x00, 0x00, 0x00, 0x00]),
            Data([0x00, 0x02, 0x00])
        ]
    )
    func malformedResponseRejected(payload: Data) {
        #expect(throws: BLEDevicePowerResponseError.self) {
            try BLEDevicePowerResponse(payload: payload)
        }
    }

    @Test("An active device is not sent a wake command")
    func queryOnActiveDeviceSkipsWake() async {
        let recorder = CommandRecorder()
        let coordinator = BLEDeviceWakeCoordinator.makeForTesting(
            sendCommand: { await recorder.record($0) }
        )
        let handshake = Task { @MainActor in
            await coordinator.ensureAwake(connectionGeneration: 1)
        }

        await recorder.waitForCommandCount(1)
        coordinator.handleResponse(payload: Self.response(echo: 0x00, state: .active))
        await handshake.value

        #expect(await recorder.commands == [.query])
        #expect(coordinator.state == .awake)
    }

    @Test("A low-power device is woken and the handshake waits for active")
    func lowPowerQueryTriggersWakeAndWaitsForActive() async {
        let recorder = CommandRecorder()
        let coordinator = BLEDeviceWakeCoordinator.makeForTesting(
            sendCommand: { await recorder.record($0) }
        )
        let handshake = Task { @MainActor in
            await coordinator.ensureAwake(connectionGeneration: 2)
        }

        await recorder.waitForCommandCount(1)
        coordinator.handleResponse(payload: Self.response(echo: 0x00, state: .lowPower))
        await recorder.waitForCommandCount(2)
        #expect(coordinator.state == .waking)

        coordinator.handleResponse(payload: Self.response(echo: 0x01, state: .active))
        await handshake.value

        #expect(await recorder.commands == [.query, .wake])
        #expect(coordinator.state == .awake)
    }

    @Test("Firmware that never answers 0x25 fails open instead of blocking the connection")
    func silentFirmwareFailsOpen() async {
        // 现役固件不认识 0x25，会静默丢弃。握手必须超时后返回并放行——fail-closed 会让所有
        // 设备当场连不上。
        let recorder = CommandRecorder()
        let clock = ControlledWakeSleeper()
        let coordinator = BLEDeviceWakeCoordinator.makeForTesting(
            sendCommand: { await recorder.record($0) },
            sleeper: { duration in try await clock.sleep(for: duration) }
        )
        let handshake = Task { @MainActor in
            await coordinator.ensureAwake(connectionGeneration: 3)
        }

        await clock.waitUntilSleeping()
        await clock.advance()
        await handshake.value

        #expect(coordinator.state == .assumedAwake)
        // 查询超时后不再尝试唤醒：老固件每次连接只付一次这个税。
        #expect(await recorder.commands == [.query])
    }

    @Test("A failed write fails open immediately without waiting for the timeout")
    func writeFailureFailsOpenImmediately() async {
        let clock = ControlledWakeSleeper()
        let coordinator = BLEDeviceWakeCoordinator.makeForTesting(
            sendCommand: { _ in throw BLEError.disconnected },
            sleeper: { duration in try await clock.sleep(for: duration) }
        )

        await coordinator.ensureAwake(connectionGeneration: 4)

        #expect(coordinator.state == .assumedAwake)
    }

    @Test("A late query response cannot release the wake wait")
    func staleQueryResponseCannotReleaseWake() async {
        // CommandEcho 存在的理由：一次连接连发 query→wake，query 的迟到应答若被当成 wake 的
        // 应答，App 会以为设备已醒并立刻开始发业务帧。
        let recorder = CommandRecorder()
        let clock = ControlledWakeSleeper()
        let coordinator = BLEDeviceWakeCoordinator.makeForTesting(
            sendCommand: { await recorder.record($0) },
            sleeper: { duration in try await clock.sleep(for: duration) }
        )
        let handshake = Task { @MainActor in
            await coordinator.ensureAwake(connectionGeneration: 5)
        }

        await recorder.waitForCommandCount(1)
        coordinator.handleResponse(payload: Self.response(echo: 0x00, state: .lowPower))
        await recorder.waitForCommandCount(2)

        // 迟到的 query 应答（echo=0x00）声称设备是 active，但此刻在等的是 wake（echo=0x01）。
        coordinator.handleResponse(payload: Self.response(echo: 0x00, state: .active))
        #expect(coordinator.state == .waking)

        await clock.waitUntilSleeping()
        await clock.advance()
        await handshake.value

        #expect(coordinator.state == .assumedAwake)
    }

    @Test("Disconnecting abandons an in-flight handshake")
    func disconnectAbandonsHandshake() async {
        let recorder = CommandRecorder()
        let coordinator = BLEDeviceWakeCoordinator.makeForTesting(
            sendCommand: { await recorder.record($0) }
        )
        let handshake = Task { @MainActor in
            await coordinator.ensureAwake(connectionGeneration: 6)
        }

        await recorder.waitForCommandCount(1)
        coordinator.handleDisconnected()
        await handshake.value

        #expect(coordinator.state == .unknown)

        // 旧代次的迟到应答不得改动新连接的状态。
        coordinator.handleResponse(payload: Self.response(echo: 0x00, state: .active))
        #expect(coordinator.state == .unknown)
    }

    @Test("An unsolicited low-power report is recorded without releasing a handshake")
    func unsolicitedSleepReportMarksObservedSleep() {
        let coordinator = BLEDeviceWakeCoordinator.makeForTesting(sendCommand: { _ in })

        coordinator.handleResponse(payload: Self.response(echo: 0xFF, state: .lowPower))
        #expect(coordinator.state == .observedSleep)

        coordinator.handleResponse(payload: Self.response(echo: 0xFF, state: .active))
        #expect(coordinator.state == .awake)
    }

    @Test("A hardware sleep event marks the device as observed sleeping")
    func hardwareSleepEventMarksObservedSleep() {
        let coordinator = BLEDeviceWakeCoordinator.makeForTesting(sendCommand: { _ in })

        coordinator.handleObservedSleep()

        #expect(coordinator.state == .observedSleep)
    }

    @Test("Power control is writable while connected but not during the security handshake")
    func devicePowerControlWritePolicy() {
        // 钉死唤醒的位置：安全握手期只放行 0x7F，唤醒必须等 .connected。
        #expect(BLEWritePolicy.canWrite(
            state: .connected,
            packetType: BLEDataType.devicePowerControl.rawValue
        ))
        #expect(!BLEWritePolicy.canWrite(
            state: .connecting,
            packetType: BLEDataType.devicePowerControl.rawValue
        ))
    }
}

private actor CommandRecorder {
    private(set) var commands: [BLEDevicePowerCommand] = []
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func record(_ command: BLEDevicePowerCommand) {
        commands.append(command)
        let satisfied = waiters.filter { $0.count <= commands.count }
        waiters.removeAll { $0.count <= commands.count }
        satisfied.forEach { $0.continuation.resume() }
    }

    func waitForCommandCount(_ count: Int) async {
        if commands.count >= count { return }
        await withCheckedContinuation { continuation in
            waiters.append((count: count, continuation: continuation))
        }
    }
}

private actor ControlledWakeSleeper {
    private var continuation: CheckedContinuation<Void, Error>?
    private var waitingContinuations: [CheckedContinuation<Void, Never>] = []

    func sleep(for _: Duration) async throws {
        // Mirror real `Task.sleep`'s cancellation behavior: a cancelled caller must bail out
        // *before* claiming `continuation`. Without this check, a `send()` timeout task that
        // was already cancelled by an early real response (e.g. the query resolving before its
        // own timeout task got a chance to run) still reaches this call, overwrites
        // `continuation` with its own, and silently strands whatever later call (e.g. the wake
        // timeout) was actually being waited on — the coordinator hangs forever even though its
        // own logic is correct, because this mock let a dead task clobber shared state.
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            waitingContinuations.forEach { $0.resume() }
            waitingContinuations = []
        }
    }

    func waitUntilSleeping() async {
        if continuation != nil { return }
        await withCheckedContinuation { continuation in
            waitingContinuations.append(continuation)
        }
    }

    func advance() {
        continuation?.resume()
        continuation = nil
    }
}
