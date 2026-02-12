import Foundation

// MARK: - BLE Sync Coordinator

@MainActor
public final class BLESyncCoordinator {
    public static let shared = BLESyncCoordinator()

    private let bleService = BLEService.shared
    private let dayPackGenerator = DayPackGenerator.shared
    private let localStorage = LocalStorage.shared
    private let policy = BLESyncPolicy()

    private var lastSyncSucceeded = true

    /// Connection timeout in seconds. Configurable for larger screen sizes
    /// that require longer refresh times (e.g., 7.3寸 full refresh ~12s).
    public var connectionTimeoutSeconds: TimeInterval = 30

    private init() {}

    public func nextSyncDate() async -> Date {
        let lastSync = await localStorage.loadLastBleSyncTime()
        return policy.nextSyncTime(now: Date(), lastSync: lastSync)
    }

    public func performSync(force: Bool = false) async {
        let now = Date()
        let lastSync = await localStorage.loadLastBleSyncTime()

        let appState = AppState.shared
        let dayPack = await dayPackGenerator.generateDayPack(
            pet: appState.pet,
            tasks: appState.tasks,
            events: appState.events,
            weather: appState.weather,
            streak: appState.streak,
            deviceMode: appState.deviceMode
        )

        let fingerprint = dayPack.stableFingerprint()
        let lastHash = await localStorage.loadLastDayPackHash()
        let contentChanged = lastHash != fingerprint

        guard policy.shouldSync(now: now, lastSync: lastSync, contentChanged: contentChanged, force: force) else {
            return
        }

        let timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(self.connectionTimeoutSeconds))
            if self.bleService.connectionState.isConnected {
                self.bleService.disconnect()
            }
        }
        defer { timeoutTask.cancel() }

        do {
            // Connect with retry: 3 attempts, 1s/2s/4s backoff
            var connected = false
            for attempt in 0..<3 {
                do {
                    try await bleService.connectToPreferredDevice(timeout: 10)
                    connected = true
                    break
                } catch {
                    #if DEBUG
                    print("[BLESyncCoordinator] Connect attempt \(attempt + 1)/3 failed")
                    #endif
                    if attempt < 2 {
                        try? await Task.sleep(for: .seconds(Double(1 << attempt)))
                    }
                }
            }
            guard connected else { throw BLEError.connectionFailed(nil) }

            try await bleService.syncTime()

            if contentChanged {
                // Send DayPack with retry: 2 attempts, 500ms/1s backoff
                var sent = false
                for attempt in 0..<2 {
                    do {
                        try await bleService.sendDayPack(dayPack)
                        sent = true
                        break
                    } catch {
                        #if DEBUG
                        print("[BLESyncCoordinator] Write attempt \(attempt + 1)/2 failed")
                        #endif
                        if attempt < 1 {
                            try? await Task.sleep(for: .milliseconds(500 * (attempt + 1)))
                        }
                    }
                }
                if sent {
                    await localStorage.saveLastDayPackHash(fingerprint)
                }
            }

            await bleService.requestEventLogsIfNeeded()
            let completedAt = Date()
            await localStorage.saveLastBleSyncTime(completedAt)
            bleService.updateLastSyncTime(completedAt)
            lastSyncSucceeded = true
        } catch {
            lastSyncSucceeded = false
            #if DEBUG
            print("[BLESyncCoordinator] Sync failed: \(error.localizedDescription)")
            #endif
        }

        if bleService.connectionState.isConnected {
            bleService.disconnect()
        }
    }
}

#if os(iOS)
import BackgroundTasks

@MainActor
public extension BLESyncCoordinator {
    func performBackgroundSync(task: BGAppRefreshTask) async {
        task.expirationHandler = { [weak self] in
            Task { @MainActor in
                self?.bleService.disconnect()
            }
        }

        await performSync()
        BLEBackgroundSyncScheduler.shared.schedule()
        task.setTaskCompleted(success: lastSyncSucceeded)
    }
}
#endif
