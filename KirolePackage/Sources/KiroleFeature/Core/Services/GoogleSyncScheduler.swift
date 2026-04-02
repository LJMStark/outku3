import Foundation

struct ForegroundSyncPolicy {
    let periodicInterval: TimeInterval = 300  // 5 minutes
    let resumeThrottleInterval: TimeInterval = 2

    func shouldSyncOnResume(now: Date, lastAttempt: Date?) -> Bool {
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= resumeThrottleInterval
    }
}

@MainActor
public final class SyncScheduler {
    public static let shared = SyncScheduler()

    private var timer: Timer?
    private var lastSyncAttemptTime: Date?
    private let policy = ForegroundSyncPolicy()

    private init() {}

    public func startForegroundSync() {
        stopForegroundSync()
        timer = Timer.scheduledTimer(withTimeInterval: policy.periodicInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performSync()
            }
        }
    }

    public func stopForegroundSync() {
        timer?.invalidate()
        timer = nil
    }

    public func syncOnResume() async {
        let now = Date()
        guard policy.shouldSyncOnResume(now: now, lastAttempt: lastSyncAttemptTime) else { return }
        await performSync(triggeredAt: now)
    }

    private func performSync() async {
        await performSync(triggeredAt: Date())
    }

    private func performSync(triggeredAt date: Date) async {
        lastSyncAttemptTime = date
        await AppState.shared.syncConnectedExternalData()
    }
}

// Backward compatibility alias
public typealias GoogleSyncScheduler = SyncScheduler
