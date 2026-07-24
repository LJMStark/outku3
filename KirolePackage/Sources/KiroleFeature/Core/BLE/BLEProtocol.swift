import Foundation

// MARK: - BLE Protocol Overview
//
// 本文件是 Kirole BLE 协议的单一真相源，集中定义 App↔Device 的数据类型字节。
//
// App → Device（本文件 BLEDataType）：
//   0x01 petStatus       宠物状态
//   0x02 taskList        任务列表
//   0x03 schedule        日程
//   0x04 weather         天气
//   0x05 time            时间同步
//   0x10 dayPack         完整每日数据包
//   0x11 taskInPage      任务详情页
//   0x12 deviceMode      设备运行模式
//   0x13 smartReminder   AI 智能提醒
//   0x14 focusStatus     专注状态与能量瓶子数（App→Device 实时推送）
//   0x15 customAvatarFrame 用户自定义伴侣头像（v2.7 SubVersion 0x04，操作/头像身份 + KRI）
//   0x16 screensaver     屏保金句/明信片（业务帧，secure 模式可发；替代旧 0xAA 开发命令）
//   0x17 sceneUnlock     场景解锁（业务帧，secure 模式可发；替代旧 0xAA 开发命令）
//   0x18 otaReboot       触发固件升级重启（零 payload；固件校验包后应答并重启，不等 App 确认）
//   0x19 wifiDebugMode   Wi-Fi PC 调试模式（App 命令 00/01/02；Device 应答 enabled+status）
//   0x1A wifiAvatarSession SoftAP 头像快传会话（双向回显 command+OpID；Device 再带 status+凭据/端点）
//   0x20 eventLogRequest 请求增量 Event Log
//   0x21 eventLogBatch   批量回传 Event Log（Device→App，此 type 仅出现在入站方向）
//   0x22 avatarControl   自定义头像提交、擦除、查询、取消与设备结果
//   0x7E secureData      安全封装（v2 SecureEnvelope）
//   0x7F securityHandshake 安全握手（v2）
//
// Device → App（入站事件，字节定义见 Models/EventLog.swift 的 EventLogType.rawByte）：
//   0x01 encoderRotateUp        旋钮顺时针
//   0x02 encoderRotateDown      旋钮逆时针
//   0x03 encoderShortPress      旋钮短按
//   0x04 encoderLongPress       旋钮长按
//   0x05 powerShortPress        电源键短按
//   0x06 powerLongPress         电源键长按
//   0x10 enterTaskIn            进入任务详情（触发 App 专注模式）
//   0x11 completeTask           标记任务完成
//   0x12 skipTask               跳过任务
//   0x13 selectedTaskChanged    切换选中任务
//   0x14 wheelSelect            旋钮选择确认
//   0x15 viewEventDetail        查看日历事件详情
//   0x16 reminderAcknowledged   用户确认智能提醒
//   0x17 reminderDismissed      智能提醒超时关闭
//   0x19 wifiDebugMode          Wi-Fi PC 调试实时应答（不进入 Event Log 批次）
//   0x20 requestRefresh         请求数据刷新
//   0x21 eventLogBatch          批量回传事件（含 EventLogType.rawByte 流）
//   0x30 deviceWake             设备唤醒（payload: 电量1B；v2.5.19+ 追加固件版本3B，仅实时帧）
//   0x31 deviceSleep            设备休眠
//   0x40 lowBattery             低电量

// MARK: - BLE Data Types (App → Device)

