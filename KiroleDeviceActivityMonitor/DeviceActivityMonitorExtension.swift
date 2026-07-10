import DeviceActivity
import Foundation

// MARK: - Device Activity Monitor Extension
//
// 专注打断检测的系统侧回调进程（协议文档 §9 / spec 2026-07-09 任务1 第 2 步接线）。
// 主 App 在专注会话开始时向 DeviceActivityCenter 注册「自选分心 App 累计使用满 1 分钟」
// 的阈值事件；事件触发时系统拉起本扩展，本扩展把打断时刻写入 App Group 并发 Darwin
// 通知。主 App 侧的桥接与常量镜像见 KirolePackage 的 FocusInterruptionDetector.swift
// （extension 不链接 KiroleFeature 包——扩展进程有严格内存上限，保持零依赖；
// 改动下列三个常量时必须两边同步）。

private enum Bridge {
    static let appGroupID = "group.com.kirole.app"
    static let pendingKey = "focus.pendingInterruptions"
    static let darwinName = "com.kirole.app.focus.interruption"
}

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)
        recordInterruption(at: Date())
    }

    private func recordInterruption(at timestamp: Date) {
        guard let defaults = UserDefaults(suiteName: Bridge.appGroupID) else { return }
        var pending = defaults.array(forKey: Bridge.pendingKey) as? [Double] ?? []
        pending.append(timestamp.timeIntervalSince1970)
        defaults.set(pending, forKey: Bridge.pendingKey)

        // Darwin 通知只做"叫醒"：主 App 在运行（含蓝牙后台）时立即取件；
        // 主 App 被挂起时通知丢失也无妨——记录已落 App Group，
        // 下次 App 激活/开始新会话时统一取件。
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(Bridge.darwinName as CFString),
            nil,
            nil,
            true
        )
    }
}
