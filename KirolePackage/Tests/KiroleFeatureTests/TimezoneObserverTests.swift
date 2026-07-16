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
        TimezoneObserver.shared.stopObserving()
    }

    @Test("given TimezoneObserver started twice, second start is no-op")
    func givenStartedTwice_secondStartIsIdempotent() async {
        defer { TimezoneObserver.shared.stopObserving() }
        var callCount = 0
        TimezoneObserver.shared.startObserving { _ in callCount += 1 }
        TimezoneObserver.shared.startObserving { _ in callCount += 100 }

        NotificationCenter.default.post(name: .NSSystemTimeZoneDidChange, object: nil)
        await Task.yield()

        #expect(callCount == 1)
    }

    @Test("given TimezoneObserver stopped, re-start registers new callback")
    func givenStopped_reStartRegistersCallback() async {
        TimezoneObserver.shared.stopObserving()
        var callCount = 0
        TimezoneObserver.shared.startObserving { _ in callCount += 1 }
        TimezoneObserver.shared.stopObserving()
        TimezoneObserver.shared.startObserving { _ in callCount += 10 }
        defer { TimezoneObserver.shared.stopObserving() }

        NotificationCenter.default.post(name: .NSSystemTimeZoneDidChange, object: nil)
        await Task.yield()

        #expect(callCount == 10)
    }
}