/// App 向 E-ink 设备发送的数据类型字节。
/// 与 Device→App 入站事件字节（`EventLogType.rawByte`）分离在不同命名空间，
/// 联调时以本文件为出站协议的唯一参考，入站协议参见 `Models/EventLog.swift`。
public enum BLEDataType: UInt8, Sendable {
    case petStatus = 0x01
    case taskList = 0x02
    case schedule = 0x03
    case weather = 0x04
    case time = 0x05
    case dayPack = 0x10
    case taskInPage = 0x11
    case deviceMode = 0x12
    case smartReminder = 0x13
    /// App→Device: 推送当前专注状态和能量瓶子数
    case focusStatus = 0x14
    /// App→Device: 暂存用户自定义伴侣头像（≤800×700 保比例）。v2.7 payload 固定为
    /// `0x04 | OperationID | AvatarID | FileLength | FileCRC32 | KRI`。固件校验后先返回
    /// 0x22 staged；收到 commit 后才原子替换当前头像。
    case customAvatarFrame = 0x15
    /// App→Device: 屏保金句/明信片业务帧（替代旧 `0xAA 01 02` 开发命令）。
    /// 经 SecureEnvelope 走 `writeData`，secure 模式可发；payload 见 `BLEDataEncoder.encodeScreensaver`。
    case screensaver = 0x16
    /// App→Device: 场景解锁业务帧（替代旧 `0xAA 01 01` 开发命令）。
    /// 经 SecureEnvelope 走 `writeData`，secure 模式可发；payload 见 `BLEDataEncoder.encodeSceneUnlock`。
    case sceneUnlock = 0x17
    /// App→Device: 触发固件升级重启（零 payload），见协议文档 §4.17
    case otaReboot = 0x18
    /// 双向实时帧：App payload 为 disable(00)/enable(01)/query(02)，设备应答为 enabled(1B)+status(1B)。
    case wifiDebugMode = 0x19
    /// 双向实时帧：App 发 command + OperationID，设备回显两者后带 status + SoftAP 凭据/端点。
    /// SoftAP 头像快传会话握手，见 §4.20/§5.20 与 `WiFiAvatarSessionCodec`。
    case wifiAvatarSession = 0x1A
    case eventLogRequest = 0x20
    case eventLogBatch = 0x21
    /// 双向实时帧：App 发 commit/erase/query/abort，设备回 staged/committed/erased/state/aborted。
    case avatarControl = 0x22
    case secureData = 0x7E
    case securityHandshake = 0x7F
}

// MARK: - WiFi Avatar Session (0x1A)
//
// App 经 `0x1A` 让设备启/停 SoftAP 并索取一次性热点凭据与 HTTP 端点；头像字节
// 走 WiFi，事务确认仍走 `0x22 AvatarControl`。完整协议见 BLE 规格 §4.20 / §5.20。
// SSID、密码、path、token 是凭据，按原始 UTF-8 编解码，不能经过显示文本净化。

/// App→Device：SoftAP 头像传输会话命令（§4.20）。
public enum WiFiAvatarSessionCommand: UInt8, Sendable, Equatable, CaseIterable {
    case close = 0x00
    case open = 0x01
    case query = 0x02
}

/// Device→App：会话应答状态码（§5.20）。
public enum WiFiAvatarSessionStatus: UInt8, Sendable, Equatable {
    case ok = 0x00
    case unsupported = 0x01
    case busy = 0x02
    case wifiInitFailed = 0x03
    case invalidCommand = 0x04
    case unknownError = 0xFF
}

/// SoftAP 网关 IPv4（大端 4 字节，通常 192.168.4.1）。
public struct IPv4Address: Sendable, Equatable, CustomStringConvertible {
    public let a: UInt8
    public let b: UInt8
    public let c: UInt8
    public let d: UInt8

    public init(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
    }

    public var description: String { "\(a).\(b).\(c).\(d)" }
}

/// App→Device 请求（固定 5 字节：Command(1) + OperationID(4 BE)）。
public struct WiFiAvatarSessionRequest: Sendable, Equatable {
    public let command: WiFiAvatarSessionCommand
    public let operationID: UInt32

    public init(command: WiFiAvatarSessionCommand, operationID: UInt32) {
        self.command = command
        self.operationID = operationID
    }
}

/// `open` 成功时设备回报的一次性热点凭据与 HTTP 端点。
public struct WiFiAvatarSessionCredentials: Sendable, Equatable {
    public let ssid: String
    public let passphrase: String
    public let gateway: IPv4Address
    public let port: UInt16
    public let path: String
    public let token: String
    public let ttlSeconds: UInt16

    public init(
        ssid: String,
        passphrase: String,
        gateway: IPv4Address,
        port: UInt16,
        path: String,
        token: String,
        ttlSeconds: UInt16
    ) {
        self.ssid = ssid
        self.passphrase = passphrase
        self.gateway = gateway
        self.port = port
        self.path = path
        self.token = token
        self.ttlSeconds = ttlSeconds
    }

    public var endpointURL: URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = gateway.description
        components.port = Int(port)
        components.path = path.hasPrefix("/") ? path : "/\(path)"
        return components.url
    }
}

