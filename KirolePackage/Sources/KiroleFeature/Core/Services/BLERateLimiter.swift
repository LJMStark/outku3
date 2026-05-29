import Foundation

public actor BLERateLimiter {
    public static let shared = BLERateLimiter()

    private var recentWriteTimestamps: [Date] = []
    private var lastSyncTriggerAt: Date?

    private let maxWritesPerSecond = 20
    /// 硬件事件（deviceWake / requestRefresh）触发整轮 sync 的最小间隔，
    /// 用于掐断"连上 → wake → sync → 断开 → 重连 → wake"的连接风暴。
    private let syncTriggerMinimumInterval: TimeInterval = 10.0

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

    /// 节流硬件事件触发的 performSync。requestRefresh / deviceWake 共用此闸：
    /// 在 syncTriggerMinimumInterval 内最多放行一次整轮 sync。
    public func allowSyncTrigger() -> Bool {
        let now = Date()
        if let lastSyncTriggerAt, now.timeIntervalSince(lastSyncTriggerAt) < syncTriggerMinimumInterval {
            return false
        }

        lastSyncTriggerAt = now
        return true
    }
}
