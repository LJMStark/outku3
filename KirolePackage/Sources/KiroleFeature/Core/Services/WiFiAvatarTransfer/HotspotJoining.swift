import Foundation

/// 加入/离开设备 SoftAP 热点的抽象。便于测试注入 mock——`NEHotspotConfiguration` 只能真机验证。
public protocol HotspotJoining: Sendable {
    /// 加入指定 SSID 的热点（一次性 join，不保存进已知网络）。成功或"已在该热点"即返回；失败抛错。
    func join(ssid: String, passphrase: String) async throws
    /// 移除该热点配置，恢复系统自动选网（best-effort，不抛错）。
    func leave(ssid: String) async
}

public enum HotspotJoinError: Error, Sendable, Equatable {
    case unsupportedPlatform
    case userDenied
    case failed(String)
}

#if os(iOS)
import NetworkExtension

/// 用 `NEHotspotConfiguration` 加入设备 SoftAP。需 entitlement
/// `com.apple.developer.networking.HotspotConfiguration`（见 Config/Kirole.entitlements）。
public struct SystemHotspotJoiner: HotspotJoining {
    public init() {}

    public func join(ssid: String, passphrase: String) async throws {
        let configuration = NEHotspotConfiguration(ssid: ssid, passphrase: passphrase, isWEP: false)
        configuration.joinOnce = true // 传输结束即断开，不保存进已知网络

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            NEHotspotConfigurationManager.shared.apply(configuration) { error in
                guard let error else {
                    continuation.resume()
                    return
                }
                let nsError = error as NSError
                guard nsError.domain == NEHotspotConfigurationErrorDomain else {
                    continuation.resume(throwing: HotspotJoinError.failed(error.localizedDescription))
                    return
                }
                switch nsError.code {
                case NEHotspotConfigurationError.alreadyAssociated.rawValue:
                    // 已连在该热点上，视作成功。
                    continuation.resume()
                case NEHotspotConfigurationError.userDenied.rawValue:
                    continuation.resume(throwing: HotspotJoinError.userDenied)
                default:
                    continuation.resume(throwing: HotspotJoinError.failed(error.localizedDescription))
                }
            }
        }
    }

    public func leave(ssid: String) async {
        NEHotspotConfigurationManager.shared.removeConfiguration(forSSID: ssid)
    }
}
#else
/// 非 iOS 平台（macOS 单元测试宿主）无 `NEHotspotConfiguration`——WiFi 传输不可用，
/// 调用方据 `unsupportedPlatform` 回退 BLE。
public struct SystemHotspotJoiner: HotspotJoining {
    public init() {}
    public func join(ssid: String, passphrase: String) async throws {
        throw HotspotJoinError.unsupportedPlatform
    }
    public func leave(ssid: String) async {}
}
#endif
