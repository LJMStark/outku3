import Foundation

/// 设备任务库（`0x23`）的成员集合口径——**唯一**决定「哪些任务、以什么顺序上 wire」的地方。
///
/// 凡是产出有序集合或集合指纹的调用点都必须走这里；只对单个任务问 yes/no 并据此管理资源
/// 生命周期（取消在途文案生成、驱逐缓存）的调用点继续用 `isEligibleForHardwareTaskLibrary`
/// 原谓词——见 `AppState.prepareChangedTaskLibraryPhaseTexts` 的注释。
enum TaskLibraryMembership {
    /// 单次事务的成员上限（2026-08-04 客户拍板）。超出静默截断，App 不做任何 UI 提示。
    ///
    /// 与两个**显示条数**上限不是一回事，别混：`ScreenSize.maxTasks`（DayPack 屏幕展示 3/5 条）
    /// 和 `BLEDataEncoder` 里 DayPack events 的 8 条都更严格，且约束的是屏幕一次显示多少，
    /// 本常量约束的是设备**保存**多少（协议 §6.8.1 的「显示条数与保存条数分离」）。
    ///
    /// 设备侧仍然**不得**自行截断：容量放不下的正确做法是整次事务失败回 `capacityExceeded`。
    static let maxRecords = 20

    /// 当天任务库的有序成员集合。保持 `AppState.tasks` 的数组顺序（= 设备队列顺序，协议 §6.8.1），
    /// **不重排**——按优先级重排会让设备队列与 App 列表分叉，与 ADR 0014/0026 冲突。
    ///
    /// 先筛后截（不是先截后筛）：未来 / 过期 / 已完成 / 待删除的任务不占 20 个名额。
    static func members(
        of tasks: [TaskItem],
        on date: Date,
        calendar: Calendar
    ) -> [TaskItem] {
        Array(
            tasks.lazy
                .filter { $0.isEligibleForHardwareTaskLibrary(on: date, calendar: calendar) }
                .prefix(maxRecords)
        )
    }

    static func memberIDs(
        of tasks: [TaskItem],
        on date: Date,
        calendar: Calendar
    ) -> Set<String> {
        Set(members(of: tasks, on: date, calendar: calendar).map(\.hardwareIdentifier))
    }
}
