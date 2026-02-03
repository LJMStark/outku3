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
    case dayPack = 0x10
    case taskInPage = 0x11
    case deviceMode = 0x12
}

// MARK: - BLE Service UUIDs

/// Kiro E-ink 设备的 BLE 服务和特征 UUID
private enum KiroBLEUUIDs {
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

    /// 扫描附近的 Kiro E-ink 设备
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
                withServices: [KiroBLEUUIDs.serviceUUID],
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

    // MARK: - Day Pack Transfer

    /// 发送 Day Pack 到 E-ink 设备
    public func sendDayPack(_ dayPack: DayPack) async throws {
        let data = encodeDayPack(dayPack)
        try await writeData(type: .dayPack, data: data)
    }

    /// 发送 Task In 页面数据到 E-ink 设备
    public func sendTaskInPage(_ taskInPage: TaskInPageData) async throws {
        let data = encodeTaskInPage(taskInPage)
        try await writeData(type: .taskInPage, data: data)
    }

    /// 发送设备模式到 E-ink 设备
    public func sendDeviceMode(_ mode: DeviceMode) async throws {
        var data = Data()
        data.append(mode == .interactive ? 0x00 : 0x01)
        try await writeData(type: .deviceMode, data: data)
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

    private func encodeDayPack(_ dayPack: DayPack) -> Data {
        var data = Data()

        // Header
        let dateComponents = Calendar.current.dateComponents([.year, .month, .day], from: dayPack.date)
        data.append(UInt8((dateComponents.year ?? 2024) - 2000))
        data.append(UInt8(dateComponents.month ?? 1))
        data.append(UInt8(dateComponents.day ?? 1))

        // Device mode
        data.append(dayPack.deviceMode == .interactive ? 0x00 : 0x01)

        // Focus challenge flag
        data.append(dayPack.focusChallengeEnabled ? 0x01 : 0x00)

        // Page 1: Start of Day
        data.appendString(dayPack.morningGreeting, maxLength: 50)
        data.appendString(dayPack.dailySummary, maxLength: 60)
        data.appendString(dayPack.firstItem, maxLength: 40)

        // Page 2: Overview
        data.appendString(dayPack.currentScheduleSummary ?? "", maxLength: 30)
        data.appendString(dayPack.companionPhrase, maxLength: 40)

        // Top tasks (max 3)
        data.append(UInt8(min(dayPack.topTasks.count, 3)))
        for task in dayPack.topTasks.prefix(3) {
            data.appendString(task.id, maxLength: 36)
            data.appendString(task.title, maxLength: 30)
            data.append(task.isCompleted ? 0x01 : 0x00)
            data.append(UInt8(task.priority))
        }

        // Page 4: Settlement
        data.append(UInt8(dayPack.settlementData.tasksCompleted))
        data.append(UInt8(dayPack.settlementData.tasksTotal))
        let points = UInt16(min(dayPack.settlementData.pointsEarned, 65535))
        data.append(contentsOf: withUnsafeBytes(of: points.bigEndian) { Array($0) })
        data.append(UInt8(dayPack.settlementData.streakDays))
        data.appendString(dayPack.settlementData.summaryMessage, maxLength: 50)
        data.appendString(dayPack.settlementData.encouragementMessage, maxLength: 50)

        return data
    }

    private func encodeTaskInPage(_ taskInPage: TaskInPageData) -> Data {
        var data = Data()
        data.appendString(taskInPage.taskId, maxLength: 36)
        data.appendString(taskInPage.taskTitle, maxLength: 40)
        data.appendString(taskInPage.taskDescription ?? "", maxLength: 100)
        data.appendString(taskInPage.estimatedDuration ?? "", maxLength: 10)
        data.appendString(taskInPage.encouragement, maxLength: 50)
        data.append(taskInPage.focusChallengeActive ? 0x01 : 0x00)
        return data
    }

    // MARK: - Event Log Parsing

    private func parseEventLog(from data: Data) -> EventLog? {
        guard data.count >= 2 else { return nil }

        let eventTypeByte = data[0]
        guard let eventType = EventLogType(rawByte: eventTypeByte) else { return nil }

        var taskId: String?
        var timestamp: Date = Date()

        if data.count > 2 {
            let taskIdLength = Int(data[1])
            if data.count >= 2 + taskIdLength {
                let taskIdData = data.subdata(in: 2..<(2 + taskIdLength))
                taskId = String(data: taskIdData, encoding: .utf8)

                let timestampOffset = 2 + taskIdLength
                if data.count >= timestampOffset + 4 {
                    let timestampData = data.subdata(in: timestampOffset..<(timestampOffset + 4))
                    let timestampInt = timestampData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
                    timestamp = Date(timeIntervalSince1970: TimeInterval(timestampInt))
                }
            }
        }

        return EventLog(
            eventType: eventType,
            taskId: taskId,
            timestamp: timestamp
        )
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
            peripheral.discoverServices([KiroBLEUUIDs.serviceUUID])
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
                  let service = services?.first(where: { $0.uuid == KiroBLEUUIDs.serviceUUID }) else {
                connectCompletion?(.failure(.serviceNotFound))
                connectCompletion = nil
                return
            }

            peripheral.discoverCharacteristics(
                [KiroBLEUUIDs.writeCharacteristicUUID, KiroBLEUUIDs.notifyCharacteristicUUID],
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
                if characteristic.uuid == KiroBLEUUIDs.writeCharacteristicUUID {
                    writeCharacteristic = characteristic
                } else if characteristic.uuid == KiroBLEUUIDs.notifyCharacteristicUUID {
                    notifyCharacteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }

            if writeCharacteristic != nil {
                connectionState = .connected
                connectedDevice = BLEDevice(
                    id: peripheralID,
                    name: peripheralName ?? "Kiro Device",
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
        // 解析 Event Log 并通知回调
        if let eventLog = parseEventLog(from: data) {
            // 处理专注会话相关事件
            handleFocusSessionEvent(eventLog)

            // 通知外部回调
            onEventLogReceived?(eventLog)
        }
    }

    /// 处理专注会话相关事件
    @MainActor
    private func handleFocusSessionEvent(_ eventLog: EventLog) {
        let focusService = FocusSessionService.shared

        switch eventLog.eventType {
        case .enterTaskIn:
            // 进入任务 - 开始专注会话
            if let taskId = eventLog.taskId {
                // 从 AppState 获取任务标题
                let taskTitle = AppState.shared.tasks.first { $0.id == taskId }?.title ?? "Unknown Task"
                focusService.startSession(taskId: taskId, taskTitle: taskTitle)
            }

        case .completeTask:
            // 完成任务 - 结束专注会话
            if let taskId = eventLog.taskId {
                focusService.completeTask(taskId: taskId)
            }

        case .skipTask:
            // 跳过任务 - 结束专注会话
            if let taskId = eventLog.taskId {
                focusService.skipTask(taskId: taskId)
            }

        default:
            break
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