/// Device→App 应答（§5.20）。回显命令和 OperationID，`status == .ok` 时携带凭据。
public struct WiFiAvatarSessionResponse: Sendable, Equatable {
    public let command: WiFiAvatarSessionCommand
    public let operationID: UInt32
    public let status: WiFiAvatarSessionStatus
    public let credentials: WiFiAvatarSessionCredentials?

    public init(
        command: WiFiAvatarSessionCommand,
        operationID: UInt32,
        status: WiFiAvatarSessionStatus,
        credentials: WiFiAvatarSessionCredentials?
    ) {
        self.command = command
        self.operationID = operationID
        self.status = status
        self.credentials = credentials
    }
}

public enum WiFiAvatarSessionCodecError: Error, Equatable, Sendable {
    case invalidRequestLength(Int)
    case invalidCommand(UInt8)
    case emptyResponse
    case truncatedResponse(field: String)
    case invalidStatus(UInt8)
    case invalidUTF8(field: String)
    case fieldTooLong(field: String, length: Int, max: Int)
    case trailingBytes(Int)
}

/// `0x1A` 请求/应答的 wire 编解码，测试与 Swift 模拟固件共用。
public enum WiFiAvatarSessionCodec {
    public static let requestLength = 1 + 4
    public static let maxSSIDLength = 32
    public static let maxPassphraseLength = 63
    public static let maxPathLength = 32
    public static let maxTokenLength = 64

    public static func encodeRequest(_ request: WiFiAvatarSessionRequest) -> Data {
        var payload = Data(capacity: requestLength)
        payload.append(request.command.rawValue)
        payload.appendBigEndian(request.operationID)
        return payload
    }

    public static func decodeRequest(_ payload: Data) throws -> WiFiAvatarSessionRequest {
        let bytes = [UInt8](payload)
        guard bytes.count == requestLength else {
            throw WiFiAvatarSessionCodecError.invalidRequestLength(bytes.count)
        }
        guard let command = WiFiAvatarSessionCommand(rawValue: bytes[0]) else {
            throw WiFiAvatarSessionCodecError.invalidCommand(bytes[0])
        }
        let operationID = (UInt32(bytes[1]) << 24)
            | (UInt32(bytes[2]) << 16)
            | (UInt32(bytes[3]) << 8)
            | UInt32(bytes[4])
        return WiFiAvatarSessionRequest(command: command, operationID: operationID)
    }

    /// 供模拟固件和测试编码应答镜像。
    public static func encodeResponse(_ response: WiFiAvatarSessionResponse) -> Data {
        var payload = Data()
        payload.append(response.command.rawValue)
        payload.appendBigEndian(response.operationID)
        payload.append(response.status.rawValue)
        let credentials = response.credentials
        appendLengthPrefixed(&payload, credentials?.ssid ?? "")
        appendLengthPrefixed(&payload, credentials?.passphrase ?? "")
        let gateway = credentials?.gateway
        payload.append(contentsOf: [gateway?.a ?? 0, gateway?.b ?? 0, gateway?.c ?? 0, gateway?.d ?? 0])
        payload.appendBigEndian(credentials?.port ?? 0)
        appendLengthPrefixed(&payload, credentials?.path ?? "")
        appendLengthPrefixed(&payload, credentials?.token ?? "")
        payload.appendBigEndian(credentials?.ttlSeconds ?? 0)
        return payload
    }

