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
//   0x1A wifiAvatarSession SoftAP 头像快传会话（App close/open/query+OpID；Device status+凭据/端点）
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
    /// 双向实时帧：App 发 close(00)/open(01)/query(02) + OperationID，设备回 status + SoftAP 凭据/端点。
    /// SoftAP 头像快传会话握手，见 §4.20/§5.20 与 `WiFiAvatarSessionCodec`。
    case wifiAvatarSession = 0x1A
    case eventLogRequest = 0x20
    case eventLogBatch = 0x21
    /// 双向实时帧：App 发 commit/erase/query/abort，设备回 staged/committed/erased/state/aborted。
    case avatarControl = 0x22
    case secureData = 0x7E
    case securityHandshake = 0x7F
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
