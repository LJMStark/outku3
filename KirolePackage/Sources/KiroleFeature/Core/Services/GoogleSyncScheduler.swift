import Foundation

@MainActor
public final class GoogleSyncScheduler: @unchecked Sendable {
    public static let shared = GoogleSyncScheduler()

    private var timer: Timer?
    private var lastSyncTime: Date?
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
        guard let lastSync = lastSyncTime else {
            await performSync()
            return
        }
        if Date().timeIntervalSince(lastSync) > resumeThreshold {
            await performSync()
        }
    }

    private func performSync() async {
        lastSyncTime = Date()
        await AppState.shared.syncGoogleData()
    }
}
