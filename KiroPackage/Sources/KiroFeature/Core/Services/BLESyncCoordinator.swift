import Foundation

// MARK: - BLE Sync Coordinator

@MainActor
public final class BLESyncCoordinator {
    public static let shared = BLESyncCoordinator()

    private let bleService = BLEService.shared
    private let dayPackGenerator = DayPackGenerator.shared
    private let localStorage = LocalStorage.shared
    private let policy = BLESyncPolicy()

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
            try? await Task.sleep(for: .seconds(30))
            if self.bleService.connectionState.isConnected {
                self.bleService.disconnect()
            }
        }
        defer { timeoutTask.cancel() }

        do {
            try await bleService.connectToPreferredDevice(timeout: 10)
            try await bleService.syncTime()

            if contentChanged {
                try await bleService.sendDayPack(dayPack)
                await localStorage.saveLastDayPackHash(fingerprint)
            }

            await bleService.requestEventLogsIfNeeded()
            let completedAt = Date()
            await localStorage.saveLastBleSyncTime(completedAt)
            bleService.updateLastSyncTime(completedAt)
        } catch {
            // 静默处理 BLE 同步失败
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
        task.setTaskCompleted(success: true)
    }
}
#endif
