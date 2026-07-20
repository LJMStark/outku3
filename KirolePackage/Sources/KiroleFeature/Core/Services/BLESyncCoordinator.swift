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
    /// 上次成功发出的 Weather(0x04) 指纹（上 wire 的四个量化值）。内存态即可：重启后首轮
    /// 多发一次 ~10B 小帧，无害；不入 LocalStorage 以避开 resettable key 的测试隔离成本。
    private var lastSentWeatherFingerprint: String?
    /// In-flight 守卫：防止并发 performSync 重复发整轮（keep-alive 常驻连接后更易触发）。
    private var isSyncing = false
    /// 在途同步期间被丢弃的 force:true 请求；当前同步收尾后补跑一次，避免硬件 requestRefresh 被吞。
    private var pendingForceSync = false

    /// Connection timeout in seconds. Configurable for larger screen sizes
    /// that require longer refresh times (e.g., 7.3寸 full refresh ~12s).
    public var connectionTimeoutSeconds: TimeInterval = 30

    private init() {}

    public func nextSyncDate() async -> Date {
        let lastSync = await localStorage.loadLastBleSyncTime()
        return policy.nextSyncTime(now: Date(), lastSync: lastSync)
    }

    public func performSync(force: Bool = false) async {
        // 并发守卫：keep-alive 默认开后连接常驻，多触发源（后台刷新 / 硬件 0x20·0x30 / 指纹变化）可能并发进入。
        // 以前靠"已连接→.connectionInProgress"意外串行；连接跳过后需显式守卫，否则会重复发整轮 + 帧交错。
        // @MainActor 下在首个 await 前同步置位，保证原子。被丢弃的 force:true 记下、收尾后补跑一次——
        // 否则在途的 force:false 若随后被 shouldSync 拦下，硬件的强制刷新就丢了。
        guard !isSyncing else {
            if force { pendingForceSync = true }
            return
        }
        isSyncing = true
        defer {
            isSyncing = false
            if pendingForceSync {
                pendingForceSync = false
                Task { @MainActor in await self.performSync(force: true) }
            }
        }

        let now = Date()
        let lastSync = await localStorage.loadLastBleSyncTime()

        let appState = AppState.shared
        // 冷启动防御：0x20/0x30 可在 loadLocalData 完成前直呼本方法，用空 tasks/events 组出
        // 空 DayPack 推上硬件（闪一屏空首页）。其余入口（syncConnectedExternalData 等）都已等待，
        // 这里补齐（幂等，加载完成后零开销）。2026-07-04 审计 F3。
        await appState.ensureInitialLoadComplete()
        // v2.5.0: the hardware bubble shows the SAME line as the App home. Refresh it, then
        // feed currentPetDialogue into the DayPack so both surfaces stay in sync.
        await appState.refreshSharedPetDialogueIfNeeded()
        let dayPack = await dayPackGenerator.generateDayPack(
            pet: appState.pet,
            tasks: appState.tasks,
            events: appState.events,
            weather: appState.weather,
            deviceMode: appState.deviceMode,
            userProfile: appState.userProfile,
            screenSize: bleService.hardwareScreenSize,
            petDialogue: appState.currentPetDialogue
        )

        let fingerprint = dayPack.stableFingerprint()
        let lastHash = await localStorage.loadLastDayPackHash()
        let contentChanged = lastHash != fingerprint
        // 天气单独参与轮次放行（不影响 DayPack 发送判定）：天气已移出 DayPack 指纹，若不在
        // 这里放行，"只有天气变化"时 0x04 要等到点轮（白天 1h/夜间 4h）才能上硬件顶栏。
        // 天气变化放行的轮只发 Time/PetStatus/Weather 小帧——DayPack 指纹未变不会全刷。
        let w = appState.weather
        // hasData=false 是无定位权限 / WeatherKit 失败时的占位默认（22/26/18 sunny）——App 头部
        // 用 hasData 把它藏掉（AppHeaderView），BLE 侧同样不得把假天气发上硬件顶栏：无真实数据
        // 时不发 0x04、也不以天气名义放行轮次，硬件保持上次显示（peer review 2026-07-04）。
        let weatherFingerprint: String? = w.hasData
            ? "\(w.temperature)|\(w.highTemp)|\(w.lowTemp)|\(w.condition)"
            : nil
        let weatherChanged = weatherFingerprint != nil && weatherFingerprint != lastSentWeatherFingerprint

        guard policy.shouldSync(now: now, lastSync: lastSync, contentChanged: contentChanged || weatherChanged, force: force) else {
            return
        }

        let timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(self.connectionTimeoutSeconds))
            guard !Task.isCancelled else { return }
            // 大帧（0x15 头像 ≤1MiB ≈ 2093 片、限流下 1-2 分钟）传输中不掐线：
            // 30s 超时到点先等它结束再评估，否则大头像永远发不完、整帧无限重试。
            while !Task.isCancelled, self.bleService.isChunkedTransferInFlight {
                try? await Task.sleep(for: .seconds(5))
            }
            guard !Task.isCancelled else { return }
            // 硬件调试需要长连接时不因超时主动断连。
            if self.bleService.connectionState.isConnected,
               !self.bleService.shouldKeepConnectionOpenForDebug {
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
                companionCharacter: appState.userProfile.companionCharacter,
                // v2.5.32: 例行 sync 恒重申自定义激活态——0x01 不再把用户图刷回内置。
                customActive: appState.userProfile.customCompanionId != nil
            )
            // 顶栏天气走独立 Weather(0x04) 帧（协议 §4.5），每轮发送。此前 sendWeather 只挂在
            // 零调用的 syncAllData 上——硬件顶栏天气从未被更新过（2026-07-04 审计 F1）。
            // 辅助帧单独容错：写失败只记日志、不算轮失败——顶栏装饰不能阻断后面的 DayPack
            // 重试与离线事件补传（与 DayPack/eventLog 的既有"失败不阻断"哲学一致）。
            if let weatherFingerprint {
                do {
                    try await bleService.sendWeather(w)
                    lastSentWeatherFingerprint = weatherFingerprint
                } catch {
                    ErrorReporter.log(
                        .sync(component: "BLE Weather", underlying: error.localizedDescription),
                        context: "BLESyncCoordinator.performSync"
                    )
                }
            }

            var dayPackSendFailed = false
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
                    // 不在此处 throw：后面的事件补传（requestEventLogsIfNeeded）是核心功能，
                    // 不能因显示帧写失败而放弃；整轮成败在末尾按本标志判定。
                    dayPackSendFailed = true
                    ErrorReporter.log(
                        .sync(component: "BLE DayPack", underlying: lastWriteError?.localizedDescription ?? "write failed after 2 attempts"),
                        context: "BLESyncCoordinator.performSync"
                    )
                }
            }

            await appState.flushPendingCustomCompanionPushIfNeeded()

            let eventLogRequestSucceeded = await bleService.requestEventLogsIfNeeded()
            if dayPackSendFailed || !eventLogRequestSucceeded {
                // 硬件还在显示旧内容，或事件补传请求(0x20)没写出去：这轮不算成功。补传是核心功能，
                // 0x20 写失败与 DayPack 写失败同等对待——不更新 lastBleSyncTime（避免 Settings 显示
                // 绿色"刚同步过"），点亮 lastSyncFailed 供用户重试；lastBleSyncTime 不前进
                // 也让 BLESyncPolicy 更早安排下一轮。
                bleService.lastSyncFailed = true
                lastSyncSucceeded = false
            } else {
                let completedAt = Date()
                await localStorage.saveLastBleSyncTime(completedAt)
                bleService.updateLastSyncTime(completedAt)
                bleService.lastSyncFailed = false
                lastSyncSucceeded = true
            }
        } catch {
            lastSyncSucceeded = false
            bleService.lastSyncFailed = true
            // 整轮同步失败的最终兜底——必须无条件上报。否则 Release/TestFlight 包（硬件团队拿的就是它）
            // 下 #if DEBUG 被裁剪，sync 失败彻底静默，硬件团队无法区分“没触发同步”和“同步失败了”。
            ErrorReporter.log(
                .sync(component: "BLESyncCoordinator", underlying: error.localizedDescription),
                context: "BLESyncCoordinator.performSync"
            )
        }

        // 智能提醒在断连前统一投递：硬件可达 → 只推 E-ink（手机保持安静）；硬件离线 → 落 iOS 本地通知，
        // 否则离线用户这条温和提醒就彻底丢了（NotificationService 此前完全没有调用方）。
        await deliverSmartReminder(appState: appState)

        // 同步收尾默认主动断连（省电脉冲式同步）；硬件调试仍需控制通道时保持连接不断。
        // 专注会话进行中也保持连接：硬件靠这条常驻连接的 notify(0x20) 唤醒被 iOS 挂起的 App
        // 推送实时专注状态（息屏后台链路）；脉冲式断连只服务空闲期。
        // 取舍（codex 复审 2026-07-13 发现3）：专注期不主动断连 → 写失败的"僵尸连接"不在此回收；
        // 但反向为写失败断连会经 handleDeviceDisconnected 杀掉专注会话（更糟），真正断链由
        // CoreBluetooth didDisconnect 兜底（→endSession→重连）。故刻意不为写失败断连。
        if bleService.connectionState.isConnected,
           !bleService.shouldKeepConnectionOpenForDebug,
           FocusSessionService.shared.activeSession == nil,
           // 头像大帧还在发就不断——由超时任务等它收尾（发完后连接闲置到下一轮 sync 收口，
           // 只是电池成本、无正确性问题）。
           !bleService.isChunkedTransferInFlight {
            bleService.disconnect()
        }
    }

    /// 路由一条到期的智能提醒：硬件可达就推设备，否则落本地通知，让离线用户也收得到。
    /// 每轮同步只评估一次（限流逻辑在 SmartReminderService 内）。
    private func deliverSmartReminder(appState: AppState) async {
        guard let reminder = await SmartReminderService.shared.evaluateAndPushReminder(
            tasks: appState.tasks,
            pet: appState.pet
        ) else { return }

        if bleService.connectionState.isConnected {
            do {
                try await bleService.sendSmartReminder(
                    text: reminder.text,
                    urgency: reminder.urgency,
                    petMood: appState.pet.mood
                )
                SmartReminderService.shared.markReminderSent()
                return
            } catch {
                ErrorReporter.log(
                    .sync(component: "BLE SmartReminder", underlying: error.localizedDescription),
                    context: "BLESyncCoordinator.deliverSmartReminder"
                )
                // 已连接却写失败：落本地通知兜底，别让提醒丢了。
            }
        }

        // 硬件离线（或 BLE 写失败）：E-ink 显示不了，回退到 iOS 本地通知。
        await NotificationService.shared.refreshAuthorizationStatus()
        let delivered = await NotificationService.shared.scheduleLocalNotification(from: reminder)
        // 只有确实投递了才消耗 30 分钟冷却；BLE 与通知都失败时留待下轮重试。
        if delivered {
            SmartReminderService.shared.markReminderSent()
        }
    }
}

