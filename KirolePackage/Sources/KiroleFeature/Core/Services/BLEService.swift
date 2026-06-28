@preconcurrency import CoreBluetooth
import Foundation
import os

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

// MARK: - BLE Security Mode

public enum BLESecurityMode: Sendable, Equatable {
    case development
    case secure

    public var displayTitle: String {
        switch self {
        case .development:
            return "Development Mode"
        case .secure:
            return "Secure Mode"
        }
    }

    public var detailText: String {
        switch self {
        case .development:
            return "Unsigned BLE transport is enabled for pre-integration development."
        case .secure:
            return "BLE v2 secure handshake and signed envelopes are enabled."
        }
    }

    public var sourceText: String {
        switch self {
        case .development:
            return "Source: BLE_SHARED_SECRET not configured"
        case .secure:
            return "Source: BLE_SHARED_SECRET configured"
        }
    }
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
    private static let bleLogger = Logger(subsystem: "com.kirole.app", category: "BLE")

    // MARK: - Published State

    public private(set) var connectionState: BLEConnectionState = .disconnected
    public private(set) var discoveredDevices: [BLEDevice] = []
    public private(set) var connectedDevice: BLEDevice?
    public private(set) var lastSyncTime: Date?

    /// 上一轮整轮同步是否失败。lastSyncTime 只在成功时更新，连续失败时它会无声变旧——
    /// 这个标志让 Settings 硬件面板能把"同步失败了"和"还没到同步窗口"区分开。
    public internal(set) var lastSyncFailed = false
    /// Last known device battery level (0-100). Updated on DeviceWake and LowBattery events.
    /// nil until the device reports a level.
    public internal(set) var deviceBatteryLevel: Int?

    // MARK: - Private Properties

    private var centralManager: CBCentralManager?
    private var connectedPeripheral: CBPeripheral?
    private var peripheralCache: [UUID: CBPeripheral] = [:]
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var packetAssembler = BLEPacketAssembler()

    private let localStorage = LocalStorage.shared
    private let securityManager = BLESecurityManager()
    private let deviceIdentityStore = BLEDeviceIdentityStore.shared
    private let rateLimiter = BLERateLimiter.shared
    private let writeGate = BLEWriteGate()

    private var scanCompletion: (([BLEDevice]) -> Void)?
    private var connectCompletion: ((Result<Void, BLEError>) -> Void)?
    private var writeCompletion: ((Result<Void, BLEError>) -> Void)?
    private var activeWriteID: UUID?
    private var nextMessageId: UInt16 = 1
    private var pendingConnectedPeripheralID: UUID?
    private var pendingConnectedPeripheralName: String?
    private var handshakeTimeoutTask: Task<Void, Never>?

