import Foundation

@MainActor
final class SharedPersistenceTestLock {
    static let shared = SharedPersistenceTestLock()

    private var isLocked = false

    func withLock<T>(_ body: () async throws -> T) async rethrows -> T {
        while isLocked {
            await Task.yield()
        }
        isLocked = true
        defer { isLocked = false }
        return try await body()
    }
}
