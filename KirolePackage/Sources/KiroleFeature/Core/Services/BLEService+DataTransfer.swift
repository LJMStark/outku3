@preconcurrency import CoreBluetooth
import Foundation
import os

enum BLEPresentationDestinationError: Error, Sendable {
    case changed
}

// MARK: - App-to-device data transfer

extension BLEService {
    var taskListSnapshotDestinationID: String {
        connectedDeviceID?.uuidString ?? ""
    }

    /// 发送宠物状态到 E-ink 设备
    public func sendPetStatus(_ pet: Pet, companionCharacter: CompanionCharacter, customActive: Bool) async throws {
        let data = BLEDataEncoder.encodePetStatus(pet, companionCharacter: companionCharacter, customActive: customActive)
        try await writeData(type: .petStatus, data: data)
    }

    /// 发送天气信息到 E-ink 设备
    public func sendWeather(_ weather: Weather) async throws {
        let data = BLEDataEncoder.encodeWeather(weather)
        try await writeData(type: .weather, data: data)
    }

    /// 同步当前时间到 E-ink 设备
    public func syncTime() async throws {
        let data = BLEDataEncoder.encodeCurrentTime()
        try await writeData(type: .time, data: data)
    }

    // syncAllData / sendTaskList / sendSchedule（DayPack 之前时代的逐帧同步路径）已删：
    // 零调用者的死路径，且把 sendWeather 一起"藏死"过（2026-07-04 审计 D2/F1）。
    // 0x02/0x03 帧仍是协议的一部分，encodeTaskList/encodeSchedule 及其格式测试保留。

    public func updateLastSyncTime(_ date: Date) {
        lastSyncTime = date
    }

    // MARK: - Day Pack Transfer

    /// 发送 Day Pack 到 E-ink 设备
    public func sendDayPack(
        _ dayPack: DayPack,
        expectedTaskStateVersion: UInt64,
        expectedDestinationID: String? = nil
    ) async throws {
        try await withTaskStateMessageGate {
            let validatePresentationState: PacketWriteValidator = {
                guard AppState.shared.taskStateVersion == expectedTaskStateVersion else {
                    throw BLEError.staleTaskSnapshot
                }
                if let expectedDestinationID,
                   self.taskListSnapshotDestinationID != expectedDestinationID {
                    throw BLEPresentationDestinationError.changed
                }
            }
            try validatePresentationState()
            let latestTasks = DayPackGenerator.topTaskSummaries(
                from: AppState.shared.tasks,
                screenSize: hardwareScreenSize
            )
            guard TaskListSnapshotContent.isEquivalent(dayPack.topTasks, latestTasks) else {
                throw BLEError.staleTaskSnapshot
            }
            let data = BLEDataEncoder.encodeDayPack(dayPack, screenSize: hardwareScreenSize)
            try await writeData(
                type: .dayPack,
                data: data,
                // The message gate, rate limiter and every packet write can suspend. Rechecking
                // here keeps every 0x10 chunk on the destination that raised the task action.
                validateBeforeWrite: validatePresentationState
            )
        }
    }

    /// Serializes the versioned task acknowledgement with complete DayPack messages. RequestRefresh
    /// uses it immediately; live Complete/Skip uses it only after the final DayPack arrives.
    func withTaskStateMessageGate(
        _ operation: @MainActor () async throws -> Void
    ) async throws {
        try await taskStateMessageGate.acquire()
        do {
            try await operation()
        } catch {
            await taskStateMessageGate.release()
            throw error
        }
        await taskStateMessageGate.release()
    }

    func writeTaskListSnapshotAckPayload(
        _ payload: Data,
        expectedTaskStateVersion: UInt64?
    ) async throws {
        try await writeTaskListSnapshotAckPayload(
            payload,
            expectedTaskStateVersion: expectedTaskStateVersion,
            beforeFirstWrite: {}
        )
    }

    func writeTaskListSnapshotAckPayload(
        _ payload: Data,
        expectedTaskStateVersion: UInt64?,
        beforeFirstWrite: @escaping @MainActor @Sendable () async throws -> Void
    ) async throws {
        let validateTaskState: PacketWriteValidator?
        if let expectedTaskStateVersion {
            validateTaskState = {
                guard AppState.shared.taskStateVersion == expectedTaskStateVersion else {
                    throw BLEError.staleTaskSnapshot
                }
            }
        } else {
            validateTaskState = nil
        }
        try await writeData(
            type: .taskListSnapshotAck,
            data: payload,
            validateBeforeWrite: validateTaskState,
            beforeFirstWrite: beforeFirstWrite
        )
    }

