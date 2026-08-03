@preconcurrency import CoreBluetooth
import Foundation
import os

// MARK: - BLE Service UUIDs

/// Kirole E-ink 设备的 BLE 服务和特征 UUID
enum KiroleBLEUUIDs {
    static let serviceUUID = CBUUID(string: "0000FFE0-0000-1000-8000-00805F9B34FB")
    static let writeCharacteristicUUID = CBUUID(string: "0000FFE1-0000-1000-8000-00805F9B34FB")
    static let notifyCharacteristicUUID = CBUUID(string: "0000FFE2-0000-1000-8000-00805F9B34FB")
}

typealias PacketWriteValidator = @MainActor @Sendable () throws -> Void

// MARK: - BLE Service

/// BLE 服务，管理与 E-ink 硬件设备的通信
@Observable
@MainActor
public final class BLEService: NSObject, TaskListSnapshotSending {
    public static let shared = BLEService()
    static let bleLogger = Logger(subsystem: "com.kirole.app", category: "BLE")

    // MARK: - Published State

    public internal(set) var connectionState: BLEConnectionState = .disconnected

    /// 当前连接外设的系统标识（未连接为 nil）。v2.5.33 用于"换硬件后自动重推 0x15 头像"：
    /// 固件持久化只救同一台重启，连上**另一台**设备时 App 侧要能察觉并重推。
    public var connectedDeviceID: UUID? { connectedPeripheral?.identifier }
    /// Connected device, or the last device selected by this single-device account.
    /// Durable avatar operations use it to avoid replaying device A's transaction on device B.
    public var lastKnownDeviceID: UUID? {
        BLEConnectionPolicy.lastKnownDeviceID(
            state: connectionState,
            connectedDeviceID: connectedDeviceID,
            lastConnectedDeviceID: lastConnectedDeviceID
        )
    }
    public internal(set) var discoveredDevices: [BLEDevice] = []
    public private(set) var connectedDevice: BLEDevice?
    public internal(set) var lastSyncTime: Date?

    /// 上一轮整轮同步是否失败。lastSyncTime 只在成功时更新，连续失败时它会无声变旧——
    /// 这个标志让 Settings 硬件面板能把"同步失败了"和"还没到同步窗口"区分开。
    public internal(set) var lastSyncFailed = false
    /// Last known device battery level (0-100). Updated on DeviceWake and LowBattery events.
    /// nil until the device reports a level.
    public internal(set) var deviceBatteryLevel: Int?
    /// 最近一次实时 DeviceWake(0x30) 上报的固件版本（协议 v2.5.19+；旧固件为 nil）。
    public internal(set) var deviceFirmwareVersion: FirmwareVersion?
    /// 0x22 设备结果回调。AppState 按 operationID 过滤迟到结果并推进持久化操作状态。
    @ObservationIgnored
    public var onAvatarControlResult: (@MainActor @Sendable (AvatarControlResult) -> Void)?
    /// 0x23 task-library commit result. The acknowledgement identifies the exact version and CRC
    /// the device made visible; later tickets persist and schedule those versions.
    @ObservationIgnored
    public var onTaskLibraryCommitAcknowledgement: (
        @MainActor @Sendable (TaskLibraryCommitAcknowledgement) -> Void
    )?

    // MARK: - Internal Transport State

    var centralManager: CBCentralManager?
    var connectedPeripheral: CBPeripheral?
    var peripheralCache: [UUID: CBPeripheral] = [:]
    var writeCharacteristic: CBCharacteristic?
    var notifyCharacteristic: CBCharacteristic?
    private var packetAssembler = BLEPacketAssembler()

    let localStorage = LocalStorage.shared
    let securityManager = BLESecurityManager()
    let deviceIdentityStore = BLEDeviceIdentityStore.shared
    let rateLimiter = BLERateLimiter.shared
    let writeGate = BLEWriteGate()
    /// Serializes complete task-state messages. The packet gate below is intentionally finer
    /// grained; without this second gate, a simple 0x1B could land between DayPack chunks.
    let taskStateMessageGate = BLEWriteGate()

    private var scanCompletion: (([BLEDevice]) -> Void)?
    var connectCompletion: ((Result<Void, BLEError>) -> Void)?
    var writeCompletion: ((Result<Void, BLEError>) -> Void)?
    var activeWriteID: UUID?
    var staleWriteAckFilter = BLEStaleWriteAckFilter()
    var nextMessageId: UInt16 = 1

