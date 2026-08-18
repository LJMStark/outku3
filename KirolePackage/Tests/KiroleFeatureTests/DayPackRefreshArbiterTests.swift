import Testing
@testable import KiroleFeature

@Suite("DayPack refresh arbiter")
struct DayPackRefreshArbiterTests {
    @Test("structural task or schedule change commits when idle")
    func structuralChangeCommitsWhenIdle() {
        #expect(
            DayPackRefreshArbiter.shouldCommitDatasets(
                structuralChanged: true,
                force: false,
                hasActiveFocusSession: false
            )
        )
    }

    @Test("focus never commits datasets even when tasks changed")
    func structuralChangeDuringFocusDoesNotCommit() {
        #expect(
            !DayPackRefreshArbiter.shouldCommitDatasets(
                structuralChanged: true,
                force: true,
                hasActiveFocusSession: true
            )
        )
    }

    @Test("device wake does not force a screen commit")
    func hardwareWakeDoesNotForceCommit() {
        #expect(!DayPackRefreshArbiter.shouldForceCommit(force: true, isHardwareWake: true))
        #expect(DayPackRefreshArbiter.shouldForceCommit(force: true, isHardwareWake: false))
        #expect(!DayPackRefreshArbiter.shouldForceCommit(force: false, isHardwareWake: false))
    }

    @Test("focus heartbeat without a structural change does not commit")
    func focusForceWithoutStructuralChangeSkipsCommit() {
        #expect(
            !DayPackRefreshArbiter.shouldCommitDatasets(
                structuralChanged: false,
                force: true,
                hasActiveFocusSession: true
            )
        )
    }

    @Test("idle force refresh still commits the current dialogue with the datasets")
    func idleForceCommits() {
        #expect(
            DayPackRefreshArbiter.shouldCommitDatasets(
                structuralChanged: false,
                force: true,
                hasActiveFocusSession: false
            )
        )
    }

    @Test("hourly round with unchanged tasks and schedule skips commit")
    func idleIntervalWithoutChangeSkipsCommit() {
        #expect(
            !DayPackRefreshArbiter.shouldCommitDatasets(
                structuralChanged: false,
                force: false,
                hasActiveFocusSession: false
            )
        )
    }
}