    /// 发送 Task In 页面数据到 E-ink 设备。只应由 BLEEventHandler 在收到 0x10 EnterTaskIn 事件后调用。
    func sendTaskInPage(
        _ taskInPage: TaskInPageData,
        expectedTaskStateVersion: UInt64
    ) async throws {
        try await withTaskStateMessageGate {
            let validateTaskState: PacketWriteValidator = {
                guard AppState.shared.taskStateVersion == expectedTaskStateVersion else {
                    throw BLEError.staleTaskSnapshot
                }
            }
            try validateTaskState()
            let data = BLEDataEncoder.encodeTaskInPage(taskInPage)
            try await writeData(
                type: .taskInPage,
                data: data,
                validateBeforeWrite: validateTaskState
            )
        }
    }

    /// Sends one complete task-library transaction. Firmware stages the reassembled payload and
    /// makes it visible only after the transaction CRC and every record validate.
    public func sendTaskLibraryTransaction(
        _ transaction: TaskLibraryTransaction,
        expectedTaskStateVersion: UInt64,
        validateAdditionalSnapshot: @escaping @MainActor @Sendable () throws -> Void = {}
    ) async throws {
        let validateSnapshot: PacketWriteValidator = {
            guard AppState.shared.taskStateVersion == expectedTaskStateVersion else {
                throw BLEError.staleTaskSnapshot
            }
            try validateAdditionalSnapshot()
        }
        try validateSnapshot()
        let payload = try TaskLibraryCodec.encodeTransaction(transaction)
        try await writeData(
            type: .taskLibraryTransaction,
            data: payload,
            validateBeforeWrite: validateSnapshot
        )
    }

    /// 发送设备模式到 E-ink 设备
    public func sendDeviceMode(_ mode: DeviceMode) async throws {
        let data = BLEDataEncoder.encodeDeviceMode(mode)
        try await writeData(type: .deviceMode, data: data)
    }

    /// 发送智能提醒到 E-ink 设备
    public func sendSmartReminder(
        text: String,
        urgency: ReminderUrgency,
        petMood: PetMood
    ) async throws {
        let data = BLEDataEncoder.encodeSmartReminder(text: text, urgency: urgency, petMood: petMood)
        _ = try await HardwarePagePresentationGate.shared.performPresentationWrite(
            droppingIfPageTransactionIntervened: false
        ) {
            try await self.writeData(type: .smartReminder, data: data)
        }
    }

    /// 推送专注状态和能量瓶子数到 E-ink 设备（所有构建均执行）
    public func sendFocusStatus(
        phase: FocusPhase,
        energyBottles: Int,
        elapsedMinutes: Int,
        taskTitle: String?,
        segmentMinutes: Int
    ) async throws {
        let payload = BLEDataEncoder.encodeFocusStatus(
            phase: phase,
            energyBottles: energyBottles,
            elapsedMinutes: elapsedMinutes,
            taskTitle: taskTitle,
            segmentMinutes: segmentMinutes
        )
        _ = try await HardwarePagePresentationGate.shared.performPresentationWrite(
            droppingIfPageTransactionIntervened: true
        ) {
            try await self.writeData(type: .focusStatus, data: payload)
        }
    }

    /// 请求设备回传 Event Log（增量）
    public func requestEventLogs(since timestamp: UInt32) async throws {
        let data = BLEDataEncoder.encodeEventLogRequest(since: timestamp)
        try await writeData(type: .eventLogRequest, data: data)
    }

    /// 发起事件补传请求(0x20)。返回值仅表示请求帧是否成功写出（不代表设备已回传——回传走后续
    /// 0x21 eventLogBatch 路径）。补传是核心功能，调用方据此判定整轮同步成败。
    @discardableResult
    public func requestEventLogsIfNeeded() async -> Bool {
        let since = await localStorage.loadLastEventLogTimestamp() ?? 0
        do {
            try await requestEventLogs(since: since)
            return true
        } catch {
            ErrorReporter.log(
                .sync(component: "BLE Event Logs", underlying: error.localizedDescription),
                context: "BLEService.requestEventLogsIfNeeded"
            )
            return false
        }
    }

    /// 推送场景解锁到 E-ink 设备。
    /// v2.5.11：从旧 `0xAA 01 01` 开发命令升级为 `0x17` 业务帧，经 `writeData` 发送——
    /// dev 模式走简单包、secure 模式自动 SecureEnvelope 封装，**两种模式均可发**
    /// （旧开发命令在配置 `BLE_SHARED_SECRET` 后会被禁用，场景切换会静默失败）。
    public func sendDisplayScene(_ scene: DisplayScene) async throws {
        let payload = BLEDataEncoder.encodeSceneUnlock(scene)
        _ = try await HardwarePagePresentationGate.shared.performPresentationWrite(
            droppingIfPageTransactionIntervened: true
        ) {
            try await self.writeData(type: .sceneUnlock, data: payload)
        }
    }

