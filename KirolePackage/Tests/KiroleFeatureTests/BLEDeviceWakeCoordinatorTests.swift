import Foundation
import Testing
@testable import KiroleFeature

/// 文件级常量：`Sleeper` 是 `@Sendable`，闭包体不能访问 MainActor 隔离的静态属性。
private let testPollInterval = Duration.milliseconds(10)
private let testResponseTimeout = Duration.seconds(1)

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

    /// 按 duration 区分两种等待：轮询间隔永远立即推进；应答超时按 `answersTimeOut` 决定
    /// 是立即触发还是实质不触发。
    ///
    /// 刻意用 `Task.sleep` 而不是自定义 continuation actor——后者不响应协作式取消，
    /// 一个已被 cancel 的超时任务会迟到执行并顶掉后来者正在等的 continuation，导致死锁。
    private static func sleeper(answersTimeOut: Bool) -> BLEDeviceWakeCoordinator.Sleeper {
        { duration in
            if duration == testPollInterval { return }
            if answersTimeOut { return }
            try await Task.sleep(for: .seconds(30))
        }
    }

    private static func makeCoordinator(
        recorder: CommandRecorder,
        answersTimeOut: Bool = false,
        maxPollAttempts: Int = 3
    ) -> BLEDeviceWakeCoordinator {
        BLEDeviceWakeCoordinator.makeForTesting(
            responseTimeout: testResponseTimeout,
            pollInterval: testPollInterval,
            maxPollAttempts: maxPollAttempts,
            sendCommand: { await recorder.record($0) },
            sleeper: Self.sleeper(answersTimeOut: answersTimeOut)
        )
    }

    // MARK: - Wire format

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

    // MARK: - Handshake

    @Test("An already-running device is not sent a wake command")
    func runningDeviceSkipsWake() async {
        let recorder = CommandRecorder()
        let coordinator = Self.makeCoordinator(recorder: recorder)
        let handshake = Task { @MainActor in
            await coordinator.ensureAwake(connectionGeneration: 1)
        }

        await recorder.waitForCommandCount(1)
        coordinator.handleResponse(payload: Self.response(echo: 0x00, state: .active))

        #expect(await handshake.value)
        #expect(await recorder.commands == [.query])
        #expect(coordinator.state == .awake)
    }

    @Test("A sleeping device is woken and then polled until it reports running")
    func sleepingDeviceIsPolledUntilRunning() async {
        // 硬件定的语义：唤醒命令下发后不等它的应答，靠间隔轮询读状态，读到 active 才放行。
        let recorder = CommandRecorder()
        let coordinator = Self.makeCoordinator(recorder: recorder)
        let handshake = Task { @MainActor in
            await coordinator.ensureAwake(connectionGeneration: 2)
        }

        await recorder.waitForCommandCount(1)
        coordinator.handleResponse(payload: Self.response(echo: 0x00, state: .lowPower))

        // 第一次轮询：还没醒。
        await recorder.waitForCommandCount(3)
        #expect(coordinator.state == .waking)
        coordinator.handleResponse(payload: Self.response(echo: 0x00, state: .lowPower))

        // 第二次轮询：醒了。
        await recorder.waitForCommandCount(4)
        coordinator.handleResponse(payload: Self.response(echo: 0x00, state: .active))

        #expect(await handshake.value)
        #expect(await recorder.commands == [.query, .wake, .query, .query])
        #expect(coordinator.state == .awake)
    }

    @Test("Firmware that never answers 0x25 fails the connection")
    func silentFirmwareFailsClosed() async {
        // flag-day：硬件要求「必须读到正常运行才能继续通信」。不认识 0x25 的固件连不上，
        // 这是刻意的——固件按协议 v2.18.0 施工后才可用。
        let recorder = CommandRecorder()
        let coordinator = Self.makeCoordinator(recorder: recorder, answersTimeOut: true)

        let didWake = await coordinator.ensureAwake(connectionGeneration: 3)

        #expect(!didWake)
        #expect(coordinator.state == .failedToWake)
        // 首次查询就无应答，不该再发唤醒。
        #expect(await recorder.commands == [.query])
    }

    @Test("A device that never wakes fails after the poll budget is spent")
    func deviceThatNeverWakesFailsAfterPollBudget() async {
        let recorder = CommandRecorder()
        let coordinator = Self.makeCoordinator(recorder: recorder, maxPollAttempts: 3)
        let handshake = Task { @MainActor in
            await coordinator.ensureAwake(connectionGeneration: 4)
        }

        await recorder.waitForCommandCount(1)
        coordinator.handleResponse(payload: Self.response(echo: 0x00, state: .lowPower))

        for expected in 3...5 {
            await recorder.waitForCommandCount(expected)
            coordinator.handleResponse(payload: Self.response(echo: 0x00, state: .lowPower))
        }

        #expect(!(await handshake.value))
        #expect(coordinator.state == .failedToWake)
        #expect(await recorder.commands == [.query, .wake, .query, .query, .query])
    }

    @Test("A rejected power query fails the connection without waking")
    func rejectedQueryFailsClosed() async {
        let recorder = CommandRecorder()
        let coordinator = Self.makeCoordinator(recorder: recorder)
        let handshake = Task { @MainActor in
            await coordinator.ensureAwake(connectionGeneration: 5)
        }

        await recorder.waitForCommandCount(1)
        coordinator.handleResponse(
            payload: Self.response(echo: 0x00, state: .lowPower, status: 0x01)
        )

        #expect(!(await handshake.value))
        #expect(coordinator.state == .failedToWake)
        #expect(await recorder.commands == [.query])
    }

    @Test("A wake acknowledgement cannot satisfy a status poll")
    func wakeAcknowledgementCannotSatisfyAPoll() async {
        // 唤醒是 fire-and-forget，但设备**可以**回一帧。CommandEcho 必须把它挡在轮询之外，
        // 否则设备一句「收到唤醒了」就会被当成「我已经在运行」。
        let recorder = CommandRecorder()
        let coordinator = Self.makeCoordinator(recorder: recorder, maxPollAttempts: 2)
        let handshake = Task { @MainActor in
            await coordinator.ensureAwake(connectionGeneration: 6)
        }

        await recorder.waitForCommandCount(1)
        coordinator.handleResponse(payload: Self.response(echo: 0x00, state: .lowPower))
        await recorder.waitForCommandCount(3)

        // 设备对 wake 的应答（echo=0x01）声称 active——不得释放正在等的 query（echo=0x00）。
        coordinator.handleResponse(payload: Self.response(echo: 0x01, state: .active))
        #expect(coordinator.state == .waking)

        coordinator.handleResponse(payload: Self.response(echo: 0x00, state: .lowPower))
        await recorder.waitForCommandCount(4)
        coordinator.handleResponse(payload: Self.response(echo: 0x00, state: .lowPower))

        #expect(!(await handshake.value))
        #expect(coordinator.state == .failedToWake)
    }

    @Test("Disconnecting abandons an in-flight handshake")
    func disconnectAbandonsHandshake() async {
        let recorder = CommandRecorder()
        let coordinator = Self.makeCoordinator(recorder: recorder)
        let handshake = Task { @MainActor in
            await coordinator.ensureAwake(connectionGeneration: 7)
        }

        await recorder.waitForCommandCount(1)
        coordinator.handleDisconnected()

        #expect(!(await handshake.value))
        #expect(coordinator.state == .unknown)

        // 旧代次的迟到应答不得改动新连接的状态。
        coordinator.handleResponse(payload: Self.response(echo: 0x00, state: .active))
        #expect(coordinator.state == .unknown)
    }

    // MARK: - Unsolicited reports

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
