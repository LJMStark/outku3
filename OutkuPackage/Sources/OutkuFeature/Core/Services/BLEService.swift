@preconcurrency import CoreBluetooth
import Foundation

// MARK: - Data Extension for BLE Encoding

private extension Data {
    /// 追加带长度前缀的字符串数据（截断到指定最大长度）
    mutating func appendString(_ string: String, maxLength: Int) {
        let stringData = string.data(using: .utf8) ?? Data()
        append(UInt8(Swift.min(stringData.count, maxLength)))
        append(stringData.prefix(maxLength))
    }
}

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
}

// MARK: - BLE Service UUIDs

/// Outku E-ink 设备的 BLE 服务和特征 UUID
private enum OutkuBLEUUIDs {
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

    // MARK: - Private Properties

    private var centralManager: CBCentralManager?
    private var connectedPeripheral: CBPeripheral?
    private var peripheralCache: [UUID: CBPeripheral] = [:]
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?

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

    /// 扫描附近的 Outku E-ink 设备
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
                withServices: [OutkuBLEUUIDs.serviceUUID],
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

        return try await withCheckedThrowingContinuation { continuation in
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

    /// 尝试重新连接上次连接的设备
    public func attemptAutoReconnect() async {
        guard autoReconnect, let deviceID = lastConnectedDeviceID else { return }

        do {
            let devices = try await scanForDevices(timeout: 5)
            if let device = devices.first(where: { $0.id == deviceID }) {
                try await connect(to: device)
            }
        } catch {
            // 自动重连失败，静默处理
        }
    }

    // MARK: - Data Transfer

    /// 发送宠物状态到 E-ink 设备
    public func sendPetStatus(_ pet: Pet) async throws {
        let data = encodePetStatus(pet)
        try await writeData(type: .petStatus, data: data)
    }

    /// 发送任务列表到 E-ink 设备
    public func sendTaskList(_ tasks: [TaskItem]) async throws {
        let data = encodeTaskList(tasks)
        try await writeData(type: .taskList, data: data)
    }

    /// 发送日程到 E-ink 设备
    public func sendSchedule(_ events: [CalendarEvent]) async throws {
        let data = encodeSchedule(events)
        try await writeData(type: .schedule, data: data)
    }

    /// 发送天气信息到 E-ink 设备
    public func sendWeather(_ weather: Weather) async throws {
        let data = encodeWeather(weather)
        try await writeData(type: .weather, data: data)
    }

    /// 同步当前时间到 E-ink 设备
    public func syncTime() async throws {
        let data = encodeCurrentTime()
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

    // MARK: - Private Methods

    private func writeData(type: BLEDataType, data: Data) async throws {
        guard connectionState.isConnected,
              let characteristic = writeCharacteristic,
              let peripheral = connectedPeripheral else {
            throw BLEError.notConnected
        }

        // 构建数据包：[类型(1字节)] + [长度(2字节)] + [数据]
        var packet = Data()
        packet.append(type.rawValue)
        let length = UInt16(data.count)
        packet.append(contentsOf: withUnsafeBytes(of: length.bigEndian) { Array($0) })
        packet.append(data)

        return try await withCheckedThrowingContinuation { continuation in
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

    // MARK: - Data Encoding

    private func encodePetStatus(_ pet: Pet) -> Data {
        var data = Data()
        data.appendString(pet.name, maxLength: 20)
        data.append(pet.mood.rawValue.first?.asciiValue ?? 0)
        data.append(pet.stage.rawValue.first?.asciiValue ?? 0)
        data.append(UInt8(min(Int(pet.progress * 100), 255)))
        return data
    }

    private func encodeTaskList(_ tasks: [TaskItem]) -> Data {
        var data = Data()
        let todayTasks = tasks.filter { $0.dueDate.map { Calendar.current.isDateInToday($0) } ?? false }
        data.append(UInt8(min(todayTasks.count, 10)))

        for task in todayTasks.prefix(10) {
            data.appendString(task.title, maxLength: 30)
            data.append(task.isCompleted ? 1 : 0)
        }
        return data
    }

    private func encodeSchedule(_ events: [CalendarEvent]) -> Data {
        var data = Data()
        let todayEvents = events.filter { Calendar.current.isDateInToday($0.startTime) }
        data.append(UInt8(min(todayEvents.count, 8)))

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        for event in todayEvents.prefix(8) {
            data.appendString(event.title, maxLength: 25)
            data.append(formatter.string(from: event.startTime).data(using: .utf8) ?? Data())
        }
        return data
    }

    private func encodeWeather(_ weather: Weather) -> Data {
        var data = Data()
        let temp = Int8(clamping: weather.temperature)
        data.append(contentsOf: withUnsafeBytes(of: temp) { Array($0) })
        data.appendString(weather.condition.rawValue, maxLength: 15)
        return data
    }

    private func encodeCurrentTime() -> Data {
        var data = Data()
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: Date()
        )
        data.append(UInt8((components.year ?? 2024) - 2000))
        data.append(UInt8(components.month ?? 1))
        data.append(UInt8(components.day ?? 1))
        data.append(UInt8(components.hour ?? 0))
        data.append(UInt8(components.minute ?? 0))
        data.append(UInt8(components.second ?? 0))
        return data
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEService: CBCentralManagerDelegate {
    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                if autoReconnect {
                    await attemptAutoReconnect()
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
            peripheral.discoverServices([OutkuBLEUUIDs.serviceUUID])
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
            cleanup()
            if autoReconnect {
                await attemptAutoReconnect()
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
                  let service = services?.first(where: { $0.uuid == OutkuBLEUUIDs.serviceUUID }) else {
                connectCompletion?(.failure(.serviceNotFound))
                connectCompletion = nil
                return
            }

            peripheral.discoverCharacteristics(
                [OutkuBLEUUIDs.writeCharacteristicUUID, OutkuBLEUUIDs.notifyCharacteristicUUID],
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
                if characteristic.uuid == OutkuBLEUUIDs.writeCharacteristicUUID {
                    writeCharacteristic = characteristic
                } else if characteristic.uuid == OutkuBLEUUIDs.notifyCharacteristicUUID {
                    notifyCharacteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }

            if writeCharacteristic != nil {
                connectionState = .connected
                connectedDevice = BLEDevice(
                    id: peripheralID,
                    name: peripheralName ?? "Outku Device",
                    rssi: 0,
                    isConnected: true
                )
                lastConnectedDeviceID = peripheralID
                connectCompletion?(.success(()))
                connectCompletion = nil
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
            handleReceivedData(receivedData)
        }
    }

    @MainActor
    private func handleReceivedData(_ data: Data) {
        // 处理从 E-ink 设备接收的数据
        // 可以扩展为处理设备状态、按钮事件等
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