    /// v2.7 暂存 KRI 头像。进度只统计 KRI 文件字节（不含 29B v4 元数据、BLE 分片头与
    /// SecureEnvelope）；每个 `.withResponse` ACK 后更新，不会把排队字节算成已发送。
    public func sendCustomAvatarKRIFrame(
        operationID: UInt32,
        avatarID: UUID,
        kriData: Data,
        progress: @escaping @MainActor @Sendable (_ sentBytes: Int, _ totalBytes: Int) -> Void
    ) async throws {
        let payload = try BLEDataEncoder.encodeCustomAvatarFrame(
            operationID: operationID,
            avatarID: avatarID,
            kriData: kriData
        )
        progress(0, kriData.count)
        try await writeData(type: .customAvatarFrame, data: payload, progress: { sentPayloadBytes, _ in
            let sentKRIBytes = min(
                kriData.count,
                max(0, sentPayloadBytes - CustomAvatarFrameV4Codec.headerLength)
            )
            progress(sentKRIBytes, kriData.count)
        })
    }

    /// 写成功只表示命令到达特征值；设备落盘结果由 0x22 回包经
    /// `onAvatarControlResult` 交给 AppState。
    public func sendAvatarControl(_ command: AvatarControlCommand) async throws {
        try await writeData(
            type: .avatarControl,
            data: BLEDataEncoder.encodeAvatarControlCommand(command)
        )
    }

    /// 推送屏保金句/明信片到 E-ink 设备。
    /// v2.5.10：从旧 `0xAA 01 02` 开发命令升级为 `0x16` 业务帧，经 `writeData` 发送——
    /// dev 模式走简单包、secure 模式自动 SecureEnvelope 封装，**两种模式均可发**
    /// （旧开发命令在配置 `BLE_SHARED_SECRET` 后会被禁用，屏保会静默发不出去）。
    public func sendScreensaverConfig(_ config: ScreensaverConfig) async throws {
        let payload = BLEDataEncoder.encodeScreensaver(config)
        _ = try await HardwarePagePresentationGate.shared.performPresentationWrite(
            droppingIfPageTransactionIntervened: false
        ) {
            try await self.writeData(type: .screensaver, data: payload)
        }
    }

    /// Sends OTAReboot (0x18) with zero payload. In secure mode, writeData
    /// automatically wraps this in SecureEnvelope (0x7E) — no special handling needed.
    public func sendOTAReboot() async throws {
        try await writeData(type: .otaReboot, data: Data())
    }

    /// 发送 Wi-Fi PC Debug (0x19) 命令。统一走 writeData，secure 模式自动封装为 0x7E。
    public func sendWiFiDebugCommand(_ command: BLEWiFiDebugCommand) async throws {
        try await writeData(type: .wifiDebugMode, data: command.payload)
    }

    /// 发送 WiFiAvatarSession (0x1A) 会话命令（close/open/query + OperationID）。
    /// 统一走 writeData，secure 模式自动封装为 0x7E。设备经 Notify 回 0x1A 应答，
    /// 由 `WiFiAvatarSessionCoordinator.handleResponse` 处理。
    public func sendWiFiAvatarSessionCommand(_ request: WiFiAvatarSessionRequest) async throws {
        try await writeData(
            type: .wifiAvatarSession,
            data: WiFiAvatarSessionCodec.encodeRequest(request)
        )
    }

    // MARK: - Packet writing

