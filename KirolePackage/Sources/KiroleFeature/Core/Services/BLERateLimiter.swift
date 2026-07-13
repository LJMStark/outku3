import Foundation

public actor BLERateLimiter {
    public static let shared = BLERateLimiter()

    private var recentWriteTimestamps: [Date] = []
    private var lastSyncTriggerAt: Date?
    private var lastRefreshTriggerAt: Date?
    private var lastFocusRefreshTriggerAt: Date?

    private let maxWritesPerSecond = 20
    /// deviceWake(0x30) 触发整轮 sync 的最小间隔，用于掐断
    /// "连上 → wake → sync → 断开 → 重连 → wake" 的连接风暴。
    /// requestRefresh(0x20) 不共用此闸——见 `allowRefreshTrigger`。
    private let syncTriggerMinimumInterval: TimeInterval = 10.0
    /// requestRefresh(0x20) 的独立节流间隔（合并窗）。0x20 是用户物理刷新意图，需独立于
    /// deviceWake：既不被其 10s 闸饿死，又用 60s 合并窗把整轮 sync 去抖为每分钟最多一次——
    /// 联调期固件会把 0x20 当 ~2s 心跳狂发，60s 窗把 30 次/分的背靠背 sync 合并为 ≤1 次/分；
    /// 固件停止心跳后，一次用户按键即时触发（窗内无近期触发即放行）。根因在固件侧（0x20 不应
    /// 心跳化），此为 App 侧临时兜底；固件修好后可回调更短值。见协议 §8.5。
    private let refreshTriggerMinimumInterval: TimeInterval = 60.0
    /// requestRefresh(0x20) 触发的**专注状态回推**(0x14) 的独立短闸。专注推送刻意放在上面 60s
    /// 合并窗**之前**（要按时更新瓶子/段位、不被整轮 sync 去抖饿死），因此需自带限流：否则固件把
    /// 0x20 当 ~2s 心跳狂发时，每个 0x20 各起一个 Task，可在首个 BLE 写完成、去重键更新之前并发
    /// 通过检查、无界排入写队列（codex 复审 2026-07-13 发现1）。20s 足以把 ~2s 心跳压到 ≤3 次/分，
    /// 又不 throttle 任何合理节奏（设计意图 ~5 分钟/次，见 §5.7）。
    private let focusRefreshTriggerMinimumInterval: TimeInterval = 20.0

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

    /// 节流 requestRefresh(0x20) 触发的专注状态(0x14)回推：actor 原子 check-and-set，
    /// 并发的 0x20 突发里只放行一个、稳态心跳压到 ≤1 次/`focusRefreshTriggerMinimumInterval`。
    /// 独立于 `allowRefreshTrigger`（整轮 sync 的 60s 合并窗）。见协议 §5.7 / §8.5。
    public func allowFocusRefreshTrigger() -> Bool {
        let now = Date()
        if let lastFocusRefreshTriggerAt,
           now.timeIntervalSince(lastFocusRefreshTriggerAt) < focusRefreshTriggerMinimumInterval {
            return false
        }

        lastFocusRefreshTriggerAt = now
        return true
    }
}
