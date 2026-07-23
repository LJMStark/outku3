import Testing
import Foundation
@testable import KiroleFeature

@Suite("BLESyncPolicyTests")
struct BLESyncPolicyTests {

    private let policy = BLESyncPolicy()

    // MARK: - contentChanged (foreground write-path)

    @Test("given content changed, when shouldSync called without force, then returns true immediately")
    func givenContentChanged_whenShouldSync_thenTrueImmediately() {
        let now = Date()
        let lastSync = now.addingTimeInterval(-30)  // only 30 seconds ago — well within throttle window

        let result = policy.shouldSync(now: now, lastSync: lastSync, contentChanged: true, force: false)

        #expect(result == true)
    }

    @Test("given content unchanged and within throttle window, when shouldSync called, then returns false")
    func givenContentUnchangedWithinWindow_whenShouldSync_thenFalse() {
        let now = Date()
        let lastSync = now.addingTimeInterval(-30)  // 30 seconds ago, within 1h window

        let result = policy.shouldSync(now: now, lastSync: lastSync, contentChanged: false, force: false)

        #expect(result == false)
    }

    @Test("given force true, when shouldSync called regardless of content or interval, then returns true")
    func givenForcedTrue_whenShouldSync_thenAlwaysTrue() {
        let now = Date()
        let lastSync = now.addingTimeInterval(-10)  // only 10 seconds ago

        let result = policy.shouldSync(now: now, lastSync: lastSync, contentChanged: false, force: true)

        #expect(result == true)
    }

    @Test("given no previous sync, when shouldSync called, then returns true")
    func givenNoPreviousSync_whenShouldSync_thenTrue() {
        let now = Date()

        let result = policy.shouldSync(now: now, lastSync: nil, contentChanged: false, force: false)

        #expect(result == true)
    }

    // MARK: - time-based throttle

    @Test("given daytime hour and 1 hour elapsed, when shouldSync called, then returns true")
    func givenDaytimeAndOneHourElapsed_whenShouldSync_thenTrue() {
        // Set up a noon-time date
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 12
        let now = Calendar.current.date(from: components) ?? Date()
        let lastSync = now.addingTimeInterval(-3601)  // just over 1 hour

        let result = policy.shouldSync(now: now, lastSync: lastSync, contentChanged: false, force: false)

        #expect(result == true)
    }

    @Test("given night hour and 4 hours elapsed, when shouldSync called, then returns true")
    func givenNightAndFourHoursElapsed_whenShouldSync_thenTrue() {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 2  // 2am — nighttime
        let now = Calendar.current.date(from: components) ?? Date()
        let lastSync = now.addingTimeInterval(-4 * 3601)  // just over 4 hours

        let result = policy.shouldSync(now: now, lastSync: lastSync, contentChanged: false, force: false)

        #expect(result == true)
    }

    @Test("given night hour and only 1 hour elapsed, when shouldSync called, then returns false")
    func givenNightAndOneHourElapsed_whenShouldSync_thenFalse() {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 2  // 2am — nighttime
        let now = Calendar.current.date(from: components) ?? Date()
        let lastSync = now.addingTimeInterval(-3601)  // just over 1 hour (but night needs 4h)

        let result = policy.shouldSync(now: now, lastSync: lastSync, contentChanged: false, force: false)

        #expect(result == false)
    }

    @Test("custom avatar validation and commit keep the BLE connection open")
    func customAvatarTransactionHoldsConnectionBeyondChunkTransfer() {
        #expect(policy.shouldHoldConnectionForCustomAvatar(
            chunkedTransferInFlight: true,
            operationState: .idle
        ))
        #expect(policy.shouldHoldConnectionForCustomAvatar(
            chunkedTransferInFlight: false,
            operationState: .validating
        ))
        #expect(policy.shouldHoldConnectionForCustomAvatar(
            chunkedTransferInFlight: false,
            operationState: .committing
        ))
        #expect(!policy.shouldHoldConnectionForCustomAvatar(
            chunkedTransferInFlight: false,
            operationState: .failed("offline")
        ))
    }

    @Test("pending erase or abort bypasses the normal sync interval")
    func priorityCustomAvatarOperationForcesSyncAdmission() {
        let now = Date()
        #expect(policy.shouldSync(
            now: now,
            lastSync: now,
            contentChanged: false,
            force: false,
            hasPriorityCustomAvatarOperation: true
        ))
        #expect(!policy.shouldSync(
            now: now,
            lastSync: now,
            contentChanged: false,
            force: false,
            hasPriorityCustomAvatarOperation: false
        ))
    }
}
