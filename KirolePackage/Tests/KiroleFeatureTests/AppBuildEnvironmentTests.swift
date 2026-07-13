import Foundation
import Testing
@testable import KiroleFeature

@Suite("AppBuildEnvironment")
struct AppBuildEnvironmentTests {

    /// 回归守卫（2026-07-14）：测试宿主进程必须被识别出来。
    /// `BLEService.initialize()` 以 `isRunningTests` 拦截 CBCentralManager 创建——
    /// 若本断言变红，说明检测在当前测试运行器下失效，AppState 测试遗留的 detached
    /// requestBLESync→performSync 任务将再次触发 TCC 蓝牙隐私 SIGABRT 崩掉整个测试进程。
    @Test("isRunningTests detects the test host process")
    func detectsTestHost() {
        #expect(AppBuildEnvironment.isRunningTests)
    }

    /// 负向守卫：生产形态的进程绝不能被判成测试宿主——误判会让 BLEService.initialize()
    /// 静默跳过 CBCentralManager 创建、整机 BLE 失效（硬件优先产品的最坏静默故障）。
    @Test("production-shaped process is NOT classified as a test host")
    func productionProcessNotDetectedAsTestHost() {
        #expect(!AppBuildEnvironment.detectTestHost(
            environment: ["HOME": "/var/mobile", "PATH": "/usr/bin"],
            arguments: ["/private/var/containers/Bundle/Application/1234-ABCD/Kirole.app/Kirole"]
        ))
        #expect(!AppBuildEnvironment.detectTestHost(environment: [:], arguments: []))
    }

    @Test("each detection signal is individually sufficient")
    func detectionSignals() {
        #expect(AppBuildEnvironment.detectTestHost(
            environment: ["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"],
            arguments: []
        ))
        #expect(AppBuildEnvironment.detectTestHost(
            environment: ["XCTestBundlePath": "/tmp/Tests.xctest"],
            arguments: []
        ))
        #expect(AppBuildEnvironment.detectTestHost(
            environment: [:],
            arguments: ["swiftpm-testing-helper", "--test-bundle-path", "/x/KiroleFeaturePackageTests.xctest/Contents/MacOS/KiroleFeaturePackageTests"]
        ))
    }
}