    private func writeData(
        type: BLEDataType,
        data: Data,
        validateBeforeWrite: PacketWriteValidator? = nil,
        beforeFirstWrite: (@MainActor @Sendable () async throws -> Void)? = nil,
        progress: (@MainActor @Sendable (_ sentBytes: Int, _ totalBytes: Int) -> Void)? = nil
    ) async throws {
        guard connectionState.isConnected,
              let characteristic = writeCharacteristic,
              let peripheral = connectedPeripheral else {
            throw BLEError.notConnected
        }

        guard requiresSecureChannel else {
            try await writeUnsignedData(
                type: type,
                data: data,
                peripheral: peripheral,
                characteristic: characteristic,
                validateBeforeWrite: validateBeforeWrite,
                beforeFirstWrite: beforeFirstWrite,
                progress: progress
            )
            return
        }

        guard securityManager.isSessionEstablished else {
            throw BLEError.securityHandshakeFailed("Secure BLE session not established")
        }

        let maxLength = peripheral.maximumWriteValueLength(for: .withResponse)

        if type == .customAvatarFrame {
            let plainPackets = try securityManager.packetizeForSecureTransport(
                type: type.rawValue,
                messageId: allocateMessageID(),
                payload: data,
                maxWriteLength: maxLength
            )
            inFlightChunkedTransfers += 1
            defer { inFlightChunkedTransfers -= 1 }
            var sentBytes = 0
            for (index, plainPacket) in plainPackets.enumerated() {
                try Task.checkCancellation()
                // 必须临写前即时签名。整批预签会让 4–5 分钟传输后半段的 issuedAt
                // 超过 SecureEnvelope 的 120 秒接收窗口。
                let packet = try securityManager.secureChunkPacket(
                    type: type.rawValue,
                    plainPacket: plainPacket,
                    maxWriteLength: maxLength
                )
                try await writePacket(
                    packet,
                    peripheral: peripheral,
                    characteristic: characteristic,
                    validateBeforeWrite: validateBeforeWrite,
                    beforeWrite: index == 0 ? beforeFirstWrite : nil
                )
                sentBytes += chunkPayloadLength(plainPacket)
                progress?(min(sentBytes, data.count), data.count)
            }
            return
        }

        let securePayload = try securityManager.securePayload(type: type.rawValue, payload: data)

        if shouldUseChunkedPacket(type: type, payloadSize: securePayload.count, maxWriteLength: maxLength) {
            let maxChunkPayloadSize = maxLength - BLEPacketizer.headerSize
            let packets = try BLEPacketizer.packetize(
                type: BLEDataType.secureData.rawValue,
                messageId: allocateMessageID(),
                payload: securePayload,
                maxChunkSize: maxChunkPayloadSize
            )
            inFlightChunkedTransfers += 1
            defer { inFlightChunkedTransfers -= 1 }
            for (index, packet) in packets.enumerated() {
                // 外层任务被取消（如切换伴侣废弃旧头像流）时立即停发——写锁只串行单个
                // packet，不检查取消的话两条 2000 片消息会逐片交错、旧流可能反杀新流。
                try Task.checkCancellation()
                try await writePacket(
                    packet,
                    peripheral: peripheral,
                    characteristic: characteristic,
                    validateBeforeWrite: validateBeforeWrite,
                    beforeWrite: index == 0 ? beforeFirstWrite : nil
                )
            }
            return
        }

        let packet = BLESimpleEncoder.encode(type: BLEDataType.secureData.rawValue, payload: securePayload)
        try await writePacket(
            packet,
            peripheral: peripheral,
            characteristic: characteristic,
            validateBeforeWrite: validateBeforeWrite,
            beforeWrite: beforeFirstWrite
        )
    }

    private func writeUnsignedData(
        type: BLEDataType,
        data: Data,
        peripheral: CBPeripheral,
        characteristic: CBCharacteristic,
        validateBeforeWrite: PacketWriteValidator?,
        beforeFirstWrite: (@MainActor @Sendable () async throws -> Void)?,
        progress: (@MainActor @Sendable (_ sentBytes: Int, _ totalBytes: Int) -> Void)?
    ) async throws {
        let maxLength = peripheral.maximumWriteValueLength(for: .withResponse)

        if shouldUseChunkedPacket(type: type, payloadSize: data.count, maxWriteLength: maxLength) {
            let maxChunkPayloadSize = maxLength - BLEPacketizer.headerSize
            let packets = try BLEPacketizer.packetize(
                type: type.rawValue,
                messageId: allocateMessageID(),
                payload: data,
                maxChunkSize: maxChunkPayloadSize
            )
            inFlightChunkedTransfers += 1
            defer { inFlightChunkedTransfers -= 1 }
            var sentBytes = 0
            for (index, packet) in packets.enumerated() {
                // 同 writeData：任务取消即停发，防多条大帧流逐片交错。
                try Task.checkCancellation()
                try await writePacket(
                    packet,
                    peripheral: peripheral,
                    characteristic: characteristic,
                    validateBeforeWrite: validateBeforeWrite,
                    beforeWrite: index == 0 ? beforeFirstWrite : nil
                )
                sentBytes += chunkPayloadLength(packet)
                progress?(min(sentBytes, data.count), data.count)
            }
            return
        }

        let packet = BLESimpleEncoder.encode(type: type.rawValue, payload: data)
        try await writePacket(
            packet,
            peripheral: peripheral,
            characteristic: characteristic,
            validateBeforeWrite: validateBeforeWrite,
            beforeWrite: beforeFirstWrite
        )
        progress?(data.count, data.count)
    }

