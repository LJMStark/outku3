import Foundation

public actor BLERateLimiter {
    public static let shared = BLERateLimiter()

    private var recentWriteTimestamps: [Date] = []
    private var lastRefreshRequestAt: Date?

    private let maxWritesPerSecond = 20
    private let refreshMinimumInterval: TimeInterval = 2.0

    public func acquireWritePermit() async {
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
            try? await Task.sleep(for: .seconds(waitSeconds))
        }
    }

    public func allowRefreshRequest() -> Bool {
        let now = Date()
        if let lastRefreshRequestAt, now.timeIntervalSince(lastRefreshRequestAt) < refreshMinimumInterval {
            return false
        }

        lastRefreshRequestAt = now
        return true
    }
}
