@preconcurrency import CoreBluetooth
import Foundation
import os

// MARK: - CBCentralManagerDelegate

extension BLEService: CBCentralManagerDelegate {
    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                if autoReconnectEffective, connectionState == .disconnected {
                    _ = await attemptAutoReconnect()
                }
            case .poweredOff:
                connectionState = .error("Bluetooth is turned off")
            case .unauthorized:
                connectionState = .error("Bluetooth permission denied")
            case .unsupported:
                connectionState = .error("Bluetooth not supported")
            default:
                break
            }
        }
    }

    nonisolated public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let deviceID = peripheral.identifier
        let deviceName = peripheral.name ?? "Unknown Device"
        let rssiValue = RSSI.intValue

        Task { @MainActor in
            if requiresSecureChannel {
                if await deviceIdentityStore.isBlocked(deviceID) {
                    return
                }

                if await deviceIdentityStore.hasTrustedDevices(),
                   !(await deviceIdentityStore.isTrusted(deviceID)) {
                    return
                }
            }

            peripheralCache[deviceID] = peripheral

            let device = BLEDevice(
                id: deviceID,
                name: deviceName,
                rssi: rssiValue
            )

            if !discoveredDevices.contains(where: { $0.id == device.id }) {
                discoveredDevices.append(device)
            }
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // manager 建于 queue: .main（initialize），delegate 回调必在主线程，assumeIsolated 安全。
        // 准入 = 代次门（杀"投递→Task 执行"间换代的旧回调）+ 外设身份（杀换代后才投递的
        // 跨外设残留回调）；同一外设的晚投递回调原理上不可分辨，见 BLEConnectionPolicy。
        let generation = MainActor.assumeIsolated { self.connectGeneration }
        Task { @MainActor in
            guard shouldProcessCallback(generationAtDelivery: generation, peripheralID: peripheral.identifier) else { return }
            connectedPeripheral = peripheral
            peripheral.delegate = self
            peripheral.discoverServices([KiroleBLEUUIDs.serviceUUID])
        }
    }

    nonisolated public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        let generation = MainActor.assumeIsolated { self.connectGeneration }
        Task { @MainActor in
            // 迟到的失败回调被丢时状态留在 .disconnected（同为 idle，不锁新连接），仅损失错误文案。
            guard shouldProcessCallback(generationAtDelivery: generation, peripheralID: peripheral.identifier) else { return }
            connectionState = .error(error?.localizedDescription ?? "Connection failed")
            connectCompletion?(.failure(.connectionFailed(error)))
            connectCompletion = nil
        }
    }

    nonisolated public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        let generation = MainActor.assumeIsolated { self.connectGeneration }
        Task { @MainActor in
            // 旧连接的迟到断连事件不得清理新尝试：代次已换 ⇒ 新尝试从 idle 起步，旧世界的
            // 收尾已由"把状态送回 idle"的那条路径做完，此处 cleanup 只会误清新尝试的状态、
            // 错误完成它的 connectCompletion，自动重连也会与在飞的新尝试打架——整体跳过。
            // 身份不符（含 cleanup 已跑完、connectedPeripheral 已空）同理。
            guard shouldProcessCallback(generationAtDelivery: generation, peripheralID: peripheral.identifier) else { return }
            // 断连只中断传输，Focus 服务保留活跃会话和连续计时。
            FocusSessionService.shared.handleDeviceDisconnected()

            // cleanup 会把 Wi-Fi 调试协调器重置为 unknown，故重连判定也必须先快照。
            let wasIntentional = isIntentionalDisconnect
            let shouldAutoReconnect = autoReconnectEffective

            // Notify OTA coordinator so it can transition to awaitingReboot
            // without waiting for a 0x18 response that will never arrive.
            if isPendingOTAReboot {
                BLEOTACoordinator.shared.handleExpectedDisconnect()
            }

            cleanup()

            guard BLEConnectionPolicy.shouldAutoReconnect(
                isIntentional: wasIntentional,
                autoReconnectEnabled: shouldAutoReconnect
            ) else { return }

            // Apple 警告：不要在 didDisconnect 回调里立刻 connect（会卡 bad state），延迟后再发起。
            reconnectTask?.cancel()
            reconnectTask = Task { @MainActor in
                try? await Task.sleep(for: Timing.reconnectDelay)
                guard !Task.isCancelled else { return }
                await attemptAutoReconnect()
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEService: CBPeripheralDelegate {
    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let services = peripheral.services
        let generation = MainActor.assumeIsolated { self.connectGeneration }

        Task { @MainActor in
            guard shouldProcessCallback(generationAtDelivery: generation, peripheralID: peripheral.identifier) else { return }
            guard error == nil,
                  let service = services?.first(where: { $0.uuid == KiroleBLEUUIDs.serviceUUID }) else {
                connectCompletion?(.failure(.serviceNotFound))
                connectCompletion = nil
                return
            }

            peripheral.discoverCharacteristics(
                [KiroleBLEUUIDs.writeCharacteristicUUID, KiroleBLEUUIDs.notifyCharacteristicUUID],
                for: service
            )
        }
    }

    nonisolated public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        let characteristics = service.characteristics
        let peripheralID = peripheral.identifier
        let peripheralName = peripheral.name
        let generation = MainActor.assumeIsolated { self.connectGeneration }

        Task { @MainActor in
            guard shouldProcessCallback(generationAtDelivery: generation, peripheralID: peripheralID) else { return }
            guard error == nil, let chars = characteristics else {
                connectCompletion?(.failure(.characteristicNotFound))
                connectCompletion = nil
                return
            }

            for characteristic in chars {
                if characteristic.uuid == KiroleBLEUUIDs.writeCharacteristicUUID {
                    writeCharacteristic = characteristic
                } else if characteristic.uuid == KiroleBLEUUIDs.notifyCharacteristicUUID {
                    notifyCharacteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }

            if writeCharacteristic != nil, notifyCharacteristic != nil {
                pendingConnectedPeripheralID = peripheralID
                pendingConnectedPeripheralName = peripheralName ?? "Kirole Device"
                Task { @MainActor in
                    // 内层 Task 有独立调度跳变，准入需再验一次。
                    guard self.shouldProcessCallback(generationAtDelivery: generation, peripheralID: peripheralID) else { return }
                    if self.requiresSecureChannel {
                        await self.startSecurityHandshake(peripheral: peripheral)
                    } else {
                        await self.completeSecureConnection()
                    }
                }
            } else {
                connectCompletion?(.failure(.characteristicNotFound))
                connectCompletion = nil
            }
        }
    }

    nonisolated public func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task { @MainActor in
            // 必须先消掉迟到 ACK 记账，再看当前槽——顺序反了会用旧 ACK 完成新写入，
            // 或在空槽期漏消计数、吞掉下一次写入的真 ACK。
            if staleWriteAckFilter.shouldDropIncomingAck() {
                return
            }

            guard writeCompletion != nil else {
                return
            }

            if let error = error {
                writeCompletion?(.failure(.writeFailed(error)))
            } else {
                writeCompletion?(.success(()))
            }
            writeCompletion = nil
            activeWriteID = nil
        }
    }

    nonisolated public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let data = characteristic.value
        let generation = MainActor.assumeIsolated { self.connectGeneration }

        Task { @MainActor in
            // 代次在连接内恒定，稳态通知不受影响；只丢"新尝试已开始后才轮到执行"的旧连接残包
            // 与非当前跟踪外设的残留通知。
            guard shouldProcessCallback(generationAtDelivery: generation, peripheralID: peripheral.identifier) else { return }
            // notify 层错误（ATT error / 加密失败 / 断连时 pending value 清空）原先被静默丢弃，
            // 硬件团队看来像 App 完全没收到。拆分 guard 单独上报，区分链路层错误与解析失败。
            if let error {
                ErrorReporter.log(
                    .sync(component: "BLE Notify", underlying: error.localizedDescription),
                    context: "BLEService.didUpdateValueFor"
                )
                return
            }
            guard let receivedData = data else { return }
            if AppBuildEnvironment.showsHardwareDebugTools {
                let firstByteText = receivedData.first.map { String(format: "%02X", $0) } ?? "??"
                Self.bleLogger.notice("BLE RX len=\(receivedData.count, privacy: .public) firstByte=0x\(firstByteText, privacy: .public)")
            }
            do {
                guard let message = try decodeReceivedMessage(receivedData) else { return }

                if requiresSecureChannel, message.type == BLEDataType.securityHandshake.rawValue {
                    try securityManager.validateHandshakeResponsePayload(message.payload)
                    await completeSecureConnection()
                    return
                }

                if !requiresSecureChannel, message.type == BLEDataType.securityHandshake.rawValue {
                    return
                }

                await BLEEventHandler.handleReceivedPayload(message, service: self)
            } catch {
                ErrorReporter.log(error, context: "BLEService.didUpdateValueFor")
                connectionState = .error(error.localizedDescription)
                if requiresSecureChannel,
                   !securityManager.isSessionEstablished,
                   let peripheralID = pendingConnectedPeripheralID {
                    await deviceIdentityStore.block(peripheralID)
                }
                connectCompletion?(.failure(.securityHandshakeFailed(error.localizedDescription)))
                connectCompletion = nil
                centralManager?.cancelPeripheralConnection(peripheral)
            }
        }
    }
}
