import Foundation
import Network

/// 探测 WiFi 接口可用性 + 等待 WiFi path 就绪的抽象。便于测试注入 mock。
public protocol WiFiReachability: Sendable {
    /// WiFi 接口当前是否可用（近似"WiFi 开关开着且有可用 path"；iOS 无精确开关 API）。
    func isWiFiInterfaceAvailable() async -> Bool
    /// 等待 WiFi path 变为 satisfied（加入设备热点后确认连上）。超时返回 false。
    func waitForWiFiPath(timeout: Duration) async -> Bool
}

/// 用 `NWPathMonitor(requiredInterfaceType: .wifi)` 观测 WiFi path。
///
/// iOS 没有"WiFi 开关是否打开"的直接 API——用 `.wifi` path 的 `.satisfied` 近似：WiFi 关 /
/// 飞行模式 / 无可用 path 时为 `.unsatisfied`。这不精确（WiFi 开但未连任何网络也可能不满足），
/// 调用方据此弹"打开 WiFi"引导并保留 BLE 兜底，不追求 100% 精确。
public struct SystemWiFiReachability: WiFiReachability {
    private let probeTimeout: Duration

    public init(probeTimeout: Duration = .milliseconds(600)) {
        self.probeTimeout = probeTimeout
    }

    public func isWiFiInterfaceAvailable() async -> Bool {
        await waitForWiFiPath(timeout: probeTimeout)
    }

    public func waitForWiFiPath(timeout: Duration) async -> Bool {
        let probe = WiFiPathProbe()
        let stream = probe.satisfiedStatusStream()
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await isSatisfied in stream where isSatisfied {
                    return true
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }
}

/// 封装 `NWPathMonitor` 生命周期。`@unchecked Sendable`：monitor 与 queue 内部自管，
/// pathUpdateHandler 只在专用 serial queue 调用。
private final class WiFiPathProbe: @unchecked Sendable {
    private let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private let queue = DispatchQueue(label: "com.kirole.wifi.reachability")

    /// 逐次 yield WiFi path 是否 satisfied。流终止（消费者取消）时自动 cancel monitor。
    func satisfiedStatusStream() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            monitor.pathUpdateHandler = { path in
                continuation.yield(path.status == .satisfied)
            }
            continuation.onTermination = { [self] _ in
                monitor.cancel()
            }
            monitor.start(queue: queue)
        }
    }
}
