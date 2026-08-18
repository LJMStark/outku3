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
                      !self.policy.shouldHoldConnectionForCustomAvatar(
                        chunkedTransferInFlight: self.bleService.isChunkedTransferInFlight,
                        operationState: AppState.shared.customAvatarOperationState
                      ) else { return }
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
