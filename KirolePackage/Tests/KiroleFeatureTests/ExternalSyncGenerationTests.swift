import Testing
@testable import KiroleFeature

@Suite("External sync commit generation")
struct ExternalSyncGenerationTests {
    @Test("Disconnecting one provider invalidates only that provider's result")
    @MainActor
    func providerInvalidationIsScoped() {
        let state = AppState.makeForTesting()
        let google = state.externalSyncGeneration(for: .google)
        let apple = state.externalSyncGeneration(for: .apple)

        state.invalidateExternalSyncResults(for: [.google])

        #expect(!state.canCommitExternalSync(.google, generation: google))
        #expect(state.canCommitExternalSync(.apple, generation: apple))
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
        let old = state.externalSyncGeneration(for: .apple)

        state.invalidateExternalSyncResults(for: [.apple])
        let current = state.externalSyncGeneration(for: .apple)

        #expect(!state.canCommitExternalSync(.apple, generation: old))
        #expect(state.canCommitExternalSync(.apple, generation: current))
    }

    @Test("A new generation is not blocked by an older in-flight sync")
    @MainActor
    func invalidationAllowsAReplacementSync() throws {
        let state = AppState.makeForTesting()
        let old = try #require(state.beginExternalSync(.google))

        #expect(state.beginExternalSync(.google) == nil)

        state.invalidateExternalSyncResults(for: [.google])
        let replacement = try #require(state.beginExternalSync(.google))

        #expect(replacement != old)
    }

    @Test("An older sync cannot release the replacement generation's slot")
    @MainActor
    func staleCompletionDoesNotReleaseReplacement() throws {
        let state = AppState.makeForTesting()
        let old = try #require(state.beginExternalSync(.apple))
        state.invalidateExternalSyncResults(for: [.apple])
        let replacement = try #require(state.beginExternalSync(.apple))

        state.finishExternalSync(.apple, generation: old)
        #expect(state.beginExternalSync(.apple) == nil)

        state.finishExternalSync(.apple, generation: replacement)
        #expect(state.beginExternalSync(.apple) != nil)
    }
}
