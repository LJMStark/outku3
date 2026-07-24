import Foundation

/// 加入设备 SoftAP 后，确认当前 WiFi 确实是设备回报的 SSID。
/// `NEHotspotConfiguration.apply` 成功只表示配置已保存并尝试加入，不能替代关联确认。
public protocol WiFiReachability: Sendable {
    func waitUntilAssociated(to ssid: String, timeout: Duration) async -> Bool
}

/// SSID 是协议凭据，必须按设备回报的原始 UTF-8 字节比较。
/// Swift `String ==` 会把 composed/decomposed Unicode 当作相等，不适合这里。
enum WiFiSSIDMatcher {
    static func matches(_ actual: String?, expected: String) -> Bool {
        guard let actual else { return false }
        return Data(actual.utf8) == Data(expected.utf8)
    }
}

#if os(iOS)
import NetworkExtension

/// 轮询系统当前 SSID，只有精确匹配设备 SoftAP 才允许上传。
/// 需要 `com.apple.developer.networking.wifi-info` entitlement；当前网络由本 App 通过
/// `NEHotspotConfiguration` 配置，因此不依赖定位授权。
public struct SystemWiFiReachability: WiFiReachability {
    private let pollInterval: Duration

    public init(pollInterval: Duration = .milliseconds(200)) {
        self.pollInterval = pollInterval
    }

    public func waitUntilAssociated(to ssid: String, timeout: Duration) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                while !Task.isCancelled {
                    if WiFiSSIDMatcher.matches(await currentSSID(), expected: ssid) {
                        return true
                    }
                    do {
                        try await Task.sleep(for: pollInterval)
                    } catch {
                        return false
                    }
                }
                return false
            }
            group.addTask {
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    return false
                }
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    private func currentSSID() async -> String? {
        await withCheckedContinuation { continuation in
            NEHotspotNetwork.fetchCurrent { network in
                continuation.resume(returning: network?.ssid)
            }
        }
    }
}
#else
/// macOS 单元测试宿主没有 iOS 当前热点 API；生产调用只发生在 iOS。
public struct SystemWiFiReachability: WiFiReachability {
    public init() {}

    public func waitUntilAssociated(to ssid: String, timeout: Duration) async -> Bool {
        false
    }
}
#endif
