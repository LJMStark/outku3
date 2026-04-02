import Foundation
import Testing
@testable import KiroleFeature

@Suite("Sync Scheduler Tests")
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
            let state = AppState.shared
            let originalIntegrations = state.integrations
            defer { state.integrations = originalIntegrations }

            state.integrations = configuredIntegrations(
                connected: [.googleCalendar, .appleReminders, .notion, .taskade]
            )

            #expect(state.connectedExternalSyncTargets() == [.google, .apple, .notion, .taskade])
        }

        @Test("Google and Apple targets are de-duplicated by provider")
        @MainActor
        func deduplicatesGroupedProviders() {
            let state = AppState.shared
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
