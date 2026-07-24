import Foundation

// MARK: - WiFi Avatar Session (0x1A) — BLE handshake for SoftAP avatar transfer
//
// 头像 WiFi 快速传输的 BLE 握手层。App 经 `0x1A` 让设备启/停 SoftAP 并索取一次性热点凭据 +
// HTTP 收图端点；头像字节走 HTTP（见 WiFiAvatarHTTPContract / AvatarHTTPUploader），事务确认仍
// 走 `0x22 AvatarControl`。协议见 `docs/BLE通信协议规格文档.md` §4.20 / §5.20 与
// `docs/WiFi头像传输协议契约草案.md`。
//
// 注意：SSID/密码/path/token 是**凭据**，不经 `Data.appendString` 的 E-ink ASCII 净化——净化
// 会破坏密码/token 里的特殊字符。这里用不净化的原始 UTF-8 长度前缀编解码。

/// App→Device：SoftAP 头像传输会话命令（§4.20）。
public enum WiFiAvatarSessionCommand: UInt8, Sendable, Equatable, CaseIterable {
    /// 停止 SoftAP、结束会话（传输成败都发）。
    case close = 0x00
    /// 启动 SoftAP 并在应答中回报热点凭据 + 端点。
    case open = 0x01
    /// 查询当前会话实际状态，不改变设备状态。
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

    /// 点分十进制，用于拼 HTTP host。
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

/// `open` 成功时设备回报的一次性热点凭据 + HTTP 端点。
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

    /// 拼出设备 HTTP 收图端点，如 `http://192.168.4.1/avatar`。
    public var endpointURL: URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = gateway.description
        components.port = Int(port)
        components.path = path.hasPrefix("/") ? path : "/\(path)"
        return components.url
    }
}

/// Device→App 应答（§5.20）。`status == .ok` 时携带凭据；否则 `credentials == nil`。
public struct WiFiAvatarSessionResponse: Sendable, Equatable {
    public let status: WiFiAvatarSessionStatus
    public let credentials: WiFiAvatarSessionCredentials?

    public init(status: WiFiAvatarSessionStatus, credentials: WiFiAvatarSessionCredentials?) {
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
    public static let requestLength = 1 + 4 // Command + OperationID(BE)

    public static let maxSSIDLength = 32
    public static let maxPassphraseLength = 63
    public static let maxPathLength = 32
    public static let maxTokenLength = 64

    // MARK: Request (App → Device)

    public static func encodeRequest(_ request: WiFiAvatarSessionRequest) -> Data {
        var payload = Data(capacity: requestLength)
        payload.append(request.command.rawValue)
        payload.appendBigEndian(request.operationID)
        return payload
    }

    /// 供模拟固件解析 App 发出的请求。
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

    // MARK: Response (Device → App)

    /// 供模拟固件/测试编码应答镜像。
    public static func encodeResponse(_ response: WiFiAvatarSessionResponse) -> Data {
        var payload = Data()
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
        return WiFiAvatarSessionResponse(status: status, credentials: credentials)
    }

    /// 原始 UTF-8 长度前缀（1B），**不做 E-ink ASCII 净化**——凭据不是显示文本。
    private static func appendLengthPrefixed(_ data: inout Data, _ string: String) {
        let stringBytes = Data(string.utf8)
        let clamped = stringBytes.prefix(255)
        data.append(UInt8(clamped.count))
        data.append(contentsOf: clamped)
    }
}

// MARK: - HTTP Endpoint Contract (App → Device over WiFi)

/// 设备 HTTP 收图端点的请求约定（见 `docs/WiFi头像传输协议契约草案.md` §3）。
public enum WiFiAvatarHTTPContract {
    public static let contentType = "application/octet-stream"
    public static let authorizationHeader = "Authorization"
    public static let operationIDHeader = "X-Kirole-Operation-Id"
    public static let avatarIDHeader = "X-Kirole-Avatar-Id"
    public static let fileLengthHeader = "X-Kirole-File-Length"
    public static let fileCRC32Header = "X-Kirole-File-CRC32"

    /// 成功响应体 `{"status":"staging",...}` 的状态值。
    public static let stagingStatus = "staging"

    /// `Bearer <token>` 授权头值。
    public static func bearer(_ token: String) -> String { "Bearer \(token)" }

    /// OperationID / CRC32 统一以 8 位小写十六进制表示。
    public static func hex(_ value: UInt32) -> String { String(format: "%08x", value) }
}
