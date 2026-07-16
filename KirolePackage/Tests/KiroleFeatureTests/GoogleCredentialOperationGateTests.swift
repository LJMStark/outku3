import Testing
@testable import KiroleFeature

@Suite("Google Credential Operation Gate")
struct GoogleCredentialOperationGateTests {
    @Test("Sign-out invalidates an async credential result captured before suspension")
    func signOutInvalidatesStaleResult() throws {
        var gate = GoogleCredentialOperationGate()
        let capturedGeneration = try #require(gate.snapshot())

        gate.invalidate(blockNewOperations: false)

        #expect(!gate.accepts(capturedGeneration))
        #expect(gate.snapshot() != nil)
    }

    @Test("Disconnect invalidates old results and blocks new operations until completion")
    func disconnectBlocksOperationsUntilCompletion() throws {
        var gate = GoogleCredentialOperationGate()
        let capturedGeneration = try #require(gate.snapshot())

        gate.invalidate(blockNewOperations: true)

        #expect(!gate.accepts(capturedGeneration))
        #expect(gate.snapshot() == nil)

        gate.unblock()
        let nextGeneration = try #require(gate.snapshot())
        #expect(nextGeneration != capturedGeneration)
        #expect(gate.accepts(nextGeneration))
    }
}