    private func chunkPayloadLength(_ packet: Data) -> Int {
        guard packet.count >= BLEPacketizer.headerSize else { return 0 }
        return Int(packet.bigEndianUInt16(at: 7))
    }

    // 旧 `writeDevelopmentDisplayPacket`（0xAA 开发命令出口，secure 下被禁用）已于 v2.5.11 移除：
    // 屏保（0x16）与场景解锁（0x17）均已改走 `writeData` 业务帧，不再有 0xAA 出站命令。

    private func shouldUseChunkedPacket(type: BLEDataType, payloadSize: Int, maxWriteLength: Int) -> Bool {
        if payloadSize + 3 > maxWriteLength { return true }
        switch type {
        case .dayPack, .taskInPage, .customAvatarFrame, .taskLibraryTransaction:
            return true
        default:
            return false
        }
    }

    private func allocateMessageID() -> UInt16 {
        let current = nextMessageId
        nextMessageId = (nextMessageId == UInt16.max) ? 1 : (nextMessageId + 1)
        return current
    }

    func writePacket(
        _ packet: Data,
        peripheral: CBPeripheral,
        characteristic: CBCharacteristic,
        validateBeforeWrite: PacketWriteValidator? = nil,
        beforeWrite: (@MainActor @Sendable () async throws -> Void)? = nil
    ) async throws {
        if AppBuildEnvironment.showsHardwareDebugTools {
            let typeText = packet.first.map { String(format: "%02X", $0) } ?? "??"
            Self.bleLogger.notice("BLE TX type=0x\(typeText, privacy: .public) len=\(packet.count, privacy: .public)")
        }
        try await writeGate.acquire()

        do {
            // HIGH-2: acquireWritePermit now throws CancellationError, allowing clean exit
            try await rateLimiter.acquireWritePermit()

            // HIGH-3: if disconnect fired while we were waiting for the rate-limiter permit,
            // writeCompletion was cleared and no ACK will ever arrive — bail early.
            guard let packetType = packet.first,
                  BLEWritePolicy.canWrite(state: connectionState, packetType: packetType) else {
                throw BLEError.disconnected
            }

            // Validation belongs after the write gate and rate limiter: both suspend. For a
            // packetized DayPack this is the last point before each chunk is committed to
            // CoreBluetooth. If tasks changed, the remaining chunks are withheld and firmware
            // never receives a complete old 0x10 message to render.
            do {
                try validateBeforeWrite?()
            } catch {
                if beforeWrite != nil,
                   let bleError = error as? BLEError,
                   case .staleTaskSnapshot = bleError {
                    throw TaskListSnapshotWriteError.staleBeforeFirstWrite
                }
                throw error
            }
            if let beforeWrite {
                try await beforeWrite()
                // Persisting the attempt marker suspends while this packet still owns the write
                // gate. Revalidate once more, then synchronously hand the first packet to
                // CoreBluetooth without another suspension point.
                guard let packetType = packet.first,
                      BLEWritePolicy.canWrite(
                        state: connectionState,
                        packetType: packetType
                      ) else {
                    throw BLEError.disconnected
                }
                do {
                    try validateBeforeWrite?()
                } catch {
                    if let bleError = error as? BLEError,
                       case .staleTaskSnapshot = bleError {
                        throw TaskListSnapshotWriteError.staleBeforeFirstWrite
                    }
                    throw error
                }
            }

            // HIGH-1: strong capture — no retain cycle (@MainActor task, singleton service)
            let writeID = UUID()
            activeWriteID = writeID
            let timeoutTask = Task { @MainActor in
                try await Task.sleep(for: .seconds(5))
                guard self.activeWriteID == writeID else { return }
                // 被弃写的 ACK 之后可能迟到；记账让 didWriteValueFor 丢掉它，
                // 否则它会误完成下一次写入的 continuation。
                self.staleWriteAckFilter.markAbandonedWrite()
                self.writeCompletion?(.failure(.writeTimeout))
                self.writeCompletion = nil
                self.activeWriteID = nil
            }

            defer { timeoutTask.cancel() }

            try await withCheckedThrowingContinuation { continuation in
                writeCompletion = { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                peripheral.writeValue(packet, for: characteristic, type: .withResponse)
            }
        } catch {
            await writeGate.release()
            throw error
        }

        await writeGate.release()
    }
}