    /// 进行中的分包消息数（@MainActor 串行，无并发写）。最坏 800×700 KRI
    /// 约 2.24MB / 4472 片，限流下需 4–5 分钟。传输期间 BLESyncCoordinator 不得因
    /// 30s 同步超时主动断连；真实断线后由用户从第 0 片重发。
    var inFlightChunkedTransfers = 0
    var isChunkedTransferInFlight: Bool { inFlightChunkedTransfers > 0 }
    /// flag-day 取证去重：本连接内已记过"固件还在发 9B 旧分包头"即不再重复（cleanup 复位）。
    private var hasLoggedLegacyChunkHeader = false
    var pendingConnectedPeripheralID: UUID?
    var pendingConnectedPeripheralName: String?
    private var handshakeTimeoutTask: Task<Void, Never>?

    /// 标记最近一次断开是否由 App 主动发起（sync 收尾 / 用户点击断开 / 后台到期）。
    /// 主动断开不应触发自动重连。生命周期：`disconnect()` 置 true，发起新连接时归零；
    /// `cleanup()` 不重置它（避免在 didDisconnect 回调到达前被清掉）。
    var isIntentionalDisconnect = false
    /// Set by BLEOTACoordinator for the whole OTA window (sending → awaitingReboot).
    /// didDisconnectPeripheral 靠它把预期中的升级重启断连路由给协调器——§4.17 允许
    /// 固件收到 0x18 后不回应答直接重启，所以 sending 阶段就必须布防，不能等应答。
    var isPendingOTAReboot = false
    /// 意外断开后的延迟重连任务，便于在主动断开 / 重新连接时取消。
    var reconnectTask: Task<Void, Never>?
    /// 扫描代次。每次发起扫描自增；扫描超时任务只在仍是本轮扫描时才结束扫描，
    /// 避免上一轮已提前结束的超时任务误停下一轮扫描。
    private var scanGeneration: UInt64 = 0
    var connectGeneration: UInt64 = 0

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let lastConnectedDeviceID = "lastConnectedBLEDeviceID"
        static let autoReconnect = "bleAutoReconnect"
        static let keepAliveDebugMode = "bleKeepAliveDebugMode"
        static let hardwareScreenSize = "bleHardwareScreenSize"
    }

    // MARK: - Timing

    enum Timing {
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

    /// 对端 E-ink 屏型。决定 DayPack `TopTasks[]` 上限（协议 §4.7：4寸≤3 / 7.3寸≤5）——
    /// 生成与编码两处都要用同一值，否则 7.3寸设备只收得到 4寸档的 3 条任务（2026-07-03 联调）。
    /// 设备暂无自报通道，由 Settings 手动选择；默认 4 寸取保守小值（4寸收 5 条会布局溢出，
    /// 7.3寸收 3 条只是没填满）。不进 LocalStorage resettable 清单：设备属性，清数据不应抹掉。
    public var hardwareScreenSize: ScreenSize {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Keys.hardwareScreenSize),
                  let size = ScreenSize(rawValue: raw) else { return .fourInch }
            return size
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Keys.hardwareScreenSize) }
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

    /// 同步收尾和看门狗是否应保留 BLE。Wi-Fi 调试已开启或正在切换时必须保留，
    /// 否则 App 会失去关闭热点与查询状态的控制通道。
    var shouldKeepConnectionOpenForDebug: Bool {
        // Wi-Fi PC 调试(0x19) 或 WiFi 头像会话(0x1A) 任一需要连接时都必须保住 BLE：
        // SoftAP 期间不主动断连，否则无法再发 close 停热点或收 0x22 staged。
        BLEConnectionPolicy.shouldKeepConnectionOpenForDebug(
            keepAliveEnabled: keepAliveDebugMode,
            wifiDebugRequiresConnection: BLEWiFiDebugCoordinator.shared.requiresBLEConnection
                || WiFiAvatarSessionCoordinator.shared.requiresBLEConnection
        )
    }

    /// 实际生效的自动重连开关：用户设置为准，但硬件调试需要长连接时强制开启，
    /// 以便固件重启 / 信号抖动导致的意外掉线能立刻恢复调试连接。
    var autoReconnectEffective: Bool {
        autoReconnect || shouldKeepConnectionOpenForDebug
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
    var requiresSecureChannel: Bool {
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
        // 测试进程守卫：macOS 测试宿主（swiftpm-testing-helper）没有蓝牙用途声明，创建
        // CBCentralManager 会触发 TCC 隐私 SIGABRT 崩掉整个测试进程——AppState 测试遗留的
        // detached requestBLESync→performSync 任务在进程收尾期就撞上过（2026-07-14）。
        // 测试里保持 centralManager 为 nil，poweredOnCentralManager 走既有
        // bluetoothNotAvailable 错误路径优雅失败，sync 链路的失败分支照常被覆盖。
        guard !AppBuildEnvironment.isRunningTests else {
            // 必须留痕：万一真机包被误判为测试宿主（如未来 XCUITest / 自定义启动参数带
            // ".xctest"），BLE 会整体静默失效、下游只看到 bluetoothNotAvailable——这行
            // 日志是唯一能定位到守卫本身的取证信号。
            ErrorReporter.log(
                .sync(component: "BLEService", underlying: "initialize() skipped: test host detected (AppBuildEnvironment.isRunningTests)"),
                context: "BLEService.initialize"
            )
            return
        }
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
                    // 本次尝试作废时，同时拆掉它已挂的 5s 握手残表——否则残表存活到
                    // 下一次尝试的握手窗口，会误杀新尝试的 connectCompletion。
                    self.handshakeTimeoutTask?.cancel()
                    self.handshakeTimeoutTask = nil
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
        // 断连结束专注必须在意图点直接触发：cleanup() 清空 connectedPeripheral 后，
        // 随后到达的合法 didDisconnect 会被 shouldProcessCallback 身份门拒绝，
        // 回调里的 handleDeviceDisconnected 永远不跑（2a7bf26 引入的回归，联审 2026-07-16 F7）。
        // 双结算无风险：回调被门拒；即使放行，endSession 的 activeSession guard 也会挡住第二次。
        FocusSessionService.shared.handleDeviceDisconnected()
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

    // MARK: - Security and inbound decoding

    func startSecurityHandshake(peripheral: CBPeripheral) async {
        // writePacket 的 await（writeGate/限速/写超时）期间本次尝试可能已被换代；
        // 换代后不得再动 connectCompletion（此刻它属于新尝试），也不得动新尝试的握手表。
        let generation = connectGeneration

        guard let characteristic = writeCharacteristic else {
            connectCompletion?(.failure(.characteristicNotFound))
            connectCompletion = nil
            return
        }

        do {
            let payload = try securityManager.makeHandshakeRequestPayload()
            let packet = BLESimpleEncoder.encode(type: BLEDataType.securityHandshake.rawValue, payload: payload)
            try await writePacket(packet, peripheral: peripheral, characteristic: characteristic)

            guard connectGeneration == generation else { return }

            handshakeTimeoutTask?.cancel()
            handshakeTimeoutTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                guard self.connectGeneration == generation else { return }
                if !self.securityManager.isSessionEstablished {
                    self.connectCompletion?(.failure(.securityHandshakeFailed("Handshake timeout")))
                    self.connectCompletion = nil
                    self.connectionState = .disconnected
                    self.centralManager?.cancelPeripheralConnection(peripheral)
                }
            }
        } catch {
            guard connectGeneration == generation else { return }
            connectCompletion?(.failure(.securityHandshakeFailed(error.localizedDescription)))
            connectCompletion = nil
            connectionState = .disconnected
            centralManager?.cancelPeripheralConnection(peripheral)
        }
    }

    func completeSecureConnection() async {
        let generation = connectGeneration
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
            // trust 的 await 期间若发生断连→cleanup→新尝试（代次已换），此刻的
            // connectCompletion 属于新尝试，不得用旧尝试的结果提前完成它。
            guard connectGeneration == generation else { return }
        }
        connectCompletion?(.success(()))
        connectCompletion = nil
        await requestEventLogsIfNeeded()
        if AppBuildEnvironment.showsHardwareDebugTools {
            await BLEWiFiDebugCoordinator.shared.queryStatus()
        }
    }

    func decodeReceivedMessageForTesting(_ receivedData: Data) throws -> BLEReceivedMessage? {
        try decodeReceivedMessage(receivedData)
    }

    func handleAvatarControlResult(_ result: AvatarControlResult) {
        onAvatarControlResult?(result)
    }

    func handleTaskLibraryCommitAcknowledgement(
        _ acknowledgement: TaskLibraryCommitAcknowledgement
    ) {
        onTaskLibraryCommitAcknowledgement?(acknowledgement)
    }

    func decodeReceivedMessage(_ receivedData: Data) throws -> BLEReceivedMessage? {
        let decodedMessage: BLEReceivedMessage?
        if let message = packetAssembler.append(packetData: receivedData) {
            decodedMessage = message
        } else if packetAssembler.isPotentialChunk(packetData: receivedData) {
            decodedMessage = nil
        } else if let message = BLESimpleDecoder.decode(receivedData) {
            decodedMessage = message
        } else {
            // flag-day 取证（v2.5.24）：分包头 9B→11B 无兼容窗口。固件没同步升级时，
            // 它发来的旧 9B 分包会走到这里被静默丢弃——简单帧（0x20/0x30 等）照常工作，
            // 唯独 0x21 离线补传无声死亡，联调时极难定位。按旧头形状识别并记日志
            // （每连接一次，cleanup 复位），不做任何兼容解析。
            logLegacyChunkHeaderIfDetected(receivedData)
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

    /// 旧 9B 分包头形状：`Type(1)|MsgId(2)|Seq(1)|Total(1)|Len(2 BE)@5|CRC(2 BE)@7|payload@9`。
    /// 长度自洽 + 逐片 CRC 命中即判定为 v2.5.24 之前的固件在发旧分包格式。
    private func logLegacyChunkHeaderIfDetected(_ data: Data) {
        guard !hasLoggedLegacyChunkHeader, data.count > 9 else { return }
        let legacyLength = Int(data.bigEndianUInt16(at: 5))
        guard legacyLength > 0, data.count == 9 + legacyLength else { return }
        let legacyCRC = data.bigEndianUInt16(at: 7)
        let payload = data.subdata(in: 9..<data.count)
        guard CRC16.ccittFalse(payload) == legacyCRC else { return }

        hasLoggedLegacyChunkHeader = true
        ErrorReporter.log(
            .sync(
                component: "BLE ChunkHeader",
                underlying: "Device is still sending pre-v2.5.24 9-byte chunk headers — firmware must upgrade to the 11-byte header (§3.2); its chunked messages (incl. 0x21 event batches) are being dropped"
            ),
            context: "BLEService.decodeReceivedMessage"
        )
    }

    func cleanup() {
        BLEWiFiDebugCoordinator.shared.handleDisconnected()
        WiFiAvatarSessionCoordinator.shared.handleDisconnected()
        AppState.shared.handleCustomAvatarDeviceDisconnected()
        handshakeTimeoutTask?.cancel()
        handshakeTimeoutTask = nil
        writeCompletion?(.failure(.disconnected))
        writeCompletion = nil
        activeWriteID = nil
        // ACK 不跨连接；跨连接残留计数会吞掉新连接的第一个真 ACK。
        staleWriteAckFilter.reset()
        connectCompletion?(.failure(.connectionFailed(nil)))
        connectCompletion = nil
        securityManager.resetSession()
        // 断连必须丢弃半成品分块重组状态：链路中断时未完成的 Assembly 槽位会永久残留，
        // 累计 8 个后 assembler 槽满，所有后续 Device→App 分块消息（含 0x21 事件补传批次）被静默丢弃。
        packetAssembler = BLEPacketAssembler()
        hasLoggedLegacyChunkHeader = false
        pendingConnectedPeripheralID = nil
        pendingConnectedPeripheralName = nil
        connectedPeripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        connectedDevice = nil
        connectionState = .disconnected
    }

    /// delegate 回调准入：代次门 + 外设身份，判定逻辑见 `BLEConnectionPolicy.shouldProcessCallback`。
    func shouldProcessCallback(generationAtDelivery: UInt64, peripheralID: UUID) -> Bool {
        BLEConnectionPolicy.shouldProcessCallback(
            generationAtDelivery: generationAtDelivery,
            currentGeneration: connectGeneration,
            callbackPeripheralID: peripheralID,
            trackedPeripheralID: connectedPeripheral?.identifier
        )
    }
}
