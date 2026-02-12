import Foundation

#if os(iOS)
import BackgroundTasks

@MainActor
public final class BLEBackgroundSyncScheduler {
    public static let shared = BLEBackgroundSyncScheduler()
    public static let taskIdentifier = "com.kirole.app.ble.sync"

    private init() {}

    public func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }

            Task { @MainActor in
                await BLESyncCoordinator.shared.performBackgroundSync(task: refreshTask)
            }
        }
    }

    public func schedule() {
        Task { @MainActor in
            let nextDate = await BLESyncCoordinator.shared.nextSyncDate()
            let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
            request.earliestBeginDate = nextDate
            do {
                try BGTaskScheduler.shared.submit(request)
            } catch {
                // 静默处理调度失败
            }
        }
    }
}
#else
@MainActor
public final class BLEBackgroundSyncScheduler {
    public static let shared = BLEBackgroundSyncScheduler()
    public static let taskIdentifier = "com.kirole.app.ble.sync"

    private init() {}

    public func register() {}
    public func schedule() {}
}
#endif
