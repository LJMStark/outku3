import Foundation

/// WiFi 传输的子阶段，桥接到 `CustomAvatarOperationState`（joiningHotspot / transferring）。
public enum WiFiTransferPhase: Sendable, Equatable {
    case joiningHotspot
    case uploading
}

public enum WiFiTransferError: Error, Sendable, Equatable {
    case wifiDisabled
    case sessionHandshakeFailed(String)
    case hotspotJoinFailed(HotspotJoinError)
    case unreachable
    case httpFailed(AvatarHTTPUploadError)
    /// 用户在 WiFi-off 弹窗选择取消/去设置（Router 层构造）——用户意图，不自动回退 BLE。
    case userInterrupted

    /// 技术性失败可自动回退 BLE；`userInterrupted` 是用户意图，冒泡成 `.interrupted`。
    /// 注：`wifiDisabled` 由 Router 优先单独处理（弹窗），不走自动回退路径。
    public var isRecoverableToBLE: Bool {
        switch self {
        case .userInterrupted: return false
        default: return true
        }
    }
}

/// Service 依赖的会话握手契约（nonisolated，便于测试注入非 `@MainActor` mock）。
/// `WiFiAvatarSessionCoordinator` 实现它。
public protocol WiFiAvatarSessionHandshaking: Sendable {
    func openSession(operationID: UInt32) async throws -> WiFiAvatarSessionCredentials
    func closeSession(operationID: UInt32) async
}

extension WiFiAvatarSessionCoordinator: WiFiAvatarSessionHandshaking {}

/// Service 的传输契约，便于 Router 测试注入 mock transport。
public protocol WiFiAvatarTransporting: Sendable {
    @MainActor func send(
        operationID: UInt32,
        avatarID: UUID,
        kriData: Data,
        onPhase: @escaping @MainActor (WiFiTransferPhase) -> Void,
        onProgress: @escaping @MainActor @Sendable (Int, Int) -> Void
    ) async throws
}

extension WiFiAvatarTransferService: WiFiAvatarTransporting {}

/// 编排 WiFi(SoftAP) 头像传输：BLE `0x1A` 握手拿凭据 → 加入设备热点 → HTTP 整块上传 KRI。
///
/// 装进 `AppState.customAvatarFrameSender` seam。职责边界 = **把字节送到设备并返回**；
/// 设备收完 KRI 后经 BLE 发 `0x22 staged`，由 `runApplyTransaction` 的事务机 await 确认——
/// 与 BLE 路径逐字节相同。任一步失败抛 `WiFiTransferError`，Router 据 `isRecoverableToBLE`
/// 回退 BLE。**无论成败（含取消）都清理**：leave 热点 + close 会话（会话另有 TTL 兜底）。
@MainActor
public final class WiFiAvatarTransferService {
    private let session: any WiFiAvatarSessionHandshaking
    private let hotspot: any HotspotJoining
    private let reachability: any WiFiReachability
    private let uploader: any AvatarHTTPUploading
    private let pathTimeout: Duration

    public init(
        session: any WiFiAvatarSessionHandshaking = WiFiAvatarSessionCoordinator.shared,
        hotspot: any HotspotJoining = SystemHotspotJoiner(),
        reachability: any WiFiReachability = SystemWiFiReachability(),
        uploader: any AvatarHTTPUploading = URLSessionAvatarUploader(),
        pathTimeout: Duration = .seconds(10)
    ) {
        self.session = session
        self.hotspot = hotspot
        self.reachability = reachability
        self.uploader = uploader
        self.pathTimeout = pathTimeout
    }

    public func send(
        operationID: UInt32,
        avatarID: UUID,
        kriData: Data,
        onPhase: @escaping @MainActor (WiFiTransferPhase) -> Void,
        onProgress: @escaping @MainActor @Sendable (Int, Int) -> Void
    ) async throws {
        guard await reachability.isWiFiInterfaceAvailable() else {
            throw WiFiTransferError.wifiDisabled
        }

        let credentials: WiFiAvatarSessionCredentials
        do {
            credentials = try await session.openSession(operationID: operationID)
        } catch let error as WiFiAvatarSessionError {
            throw WiFiTransferError.sessionHandshakeFailed(error.message)
        }

        // 会话已开——此后任何路径（成功 / 失败 / 取消）都要清理。
        do {
            try await runTransfer(
                credentials: credentials,
                operationID: operationID,
                avatarID: avatarID,
                kriData: kriData,
                onPhase: onPhase,
                onProgress: onProgress
            )
        } catch {
            await cleanup(credentials: credentials, operationID: operationID)
            throw error
        }
        await cleanup(credentials: credentials, operationID: operationID)
    }

    private func runTransfer(
        credentials: WiFiAvatarSessionCredentials,
        operationID: UInt32,
        avatarID: UUID,
        kriData: Data,
        onPhase: @escaping @MainActor (WiFiTransferPhase) -> Void,
        onProgress: @escaping @MainActor @Sendable (Int, Int) -> Void
    ) async throws {
        onPhase(.joiningHotspot)
        do {
            try await hotspot.join(ssid: credentials.ssid, passphrase: credentials.passphrase)
        } catch let error as HotspotJoinError {
            throw WiFiTransferError.hotspotJoinFailed(error)
        }

        guard await reachability.waitForWiFiPath(timeout: pathTimeout) else {
            throw WiFiTransferError.unreachable
        }
        guard let endpoint = credentials.endpointURL else {
            throw WiFiTransferError.unreachable
        }

        onPhase(.uploading)
        let headers = Self.uploadHeaders(
            operationID: operationID,
            avatarID: avatarID,
            byteLength: kriData.count,
            crc32: CRC32.ieee(kriData),
            token: credentials.token
        )
        do {
            try await uploader.upload(
                kriData: kriData,
                to: endpoint,
                headers: headers,
                // uploader 在后台队列回调进度；跳回主线程更新 UI 状态。
                onProgress: { sentBytes, totalBytes in
                    Task { @MainActor in onProgress(sentBytes, totalBytes) }
                }
            )
        } catch let error as AvatarHTTPUploadError {
            throw WiFiTransferError.httpFailed(error)
        }
        // 成功——设备收完 KRI 会经 BLE 发 0x22 staged，由事务机 await 确认。
    }

    private func cleanup(credentials: WiFiAvatarSessionCredentials, operationID: UInt32) async {
        await hotspot.leave(ssid: credentials.ssid)
        await session.closeSession(operationID: operationID)
    }

    /// 构造 HTTP 上传头（见 `docs/WiFi头像传输协议契约草案.md` §3.1）。
    static func uploadHeaders(
        operationID: UInt32,
        avatarID: UUID,
        byteLength: Int,
        crc32: UInt32,
        token: String
    ) -> [String: String] {
        [
            WiFiAvatarHTTPContract.authorizationHeader: WiFiAvatarHTTPContract.bearer(token),
            WiFiAvatarHTTPContract.operationIDHeader: WiFiAvatarHTTPContract.hex(operationID),
            WiFiAvatarHTTPContract.avatarIDHeader: avatarID.uuidString,
            WiFiAvatarHTTPContract.fileLengthHeader: String(byteLength),
            WiFiAvatarHTTPContract.fileCRC32Header: WiFiAvatarHTTPContract.hex(crc32),
        ]
    }
}
