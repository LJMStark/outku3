import Foundation

public actor BLERateLimiter {
    public static let shared = BLERateLimiter()

    private var recentWriteTimestamps: [Date] = []
    private var lastSyncTriggerAt: Date?
    private var lastRefreshTriggerAt: Date?

    private let maxWritesPerSecond = 20
    /// deviceWake(0x30) 触发整轮 sync 的最小间隔，用于掐断
    /// "连上 → wake → sync → 断开 → 重连 → wake" 的连接风暴。
    /// requestRefresh(0x20) 不共用此闸——见 `allowRefreshTrigger`。
    private let syncTriggerMinimumInterval: TimeInterval = 10.0
    /// requestRefresh(0x20) 的独立节流间隔。0x20 是用户物理刷新意图，需独立于 deviceWake：
    /// 既不被其 10s 闸饿死，又用更短的 2s 下限防固件把 0x20 当心跳狂发导致背靠背整轮 sync。
    private let refreshTriggerMinimumInterval: TimeInterval = 2.0

    public func acquireWritePermit() async throws {
        while true {
            let now = Date()
            recentWriteTimestamps = recentWriteTimestamps.filter { now.timeIntervalSince($0) < 1.0 }

            if recentWriteTimestamps.count < maxWritesPerSecond {
                recentWriteTimestamps.append(now)
                return
            }

            guard let earliest = recentWriteTimestamps.min() else {
                continue
            }

            let waitSeconds = max(0.01, 1.0 - now.timeIntervalSince(earliest))
            try await Task.sleep(for: .seconds(waitSeconds))
        }
    }

    /// 节流 deviceWake(0x30) 触发的 performSync：在 syncTriggerMinimumInterval 内最多放行一次。
    /// requestRefresh(0x20) 用独立的 `allowRefreshTrigger`，避免被频繁唤醒饿死。
    public func allowSyncTrigger() -> Bool {
        let now = Date()
        if let lastSyncTriggerAt, now.timeIntervalSince(lastSyncTriggerAt) < syncTriggerMinimumInterval {
            return false
        }

        lastSyncTriggerAt = now
        return true
    }

    /// 节流 requestRefresh(0x20) 触发的 performSync：独立于 `allowSyncTrigger`，
    /// 在 refreshTriggerMinimumInterval 内最多放行一次，防止 0x20 心跳化造成背靠背整轮 sync。
    public func allowRefreshTrigger() -> Bool {
        let now = Date()
        if let lastRefreshTriggerAt, now.timeIntervalSince(lastRefreshTriggerAt) < refreshTriggerMinimumInterval {
            return false
        }

        lastRefreshTriggerAt = now
        return true
    }
}