#if os(iOS)
// @preconcurrency: BGAppRefreshTask 未标注 Sendable，但 setTaskCompleted 可跨线程调用（Apple 的
// OperationQueue 范式即在 completionBlock off-main 调用），到期 handler 需同步结案故必须捕获 task。
@preconcurrency import BackgroundTasks
import os

@MainActor
public extension BLESyncCoordinator {
    func performBackgroundSync(task: BGAppRefreshTask) async {
        // 本次任务局部的线程安全幂等结案器：到期(可能在非主线程)与正常路径都调 complete，
        // unfair lock 保证 setTaskCompleted 只发生一次（重复调用会 crash，漏调会被 watchdog 强杀）。
        let completed = OSAllocatedUnfairLock(initialState: false)
        @Sendable func complete(success: Bool) {
            let firstTime = completed.withLock { done -> Bool in
                guard !done else { return false }
                done = true
                return true
            }
            if firstTime {
                task.setTaskCompleted(success: success)
            }
        }

        task.expirationHandler = { [weak self] in
            // 到期必须【同步】结案，不能排队等 MainActor（系统可能马上挂起进程，晚一步即被 watchdog
            // 强杀并削减后台预算）。断连优先级更低，丢到 MainActor 即可。专注会话或
            // Wi-Fi 联调进行中保持连接，供硬件 notify 和热点关闭/查询继续使用。
            complete(success: false)
            Task { @MainActor in
                guard let self,
                      FocusSessionService.shared.activeSession == nil,
                      !self.bleService.shouldKeepConnectionOpenForDebug,
                      !self.bleService.isChunkedTransferInFlight else { return }
                self.bleService.disconnect()
            }
        }

        await AuthManager.shared.initialize()
        await AppState.shared.syncConnectedExternalData()
        await performSync()
        BLEBackgroundSyncScheduler.shared.schedule()
        complete(success: lastSyncSucceeded)
    }
}
#endif
