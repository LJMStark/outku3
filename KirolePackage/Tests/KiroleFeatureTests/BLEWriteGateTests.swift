import Testing
@testable import KiroleFeature

@Suite("BLEWriteGate")
struct BLEWriteGateTests {

    @Test("acquire and release round-trip completes normally")
    func acquireReleaseRoundTrip() async throws {
        let gate = BLEWriteGate()
        try await gate.acquire()
        await gate.release()
        // Second acquire must succeed immediately (gate was released)
        try await gate.acquire()
        await gate.release()
    }

    @Test("cancelled waiter receives CancellationError without deadlocking the gate")
    func cancelledWaiterDoesNotDeadlockGate() async throws {
        let gate = BLEWriteGate()
        try await gate.acquire()  // Hold the lock

        let waiterTask = Task<Void, Error> {
            try await gate.acquire()  // Queues behind the held lock
        }

        // Yield briefly so waiterTask can enter withCheckedThrowingContinuation
        try await Task.sleep(for: .milliseconds(20))
        waiterTask.cancel()

        do {
            try await waiterTask.value
            Issue.record("Expected CancellationError but acquire succeeded")
        } catch is CancellationError {
            // Expected path
        }

        // Release the lock — cancelWaiter already removed the entry, so gate becomes free
        await gate.release()

        // Verify gate is not deadlocked: a fresh acquire must complete promptly
        let subsequentTask = Task<Void, Error> {
            try await gate.acquire()
            await gate.release()
        }
        // If deadlocked this would hang; 500ms is generous
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await subsequentTask.value }
            group.addTask {
                try await Task.sleep(for: .milliseconds(500))
                throw CancellationError()
            }
            try await group.next()!
            group.cancelAll()
        }
    }

    @Test("cancelling one waiter does not block other waiters")
    func cancelOneWaiterOthersUnaffected() async throws {
        let gate = BLEWriteGate()
        try await gate.acquire()  // Task 0 holds the lock

        // Task 1: will be cancelled
        let waiter1 = Task<Void, Error> { try await gate.acquire() }
        // Task 2: should succeed after release
        let waiter2 = Task<Void, Error> {
            try await gate.acquire()
            await gate.release()
        }

        try await Task.sleep(for: .milliseconds(20))
        waiter1.cancel()

        // Consume waiter1's result (CancellationError expected)
        _ = await waiter1.result

        // Release: hands off to waiter2
        await gate.release()

        // waiter2 must complete without error
        try await waiter2.value
    }
}
