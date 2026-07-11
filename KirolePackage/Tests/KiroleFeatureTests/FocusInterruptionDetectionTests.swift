import Foundation
import Testing
@testable import KiroleFeature

// MARK: - Mocks

@MainActor
private final class MockInterruptionDetector: FocusInterruptionDetecting {
    var detectionState: FocusInterruptionDetectionState = .active
    var onInterruption: ((Date, TimeInterval) -> Void)?
    var startMonitoringCount = 0
    var stopMonitoringCount = 0

    func startMonitoring() { startMonitoringCount += 1 }
    func stopMonitoring() { stopMonitoringCount += 1 }

    func simulateInterruption(at timestamp: Date, duration: TimeInterval = 60) {
        onInterruption?(timestamp, duration)
    }
}

@MainActor
private final class DetectorMockFocusGuardService: FocusGuardService {
    var authorizationStatus: FocusAuthorizationStatus = .approved
    var isDeepFocusFeatureEnabled: Bool = true
    var isDeepFocusCapable: Bool = true
    var canShowDeepFocusEntry: Bool = true
    var selectedApplicationCount: Int = 0
    var isPickerPresented: Bool = false
    var selection: FocusAppSelection?

    func refreshAuthorizationStatus() async {}
    func requestAuthorization() async -> FocusAuthorizationStatus { authorizationStatus }
    func presentAppPicker() {}
    func applyShield(selection: FocusAppSelection) throws {}
    func clearShield() {}
    func currentSelection() -> FocusAppSelection? { selection }
}

// MARK: - Session Integration

@MainActor
@Suite("Focus Interruption Detection")
struct FocusInterruptionDetectionTests {

    private func makeService(detector: MockInterruptionDetector) -> FocusSessionService {
        FocusSessionService.makeForTesting(
            focusGuardService: DetectorMockFocusGuardService(),
            interruptionDetector: detector,
            persistenceEnabled: false
        )
    }

    @Test("Detector interruption during a session resets the current segment")
    func detectorInterruptionResetsSegment() async {
        let detector = MockInterruptionDetector()
        let service = makeService(detector: detector)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        await service.startSession(taskId: "t1", taskTitle: "Task", startTime: start)

        let interruptionAt = start.addingTimeInterval(20 * 60)
        detector.simulateInterruption(at: interruptionAt, duration: 60)

        let now = start.addingTimeInterval(25 * 60)
        let events = service.currentUnlockEvents(until: now)
        #expect(events.count == 1)
        #expect(events[0].timestamp == interruptionAt)
        #expect(events[0].duration == 60)

        let segmentStart = FocusTimeCalculator.currentSegmentStart(
            sessionStart: start,
            now: now,
            screenUnlockEvents: events
        )
        #expect(segmentStart == interruptionAt.addingTimeInterval(60))
    }

    @Test("Interruption with no active session is ignored")
    func interruptionIgnoredWhenIdle() async {
        let detector = MockInterruptionDetector()
        let service = makeService(detector: detector)

        detector.simulateInterruption(at: Date(timeIntervalSince1970: 1_700_000_000))

        await service.startSession(
            taskId: "t1",
            taskTitle: "Task",
            startTime: Date(timeIntervalSince1970: 1_700_000_500)
        )
        let events = service.currentUnlockEvents(
            until: Date(timeIntervalSince1970: 1_700_003_000)
        )
        #expect(events.isEmpty)
    }

    @Test("Session lifecycle drives detector monitoring")
    func sessionLifecycleDrivesMonitoring() async {
        let detector = MockInterruptionDetector()
        let service = makeService(detector: detector)
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        await service.startSession(taskId: "t1", taskTitle: "Task", startTime: start)
        #expect(detector.startMonitoringCount == 1)

        service.endSession(reason: .completed, endTime: start.addingTimeInterval(600))
        #expect(detector.stopMonitoringCount == 1)
    }

