import Foundation

@MainActor
public final class SyncScheduler: @unchecked Sendable {
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

        if AuthManager.shared.isGoogleConnected {
            lastGoogleSyncTime = now
            await AppState.shared.syncGoogleData()
        }

        let appState = AppState.shared
        let calendarConnected = appState.integrations.first(where: { $0.type == .appleCalendar })?.isConnected ?? false
        let remindersConnected = appState.integrations.first(where: { $0.type == .appleReminders })?.isConnected ?? false

        if calendarConnected || remindersConnected {
            lastAppleSyncTime = now
            await appState.syncAppleData()
        }
    }
}

// Backward compatibility alias
public typealias GoogleSyncScheduler = SyncScheduler
