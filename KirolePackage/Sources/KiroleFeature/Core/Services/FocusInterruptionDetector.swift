import Foundation

#if os(iOS) && canImport(DeviceActivity)
import DeviceActivity
#endif
#if os(iOS) && canImport(FamilyControls)
import FamilyControls
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Focus Interruption Detection

/// 打断检测的当前状态，驱动专注界面上「检测是否开启」的明示文案。
/// 产品决定（spec 2026-07-09 D-2）：未授权 / 清单空 / 扩展未上线时**无打断检测**，
/// 界面必须如实明示，禁止静默回退到任何近似信号。
public enum FocusInterruptionDetectionState: Equatable, Sendable {
    /// 检测生效中：使用自选分心 App 会被记为打断
    case active
    /// 屏幕使用时间未授权
    case unauthorized
    /// 分心 App 清单为空（清单复用深度专注的自选应用，spec D-1）
    case selectionEmpty
    /// DeviceActivityMonitor 监测扩展未随本构建部署（历史构建/极端降级态）
    case extensionUnavailable
    /// DeviceActivity 阈值事件武装/重挂失败（系统调用抛错）——检测实际没在跑，
    /// 按 D-2 如实明示，禁止装作在检测
    case monitoringFailed
}

/// 专注打断检测源。
///
/// 打断的定义（产品设计，spec D-1/D-3）：**专注期间使用了用户自选的分心 App**。
/// 打开/停留在 Kirole 的专注界面不算打断；被深度专注拦截页挡下的打开尝试不算打断。
/// 旧的「Kirole 回到前台即打断」信号与设计相反，已随本协议移除、不保留回退路径。
@MainActor
public protocol FocusInterruptionDetecting: AnyObject {
    var detectionState: FocusInterruptionDetectionState { get }
    /// 检测到一次打断：参数为打断起始时刻与已知时长（检测源的阈值粒度，分钟级）。
    var onInterruption: ((Date, TimeInterval) -> Void)? { get set }
    /// 专注会话开始时调用；`detectionState != .active` 时应为无害 no-op。
    func startMonitoring()
    /// 专注会话结束时调用。
    func stopMonitoring()
    /// 主动补取挂起期间累积到 App Group 的打断记录并逐条回调。
    /// 被 BLE 后台唤醒（0x20/0x30）时调用：Darwin 通知不投递给完全挂起的进程，故唤醒后需
    /// 主动抽一次，专注快照才不会漏掉应归零的打断（息屏后台链路）。
    func drainPendingInterruptions()
}

/// 默认无操作：仅 ScreenTime 实现有 App Group 待取记录；其它检测源/测试 mock 按需覆盖。
public extension FocusInterruptionDetecting {
    func drainPendingInterruptions() {}
}

// MARK: - Screen Time Implementation

/// 基于 iOS 屏幕使用时间（DeviceActivity）的打断检测。
///
/// 链路：主 App 在会话开始时向 `DeviceActivityCenter` 注册「自选分心 App 累计使用
/// 满 1 分钟」的阈值事件 → 事件触发时系统拉起 `KiroleDeviceActivityMonitor` 扩展
/// （工程根目录同名 target；其 Bridge 常量与本文件镜像，改动必须两边同步）→
/// 扩展把打断时刻写入 App Group 并发 Darwin 通知 → 本类取件后回调
/// `onInterruption`，并重新武装下一个阈值事件。
///
/// 取件时机有三个：Darwin 通知（App 在运行时立即）、App 回到前台（挂起期间的
/// 补取——注意这只是**取件时机**，不是打断信号本身，与 D-2 不冲突）、新会话开始
/// （上一会话残留记录直接丢弃，不污染新会话）。
@MainActor
public final class ScreenTimeInterruptionDetector: FocusInterruptionDetecting {
    public static let shared = ScreenTimeInterruptionDetector()

    /// DeviceActivityMonitor 扩展已随构建部署（2026-07-10，Family Controls
    /// 发布权限获批后接线）。保留此旗标以便未来诊断/降级。
    static let monitorExtensionDeployed = true

    // 与扩展侧（KiroleDeviceActivityMonitor/DeviceActivityMonitorExtension.swift
    // 的 Bridge enum）逐字镜像的三个常量——改动必须两边同步。
    private static let appGroupID = "group.com.kirole.app"
    private static let pendingKey = "focus.pendingInterruptions"
    private static let darwinName = "com.kirole.app.focus.interruption"

    /// 阈值粒度：自选分心 App 累计使用满 1 分钟记一次打断。
    private static let interruptionThresholdSeconds: TimeInterval = 60

    public var onInterruption: ((Date, TimeInterval) -> Void)?

    private let focusGuard: any FocusGuardService
    private var isMonitoring = false
    /// 本会话的阈值事件武装/重挂是否失败过。置位后 detectionState 如实返回
    /// .monitoringFailed（D-2 禁止装作在检测）；下次 start/stopMonitoring 清零重试。
    private var hasArmingFailed = false
    /// 每次（重新）武装阈值事件递增，保证事件名唯一——同名事件在同一监测区间
    /// 只触发一次，重新武装靠换名实现。
    private var eventCounter = 0

    #if os(iOS) && canImport(DeviceActivity)
    private let activityName = DeviceActivityName("kirole.focusSession")
    private let center = DeviceActivityCenter()
    #endif

