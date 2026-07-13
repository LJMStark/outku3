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
}