    public static func decodeResponse(_ payload: Data) throws -> WiFiAvatarSessionResponse {
        let bytes = [UInt8](payload)
        guard !bytes.isEmpty else { throw WiFiAvatarSessionCodecError.emptyResponse }

        var offset = 0
        func requireBytes(_ count: Int, field: String) throws {
            guard offset + count <= bytes.count else {
                throw WiFiAvatarSessionCodecError.truncatedResponse(field: field)
            }
        }
        func readString(field: String, max: Int) throws -> String {
            try requireBytes(1, field: field)
            let length = Int(bytes[offset])
            offset += 1
            guard length <= max else {
                throw WiFiAvatarSessionCodecError.fieldTooLong(field: field, length: length, max: max)
            }
            try requireBytes(length, field: field)
            let slice = bytes[offset ..< offset + length]
            offset += length
            guard let string = String(bytes: slice, encoding: .utf8) else {
                throw WiFiAvatarSessionCodecError.invalidUTF8(field: field)
            }
            return string
        }
        func readUInt16(field: String) throws -> UInt16 {
            try requireBytes(2, field: field)
            let value = UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
            offset += 2
            return value
        }

        func readUInt32(field: String) throws -> UInt32 {
            try requireBytes(4, field: field)
            let value = (UInt32(bytes[offset]) << 24)
                | (UInt32(bytes[offset + 1]) << 16)
                | (UInt32(bytes[offset + 2]) << 8)
                | UInt32(bytes[offset + 3])
            offset += 4
            return value
        }

        try requireBytes(1, field: "command")
        let commandByte = bytes[offset]
        offset += 1
        guard let command = WiFiAvatarSessionCommand(rawValue: commandByte) else {
            throw WiFiAvatarSessionCodecError.invalidCommand(commandByte)
        }
        let operationID = try readUInt32(field: "operationID")

        try requireBytes(1, field: "status")
        let statusByte = bytes[offset]
        offset += 1
        guard let status = WiFiAvatarSessionStatus(rawValue: statusByte) else {
            throw WiFiAvatarSessionCodecError.invalidStatus(statusByte)
        }

        let ssid = try readString(field: "ssid", max: maxSSIDLength)
        let passphrase = try readString(field: "passphrase", max: maxPassphraseLength)
        try requireBytes(4, field: "gateway")
        let gateway = IPv4Address(bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
        offset += 4
        let port = try readUInt16(field: "port")
        let path = try readString(field: "path", max: maxPathLength)
        let token = try readString(field: "token", max: maxTokenLength)
        let ttl = try readUInt16(field: "ttl")

        guard offset == bytes.count else {
            throw WiFiAvatarSessionCodecError.trailingBytes(bytes.count - offset)
        }

        let credentials: WiFiAvatarSessionCredentials? = status == .ok
            ? WiFiAvatarSessionCredentials(
                ssid: ssid,
                passphrase: passphrase,
                gateway: gateway,
                port: port,
                path: path,
                token: token,
                ttlSeconds: ttl
            )
            : nil
        return WiFiAvatarSessionResponse(
            command: command,
            operationID: operationID,
            status: status,
            credentials: credentials
        )
    }

    private static func appendLengthPrefixed(_ data: inout Data, _ string: String) {
        let stringBytes = Data(string.utf8)
        let clamped = stringBytes.prefix(255)
        data.append(UInt8(clamped.count))
        data.append(contentsOf: clamped)
    }
}

// MARK: - Custom Avatar Protocol v2.7

public enum BLEAvatarProtocolError: Error, Equatable, Sendable {
    case unsupportedSubVersion(UInt8)
    case invalidPayloadLength(expected: Int, actual: Int)
    case fileLengthOverflow(Int)
    case fileLengthMismatch(declared: UInt32, actual: Int)
    case crcMismatch(expected: UInt32, actual: UInt32)
    case invalidKRI
    case invalidCommand(UInt8)
    case invalidAvatarID
    case invalidStatus(UInt8)
    case invalidState(UInt8)
    case invalidBoolean(UInt8)
    case inconsistentInventory
    case inconsistentStatus
    case writeLengthTooSmall(Int)
}

public struct CustomAvatarFrameV4: Equatable, Sendable {
    public let operationID: UInt32
    public let avatarID: UUID
    public let fileLength: UInt32
    public let fileCRC32: UInt32
    public let kriData: Data

    public init(
        operationID: UInt32,
        avatarID: UUID,
        fileLength: UInt32,
        fileCRC32: UInt32,
        kriData: Data
    ) {
        self.operationID = operationID
        self.avatarID = avatarID
        self.fileLength = fileLength
        self.fileCRC32 = fileCRC32
        self.kriData = kriData
    }
}

public enum CustomAvatarFrameV4Codec {
    public static let subVersion: UInt8 = 0x04
    public static let headerLength = 1 + 4 + 16 + 4 + 4

    public static func encode(operationID: UInt32, avatarID: UUID, kriData: Data) throws -> Data {
        guard AvatarImageProcessor.isValidAvatarKRI(kriData) else {
            throw BLEAvatarProtocolError.invalidKRI
        }
        guard kriData.count <= Int(UInt32.max) else {
            throw BLEAvatarProtocolError.fileLengthOverflow(kriData.count)
        }

        var payload = Data(capacity: headerLength + kriData.count)
        payload.append(subVersion)
        payload.appendBigEndian(operationID)
        payload.append(UUIDWireCodec.encode(avatarID))
        payload.appendBigEndian(UInt32(kriData.count))
        payload.appendBigEndian(CRC32.ieee(kriData))
        payload.append(kriData)
        return payload
    }