    init(focusGuard: any FocusGuardService = ScreenTimeFocusGuardService.shared) {
        self.focusGuard = focusGuard
        registerDarwinObserver()
        registerForegroundDrain()
    }

    public var detectionState: FocusInterruptionDetectionState {
        guard Self.monitorExtensionDeployed else { return .extensionUnavailable }
        guard focusGuard.authorizationStatus == .approved else { return .unauthorized }
        guard let selection = focusGuard.currentSelection(), !selection.isEmpty else {
            return .selectionEmpty
        }
        // 静态前提都满足，但系统监测没武装成功——同样不算在检测（D-2）。
        if hasArmingFailed { return .monitoringFailed }
        return .active
    }

    public func startMonitoring() {
        // 新会话重新尝试：上一会话的武装失败不粘住这次。
        hasArmingFailed = false
        guard detectionState == .active else { return }
        // 丢弃上一会话/App 死亡期间的残留记录，避免旧打断立刻污染新会话。
        drainPendingRecords(emit: false)
        #if os(iOS) && canImport(DeviceActivity) && canImport(FamilyControls)
        do {
            try armThresholdEvent()
            isMonitoring = true
        } catch {
            hasArmingFailed = true
            ErrorReporter.log(
                .sync(component: "FocusInterruptionMonitor", underlying: error.localizedDescription),
                context: "ScreenTimeInterruptionDetector.startMonitoring"
            )
        }
        #endif
    }

    public func stopMonitoring() {
        isMonitoring = false
        hasArmingFailed = false
        #if os(iOS) && canImport(DeviceActivity)
        center.stopMonitoring([activityName])
        #endif
    }

    /// 见协议 `drainPendingInterruptions()`：被 BLE 后台唤醒时主动补取 App Group 里挂起期间
    /// 累积的打断记录并逐条回调（等同回前台/Darwin 取件，只是多了一个唤醒时机）。
    public func drainPendingInterruptions() {
        drainPendingRecords(emit: true)
    }

    // MARK: - DeviceActivity arming

    #if os(iOS) && canImport(DeviceActivity) && canImport(FamilyControls)
    /// 以当前自选清单武装一个新的 1 分钟累计使用阈值事件。
    /// 监测区间用全天重复窗（DeviceActivity 要求 schedule），会话边界由
    /// start/stopMonitoring 控制。
    private func armThresholdEvent() throws {
        guard let selection = focusGuard.currentSelection() else {
            throw FocusGuardError.selectionMissing
        }
        let decoded = try PropertyListDecoder().decode(
            FamilyActivitySelection.self,
            from: selection.tokenData
        )
        guard !decoded.applicationTokens.isEmpty || !decoded.categoryTokens.isEmpty else {
            throw FocusGuardError.selectionMissing
        }

        eventCounter += 1
        let event = DeviceActivityEvent(
            applications: decoded.applicationTokens,
            categories: decoded.categoryTokens,
            webDomains: decoded.webDomainTokens,
            threshold: DateComponents(minute: 1)
        )
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        // 换名重挂：先停旧监测再以新事件名启动，实现阈值事件的重新武装。
        center.stopMonitoring([activityName])
        try center.startMonitoring(
            activityName,
            during: schedule,
            events: [DeviceActivityEvent.Name("kirole.interruption.\(eventCounter)"): event]
        )
    }
    #endif

    // MARK: - App Group bridge (records written by the monitor extension)

    /// 取出扩展写入的打断记录。`emit == true` 时逐条回调并（监测中）重新武装
    /// 下一个阈值事件；`false` 时仅清空（新会话开始前丢弃残留）。
    private func drainPendingRecords(emit: Bool) {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else { return }
        let pending = defaults.array(forKey: Self.pendingKey) as? [Double] ?? []
        guard !pending.isEmpty else { return }
        defaults.removeObject(forKey: Self.pendingKey)

        guard emit else { return }
        for timestamp in pending {
            onInterruption?(
                Date(timeIntervalSince1970: timestamp),
                Self.interruptionThresholdSeconds
            )
        }
        #if os(iOS) && canImport(DeviceActivity) && canImport(FamilyControls)
        if isMonitoring {
            do {
                try armThresholdEvent()
            } catch {
                // 重挂失败后不会再有阈值事件——检测实质已停，必须如实明示（D-2）。
                hasArmingFailed = true
                ErrorReporter.log(
                    .sync(component: "FocusInterruptionMonitor", underlying: error.localizedDescription),
                    context: "ScreenTimeInterruptionDetector.rearm"
                )
            }
        }
        #endif
    }

    /// Darwin 通知：扩展触发时若主 App 在运行（含蓝牙后台），立即取件。
    private func registerDarwinObserver() {
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let detector = Unmanaged<ScreenTimeInterruptionDetector>
                    .fromOpaque(observer)
                    .takeUnretainedValue()
                Task { @MainActor in
                    detector.drainPendingRecords(emit: true)
                }
            },
            Self.darwinName as CFString,
            nil,
            .deliverImmediately
        )
    }

    /// App 回到前台时补取挂起期间落在 App Group 里的记录。
    /// 注意：这只是取件时机，打断本身由系统监测判定——不是「回前台即打断」的复活。
    private func registerForegroundDrain() {
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.drainPendingRecords(emit: true)
            }
        }
        #endif
    }
}
