import Foundation

actor BLEWriteGate {
    private var isWriting = false
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []

    /// Acquire the gate. Throws `CancellationError` if the calling task is cancelled while waiting.
    func acquire() async throws {
        guard isWriting else {
            isWriting = true
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append((id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
    }

    func release() {
        guard let next = waiters.first else {
            isWriting = false
            return
        }
        waiters.removeFirst()
        next.continuation.resume()
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }
}
