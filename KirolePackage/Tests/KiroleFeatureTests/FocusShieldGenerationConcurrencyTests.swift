import Testing
@testable import KiroleFeature

@Suite("Focus shield generation concurrency", .serialized)
struct FocusShieldGenerationConcurrencyTests {
    @Test("A failed active start clears a newer shield generation transferred to it")
    @MainActor
    func failedActiveStartClearsTransferredShieldGeneration() async {
        await SharedPersistenceTestLock.shared.withLock {
            await LocalStorage.shared.saveDeepFocusShieldActive(false)
            let activeSaveBarrier = FocusLaunchBarrier()
            let persistence = FocusPersistenceFailureStub(
                failActiveSaves: 1,
                activeSaveBarrier: activeSaveBarrier
            )
            let guardService = ControlledFocusGuardStub()
            let service = FocusSessionService.makeForTesting(
                focusGuardService: guardService,
                persistenceEnabled: true,
                focusPersistence: persistence,
                taskOperationLedger: TaskOperationLedger(
                    persistenceEnabled: false,
                    initialEntries: []
                )
            )

            let staleResolvedStart = Task { @MainActor in
                await service.startSession(
                    taskId: "focus-transferred-generation",
                    taskTitle: "Transferred generation",
                    mode: .deepFocus
                )
            }
            for _ in 0..<100 where guardService.refreshCallCount < 1 {
                await Task.yield()
            }

            let activeStart = Task { @MainActor in
                await service.startSession(
                    taskId: "focus-transferred-generation",
                    taskTitle: "Transferred generation",
                    mode: .deepFocus
                )
            }
            for _ in 0..<100 where guardService.refreshCallCount < 2 {
                await Task.yield()
            }
            #expect(guardService.refreshCallCount == 2)

            // Let the second start own generation 1 and suspend while saving its active marker.
            guardService.releaseLastRefresh()
            for _ in 0..<100 where !(await persistence.hasStartedActiveSave()) {
                await Task.yield()
            }
            #expect(await persistence.hasStartedActiveSave())

            // The older resolved start now applies generation 2, sees the same task already
            // active, and transfers that newer generation to the suspended active start.
            guardService.releaseFirstRefresh()
            let staleResult = await staleResolvedStart.value
            guard case .alreadyActive(let transferredOwner) = staleResult else {
                Issue.record("Expected the stale start to transfer its shield to the active start")
                await activeSaveBarrier.release()
                return
            }
            #expect(service.activeSession?.id == transferredOwner.id)
            #expect(guardService.applyShieldCalls == 2)
            #expect(guardService.isShieldApplied)

            await activeSaveBarrier.release()
            let activeResult = await activeStart.value
            guard case .persistenceUnavailable = activeResult else {
                Issue.record("Expected the active marker save to fail")
                return
            }

            #expect(service.activeSession == nil)
            #expect(await persistence.activeSession() == nil)
            #expect(guardService.clearShieldCalls == 1)
            #expect(!guardService.isShieldApplied)
            #expect(!(await LocalStorage.shared.loadDeepFocusShieldActive()))
        }
    }
}
