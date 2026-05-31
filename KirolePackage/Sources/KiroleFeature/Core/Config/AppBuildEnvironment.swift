import Foundation

// MARK: - App Build Environment

/// 构建环境判定。
///
/// 用途：把"仅联调可见"的硬件 / 固件调试开关，**同时**暴露给 DEBUG 包和 TestFlight 包，
/// 但对 App Store 正式上架包隐藏。
///
/// 动机：硬件团队拿到的"测试版本"通常是 **TestFlight 包（Release 配置）**，不是 Xcode 直连的
/// DEBUG 包。如果调试开关只用 `#if DEBUG` 包裹，TestFlight 包里根本不会出现，硬件团队找不到。
/// 因此这里提供 `showsHardwareDebugTools`，用 `DEBUG || isTestFlight` 作为门控真相源。
public enum AppBuildEnvironment {

    /// 是否为 TestFlight 安装。
    ///
    /// 判据：TestFlight 安装的收据文件名为 `sandboxReceipt`，App Store 正式包为 `receipt`。
    /// 模拟器 / 未签名包通常没有收据 URL，返回 `false`。
    /// 是否为 TestFlight 安装。进程生命周期内不变，故惰性求值一次后缓存——避免在 `keepAliveDebugMode`
    /// 等热路径 getter 里反复执行 `fileExists` 同步系统调用。
    public static let isTestFlight: Bool = {
        // 必须校验收据文件**确实存在**：`sandboxReceipt` 文件名不是 TestFlight 专属，Xcode 开发 /
        // Ad Hoc 也可能出现该 URL 但文件不存在；只有 TestFlight 安装才会落地真实的 sandboxReceipt 文件。
        guard let receiptURL = Bundle.main.appStoreReceiptURL,
              FileManager.default.fileExists(atPath: receiptURL.path) else { return false }
        return receiptURL.lastPathComponent == "sandboxReceipt"
    }()

    /// 是否应暴露面向硬件 / 固件联调的开发者开关。
    ///
    /// **测试阶段：恒 `true`、全包可见。** 尚无 App Store 正式包，硬件 / 固件调试工具应随时可用。
    /// 原先用 `DEBUG || isTestFlight` 门控，但 `isTestFlight` 在真机 TestFlight 上不可靠——
    /// 新版 iOS 的 `appStoreReceiptURL` 收据文件常不落地（StoreKit 2 不再写旧收据），导致门控
    /// 误判为 false、把调试开关与 keep-alive 默认值一并藏掉。联调阶段不值得纠结。
    /// **上架 App Store 前恢复门控**：改回 `#if DEBUG return true #else return isTestFlight #endif`。
    public static var showsHardwareDebugTools: Bool {
        true
    }
}
