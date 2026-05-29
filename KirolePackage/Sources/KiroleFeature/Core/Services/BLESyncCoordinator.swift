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
            deviceMode: appState.deviceMode,
            userProfile: appState.userProfile
        )

        let fingerprint = dayPack.stableFingerprint()
        let lastHash = await localStorage.loadLastDayPackHash()
        let contentChanged = lastHash != fingerprint

        guard policy.shouldSync(now: now, lastSync: lastSync, contentChanged: contentChanged, force: force) else {
            return
        }

        let timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(self.connectionTimeoutSeconds))
            // keep-alive 调试模式下不因超时主动断连，保留长连接供固件调试。
            if self.bleService.connectionState.isConnected, !self.bleService.keepAliveDebugMode {
                self.bleService.disconnect()
            }
        }
        defer { timeoutTask.cancel() }

        do {
            // keep-alive 模式下连接可能仍保持。已连接就跳过连接步骤——否则 connectKnownPeripheral 会因
            // canBeginConnect=false 抛 .connectionInProgress，导致首次同步后每轮同步/补传全部失败。
            if !bleService.connectionState.isConnected {
                // Connect with retry: 3 attempts, 1s/2s/4s backoff
                var connected = false
                var lastConnectError: Error?
                for attempt in 0..<3 {
                    do {
                        try await bleService.connectToPreferredDevice(timeout: 10)
                        connected = true
                        break
                    } catch {
                        lastConnectError = error
                        #if DEBUG
                        print("[BLESyncCoordinator] Connect attempt \(attempt + 1)/3 failed: \(error.localizedDescription)")
                        #endif
                        if attempt < 2 {
                            try? await Task.sleep(for: .seconds(Double(1 << attempt)))
                        }
                    }
                }
                // 保留底层原因：connectionFailed(error) 的描述会带上 underlying，外层 catch 即可在 Release 看到。
                guard connected else { throw BLEError.connectionFailed(lastConnectError) }
            }

            try await bleService.syncTime()
            try await bleService.sendPetStatus(
                appState.pet,
                companionCharacter: appState.userProfile.companionCharacter
            )

            if contentChanged {
                // Send DayPack with retry: 2 attempts, 500ms/1s backoff
                var sent = false
                var lastWriteError: Error?
                for attempt in 0..<2 {
                    do {
                        try await bleService.sendDayPack(dayPack)
                        sent = true
                        break
                    } catch {
                        lastWriteError = error
                        #if DEBUG
                        print("[BLESyncCoordinator] Write attempt \(attempt + 1)/2 failed: \(error.localizedDescription)")
                        #endif
                        if attempt < 1 {
                            try? await Task.sleep(for: .milliseconds(500 * (attempt + 1)))
                        }
                    }
                }
                if sent {
                    await localStorage.saveLastDayPackHash(fingerprint)
                } else {
                    // DayPack 是 App→硬件最核心的帧；两次写失败必须留痕，否则硬件一直显示旧数据、
                    // App 端在 Release 下毫无信号（下轮会重试，但失败本身不可见）。
                    ErrorReporter.log(
                        .sync(component: "BLE DayPack", underlying: lastWriteError?.localizedDescription ?? "write failed after 2 attempts"),
                        context: "BLESyncCoordinator.performSync"
                    )
                }
            }

            await appState.flushPendingCustomCompanionPushIfNeeded()

            if let reminder = await SmartReminderService.shared.evaluateAndPushReminder(
                tasks: appState.tasks,
                pet: appState.pet
            ) {
                do {
                    try await bleService.sendSmartReminder(
                        text: reminder.text,
                        urgency: reminder.urgency,
                        petMood: appState.pet.mood
                    )
                } catch {
                    ErrorReporter.log(
                        .sync(component: "BLE SmartReminder", underlying: error.localizedDescription),
                        context: "BLESyncCoordinator.performSync"
                    )
                }
            }

            await bleService.requestEventLogsIfNeeded()
            let completedAt = Date()
            await localStorage.saveLastBleSyncTime(completedAt)
            bleService.updateLastSyncTime(completedAt)
            lastSyncSucceeded = true
        } catch {
            lastSyncSucceeded = false
            // 整轮同步失败的最终兜底——必须无条件上报。否则 Release/TestFlight 包（硬件团队拿的就是它）
            // 下 #if DEBUG 被裁剪，sync 失败彻底静默，硬件团队无法区分“没触发同步”和“同步失败了”。
            ErrorReporter.log(
                .sync(component: "BLESyncCoordinator", underlying: error.localizedDescription),
                context: "BLESyncCoordinator.performSync"
            )
        }

        // 同步收尾默认主动断连（省电脉冲式同步）；keep-alive 调试模式下保持连接不断。
        if bleService.connectionState.isConnected, !bleService.keepAliveDebugMode {
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
                guard let self, !self.bleService.keepAliveDebugMode else { return }
                self.bleService.disconnect()
            }
        }

        await AuthManager.shared.initialize()
        await AppState.shared.syncConnectedExternalData()
        await performSync()
        BLEBackgroundSyncScheduler.shared.schedule()
        task.setTaskCompleted(success: lastSyncSucceeded)
    }
}
#endif
