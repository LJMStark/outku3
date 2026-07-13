import Foundation
import Testing
@testable import KiroleFeature

@MainActor
private final class DebugTimelineFocusGuardService: FocusGuardService {
    var authorizationStatus: FocusAuthorizationStatus = .approved
    var isDeepFocusFeatureEnabled = true
    var isDeepFocusCapable = true
    var canShowDeepFocusEntry = true
    var selectedApplicationCount = 0
    var isPickerPresented = false

    func refreshAuthorizationStatus() async {}
    func requestAuthorization() async -> FocusAuthorizationStatus { authorizationStatus }
    func presentAppPicker() {}
    func applyShield(selection: FocusAppSelection) throws {}
    func clearShield() {}
    func currentSelection() -> FocusAppSelection? { nil }
}

@MainActor
private final class DebugTimelineInterruptionDetector: FocusInterruptionDetecting {
    var detectionState: FocusInterruptionDetectionState = .active
    var onInterruption: ((Date, TimeInterval) -> Void)?

    func startMonitoring() {}
    func stopMonitoring() {}

    func interrupt(at timestamp: Date, duration: TimeInterval) {
        onInterruption?(timestamp, duration)
    }
}

@MainActor
@Suite("Focus Debug Timeline")
struct FocusDebugTimelineTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeService(
        detector: DebugTimelineInterruptionDetector = DebugTimelineInterruptionDetector()
    ) -> FocusSessionService {
        FocusSessionService.makeForTesting(
            focusGuardService: DebugTimelineFocusGuardService(),
            interruptionDetector: detector,
            persistenceEnabled: false
        )
    }

    @Test("Normal speed uses real elapsed time")
    func normalSpeed() async {
        let service = makeService()
        await service.startSession(taskId: "normal", taskTitle: "Normal", startTime: start)

        let snapshot = service.progressSnapshot(now: start.addingTimeInterval(10))

        #expect(snapshot.elapsedSeconds == 10)
        #expect(snapshot.segmentSeconds == 10)
        #expect(snapshot.earnedEnergyBottles == 0)
    }

    @Test("60x speed and repeated rate changes remain continuous")
    func accelerationCheckpointsRemainContinuous() async {
        let service = makeService()
        await service.startSession(taskId: "accelerated", taskTitle: "Accelerated", startTime: start)

        service.setFocusTimeAcceleration(true, now: start)
        #expect(service.progressSnapshot(now: start.addingTimeInterval(2)).elapsedSeconds == 120)

        service.setFocusTimeAcceleration(false, now: start.addingTimeInterval(2))
        #expect(service.progressSnapshot(now: start.addingTimeInterval(12)).elapsedSeconds == 130)

        service.setFocusTimeAcceleration(true, now: start.addingTimeInterval(12))
        #expect(service.progressSnapshot(now: start.addingTimeInterval(13)).elapsedSeconds == 190)

        service.setFocusTimeAcceleration(false, now: start.addingTimeInterval(13))
        #expect(service.progressSnapshot(now: start.addingTimeInterval(23)).elapsedSeconds == 200)
    }

    @Test("Repeated manual advances cross bottle boundaries")
    func repeatedManualAdvances() async {
        let service = makeService()
        await service.startSession(taskId: "advance", taskTitle: "Advance", startTime: start)

        service.advanceFocusTime(by: 30 * 60, now: start)
        service.advanceFocusTime(by: 30 * 60, now: start)
        let snapshot = service.progressSnapshot(now: start)

        #expect(snapshot.elapsedSeconds == 60 * 60)
        #expect(snapshot.segmentMinutes == 60)
        #expect(snapshot.earnedEnergyBottles == 2)
    }

    @Test("Accelerated interruption resets current bottle without changing the real timestamps")
    func acceleratedInterruptionResetsSegment() async {
        let detector = DebugTimelineInterruptionDetector()
        let service = makeService(detector: detector)
        await service.startSession(taskId: "interrupted", taskTitle: "Interrupted", startTime: start)
        service.setFocusTimeAcceleration(true, now: start)

        let realInterruption = start.addingTimeInterval(20)
        detector.interrupt(at: realInterruption, duration: 1)
        let snapshot = service.progressSnapshot(now: start.addingTimeInterval(46))

        #expect(service.currentUnlockEvents(until: start.addingTimeInterval(46)).first?.timestamp == realInterruption)
        #expect(snapshot.elapsedMinutes == 46)
        #expect(snapshot.segmentMinutes == 25)
        #expect(snapshot.earnedEnergyBottles == 0)
    }

    @Test("Live snapshot and settlement use the same virtual duration while dates stay real")
    func snapshotMatchesSettlement() async {
        let service = makeService()
        await service.startSession(taskId: "settlement", taskTitle: "Settlement", startTime: start)
        service.setFocusTimeAcceleration(true, now: start)
        let realEnd = start.addingTimeInterval(65)
        let liveSnapshot = service.progressSnapshot(now: realEnd)

        service.endSession(reason: .completed, endTime: realEnd)

        let settled = service.todaySessions.last
        #expect(liveSnapshot.elapsedMinutes == 65)
        #expect(liveSnapshot.earnedEnergyBottles == 2)
        #expect(settled?.endTime == realEnd)
        #expect(settled?.calculatedFocusTime == liveSnapshot.countableFocusTime)
        #expect(settled?.earnedEnergyBottles == liveSnapshot.earnedEnergyBottles)
    }

    @Test("A same-second hardware end keeps a fractional manual advance checkpoint")
    func sameSecondHardwareEndKeepsManualAdvance() async {
        let service = makeService()
        await service.startSession(taskId: "same-second", taskTitle: "Same Second", startTime: start)
        let advanceTime = start.addingTimeInterval(0.8)
        service.advanceFocusTime(by: 30 * 60, now: advanceTime)

        // Hardware event timestamps are UInt32 seconds and therefore arrive truncated.
        service.endSession(reason: .completed, endTime: start)

        let settled = service.todaySessions.last
        let settledFocusTime = settled?.calculatedFocusTime ?? 0
        let expectedFocusTime: TimeInterval = 1_800.8
        #expect(settled?.endTime == start)
        #expect(settled?.earnedEnergyBottles == 1)
        #expect(abs(settledFocusTime - expectedFocusTime) < 0.001)
    }

    @Test("A new session clears acceleration and manual offsets")
    func newSessionClearsDebugTimeline() async {
        let service = makeService()
        await service.startSession(taskId: "first", taskTitle: "First", startTime: start)
        service.setFocusTimeAcceleration(true, now: start)
        service.advanceFocusTime(by: 30 * 60, now: start)
        service.endSession(reason: .skipped, endTime: start.addingTimeInterval(1))

        let secondStart = start.addingTimeInterval(100)
        await service.startSession(taskId: "second", taskTitle: "Second", startTime: secondStart)
        let snapshot = service.progressSnapshot(now: secondStart.addingTimeInterval(10))

        #expect(service.isFocusTimeAccelerated == false)
        #expect(snapshot.elapsedSeconds == 10)
        #expect(snapshot.earnedEnergyBottles == 0)
    }
}
