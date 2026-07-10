import Foundation

#if os(iOS) && canImport(DeviceActivity)
import DeviceActivity
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
    /// DeviceActivity 监测扩展尚未随 App 部署（extension target 的
    /// Family Controls 发布权限需向 Apple 单独申请，批复后接线）
    case extensionUnavailable
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
}

// MARK: - Screen Time Implementation

/// 基于 iOS 屏幕使用时间（DeviceActivity）的打断检测。
///
/// 完整链路需要一个 `DeviceActivityMonitor` app extension（独立 target）在
/// 阈值事件触发时经 App Group 回报——该 extension 的 Family Controls
/// **发布**权限需向 Apple 单独申请（数天级审批），因此分两步落地：
/// 1. 本文件（已落地）：协议、状态判定、与 FocusSessionService 的接线；
///    `monitorExtensionDeployed == false` 使 `detectionState` 恒为
///    `.extensionUnavailable`，UI 如实显示"检测未开启"——绝不声称在检测。
/// 2. 扩展 target + 事件桥接（待 Apple 批复后）：翻转
///    `monitorExtensionDeployed`，在 `startMonitoring()` 里调
///    `DeviceActivityCenter.startMonitoring(_:during:events:)`（selection 取自
///    深度专注清单、分钟级阈值事件），extension 回报经 App Group +
///    Darwin 通知桥回 `onInterruption`。
@MainActor
public final class ScreenTimeInterruptionDetector: FocusInterruptionDetecting {
    public static let shared = ScreenTimeInterruptionDetector()

    /// DeviceActivityMonitor 扩展是否已随本构建部署。见类型注释的两步落地说明。
    static let monitorExtensionDeployed = false

    public var onInterruption: ((Date, TimeInterval) -> Void)?

    private let focusGuard: any FocusGuardService

    init(focusGuard: any FocusGuardService = ScreenTimeFocusGuardService.shared) {
        self.focusGuard = focusGuard
    }

    public var detectionState: FocusInterruptionDetectionState {
        guard Self.monitorExtensionDeployed else { return .extensionUnavailable }
        guard focusGuard.authorizationStatus == .approved else { return .unauthorized }
        guard let selection = focusGuard.currentSelection(), !selection.isEmpty else {
            return .selectionEmpty
        }
        return .active
    }

    public func startMonitoring() {
        guard detectionState == .active else { return }
        // 扩展落地前 monitorExtensionDeployed == false，此分支不可达；
        // 落地后在此启动 DeviceActivityCenter 监测并订阅扩展回报。
    }

    public func stopMonitoring() {
        // 对应 startMonitoring 的清理；当前无活动监测可停。
    }
}
