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

    // MARK: - 分级（2026-07-02）：部分失败走黄色 warnings，红色只留整轮失败

    @Test("given Google sync with warnings, when outcome applied, then a yellow warning is set and no red error")
    func givenSyncWithWarnings_whenOutcomeApplied_thenWarningSetNoError() {
        AppState.shared.remoteSyncErrors = [:]
        AppState.shared.remoteSyncWarnings = [:]

        AppState.shared.applyGoogleSyncOutcome(
            eventsCount: 1, tasksCount: 0,
            warnings: ["Calendar access limited"],
            durationMs: 30
        )

        #expect(AppState.shared.remoteSyncErrors["Google"] == nil)
        #expect(AppState.shared.remoteSyncWarnings["Google"]?.contains("Calendar access limited") == true)
        AppState.shared.remoteSyncWarnings = [:]
    }

    @Test("given a previous red error, when sync partially succeeds, then red is downgraded to yellow")
    func givenRedError_whenPartialSuccess_thenDowngradedToWarning() {
        AppState.shared.remoteSyncErrors["Google"] = "Previous full failure"
        AppState.shared.remoteSyncWarnings = [:]

        AppState.shared.applyGoogleSyncOutcome(
            eventsCount: 2, tasksCount: 1,
            warnings: ["Tasks sync failed: quota"],
            durationMs: 40
        )

        #expect(AppState.shared.remoteSyncErrors["Google"] == nil)
        #expect(AppState.shared.remoteSyncWarnings["Google"] != nil)
        AppState.shared.remoteSyncWarnings = [:]
    }

    @Test("given a previous warning, when sync fully succeeds, then warning is cleared and timestamp stamped")
    func givenWarning_whenFullSuccess_thenWarningClearedAndStamped() {
        AppState.shared.remoteSyncWarnings["Google"] = "Synced with warnings — old"
        AppState.shared.integrationLastSyncedAt.removeValue(forKey: "Google")

        AppState.shared.applyGoogleSyncOutcome(eventsCount: 3, tasksCount: 2, warnings: [], durationMs: 25)

        #expect(AppState.shared.remoteSyncWarnings["Google"] == nil)
        #expect(AppState.shared.integrationLastSyncedAt["Google"] != nil)
        AppState.shared.integrationLastSyncedAt.removeValue(forKey: "Google")
    }

    @Test("given partial success, when outcome applied, then last-synced timestamp is still stamped")
    func givenPartialSuccess_whenOutcomeApplied_thenTimestampStamped() {
        AppState.shared.integrationLastSyncedAt.removeValue(forKey: "Google")
        AppState.shared.remoteSyncWarnings = [:]

        AppState.shared.applyGoogleSyncOutcome(
            eventsCount: 1, tasksCount: 0,
            warnings: ["Calendar sync failed: one calendar"],
            durationMs: 30
        )

        #expect(AppState.shared.integrationLastSyncedAt["Google"] != nil)
        AppState.shared.remoteSyncWarnings = [:]
        AppState.shared.integrationLastSyncedAt.removeValue(forKey: "Google")
    }

    // MARK: - 离线判定启发式

    @Test("offline-style error descriptions are classified as offline")
    func offlineDescriptionsClassified() {
        #expect(AppState.isOfflineErrorDescription("The Internet connection appears to be offline."))
        #expect(AppState.isOfflineErrorDescription("The network connection was lost."))
        #expect(AppState.isOfflineErrorDescription("Calendar sync failed: The Internet connection appears to be offline."))
    }

    @Test("non-network errors are not classified as offline")
    func nonOfflineDescriptionsNotClassified() {
        #expect(!AppState.isOfflineErrorDescription("The operation couldn't be completed. (403 insufficient permissions)"))
        #expect(!AppState.isOfflineErrorDescription("invalid_grant"))
    }
}