    public static func decode(_ payload: Data) throws -> CustomAvatarFrameV4 {
        guard payload.count >= headerLength else {
            throw BLEAvatarProtocolError.invalidPayloadLength(expected: headerLength, actual: payload.count)
        }
        guard payload[0] == subVersion else {
            throw BLEAvatarProtocolError.unsupportedSubVersion(payload[0])
        }

        let operationID = payload.bigEndianUInt32(at: 1)
        let avatarID = UUIDWireCodec.decode(payload.subdata(in: 5..<21))
        let fileLength = payload.bigEndianUInt32(at: 21)
        let expectedCRC = payload.bigEndianUInt32(at: 25)
        let kriData = payload.subdata(in: headerLength..<payload.count)
        guard kriData.count == Int(fileLength) else {
            throw BLEAvatarProtocolError.fileLengthMismatch(declared: fileLength, actual: kriData.count)
        }
        let actualCRC = CRC32.ieee(kriData)
        guard actualCRC == expectedCRC else {
            throw BLEAvatarProtocolError.crcMismatch(expected: expectedCRC, actual: actualCRC)
        }
        guard AvatarImageProcessor.isValidAvatarKRI(kriData) else {
            throw BLEAvatarProtocolError.invalidKRI
        }

        return CustomAvatarFrameV4(
            operationID: operationID,
            avatarID: avatarID,
            fileLength: fileLength,
            fileCRC32: expectedCRC,
            kriData: kriData
        )
    }
}

public enum AvatarControlCommand: Equatable, Sendable {
    case commit(operationID: UInt32, avatarID: UUID)
    case eraseExact(operationID: UInt32, avatarID: UUID)
    case eraseAll(operationID: UInt32)
    case query(operationID: UInt32)
    case abort(operationID: UInt32)

    public var operationID: UInt32 {
        switch self {
        case .commit(let operationID, _), .eraseExact(let operationID, _),
             .eraseAll(let operationID), .query(let operationID), .abort(let operationID):
            operationID
        }
    }

    public var avatarID: UUID? {
        switch self {
        case .commit(_, let avatarID), .eraseExact(_, let avatarID): avatarID
        case .eraseAll, .query, .abort: nil
        }
    }

    var commandByte: UInt8 {
        switch self {
        case .commit: 0x01
        case .eraseExact: 0x02
        case .eraseAll: 0x03
        case .query: 0x04
        case .abort: 0x05
        }
    }
}

public enum AvatarControlStatus: UInt8, Codable, Sendable {
    case staged = 0x01
    case committed = 0x02
    case erased = 0x03
    case state = 0x04
    case aborted = 0x05
}

public enum AvatarControlState: UInt8, Codable, Sendable {
    case empty = 0x00
    case staged = 0x01
    case committed = 0x02
}

public struct AvatarControlResult: Equatable, Sendable {
    public let operationID: UInt32
    public let status: AvatarControlStatus
    public let avatarState: AvatarControlState
    public let customActive: Bool
    public let avatarID: UUID?
    public let byteLength: UInt32
    public let crc32: UInt32

    public init(
        operationID: UInt32,
        status: AvatarControlStatus,
        avatarState: AvatarControlState,
        customActive: Bool,
        avatarID: UUID?,
        byteLength: UInt32,
        crc32: UInt32
    ) {
        self.operationID = operationID
        self.status = status
        self.avatarState = avatarState
        self.customActive = customActive
        self.avatarID = avatarID
        self.byteLength = byteLength
        self.crc32 = crc32
    }
}

public enum AvatarControlCodec {
    public static let commandLength = 1 + 4 + 16
    public static let resultLength = 4 + 1 + 1 + 1 + 16 + 4 + 4

    public static func encodeCommand(_ command: AvatarControlCommand) -> Data {
        var payload = Data(capacity: commandLength)
        payload.append(command.commandByte)
        payload.appendBigEndian(command.operationID)
        payload.append(command.avatarID.map(UUIDWireCodec.encode) ?? Data(repeating: 0, count: 16))
        return payload
    }

