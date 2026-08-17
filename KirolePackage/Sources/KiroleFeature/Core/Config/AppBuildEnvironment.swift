import Foundation
import os

// MARK: - App Build Environment

/// 构建环境判定。
///
/// 联调行为闸 `showsHardwareDebugTools` 默认关闭。InternalRelease 的 app shell
/// 在 `InternalBuildBoundary.activate()` 里打开内部硬件通道；App Store 包从不调用。
/// 联调 UI 不靠这个旗，而靠 app target 注入的 `InternalToolsViews`。
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

    /// 是否运行在测试进程内（`swift test` / `xcodebuild test`）。
    ///
    /// 判据（实测 2026-07-14）：xcodebuild/xctest 宿主带 `XCTestConfigurationFilePath` /
    /// `XCTestBundlePath` 环境变量；`swift test`（swiftpm-testing-helper + Swift Testing）
    /// 把 .xctest 以裸可执行镜像加载——不进 `Bundle.allBundles`、也无上述环境变量，
    /// 但 `--test-bundle-path …/*.xctest/…` 一定出现在进程参数里。
    /// 进程生命周期内不变，惰性求值一次后缓存（同 `isTestFlight`）。
    ///
    /// 用途：测试宿主进程没有 `NSBluetoothAlwaysUsageDescription`，任何路径创建
    /// `CBCentralManager` 都会触发 TCC 隐私 SIGABRT——`BLEService.initialize()` 以此守卫。
    public static let isRunningTests: Bool = detectTestHost(
        environment: ProcessInfo.processInfo.environment,
        arguments: ProcessInfo.processInfo.arguments
    )

    /// 纯函数形态的检测本体：注入 environment/arguments 使**负向**可测——
    /// 误把生产进程判成测试宿主会让 BLEService.initialize() 静默跳过
    /// CBCentralManager 创建、整机 BLE 失效，这个分支必须能被单测钉住。
    static func detectTestHost(environment: [String: String], arguments: [String]) -> Bool {
        if environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil {
            return true
        }
        return arguments.contains { $0.contains(".xctest") }
    }

    /// 联调行为闸（连接后查 Wi-Fi Debug、BLE 收发日志、专注虚拟时间）。
    /// 正式包从不打开。InternalRelease 由 app shell `activate()` 打开。
    /// 联调 UI 不靠这个旗，而靠 app target 注入的 `InternalToolsViews`。
    /// Keep Alive 不走这扇闸：MVP 阶段两套包都保持 BLE 长连接。
    public static var showsHardwareDebugTools: Bool {
        isInternalHardwareChannelEnabled
    }

    /// MVP：顾客包和内部包都默认保持 BLE 长连接。
    /// 内部 Settings 仍可关掉；正式包没有开关，一律开着。
    public static func keepAliveEnabled(storedPreference: Bool?) -> Bool {
        if showsHardwareDebugTools {
            return storedPreference ?? true
        }
        return true
    }

    /// 仅 InternalRelease 的 app shell 在 `activate()` 时打开。正式包从不调用。
    public static var isInternalHardwareChannelEnabled: Bool {
        internalHardwareChannel.withLock { $0 }
    }

    public static func enableInternalHardwareChannel() {
        internalHardwareChannel.withLock { $0 = true }
    }

    /// 测试复位。生产路径不得调用。
    static func resetInternalHardwareChannelForTesting() {
        internalHardwareChannel.withLock { $0 = false }
    }

    private static let internalHardwareChannel = OSAllocatedUnfairLock(initialState: false)

    /// 是否显示会改变设备出厂状态的工厂工具。
    ///
    /// 工厂命令比普通联调开关更危险：Debug 与 TestFlight 可见，App Store 正式包隐藏。
    /// TestFlight 只看收据文件名，不要求文件已经落盘；StoreKit 2 下收据文件可能不存在，
    /// 但 `appStoreReceiptURL` 仍能提供 `sandboxReceipt` / `receipt` 的安装来源差异。
    public static var showsFactoryDebugTools: Bool {
        #if DEBUG
        let isDebugBuild = true
        #else
        let isDebugBuild = false
        #endif
        return shouldShowFactoryDebugTools(
            isDebugBuild: isDebugBuild,
            receiptName: Bundle.main.appStoreReceiptURL?.lastPathComponent
        )
    }

    static func shouldShowFactoryDebugTools(
        isDebugBuild: Bool,
        receiptName: String?
    ) -> Bool {
        isDebugBuild || receiptName == "sandboxReceipt"
    }
}