    /// 标记最近一次断开是否由 App 主动发起（sync 收尾 / 用户点击断开 / 后台到期）。
    /// 主动断开不应触发自动重连。生命周期：`disconnect()` 置 true，发起新连接时归零；
    /// `cleanup()` 不重置它（避免在 didDisconnect 回调到达前被清掉）。
    private var isIntentionalDisconnect = false
    /// 意外断开后的延迟重连任务，便于在主动断开 / 重新连接时取消。
    private var reconnectTask: Task<Void, Never>?
    /// 扫描代次。每次发起扫描自增；扫描超时任务只在仍是本轮扫描时才结束扫描，
    /// 避免上一轮已提前结束的超时任务误停下一轮扫描。
    private var scanGeneration: UInt64 = 0
    private var connectGeneration: UInt64 = 0

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let lastConnectedDeviceID = "lastConnectedBLEDeviceID"
        static let autoReconnect = "bleAutoReconnect"
        static let keepAliveDebugMode = "bleKeepAliveDebugMode"
    }

    // MARK: - Timing

    private enum Timing {
        /// Apple 警告：在 `didDisconnect` / `didFailToConnect` 回调里立刻 `connect`，
        /// 会让蓝牙框架卡在 bad state（state=connecting 但 pending connection 未真正建立）。
        /// 官方建议至少等 ~20ms，这里用 50ms 留余量。
        static let reconnectDelay: Duration = .milliseconds(50)
        /// 主动连接（UI / sync）的连接超时。
        static let connectTimeout: Duration = .seconds(15)
    }

    // MARK: - Settings

    public var autoReconnect: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.autoReconnect) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.autoReconnect) }
    }

    /// 固件联调专用：开启后 App **不**在同步收尾 / 超时看门狗 / 后台到期时主动断连，
    /// 保持长连接供硬件团队调试固件；意外掉线时也强制尝试自动重连。
    ///
    /// 默认值：**测试阶段全包默认开启**（硬件团队拿到即用，无需手动开）；用户在设置里手动改过则
    /// 永远以其选择为准。getter 仍以 `AppBuildEnvironment.showsHardwareDebugTools` 为闸门——当前
    /// 测试阶段该闸恒 `true`；上架 App Store 前恢复门控后，正式包会自动回到省电脉冲式同步
    /// （即使本地残留 `true` 也不启用）。
    public var keepAliveDebugMode: Bool {
        get {
            guard AppBuildEnvironment.showsHardwareDebugTools else { return false }
            if let stored = UserDefaults.standard.object(forKey: Keys.keepAliveDebugMode) as? Bool {
                return stored
            }
            return true
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.keepAliveDebugMode) }
    }

    /// 实际生效的自动重连开关：用户设置为准，但 keep-alive 调试模式下强制开启，
    /// 以便固件重启 / 信号抖动导致的意外掉线能立刻恢复调试连接。
    private var autoReconnectEffective: Bool {
        autoReconnect || keepAliveDebugMode
    }

    public nonisolated static var configuredSecurityMode: BLESecurityMode {
        guard let secret = AppSecrets.bleSharedSecret, !secret.isEmpty else {
            return .development
        }
        return .secure
    }

    public var securityMode: BLESecurityMode {
        requiresSecureChannel ? .secure : .development
    }

    /// 开发期未注入共享密钥时，允许使用未签名传输做本地联调。
    private var requiresSecureChannel: Bool {
        guard let secret = AppSecrets.bleSharedSecret else { return false }
        return !secret.isEmpty
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
        // 互斥：以 connectionState 为唯一真相源。已在扫描 / 连接 / 已连接则直接拒绝，
        // 杜绝并发 scanForDevices 互相覆盖单槽 scanCompletion / continuation
        // （历史 bug：被覆盖的 continuation 永不 resume → 永久挂起 + 卡死 Searching）。
        guard BLEConnectionPolicy.canBeginScan(state: connectionState) else {
            throw BLEError.scanAlreadyInProgress
        }
        // 同步占位（@MainActor 串行保证从 guard 到此处原子），后续 await 期间任何并发入口都会被拒绝。
        connectionState = .scanning

        let manager: CBCentralManager
        do {
            manager = try await poweredOnCentralManager(timeout: 3)
        } catch {
            if connectionState == .scanning {
                connectionState = .error(error.localizedDescription)
            }
            throw error
        }

        discoveredDevices = []
        peripheralCache = [:]
        scanGeneration &+= 1
        let generation = scanGeneration

        return await withCheckedContinuation { continuation in
            scanCompletion = { devices in
                continuation.resume(returning: devices)
            }

            manager.scanForPeripherals(
                withServices: [KiroleBLEUUIDs.serviceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )

            // 超时后结束扫描（finishScan 幂等）。仅当仍是本轮扫描时才结束，
            // 避免上一轮已提前结束的超时任务误停下一轮扫描。
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                guard self.scanGeneration == generation else { return }
                self.finishScan()
            }
        }
    }

    /// 停止扫描（公共 API：UI 在用户点击连接前调用）。
    public func stopScanning() {
        finishScan()
    }

    /// 结束当前扫描：停止 CoreBluetooth 扫描、把状态拨回空闲、并 resolve 唯一的扫描 continuation。
    /// 幂等——`scanCompletion` 取出后立即置 nil，重复调用不会二次 resume，也不会卡住 `.scanning`。
    private func finishScan() {
        centralManager?.stopScan()
        if connectionState == .scanning {
            connectionState = .disconnected
        }
        let completion = scanCompletion
        scanCompletion = nil
        completion?(discoveredDevices)
    }

    // MARK: - Connection

    /// 连接到指定设备（UI 选择设备后调用）。
    public func connect(to device: BLEDevice) async throws {
        let manager = try await poweredOnCentralManager(timeout: 2)
        guard let peripheral = peripheralCache[device.id] else {
            throw BLEError.deviceNotFound
        }
        try await connectKnownPeripheral(peripheral, manager: manager)
    }

    /// 连接一个已知的 CBPeripheral（来自缓存 / retrievePeripherals / retrieveConnectedPeripherals）。
    /// 带连接超时，用于 UI 与 sync 的主动连接路径。
    private func connectKnownPeripheral(_ peripheral: CBPeripheral, manager: CBCentralManager) async throws {
        // 互斥：以 connectionState 为真相源，已在连接 / 已连接则拒绝，避免并发覆盖 connectCompletion。
        guard BLEConnectionPolicy.canBeginConnect(state: connectionState) else {
            throw BLEError.connectionInProgress
        }
        // 同步占位（@MainActor 串行保证原子）。新连接周期开始，清除主动断开标记。
        connectionState = .connecting
        isIntentionalDisconnect = false
        connectGeneration &+= 1
        let generation = connectGeneration

        if requiresSecureChannel {
            do {
                try await ensurePeripheralTrusted(peripheral.identifier)
            } catch {
                if connectionState == .connecting { connectionState = .disconnected }
                throw error
            }
        }

        securityManager.resetSession()
        pendingConnectedPeripheralID = nil
        pendingConnectedPeripheralName = nil
        connectedPeripheral = peripheral

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
                try? await Task.sleep(for: Timing.connectTimeout)
                guard self.connectGeneration == generation else { return }
                if self.connectionState == .connecting {
                    self.connectCompletion?(.failure(.connectionTimeout))
                    self.connectCompletion = nil
                    // 主动取消 pending 连接：打标记，避免 didDisconnect 回调误判为意外断开而重连。
                    self.isIntentionalDisconnect = true
                    manager.cancelPeripheralConnection(peripheral)
                    self.connectedPeripheral = nil
                    self.connectionState = .disconnected
                }
            }
        }
    }

    /// 安全模式下校验外设是否可信。
    private func ensurePeripheralTrusted(_ id: UUID) async throws {
        if await deviceIdentityStore.isBlocked(id) {
            throw BLEError.unauthorizedDevice
        }
        if await deviceIdentityStore.hasTrustedDevices(),
           !(await deviceIdentityStore.isTrusted(id)) {
            throw BLEError.unauthorizedDevice
        }
    }

    /// 断开当前连接 / 取消在途的 pending 连接。
    /// 标记为主动断开，使 didDisconnect 回调不触发自动重连。
    public func disconnect() {
        isIntentionalDisconnect = true
        reconnectTask?.cancel()
        reconnectTask = nil
        if let peripheral = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        cleanup()
    }

    public func clearTrustedDevices() async {
        disconnect()
        await deviceIdentityStore.clearDeviceIdentities()
        lastConnectedDeviceID = nil
        discoveredDevices = []
        peripheralCache = [:]
        packetAssembler = BLEPacketAssembler()
    }

    /// 尝试连接一个已知外设。成功返回 true；连接超时 / 失败返回 false（允许调用方继续兜底）；
    /// 安全拒绝（unauthorizedDevice）或并发冲突（connectionInProgress）等致命错误向上抛出，
    /// 不应被兜底掩盖。
    private func tryConnectKnown(_ peripheral: CBPeripheral, manager: CBCentralManager) async throws -> Bool {
        do {
            try await connectKnownPeripheral(peripheral, manager: manager)
            return true
        } catch BLEError.unauthorizedDevice {
            throw BLEError.unauthorizedDevice
        } catch BLEError.connectionInProgress {
            throw BLEError.connectionInProgress
        } catch {
            return false
        }
    }

    /// 连接上次连接的设备。优先用已知 identifier 直连（Apple 推荐，避免扫描），
    /// 再尝试系统已连接设备，最后才回退扫描。任一直连的非致命失败都会继续后续兜底，
    /// 避免旧 UUID 直连超时后直接放弃，让"找不到设备"更脆弱。
    public func connectToPreferredDevice(timeout: TimeInterval = 10) async throws {
        let manager = try await poweredOnCentralManager(timeout: 3)

        // 1. 已知设备 identifier：retrievePeripherals 直接取回并连接，跳过扫描。
        if let knownID = lastConnectedDeviceID,
           let peripheral = manager.retrievePeripherals(withIdentifiers: [knownID]).first {
            peripheralCache[peripheral.identifier] = peripheral
            if try await tryConnectKnown(peripheral, manager: manager) { return }
        }

        // 2. 系统当前已连接的同服务设备。
        if let peripheral = manager.retrieveConnectedPeripherals(
            withServices: [KiroleBLEUUIDs.serviceUUID]
        ).first {
            peripheralCache[peripheral.identifier] = peripheral
            if try await tryConnectKnown(peripheral, manager: manager) { return }
        }

        // 3. 兜底：扫描发现后连接。
        let devices = try await scanForDevices(timeout: timeout)
        guard !devices.isEmpty else {
            throw BLEError.deviceNotFound
        }
        let device = devices.first(where: { $0.id == lastConnectedDeviceID }) ?? devices.first
        if let device {
            try await connect(to: device)
        }
    }

    /// 意外断开后的后台自动重连：用 CoreBluetooth 的 pending connection（不超时）等待设备
    /// 回到范围后自动重连，仅使用 retrievePeripherals（不扫描），从根上避免扫描风暴与卡死。
    /// 返回是否成功发起了重连尝试。
    @discardableResult
    public func attemptAutoReconnect() async -> Bool {
        guard autoReconnectEffective else { return false }
        return await beginPendingReconnect()
    }

    private func beginPendingReconnect() async -> Bool {
        guard BLEConnectionPolicy.canBeginConnect(state: connectionState) else { return false }
        guard let manager = try? await poweredOnCentralManager(timeout: 3) else { return false }
        guard let knownID = lastConnectedDeviceID,
              let peripheral = manager.retrievePeripherals(withIdentifiers: [knownID]).first else {
            return false
        }
        // await 期间状态可能已变，重新确认仍可发起。
        guard BLEConnectionPolicy.canBeginConnect(state: connectionState) else { return false }

        if requiresSecureChannel {
            guard (try? await ensurePeripheralTrusted(peripheral.identifier)) != nil,
                  BLEConnectionPolicy.canBeginConnect(state: connectionState) else {
                return false
            }
        }

        // await 期间用户可能主动断开（disconnect 会置位 isIntentionalDisconnect 并取消 reconnectTask）：
        // 真正发起连接前再确认一次，避免主动断开后仍发起 pending 重连。
        guard !isIntentionalDisconnect, !Task.isCancelled else { return false }

        connectionState = .connecting
        isIntentionalDisconnect = false
        connectGeneration &+= 1
        securityManager.resetSession()
        pendingConnectedPeripheralID = nil
        pendingConnectedPeripheralName = nil
        connectedPeripheral = peripheral

        // pending connection：不设超时、不 await。设备进入范围后 didConnect 自动推进握手链路。
        manager.connect(peripheral, options: nil)
        return true
    }

    private func poweredOnCentralManager(timeout: TimeInterval) async throws -> CBCentralManager {
        initialize()

        guard let manager = centralManager else {
            throw BLEError.bluetoothNotAvailable
        }

        let deadline = Date().addingTimeInterval(timeout)

        while true {
            switch manager.state {
            case .poweredOn:
                return manager
            case .poweredOff, .unauthorized, .unsupported:
                throw BLEError.bluetoothNotAvailable
            case .resetting, .unknown:
                if Date() >= deadline {
                    throw BLEError.bluetoothNotAvailable
                }
                try? await Task.sleep(for: .milliseconds(100))
            @unknown default:
                throw BLEError.bluetoothNotAvailable
            }
        }
    }

    // MARK: - Data Transfer

    /// 发送宠物状态到 E-ink 设备
    public func sendPetStatus(_ pet: Pet, companionCharacter: CompanionCharacter) async throws {
        let data = BLEDataEncoder.encodePetStatus(pet, companionCharacter: companionCharacter)
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
    public func syncAllData(
        pet: Pet,
        companionCharacter: CompanionCharacter,
        tasks: [TaskItem],
        events: [CalendarEvent],
        weather: Weather
    ) async throws {
        try await sendPetStatus(pet, companionCharacter: companionCharacter)
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

    /// 发送 Task In 页面数据到 E-ink 设备。只应由 BLEEventHandler 在收到 0x10 EnterTaskIn 事件后调用。
    func sendTaskInPage(_ taskInPage: TaskInPageData) async throws {
        let data = BLEDataEncoder.encodeTaskInPage(taskInPage)
        try await writeData(type: .taskInPage, data: data)
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
        try await writeData(type: .smartReminder, data: data)
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
        try await writeData(type: .focusStatus, data: payload)
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

    public func sendDisplayScene(_ scene: DisplayScene) async throws {
        let packet = BLEPacketizer.buildSceneUnlockPacket(sceneId: scene.commandByte)
        try await writeDevelopmentDisplayPacket(packet)
    }

    /// 推送用户自定义伴侣的像素帧到 E-ink 设备。
    /// pixelData 应为 4bpp packed 数据（通常 96×96 → 4608 字节），由 BLEDataEncoder.encodePixelData 生成。
    /// 注意：硬件端的接收/渲染逻辑待与硬件团队对齐 0x15 customAvatarFrame 协议后启用。
    public func sendCustomAvatarFrame(pixelData: Data) async throws {
        let payload = BLEDataEncoder.encodeCustomAvatarFrame(pixelData: pixelData)
        try await writeData(type: .customAvatarFrame, data: payload)
    }

    public func sendScreensaverConfig(_ config: ScreensaverConfig) async throws {
        let packet = BLEPacketizer.buildScreensaverPacket(config: config)
        try await writeDevelopmentDisplayPacket(packet)
    }

    // MARK: - Private Methods

    private func writeData(type: BLEDataType, data: Data) async throws {
        guard connectionState.isConnected,
              let characteristic = writeCharacteristic,
              let peripheral = connectedPeripheral else {
            throw BLEError.notConnected
        }

        guard requiresSecureChannel else {
            try await writeUnsignedData(type: type, data: data, peripheral: peripheral, characteristic: characteristic)
            return
        }

        guard securityManager.isSessionEstablished else {
            throw BLEError.securityHandshakeFailed("Secure BLE session not established")
        }

        let securePayload = try securityManager.securePayload(type: type.rawValue, payload: data)
        let maxLength = peripheral.maximumWriteValueLength(for: .withResponse)

        if shouldUseChunkedPacket(type: type, payloadSize: securePayload.count, maxWriteLength: maxLength) {
            let maxChunkPayloadSize = maxLength - BLEPacketizer.headerSize
            let packets = try BLEPacketizer.packetize(
                type: BLEDataType.secureData.rawValue,
                messageId: allocateMessageID(),
                payload: securePayload,
                maxChunkSize: maxChunkPayloadSize
            )
            for packet in packets {
                try await writePacket(packet, peripheral: peripheral, characteristic: characteristic)
            }
            return
        }

        let packet = BLESimpleEncoder.encode(type: BLEDataType.secureData.rawValue, payload: securePayload)
        try await writePacket(packet, peripheral: peripheral, characteristic: characteristic)
    }

    private func writeUnsignedData(
        type: BLEDataType,
        data: Data,
        peripheral: CBPeripheral,
        characteristic: CBCharacteristic
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
            for packet in packets {
                try await writePacket(packet, peripheral: peripheral, characteristic: characteristic)
            }
            return
        }

        let packet = BLESimpleEncoder.encode(type: type.rawValue, payload: data)
        try await writePacket(packet, peripheral: peripheral, characteristic: characteristic)
    }

    private func writeDevelopmentDisplayPacket(_ packet: Data) async throws {
        guard connectionState.isConnected,
              let characteristic = writeCharacteristic,
              let peripheral = connectedPeripheral else {
            throw BLEError.notConnected
        }

        guard !requiresSecureChannel else {
            throw BLEError.securityHandshakeFailed("Custom display commands require development mode")
        }

        try await writePacket(packet, peripheral: peripheral, characteristic: characteristic)
    }

    private func shouldUseChunkedPacket(type: BLEDataType, payloadSize: Int, maxWriteLength: Int) -> Bool {
        if payloadSize + 3 > maxWriteLength { return true }
        switch type {
        case .dayPack, .taskInPage, .customAvatarFrame:
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

    private func writePacket(
        _ packet: Data,
        peripheral: CBPeripheral,
        characteristic: CBCharacteristic
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
            guard connectionState.isConnected else {
                throw BLEError.disconnected
            }

            // HIGH-1: strong capture — no retain cycle (@MainActor task, singleton service)
            let writeID = UUID()
            activeWriteID = writeID
            let timeoutTask = Task { @MainActor in
                try await Task.sleep(for: .seconds(5))
                guard self.activeWriteID == writeID else { return }
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

    private func startSecurityHandshake(peripheral: CBPeripheral) async {
        guard let characteristic = writeCharacteristic else {
            connectCompletion?(.failure(.characteristicNotFound))
            connectCompletion = nil
            return
        }

        do {
            let payload = try securityManager.makeHandshakeRequestPayload()
            let packet = BLESimpleEncoder.encode(type: BLEDataType.securityHandshake.rawValue, payload: payload)
            try await writePacket(packet, peripheral: peripheral, characteristic: characteristic)

            handshakeTimeoutTask?.cancel()
            handshakeTimeoutTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                if !self.securityManager.isSessionEstablished {
                    self.connectCompletion?(.failure(.securityHandshakeFailed("Handshake timeout")))
                    self.connectCompletion = nil
                    self.connectionState = .disconnected
                    self.centralManager?.cancelPeripheralConnection(peripheral)
                }
            }
        } catch {
            connectCompletion?(.failure(.securityHandshakeFailed(error.localizedDescription)))
            connectCompletion = nil
            connectionState = .disconnected
            centralManager?.cancelPeripheralConnection(peripheral)
        }
    }

    private func completeSecureConnection() async {
        handshakeTimeoutTask?.cancel()
        handshakeTimeoutTask = nil

        guard let peripheralID = pendingConnectedPeripheralID else {
            connectCompletion?(.failure(.securityHandshakeFailed("Missing connected device identity")))
            connectCompletion = nil
            connectionState = .disconnected
            return
        }

        let name = pendingConnectedPeripheralName ?? "Kirole Device"
        connectionState = .connected
        connectedDevice = BLEDevice(
            id: peripheralID,
            name: name,
            rssi: 0,
            isConnected: true
        )
        lastConnectedDeviceID = peripheralID
        if requiresSecureChannel {
            await deviceIdentityStore.trust(peripheralID)
        }
        connectCompletion?(.success(()))
        connectCompletion = nil
        await requestEventLogsIfNeeded()
    }

    func decodeReceivedMessageForTesting(_ receivedData: Data) throws -> BLEReceivedMessage? {
        try decodeReceivedMessage(receivedData)
    }

    private func decodeReceivedMessage(_ receivedData: Data) throws -> BLEReceivedMessage? {
        let decodedMessage: BLEReceivedMessage?
        if let message = packetAssembler.append(packetData: receivedData) {
            decodedMessage = message
        } else if packetAssembler.isPotentialChunk(packetData: receivedData) {
            decodedMessage = nil
        } else if let message = BLESimpleDecoder.decode(receivedData) {
            decodedMessage = message
        } else {
            decodedMessage = nil
        }

        guard let message = decodedMessage else { return nil }

        guard requiresSecureChannel else {
            return message
        }

        if message.type == BLEDataType.securityHandshake.rawValue {
            return message
        }

        guard message.type == BLEDataType.secureData.rawValue else {
            throw BLEError.securityHandshakeFailed("Received non-secure BLE payload")
        }

        return try securityManager.openSecurePayload(message.payload)
    }

    private func cleanup() {
        handshakeTimeoutTask?.cancel()
        handshakeTimeoutTask = nil
        writeCompletion?(.failure(.disconnected))
        writeCompletion = nil
        activeWriteID = nil
        connectCompletion?(.failure(.connectionFailed(nil)))
        connectCompletion = nil
        securityManager.resetSession()
        // 断连必须丢弃半成品分块重组状态：链路中断时未完成的 Assembly 槽位会永久残留，
        // 累计 8 个后 assembler 槽满，所有后续 Device→App 分块消息（含 0x21 事件补传批次）被静默丢弃。
        packetAssembler = BLEPacketAssembler()
        pendingConnectedPeripheralID = nil
        pendingConnectedPeripheralName = nil
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

            // 在 cleanup 之前捕获断开意图（cleanup 不重置该标记）。
            let wasIntentional = isIntentionalDisconnect
            cleanup()

            guard BLEConnectionPolicy.shouldAutoReconnect(
                isIntentional: wasIntentional,
                autoReconnectEnabled: autoReconnectEffective
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

            if writeCharacteristic != nil, notifyCharacteristic != nil {
                pendingConnectedPeripheralID = peripheralID
                pendingConnectedPeripheralName = peripheralName ?? "Kirole Device"
                Task { @MainActor in
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

        Task { @MainActor in
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

// MARK: - BLE Errors

public enum BLEError: LocalizedError, Sendable {
    case bluetoothNotAvailable
    case deviceNotFound
    case unauthorizedDevice
    case connectionTimeout
    case connectionFailed(Error?)
    case notConnected
    case serviceNotFound
    case characteristicNotFound
    case writeFailed(Error?)
    case securityHandshakeFailed(String)
    case disconnected
    case writeTimeout
    case scanAlreadyInProgress
    case connectionInProgress

    public var errorDescription: String? {
        switch self {
        case .bluetoothNotAvailable:
            return "Bluetooth is not available"
        case .deviceNotFound:
            return "Device not found"
        case .unauthorizedDevice:
            return "Unauthorized BLE device"
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
        case .securityHandshakeFailed(let reason):
            return "BLE security handshake failed: \(reason)"
        case .disconnected:
            return "Device disconnected"
        case .writeTimeout:
            return "BLE write timed out"
        case .scanAlreadyInProgress:
            return "A BLE scan is already in progress"
        case .connectionInProgress:
            return "A BLE connection is already in progress"
        }
    }
}
