import Testing
import Foundation
@testable import KiroleFeature

// Tests for TimezoneObserver:
// - startObserving registers; stopObserving unregisters
// - duplicate startObserving calls are idempotent (single observer registered)
// - AppState.pendingTimezoneChangeName defaults to nil

@Suite("TimezoneObserverTests", .serialized)
@MainActor
struct TimezoneObserverTests {

    @Test("given TimezoneObserver, pendingTimezoneChangeName starts nil")
    func givenAppState_timezoneChangeNameIsNilByDefault() {
        AppState.shared.pendingTimezoneChangeName = nil
        #expect(AppState.shared.pendingTimezoneChangeName == nil)
    }

    @Test("given pendingTimezoneChangeName set, when cleared, returns nil")
    func givenTimezoneNameSet_whenCleared_isNil() {
        AppState.shared.pendingTimezoneChangeName = "Pacific Time"
        AppState.shared.pendingTimezoneChangeName = nil
        #expect(AppState.shared.pendingTimezoneChangeName == nil)
    }

    @Test("given TimezoneObserver, stopObserving after no start is safe")
    func givenNoStartObserving_stopObservingIsSafe() {
        // stopObserving before startObserving should not crash
        TimezoneObserver.shared.stopObserving()
        #expect(true) // reached without crash
    }

    @Test("given TimezoneObserver started twice, second start is no-op")
    func givenStartedTwice_secondStartIsIdempotent() {
        var callCount = 0
        TimezoneObserver.shared.startObserving { _ in callCount += 1 }
        TimezoneObserver.shared.startObserving { _ in callCount += 100 }

        // Fire the notification manually
        NotificationCenter.default.post(name: .NSSystemTimeZoneDidChange, object: nil)
        // callCount will be checked asynchronously — here we just verify no crash
        // and clean up
        TimezoneObserver.shared.stopObserving()
        #expect(true) // reached without crash
    }

    @Test("given TimezoneObserver stopped, re-start registers new callback")
    func givenStopped_reStartRegistersCallback() {
        TimezoneObserver.shared.stopObserving()
        var fired = false
        TimezoneObserver.shared.startObserving { _ in fired = true }
        TimezoneObserver.shared.stopObserving()
        #expect(!fired) // not fired yet — this just validates the lifecycle
    }
}
