import Testing
@testable import KiroleFeature

@Suite("External sync commit generation")
struct ExternalSyncGenerationTests {
    @Test("Disconnecting one provider invalidates only that provider's result")
    @MainActor
    func providerInvalidationIsScoped() {
        let state = AppState.makeForTesting()
        let google = state.externalSyncGeneration(for: .google)
        let notion = state.externalSyncGeneration(for: .notion)

        state.invalidateExternalSyncResults(for: [.google])

        #expect(!state.canCommitExternalSync(.google, generation: google))
        #expect(state.canCommitExternalSync(.notion, generation: notion))
    }

    @Test("Sign out invalidates every provider result before persistence awaits")
    @MainActor
    func signOutInvalidatesEveryProvider() {
        let state = AppState.makeForTesting()
        let snapshots = Dictionary(
            uniqueKeysWithValues: ExternalSyncTarget.allCases.map {
                ($0, state.externalSyncGeneration(for: $0))
            }
        )

        state.invalidateAllExternalSyncResults()

        for (target, generation) in snapshots {
            #expect(!state.canCommitExternalSync(target, generation: generation))
        }
    }

    @Test("A new provider generation can commit after an older result is invalidated")
    @MainActor
    func newGenerationCanCommit() {
        let state = AppState.makeForTesting()
        let old = state.externalSyncGeneration(for: .taskade)

        state.invalidateExternalSyncResults(for: [.taskade])
        let current = state.externalSyncGeneration(for: .taskade)

        #expect(!state.canCommitExternalSync(.taskade, generation: old))
        #expect(state.canCommitExternalSync(.taskade, generation: current))
    }

    @Test("A new generation is not blocked by an older in-flight sync")
    @MainActor
    func invalidationAllowsAReplacementSync() throws {
        let state = AppState.makeForTesting()
        let old = try #require(state.beginExternalSync(.notion))

        #expect(state.beginExternalSync(.notion) == nil)

        state.invalidateExternalSyncResults(for: [.notion])
        let replacement = try #require(state.beginExternalSync(.notion))

        #expect(replacement != old)
    }

    @Test("An older sync cannot release the replacement generation's slot")
    @MainActor
    func staleCompletionDoesNotReleaseReplacement() throws {
        let state = AppState.makeForTesting()
        let old = try #require(state.beginExternalSync(.todoist))
        state.invalidateExternalSyncResults(for: [.todoist])
        let replacement = try #require(state.beginExternalSync(.todoist))

        state.finishExternalSync(.todoist, generation: old)
        #expect(state.beginExternalSync(.todoist) == nil)

        state.finishExternalSync(.todoist, generation: replacement)
        #expect(state.beginExternalSync(.todoist) != nil)
    }
}
