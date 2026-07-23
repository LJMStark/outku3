@preconcurrency import CoreBluetooth
import Foundation
import os

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
    public private(set) var discoveredDevices: [BLEDevice] = []
    public private(set) var connectedDevice: BLEDevice?
    public private(set) var lastSyncTime: Date?

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
    private var staleWriteAckFilter = BLEStaleWriteAckFilter()
    private var nextMessageId: UInt16 = 1

    /// 进行中的分包消息数（@MainActor 串行，无并发写）。最坏 800×700 KRI
    /// 约 2.24MB / 4472 片，限流下需 4–5 分钟。传输期间 BLESyncCoordinator 不得因
    /// 30s 同步超时主动断连；真实断线后由用户从第 0 片重发。
    private var inFlightChunkedTransfers = 0
    var isChunkedTransferInFlight: Bool { inFlightChunkedTransfers > 0 }
    /// flag-day 取证去重：本连接内已记过"固件还在发 9B 旧分包头"即不再重复（cleanup 复位）。
    private var hasLoggedLegacyChunkHeader = false
    private var pendingConnectedPeripheralID: UUID?
    private var pendingConnectedPeripheralName: String?
    private var handshakeTimeoutTask: Task<Void, Never>?

    /// 标记最近一次断开是否由 App 主动发起（sync 收尾 / 用户点击断开 / 后台到期）。
    /// 主动断开不应触发自动重连。生命周期：`disconnect()` 置 true，发起新连接时归零；
    /// `cleanup()` 不重置它（避免在 didDisconnect 回调到达前被清掉）。
    private var isIntentionalDisconnect = false
    /// Set by BLEOTACoordinator for the whole OTA window (sending → awaitingReboot).
    /// didDisconnectPeripheral 靠它把预期中的升级重启断连路由给协调器——§4.17 允许
    /// 固件收到 0x18 后不回应答直接重启，所以 sending 阶段就必须布防，不能等应答。
    var isPendingOTAReboot = false
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
        static let hardwareScreenSize = "bleHardwareScreenSize"
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
        BLEConnectionPolicy.shouldKeepConnectionOpenForDebug(
            keepAliveEnabled: keepAliveDebugMode,
            wifiDebugRequiresConnection: BLEWiFiDebugCoordinator.shared.requiresBLEConnection
        )
    }

    /// 实际生效的自动重连开关：用户设置为准，但硬件调试需要长连接时强制开启，
    /// 以便固件重启 / 信号抖动导致的意外掉线能立刻恢复调试连接。
    private var autoReconnectEffective: Bool {
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

    // MARK: - Data Transfer

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
    public func sendDayPack(_ dayPack: DayPack) async throws {
        let data = BLEDataEncoder.encodeDayPack(dayPack, screenSize: hardwareScreenSize)
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

    /// 推送场景解锁到 E-ink 设备。
    /// v2.5.11：从旧 `0xAA 01 01` 开发命令升级为 `0x17` 业务帧，经 `writeData` 发送——
    /// dev 模式走简单包、secure 模式自动 SecureEnvelope 封装，**两种模式均可发**
    /// （旧开发命令在配置 `BLE_SHARED_SECRET` 后会被禁用，场景切换会静默失败）。
    public func sendDisplayScene(_ scene: DisplayScene) async throws {
        let payload = BLEDataEncoder.encodeSceneUnlock(scene)
        try await writeData(type: .sceneUnlock, data: payload)
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
        try await writeData(type: .customAvatarFrame, data: payload) { sentPayloadBytes, _ in
            let sentKRIBytes = min(
                kriData.count,
                max(0, sentPayloadBytes - CustomAvatarFrameV4Codec.headerLength)
            )
            progress(sentKRIBytes, kriData.count)
        }
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
        try await writeData(type: .screensaver, data: payload)
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

    // MARK: - Private Methods

    private func writeData(
        type: BLEDataType,
        data: Data,
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
            for plainPacket in plainPackets {
                try Task.checkCancellation()
                // 必须临写前即时签名。整批预签会让 4–5 分钟传输后半段的 issuedAt
                // 超过 SecureEnvelope 的 120 秒接收窗口。
                let packet = try securityManager.secureChunkPacket(
                    type: type.rawValue,
                    plainPacket: plainPacket,
                    maxWriteLength: maxLength
                )
                try await writePacket(packet, peripheral: peripheral, characteristic: characteristic)
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
            for packet in packets {
                // 外层任务被取消（如切换伴侣废弃旧头像流）时立即停发——写锁只串行单个
                // packet，不检查取消的话两条 2000 片消息会逐片交错、旧流可能反杀新流。
                try Task.checkCancellation()
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
        characteristic: CBCharacteristic,
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
            for packet in packets {
                // 同 writeData：任务取消即停发，防多条大帧流逐片交错。
                try Task.checkCancellation()
                try await writePacket(packet, peripheral: peripheral, characteristic: characteristic)
                sentBytes += chunkPayloadLength(packet)
                progress?(min(sentBytes, data.count), data.count)
            }
            return
        }

        let packet = BLESimpleEncoder.encode(type: type.rawValue, payload: data)
        try await writePacket(packet, peripheral: peripheral, characteristic: characteristic)
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
            guard let packetType = packet.first,
                  BLEWritePolicy.canWrite(state: connectionState, packetType: packetType) else {
                throw BLEError.disconnected
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

    private func startSecurityHandshake(peripheral: CBPeripheral) async {
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

    private func completeSecureConnection() async {
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

    private func decodeReceivedMessage(_ receivedData: Data) throws -> BLEReceivedMessage? {
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

    private func cleanup() {
        BLEWiFiDebugCoordinator.shared.handleDisconnected()
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
    private func shouldProcessCallback(generationAtDelivery: UInt64, peripheralID: UUID) -> Bool {
        BLEConnectionPolicy.shouldProcessCallback(
            generationAtDelivery: generationAtDelivery,
            currentGeneration: connectGeneration,
            callbackPeripheralID: peripheralID,
            trackedPeripheralID: connectedPeripheral?.identifier
        )
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
            // 设备断开时结束活跃的专注会话
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
