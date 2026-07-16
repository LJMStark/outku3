import Testing
@testable import KiroleFeature

@Suite("Integration Auth Reconciliation")
struct IntegrationAuthReconciliationTests {
    @Test("Legacy authenticated providers are imported when no saved preference exists")
    @MainActor
    func importsLegacyAuthenticatedProvider() {
        let state = AppState.makeForTesting()

        let didReconcile = state.reconcileAuthenticatedIntegrationTypes([.googleCalendar])

        #expect(didReconcile)
        #expect(state.isIntegrationConnected(.googleCalendar))
    }

    @Test("An empty pre-auth check does not consume the one-time legacy bootstrap")
    @MainActor
    func emptyAuthCheckDoesNotConsumeBootstrap() {
        let state = AppState.makeForTesting()

        #expect(!state.reconcileAuthenticatedIntegrationTypes([]))
        #expect(state.reconcileAuthenticatedIntegrationTypes([.googleCalendar]))
        #expect(state.isIntegrationConnected(.googleCalendar))
    }

    @Test("A saved disconnect is not re-enabled by an existing auth scope")
    @MainActor
    func preservesSavedDisconnect() {
        let state = AppState.makeForTesting()
        state.integrations = state.integrationCoordinator.setIntegrationStatus(
            integrations: state.integrations,
            type: .googleCalendar,
            isConnected: false
        )
        state.hasExplicitIntegrationConnectionPreferences = true

        let didReconcile = state.reconcileAuthenticatedIntegrationTypes([.googleCalendar])

        #expect(!didReconcile)
        #expect(!state.isIntegrationConnected(.googleCalendar))
    }

    @Test("Auth bootstrap runs only once so a later user disconnect stays disconnected")
    @MainActor
    func bootstrapRunsOnce() {
        let state = AppState.makeForTesting()
        #expect(state.reconcileAuthenticatedIntegrationTypes([.googleTasks]))
        state.integrations = state.integrationCoordinator.setIntegrationStatus(
            integrations: state.integrations,
            type: .googleTasks,
            isConnected: false
        )

        let secondReconcile = state.reconcileAuthenticatedIntegrationTypes([.googleTasks])

        #expect(!secondReconcile)
        #expect(!state.isIntegrationConnected(.googleTasks))
    }
}
