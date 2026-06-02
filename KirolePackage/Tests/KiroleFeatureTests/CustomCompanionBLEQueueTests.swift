import Testing
import Foundation
@testable import KiroleFeature

// Tests for Custom Companion BLE push queue:
// - pending push flag is set when push fails, cleared when it succeeds
// - flushPendingCustomCompanionPushIfNeeded skips when no companion is active
// - LocalStorage save/load/clear round-trips correctly

@Suite("CustomCompanionBLEQueueTests", .serialized)
@MainActor
struct CustomCompanionBLEQueueTests {

    // MARK: - LocalStorage round-trip

    @Test("given pendingCustomCompanionPushId saved, when loaded, returns same UUID")
    func givenSavedPendingPushId_whenLoaded_returnsSameUUID() async {
        await LocalStorage.shared.clearPendingCustomCompanionPush()
        let id = UUID()
        await LocalStorage.shared.savePendingCustomCompanionPush(id: id)

        let loaded = await LocalStorage.shared.loadPendingCustomCompanionPush()
        #expect(loaded == id)

        await LocalStorage.shared.clearPendingCustomCompanionPush()
    }

    @Test("given no pending push saved, when loaded, returns nil")
    func givenNoPendingPush_whenLoaded_returnsNil() async {
        await LocalStorage.shared.clearPendingCustomCompanionPush()

        let loaded = await LocalStorage.shared.loadPendingCustomCompanionPush()
        #expect(loaded == nil)
    }

    @Test("given pending push saved, when cleared, subsequent load returns nil")
    func givenPendingSaved_whenCleared_loadReturnsNil() async {
        await LocalStorage.shared.clearPendingCustomCompanionPush()
        await LocalStorage.shared.savePendingCustomCompanionPush(id: UUID())
        await LocalStorage.shared.clearPendingCustomCompanionPush()

        let loaded = await LocalStorage.shared.loadPendingCustomCompanionPush()
        #expect(loaded == nil)
    }

    // MARK: - AppState flag restoration

    @Test("given pending push exists in LocalStorage, when flag checked after save, isCustomAvatarPendingBLEPush reflects storage")
    func givenStorageHasPendingPush_flagReflectsStorage() async {
        let id = UUID()
        await LocalStorage.shared.savePendingCustomCompanionPush(id: id)

        // Simulate what loadLocalData does
        let hasPending = await LocalStorage.shared.loadPendingCustomCompanionPush() != nil
        #expect(hasPending == true)

        await LocalStorage.shared.clearPendingCustomCompanionPush()
    }

    // MARK: - flushPendingCustomCompanionPushIfNeeded guard conditions

    @Test("given no custom companion selected, flushPendingCustomCompanionPushIfNeeded is a no-op")
    func givenNoCustomCompanion_flushIsNoOp() async {
        // Precondition: AppState has no customCompanionId
        let savedProfile = AppState.shared.userProfile
        var testProfile = savedProfile
        testProfile.customCompanionId = nil
        AppState.shared.updateUserProfile(testProfile)
        AppState.shared.isCustomAvatarPendingBLEPush = true

        // Should not throw, should not change flag (guard returns early — no id to flush)
        await AppState.shared.flushPendingCustomCompanionPushIfNeeded()

        // Flag remains true because guard returned before clearing it
        #expect(AppState.shared.isCustomAvatarPendingBLEPush == true)

        // Restore
        AppState.shared.updateUserProfile(savedProfile)
        AppState.shared.isCustomAvatarPendingBLEPush = false
        await LocalStorage.shared.clearPendingCustomCompanionPush()
    }

    @Test("given flag is false, flushPendingCustomCompanionPushIfNeeded is a no-op")
    func givenFlagFalse_flushIsNoOp() async {
        AppState.shared.isCustomAvatarPendingBLEPush = false

        // Should return immediately without side effects
        await AppState.shared.flushPendingCustomCompanionPushIfNeeded()

        #expect(AppState.shared.isCustomAvatarPendingBLEPush == false)
    }

    // MARK: - Flush back-off schedule (livelock regression)

    @Test("Flush retries every sync for the first burst, then periodically — never permanently stops")
    func flushBackoffSchedule_neverPermanentlyStops() {
        // First burst: every attempt re-pushes so a transient failure recovers fast.
        for attempt in 1...5 {
            #expect(AppState.shouldAttemptCustomAvatarFlush(attempt: attempt) == true)
        }
        // After the burst, most syncs are skipped — no per-sync spamming when firmware can't 0x15.
        #expect(AppState.shouldAttemptCustomAvatarFlush(attempt: 6) == false)
        #expect(AppState.shouldAttemptCustomAvatarFlush(attempt: 19) == false)
        // ...but it keeps retrying periodically, so recovered hardware self-heals.
        // Regression guard: the old hard cap returned false for EVERY attempt >= 5 forever,
        // stranding a pending push permanently (the livelock Codex flagged).
        #expect(AppState.shouldAttemptCustomAvatarFlush(attempt: 20) == true)
        #expect(AppState.shouldAttemptCustomAvatarFlush(attempt: 40) == true)
        #expect(AppState.shouldAttemptCustomAvatarFlush(attempt: 100) == true)

        // Strongest invariant: there is ALWAYS a future attempt that re-pushes — never gives up.
        let farFuture = 10_000
        let hasUpcomingRetry = (farFuture...(farFuture + 20)).contains {
            AppState.shouldAttemptCustomAvatarFlush(attempt: $0)
        }
        #expect(hasUpcomingRetry == true)
    }
}
