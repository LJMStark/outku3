import Foundation
import Testing
@testable import KiroleFeature

@Suite("Simulator bridge task commands")
struct SimulatorBridgeTaskCommandTests {
    @Test("Local queue entry decodes the same top-level task identity used by complete and skip")
    func startTaskCommandDecodes() {
        let command = SimulatorBridge.taskCommand(from: """
        {"type":"hw_start_task","taskId":"task-1"}
        """)

        #expect(command == .start(taskID: "task-1"))
    }

    @Test("Missing or nested task identities are rejected")
    func malformedTaskCommandsAreRejected() {
        #expect(SimulatorBridge.taskCommand(from: """
        {"type":"hw_start_task","payload":{"taskId":"task-1"}}
        """) == nil)
        #expect(SimulatorBridge.taskCommand(from: """
        {"type":"hw_start_task","taskId":""}
        """) == nil)
    }
}