    @Test("Settlement voids the sub-30-minute leftovers around an interruption")
    func settlementRespectsInterruption() async {
        let detector = MockInterruptionDetector()
        let service = makeService(detector: detector)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        await service.startSession(taskId: "t1", taskTitle: "Task", startTime: start)

        // 20 min in: distracting-app usage detected → both the 20-min head and
        // the ~25-min tail stay under the 30-min block, so no bottle is earned.
        detector.simulateInterruption(at: start.addingTimeInterval(20 * 60), duration: 60)
        service.endSession(reason: .completed, endTime: start.addingTimeInterval(46 * 60))

        let settled = service.todaySessions.last
        #expect(settled != nil)
        #expect(settled?.earnedEnergyBottles == 0)
        #expect(settled?.screenUnlockEvents.count == 1)
    }

    @Test("Uninterrupted session earns a bottle per full 30 minutes")
    func uninterruptedSessionEarnsBottles() async {
        let detector = MockInterruptionDetector()
        let service = makeService(detector: detector)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        await service.startSession(taskId: "t1", taskTitle: "Task", startTime: start)

        service.endSession(reason: .completed, endTime: start.addingTimeInterval(65 * 60))

        #expect(service.todaySessions.last?.earnedEnergyBottles == 2)
    }

    @Test("Interruption events do not leak into the next session")
    func interruptionsDoNotLeakAcrossSessions() async {
        let detector = MockInterruptionDetector()
        let service = makeService(detector: detector)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        await service.startSession(taskId: "t1", taskTitle: "Task", startTime: start)
        detector.simulateInterruption(at: start.addingTimeInterval(300), duration: 60)
        service.endSession(reason: .completed, endTime: start.addingTimeInterval(600))

        let secondStart = start.addingTimeInterval(1200)
        await service.startSession(taskId: "t2", taskTitle: "Task 2", startTime: secondStart)
        let events = service.currentUnlockEvents(until: secondStart.addingTimeInterval(600))
        #expect(events.isEmpty)
    }
}

// MARK: - Detector State Mapping

@MainActor
@Suite("ScreenTime Detector State")
struct ScreenTimeDetectorStateTests {

    @Test("Deployed extension: state maps authorization and selection honestly")
    func detectionStateMapping() {
        let guardService = DetectorMockFocusGuardService()
        let detector = ScreenTimeInterruptionDetector(focusGuard: guardService)

        // 扩展已随构建部署（2026-07-10 接线后）。
        #expect(ScreenTimeInterruptionDetector.monitorExtensionDeployed == true)

        guardService.authorizationStatus = .denied
        #expect(detector.detectionState == .unauthorized)

        guardService.authorizationStatus = .approved
        guardService.selection = nil
        #expect(detector.detectionState == .selectionEmpty)

        guardService.selection = FocusAppSelection(tokenData: Data(), selectedApplicationCount: 0)
        #expect(detector.detectionState == .selectionEmpty)

        guardService.selection = FocusAppSelection(tokenData: Data([0x01]), selectedApplicationCount: 2)
        #expect(detector.detectionState == .active)
    }

    @Test("startMonitoring is a no-op unless detection is active")
    func startMonitoringGated() {
        let guardService = DetectorMockFocusGuardService()
        guardService.authorizationStatus = .denied
        let detector = ScreenTimeInterruptionDetector(focusGuard: guardService)

        var fired = false
        detector.onInterruption = { _, _ in fired = true }
        detector.startMonitoring()
        detector.stopMonitoring()
        #expect(fired == false)
    }

    #if os(iOS) && canImport(DeviceActivity) && canImport(FamilyControls)
    // 仅 iOS：macOS 下 armThresholdEvent 整块不编译，失败路径不存在。
    // 模拟器跑 xcodebuild test 时生效。
    @Test("Arming failure surfaces as monitoringFailed instead of pretending to be active")
    func armingFailureSurfacesHonestly() {
        let guardService = DetectorMockFocusGuardService()
        guardService.authorizationStatus = .approved
        // 计数非空但 tokenData 不是合法 FamilyActivitySelection：
        // armThresholdEvent 解码即抛，稳定走进 catch 分支。
        guardService.selection = FocusAppSelection(tokenData: Data([0x01]), selectedApplicationCount: 2)
        let detector = ScreenTimeInterruptionDetector(focusGuard: guardService)
        #expect(detector.detectionState == .active)

        detector.startMonitoring()
        #expect(detector.detectionState == .monitoringFailed)

        // 会话结束清除失败态：不粘到下一次会话的重试。
        detector.stopMonitoring()
        #expect(detector.detectionState == .active)
    }
    #endif
}
