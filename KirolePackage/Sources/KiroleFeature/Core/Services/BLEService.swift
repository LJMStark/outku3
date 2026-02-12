@preconcurrency import CoreBluetooth
import Foundation

// MARK: - BLE Device

/// E-ink 设备信息
public struct BLEDevice: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let rssi: Int
    public var isConnected: Bool

    public init(id: UUID, name: String, rssi: Int, isConnected: Bool = false) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.isConnected = isConnected
    }
}

// MARK: - BLE Connection State

public enum BLEConnectionState: Sendable, Equatable {
    case disconnected
    case scanning
    case connecting
    case connected
    case error(String)

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

// MARK: - BLE Data Types

/// 发送到 E-ink 设备的数据类型
public enum BLEDataType: UInt8, Sendable {
    case petStatus = 0x01
    case taskList = 0x02
    case schedule = 0x03
    case weather = 0x04
    case time = 0x05
    case dayPack = 0x10
    case taskInPage = 0x11
    case deviceMode = 0x12
    case eventLogRequest = 0x20
    case eventLogBatch = 0x21
}

// MARK: - BLE Service UUIDs

/// Kirole E-ink 设备的 BLE 服务和特征 UUID
private enum KiroleBLEUUIDs {
    static let serviceUUID = CBUUID(string: "0000FFE0-0000-1000-8000-00805F9B34FB")
    static let writeCharacteristicUUID = CBUUID(string: "0000FFE1-0000-1000-8000-00805F9B34FB")
    static let notifyCharacteristicUUID = CBUUID(string: "0000FFE2-0000-1000-8000-00805F9B34FB")
}

// MARK: - BLE Service

/// BLE 服务，管理与 E-ink 硬件设备的通信
@Observable
@MainActor
public final class BLEService: NSObject {
    public static let shared = BLEService()

    // MARK: - Published State

    public private(set) var connectionState: BLEConnectionState = .disconnected
    public private(set) var discoveredDevices: [BLEDevice] = []
    public private(set) var connectedDevice: BLEDevice?
    public private(set) var lastSyncTime: Date?

    /// Callback for handling received event logs from device
    public var onEventLogReceived: ((EventLog) -> Void)?

    // MARK: - Private Properties

    private var centralManager: CBCentralManager?
    private var connectedPeripheral: CBPeripheral?
    private var peripheralCache: [UUID: CBPeripheral] = [:]
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var packetAssembler = BLEPacketAssembler()

    private let localStorage = LocalStorage.shared

    private var scanCompletion: (([BLEDevice]) -> Void)?
    private var connectCompletion: ((Result<Void, BLEError>) -> Void)?
    private var writeCompletion: ((Result<Void, BLEError>) -> Void)?

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let lastConnectedDeviceID = "lastConnectedBLEDeviceID"
        static let autoReconnect = "bleAutoReconnect"
    }

    // MARK: - Settings

