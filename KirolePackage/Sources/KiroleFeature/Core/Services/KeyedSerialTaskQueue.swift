import Foundation

/// Runs asynchronous operations in submission order per key while allowing different keys to
/// progress independently. This is useful for last-write-wins APIs that do not offer versions.
@MainActor
final class KeyedSerialTaskQueue<Key: Hashable & Sendable> {
    private struct Entry {
        let id: UUID
        let task: Task<Void, Never>
    }

    private var tails: [Key: Entry] = [:]

    @discardableResult
    func enqueue(
        for key: Key,
        operation: @escaping @MainActor @Sendable () async -> Void
    ) -> Task<Void, Never> {
        let previous = tails[key]?.task
        let entryID = UUID()
        let task = Task { @MainActor [weak self] in
            await previous?.value
            if !Task.isCancelled {
                await operation()
            }
            self?.removeTail(for: key, matching: entryID)
        }
        tails[key] = Entry(id: entryID, task: task)
        return task
    }

    func run<Value: Sendable>(
        for key: Key,
        operation: @escaping @MainActor @Sendable () async throws -> Value
    ) async throws -> Value {
        let previous = tails[key]?.task
        let entryID = UUID()
        let resultTask = Task<Value, Error> { @MainActor in
            await previous?.value
            try Task.checkCancellation()
            return try await operation()
        }
        let tailTask = Task { @MainActor [weak self] in
            do {
                _ = try await resultTask.value
            } catch {
                // The caller owns the result; the queue tail only preserves ordering.
            }
            self?.removeTail(for: key, matching: entryID)
        }
        tails[key] = Entry(id: entryID, task: tailTask)
        // Task.value 不会把等待方的取消传给被等任务；不转发的话，调用方被取消后
        // 操作照常执行、结果无人认领。转发后：未起跑的操作被 checkCancellation 拦下，
        // 已起跑的操作可自行观察 Task.isCancelled（后继操作不受影响，尾任务仍保序）。
        return try await withTaskCancellationHandler {
            try await resultTask.value
        } onCancel: {
            resultTask.cancel()
        }
    }

    private func removeTail(for key: Key, matching entryID: UUID) {
        guard tails[key]?.id == entryID else { return }
        tails.removeValue(forKey: key)
    }
}
