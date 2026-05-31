import Testing
import Foundation
@testable import KiroleFeature

// Tests for AppState.remoteSyncErrors state machine:
// - error is set when sync fails
// - error is cleared when sync succeeds for that provider
// Uses AppState.shared; each test resets remoteSyncErrors before and after.

@Suite("RemoteSyncErrorsTests")
@MainActor
struct RemoteSyncErrorsTests {

    // MARK: - applyGoogleSyncOutcome (success path clears error)

    @Test("given Google sync error, when sync succeeds with no warnings, then Google error is cleared")
    func givenGoogleError_whenSyncSucceedsWithNoWarnings_thenErrorCleared() {
        AppState.shared.remoteSyncErrors["Google"] = "Previous sync failure"

        AppState.shared.applyGoogleSyncOutcome(eventsCount: 2, tasksCount: 1, warnings: [], durationMs: 50)

        #expect(AppState.shared.remoteSyncErrors["Google"] == nil)
        AppState.shared.remoteSyncErrors = [:]
    }

    @Test("given no previous error, when sync succeeds, then remoteSyncErrors remains empty")
    func givenNoError_whenSyncSucceeds_thenRemainsEmpty() {
        AppState.shared.remoteSyncErrors = [:]

        AppState.shared.applyGoogleSyncOutcome(eventsCount: 0, tasksCount: 0, warnings: [], durationMs: 10)

        #expect(AppState.shared.remoteSyncErrors.isEmpty)
    }

    @Test("given Google error and Notion error, when Google sync succeeds, then only Notion error remains")
    func givenTwoErrors_whenGoogleSucceeds_thenOnlyNotionRemains() {
        AppState.shared.remoteSyncErrors["Google"] = "Google failed"
        AppState.shared.remoteSyncErrors["Notion"] = "Notion failed"

        AppState.shared.applyGoogleSyncOutcome(eventsCount: 1, tasksCount: 0, warnings: [], durationMs: 20)

        #expect(AppState.shared.remoteSyncErrors["Google"] == nil)
        #expect(AppState.shared.remoteSyncErrors["Notion"] != nil)
        AppState.shared.remoteSyncErrors = [:]
    }

    @Test("given Google sync with warnings, when outcome applied, then Google error is set")
    func givenSyncWithWarnings_whenOutcomeApplied_thenGoogleErrorSet() {
        AppState.shared.remoteSyncErrors = [:]

        AppState.shared.applyGoogleSyncOutcome(
            eventsCount: 1, tasksCount: 0,
            warnings: ["Calendar access limited"],
            durationMs: 30
        )

        #expect(AppState.shared.remoteSyncErrors["Google"] != nil)
        AppState.shared.remoteSyncErrors = [:]
    }
}