    public var autoReconnect: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.autoReconnect) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.autoReconnect) }
    }

    private var lastConnectedDeviceID: UUID? {
        get {
            guard let string = UserDefaults.standard.string(forKey: Keys.lastConnectedDeviceID) else {
                return nil
            }
            return UUID(uuidString: string)
        }
        set {
            UserDefaults.standard.set(newValue?.uuidString, forKey: Keys.lastConnectedDeviceID)
        }
    }

    // MARK: - Initialization

    private override init() {
        super.init()
        UserDefaults.standard.register(defaults: [Keys.autoReconnect: true])
    }

    /// 初始化 BLE 中央管理器
    public func initialize() {
        guard centralManager == nil else { return }
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Scanning

    /// 扫描附近的 Kirole E-ink 设备
    public func scanForDevices(timeout: TimeInterval = 10) async throws -> [BLEDevice] {
        initialize()

        guard let manager = centralManager, manager.state == .poweredOn else {
            throw BLEError.bluetoothNotAvailable
        }

        connectionState = .scanning
        discoveredDevices = []
        peripheralCache = [:]

        return await withCheckedContinuation { continuation in
            scanCompletion = { devices in
                continuation.resume(returning: devices)
            }

            manager.scanForPeripherals(
                withServices: [KiroleBLEUUIDs.serviceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )

            // 超时后停止扫描
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                self.stopScanning()
            }
        }
    }

    /// 停止扫描
    public func stopScanning() {
        centralManager?.stopScan()

        if connectionState == .scanning {
            connectionState = .disconnected
        }

        scanCompletion?(discoveredDevices)
        scanCompletion = nil
    }

    // MARK: - Connection

    /// 连接到指定设备
    public func connect(to device: BLEDevice) async throws {
        guard let manager = centralManager, manager.state == .poweredOn else {
            throw BLEError.bluetoothNotAvailable
        }

        guard let peripheral = peripheralCache[device.id] else {
            throw BLEError.deviceNotFound
        }

        connectionState = .connecting

        try await withCheckedThrowingContinuation { continuation in
            connectCompletion = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            manager.connect(peripheral, options: nil)

            // 连接超时
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(15))
                if self.connectionState == .connecting {
                    self.connectCompletion?(.failure(.connectionTimeout))
                    self.connectCompletion = nil
                    manager.cancelPeripheralConnection(peripheral)
                    self.connectionState = .disconnected
                }
            }
        }
    }

    /// 断开当前连接
    public func disconnect() {
        guard let peripheral = connectedPeripheral else { return }
        centralManager?.cancelPeripheralConnection(peripheral)
        cleanup()
    }

    /// 扫描并连接上次连接的设备，若不可用则连接第一个设备
    public func connectToPreferredDevice(timeout: TimeInterval = 10) async throws {
        let devices = try await scanForDevices(timeout: timeout)
        guard !devices.isEmpty else {
            throw BLEError.deviceNotFound
        }

        let device = devices.first(where: { $0.id == lastConnectedDeviceID }) ?? devices.first
        if let device {
            try await connect(to: device)
        }
    }

    /// 尝试自动重连，返回是否成功
    public func attemptAutoReconnect() async -> Bool {
        guard autoReconnect else { return false }

        do {
            try await connectToPreferredDevice(timeout: 5)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Data Transfer

    /// 发送宠物状态到 E-ink 设备
    public func sendPetStatus(_ pet: Pet) async throws {
        let data = BLEDataEncoder.encodePetStatus(pet)
        try await writeData(type: .petStatus, data: data)
    }

    /// 发送任务列表到 E-ink 设备
    public func sendTaskList(_ tasks: [TaskItem]) async throws {
        let data = BLEDataEncoder.encodeTaskList(tasks)
        try await writeData(type: .taskList, data: data)
    }

    /// 发送日程到 E-ink 设备
    public func sendSchedule(_ events: [CalendarEvent]) async throws {
        let data = BLEDataEncoder.encodeSchedule(events)
        try await writeData(type: .schedule, data: data)
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

    /// 同步所有数据到 E-ink 设备
    public func syncAllData(pet: Pet, tasks: [TaskItem], events: [CalendarEvent], weather: Weather) async throws {
        try await sendPetStatus(pet)
        try await sendTaskList(tasks)
        try await sendSchedule(events)
        try await sendWeather(weather)
        try await syncTime()
        lastSyncTime = Date()
    }

    public func updateLastSyncTime(_ date: Date) {
        lastSyncTime = date
    }

    // MARK: - Day Pack Transfer

    /// 发送 Day Pack 到 E-ink 设备
    public func sendDayPack(_ dayPack: DayPack) async throws {
        let data = BLEDataEncoder.encodeDayPack(dayPack)
        try await writeData(type: .dayPack, data: data)
    }

    /// 发送 Task In 页面数据到 E-ink 设备
    public func sendTaskInPage(_ taskInPage: TaskInPageData) async throws {
        let data = BLEDataEncoder.encodeTaskInPage(taskInPage)
        try await writeData(type: .taskInPage, data: data)
    }

    /// 发送设备模式到 E-ink 设备
    public func sendDeviceMode(_ mode: DeviceMode) async throws {
        let data = BLEDataEncoder.encodeDeviceMode(mode)
        try await writeData(type: .deviceMode, data: data)
    }

    /// 请求设备回传 Event Log（增量）
    public func requestEventLogs(since timestamp: UInt32) async throws {
        let data = BLEDataEncoder.encodeEventLogRequest(since: timestamp)
        try await writeData(type: .eventLogRequest, data: data)
    }

    public func requestEventLogsIfNeeded() async {
        let since = await localStorage.loadLastEventLogTimestamp() ?? 0
        try? await requestEventLogs(since: since)
    }

    // MARK: - Private Methods

    private func writeData(type: BLEDataType, data: Data) async throws {
        guard connectionState.isConnected,
              let characteristic = writeCharacteristic,
              let peripheral = connectedPeripheral else {
            throw BLEError.notConnected
        }

        let packet = BLESimpleEncoder.encode(type: type.rawValue, payload: data)
        let maxLength = peripheral.maximumWriteValueLength(for: .withResponse)

        var offset = 0
        while offset < packet.count {
            let end = min(offset + maxLength, packet.count)
            let chunk = packet.subdata(in: offset..<end)
            try await writePacket(chunk, peripheral: peripheral, characteristic: characteristic)
            offset = end
        }
    }

    private func writePacket(
        _ packet: Data,
        peripheral: CBPeripheral,
        characteristic: CBCharacteristic
    ) async throws {
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
    }

    private func cleanup() {
        connectedPeripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        connectedDevice = nil
        connectionState = .disconnected
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEService: CBCentralManagerDelegate {
    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                if autoReconnect {
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
        Task { @MainActor in
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
        Task { @MainActor in
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
        Task { @MainActor in
            // 设备断开时结束活跃的专注会话
            FocusSessionService.shared.handleDeviceDisconnected()

            cleanup()
            if autoReconnect {
                _ = await attemptAutoReconnect()
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEService: CBPeripheralDelegate {
    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let services = peripheral.services

        Task { @MainActor in
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

        Task { @MainActor in
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

            if writeCharacteristic != nil {
                connectionState = .connected
                connectedDevice = BLEDevice(
                    id: peripheralID,
                    name: peripheralName ?? "Kirole Device",
                    rssi: 0,
                    isConnected: true
                )
                lastConnectedDeviceID = peripheralID
                connectCompletion?(.success(()))
                connectCompletion = nil

                Task { @MainActor in
                    await self.requestEventLogsIfNeeded()
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
            if let error = error {
                writeCompletion?(.failure(.writeFailed(error)))
            } else {
                writeCompletion?(.success(()))
            }
            writeCompletion = nil
        }
    }

    nonisolated public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        let data = characteristic.value

        Task { @MainActor in
            guard error == nil, let receivedData = data else { return }

            // Try simple 2-byte header decoder first (hardware spec v1.1.0)
            if let message = BLESimpleDecoder.decode(receivedData) {
                BLEEventHandler.handleReceivedPayload(message, service: self)
            }
            // Fall back to chunked packet assembler for multi-packet messages
            else if let message = packetAssembler.append(packetData: receivedData) {
                BLEEventHandler.handleReceivedPayload(message, service: self)
            }
            // Fall back to raw event log record parsing
            else if let eventLog = BLEEventHandler.parseEventLogRecord(from: receivedData) {
                BLEEventHandler.handleEventLogs([eventLog], service: self)
            }
        }
    }
}

// MARK: - BLE Errors

public enum BLEError: LocalizedError, Sendable {
    case bluetoothNotAvailable
    case deviceNotFound
    case connectionTimeout
    case connectionFailed(Error?)
    case notConnected
    case serviceNotFound
    case characteristicNotFound
    case writeFailed(Error?)

    public var errorDescription: String? {
        switch self {
        case .bluetoothNotAvailable:
            return "Bluetooth is not available"
        case .deviceNotFound:
            return "Device not found"
        case .connectionTimeout:
            return "Connection timed out"
        case .connectionFailed(let error):
            return "Connection failed: \(error?.localizedDescription ?? "Unknown error")"
        case .notConnected:
            return "Not connected to device"
        case .serviceNotFound:
            return "BLE service not found"
        case .characteristicNotFound:
            return "BLE characteristic not found"
        case .writeFailed(let error):
            return "Write failed: \(error?.localizedDescription ?? "Unknown error")"
        }
    }
}
