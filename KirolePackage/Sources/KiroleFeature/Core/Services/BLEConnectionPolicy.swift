import Foundation

// MARK: - BLE Connection Policy

/// BLE 连接状态机的纯决策逻辑。
///
/// 从 `BLEService` 的 CoreBluetooth 副作用中抽离出来，便于单测且无 I/O。
/// 这些函数是"扫描 / 连接 / 重连是否可以发起"的**唯一真相源**——`BLEService`
/// 只负责把它们的结论接到真实的 `CBCentralManager` 调用上。
///
/// 抽离动机见 BLE 重连卡死复盘：并发 `scanForDevices` 曾覆盖单槽 continuation
/// 造成永久挂起 + `connectionState` 卡在 `.scanning`，UI 永远显示 Searching。
/// 把"能否发起"收敛成基于 `connectionState` 的纯判定后，并发入口会被直接拒绝，
/// 从根本上消除竞态。
public enum BLEConnectionPolicy {

    /// 处于空闲态（没有正在进行的扫描 / 连接 / 已连接）时才允许发起新动作。
    private static func isIdle(_ state: BLEConnectionState) -> Bool {
        switch state {
        case .disconnected, .error:
            return true
        case .scanning, .connecting, .connected:
            return false
        }
    }

    /// 当前状态是否允许发起一次新的扫描。
    ///
    /// 互斥真相源：只要已处于 `.scanning` / `.connecting` / `.connected`，就拒绝新扫描，
    /// 杜绝并发 `scanForDevices` 互相覆盖 `scanCompletion` 与 continuation。
    public static func canBeginScan(state: BLEConnectionState) -> Bool {
        isIdle(state)
    }

    /// 当前状态是否允许发起一次新的连接尝试。
    ///
    /// 同样以 `connectionState` 为互斥真相源，避免并发连接覆盖 `connectCompletion`。
    public static func canBeginConnect(state: BLEConnectionState) -> Bool {
        isIdle(state)
    }

    /// 设备断开后是否应当自动重连。
    ///
    /// 主动断开（sync 收尾、用户点击断开、后台任务到期）**不**应触发自动重连，否则会形成
    /// "连上 → 同步 → 主动断开 → 自动重连 → 设备又发 wake/refresh → 再同步 → 再断开" 的
    /// 连接风暴，并放大扫描竞态。只有意外断开（信号丢失等）且用户开启了自动重连时才重连。
    public static func shouldAutoReconnect(isIntentional: Bool, autoReconnectEnabled: Bool) -> Bool {
        autoReconnectEnabled && !isIntentional
    }

    /// 固件联调是否仍依赖当前 BLE 控制通道。
    public static func shouldKeepConnectionOpenForDebug(
        keepAliveEnabled: Bool,
        wifiDebugRequiresConnection: Bool
    ) -> Bool {
        keepAliveEnabled || wifiDebugRequiresConnection
    }
}
