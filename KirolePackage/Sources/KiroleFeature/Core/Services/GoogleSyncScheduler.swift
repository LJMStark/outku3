import Foundation

@MainActor
public final class SyncScheduler {
    public static let shared = SyncScheduler()

    private var timer: Timer?
    private var lastGoogleSyncTime: Date?
    private var lastAppleSyncTime: Date?
    private let syncInterval: TimeInterval = 300  // 5 minutes
    private let resumeThreshold: TimeInterval = 600  // 10 minutes

    private init() {}

    public func startForegroundSync() {
        stopForegroundSync()
        timer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
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
        let googleStale = lastGoogleSyncTime.map { now.timeIntervalSince($0) > resumeThreshold } ?? true
        let appleStale = lastAppleSyncTime.map { now.timeIntervalSince($0) > resumeThreshold } ?? true

        if googleStale || appleStale {
            await performSync()
        }
    }

    private func performSync() async {
        let now = Date()
        let appState = AppState.shared

        if AuthManager.shared.isGoogleConnected {
            lastGoogleSyncTime = now
            await appState.syncGoogleData()
        }

        let hasAppleIntegration = appState.integrations.contains {
            ($0.type == .appleCalendar || $0.type == .appleReminders) && $0.isConnected
        }

        if hasAppleIntegration {
            lastAppleSyncTime = now
            await appState.syncAppleData()
        }
    }
}

// Backward compatibility alias
public typealias GoogleSyncScheduler = SyncScheduler
