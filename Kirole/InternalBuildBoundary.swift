import Foundation
import os

/// Release-channel compile-time boundary (AGENTS.md "Release Channel Policy").
///
/// `KIROLE_INTERNAL` 只由 `Config/InternalRelease.xcconfig` 定义；`AppStoreRelease`
/// 绝不可定义它，`Debug` 也不定义（Debug 是开发工具，不是分发渠道，政策明确
/// 禁止用 DEBUG 标识 Internal TestFlight）。
///
/// Xcode 在编译 SwiftPM 包目标时有意忽略自定义配置的
/// `SWIFT_ACTIVE_COMPILATION_CONDITIONS`，所以这个条件只在 app target
/// （`Kirole/` 目录）可见。内部专用实现必须放在 app target 或独立链接的
/// package product，不能藏在 `KirolePackage` 内部的 `#if` 里——那种写法在两个
/// 分发配置下编译结果完全相同，等于没有边界。
///
/// 成对门控：`scripts/verify-release-boundary.sh` 构建两个分发配置并断言
/// `marker` 在 InternalRelease 产物中存在、在 AppStoreRelease 产物中不存在。
enum InternalBuildBoundary {
    #if KIROLE_INTERNAL
    /// 符号扫描锚点。改动此字符串必须同步更新 scripts/verify-release-boundary.sh。
    static let marker = "KIROLE-INTERNAL-CHANNEL-ACTIVE-3F9C"

    static func activate() {
        Logger(subsystem: "com.kirole.app", category: "release-channel")
            .info("Internal distribution channel active: \(marker, privacy: .public)")
    }
    #else
    static func activate() {}
    #endif
}
