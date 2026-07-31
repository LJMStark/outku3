import Foundation
import Testing
@testable import KiroleFeature

@Suite("Sync Scheduler Tests", .serialized)
struct SyncSchedulerTests {
    @Suite("Foreground Sync Policy")
    struct ForegroundSyncPolicyTests {
        @Test("Resume sync runs immediately when no previous attempt exists")
        func syncsWithoutPreviousAttempt() {
            let policy = ForegroundSyncPolicy()

            #expect(policy.shouldSyncOnResume(now: Date(), lastAttempt: nil))
        }

        @Test("Resume sync is throttled for rapid foreground re-entry")
        func throttlesRapidForegroundReentry() {
            let policy = ForegroundSyncPolicy()
            let now = Date()
            let lastAttempt = now.addingTimeInterval(-(policy.resumeThrottleInterval - 1))

            #expect(policy.shouldSyncOnResume(now: now, lastAttempt: lastAttempt) == false)
        }

        @Test("Resume sync proceeds after throttle window elapses")
        func syncsAfterThrottleWindow() {
            let policy = ForegroundSyncPolicy()
            let now = Date()
            let lastAttempt = now.addingTimeInterval(-policy.resumeThrottleInterval)

            #expect(policy.shouldSyncOnResume(now: now, lastAttempt: lastAttempt))
        }
    }

    @Suite("External Sync Targets")
    struct ExternalSyncTargetsTests {
        @Test("Connected targets include all supported external sources")
        @MainActor
        func includesAllSupportedSources() {
            let state = AppState.makeForTesting()
            let originalIntegrations = state.integrations
            defer { state.integrations = originalIntegrations }

            state.integrations = configuredIntegrations(
                connected: [.googleCalendar, .appleReminders, .notion, .taskade]
            )

            #expect(state.connectedExternalSyncTargets() == [.google, .apple, .notion, .taskade])
        }

        @Test("A duplicate source sync waits for the active operation instead of returning early")
        @MainActor
        func duplicateSourceWaitsForActiveOperation() async {
            let state = AppState.makeForTesting()
            #expect(await state.claimExternalSync(.google))

            var duplicateFinished = false
            let duplicate = Task { @MainActor in
                let claimed = await state.claimExternalSync(.google)
                duplicateFinished = true
                return claimed
            }
            await Task.yield()

            #expect(!duplicateFinished)
            state.finishExternalSync(.google)
            #expect(await duplicate.value == false)
            #expect(duplicateFinished)
        }

        @Test("Google and Apple targets are de-duplicated by provider")
        @MainActor
        func deduplicatesGroupedProviders() {
            let state = AppState.makeForTesting()
            let originalIntegrations = state.integrations
            defer { state.integrations = originalIntegrations }

            state.integrations = configuredIntegrations(
                connected: [.googleCalendar, .googleTasks, .appleCalendar, .appleReminders]
            )

            #expect(state.connectedExternalSyncTargets() == [.google, .apple])
        }

        @MainActor
        private func configuredIntegrations(
            connected: Set<IntegrationType>
        ) -> [Integration] {
            Integration.defaultIntegrations.map { integration in
                var updated = integration
                updated.isConnected = connected.contains(integration.type)
                return updated
            }
        }
    }
}