    public static func decodeCommand(_ payload: Data) throws -> AvatarControlCommand {
        guard payload.count == commandLength else {
            throw BLEAvatarProtocolError.invalidPayloadLength(expected: commandLength, actual: payload.count)
        }
        let commandByte = payload[0]
        let operationID = payload.bigEndianUInt32(at: 1)
        let avatarBytes = payload.subdata(in: 5..<21)
        let hasAvatarID = !avatarBytes.allSatisfy { $0 == 0 }

        switch commandByte {
        case 0x01, 0x02:
            guard hasAvatarID else { throw BLEAvatarProtocolError.invalidAvatarID }
            let avatarID = UUIDWireCodec.decode(avatarBytes)
            return commandByte == 0x01
                ? .commit(operationID: operationID, avatarID: avatarID)
                : .eraseExact(operationID: operationID, avatarID: avatarID)
        case 0x03, 0x04, 0x05:
            guard !hasAvatarID else { throw BLEAvatarProtocolError.invalidAvatarID }
            switch commandByte {
            case 0x03: return .eraseAll(operationID: operationID)
            case 0x04: return .query(operationID: operationID)
            default: return .abort(operationID: operationID)
            }
        default:
            throw BLEAvatarProtocolError.invalidCommand(commandByte)
        }
    }

    /// 测试与 Swift 模拟固件共用的设备结果编码镜像。
    public static func encodeResult(_ result: AvatarControlResult) -> Data {
        var payload = Data(capacity: resultLength)
        payload.appendBigEndian(result.operationID)
        payload.append(result.status.rawValue)
        payload.append(result.avatarState.rawValue)
        payload.append(result.customActive ? 0x01 : 0x00)
        payload.append(result.avatarID.map(UUIDWireCodec.encode) ?? Data(repeating: 0, count: 16))
        payload.appendBigEndian(result.byteLength)
        payload.appendBigEndian(result.crc32)
        return payload
    }

    public static func decodeResult(_ payload: Data) throws -> AvatarControlResult {
        guard payload.count == resultLength else {
            throw BLEAvatarProtocolError.invalidPayloadLength(expected: resultLength, actual: payload.count)
        }
        guard let status = AvatarControlStatus(rawValue: payload[4]) else {
            throw BLEAvatarProtocolError.invalidStatus(payload[4])
        }
        guard let state = AvatarControlState(rawValue: payload[5]) else {
            throw BLEAvatarProtocolError.invalidState(payload[5])
        }
        guard payload[6] <= 0x01 else {
            throw BLEAvatarProtocolError.invalidBoolean(payload[6])
        }

        let customActive = payload[6] == 0x01
        let avatarBytes = payload.subdata(in: 7..<23)
        let avatarID = avatarBytes.allSatisfy { $0 == 0 } ? nil : UUIDWireCodec.decode(avatarBytes)
        let byteLength = payload.bigEndianUInt32(at: 23)
        let crc32 = payload.bigEndianUInt32(at: 27)

        switch state {
        case .empty:
            guard !customActive, avatarID == nil, byteLength == 0, crc32 == 0 else {
                throw BLEAvatarProtocolError.inconsistentInventory
            }
        case .staged, .committed:
            guard avatarID != nil,
                  byteLength >= UInt32(KRIEncoder.headerByteCount),
                  byteLength <= UInt32(AvatarImageProcessor.maxKRIEncodedByteCount) else {
                throw BLEAvatarProtocolError.inconsistentInventory
            }
        }

        let statusMatchesState: Bool
        switch status {
        case .staged:
            statusMatchesState = state == .staged
        case .committed:
            statusMatchesState = state == .committed && customActive
        case .erased:
            statusMatchesState = state != .staged
        case .state:
            statusMatchesState = true
        case .aborted:
            statusMatchesState = state != .staged
        }
        guard statusMatchesState else {
            throw BLEAvatarProtocolError.inconsistentStatus
        }

        return AvatarControlResult(
            operationID: payload.bigEndianUInt32(at: 0),
            status: status,
            avatarState: state,
            customActive: customActive,
            avatarID: avatarID,
            byteLength: byteLength,
            crc32: crc32
        )
    }
}

enum UUIDWireCodec {
    static func encode(_ id: UUID) -> Data {
        var value = id.uuid
        return withUnsafeBytes(of: &value) { Data($0) }
    }

    static func decode(_ data: Data) -> UUID {
        precondition(data.count == 16)
        let bytes = [UInt8](data)
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
