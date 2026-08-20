import Foundation

@MainActor
final class BLEDeviceWakeBarrier {
    private var generation: UInt64 = 0
    private var didObserveDeviceWake = false
    private var watchdogTask: Task<Void, Never>?
    private var watchdogGeneration: UInt64?
    private var watchdogHandler: (@MainActor @Sendable () -> Void)?
    private var timeoutRecoveryClaimed = false

    func prepare(generation: UInt64) {
        watchdogTask?.cancel()
        watchdogTask = nil
        watchdogGeneration = nil
        watchdogHandler = nil
        self.generation = generation
        didObserveDeviceWake = false
        timeoutRecoveryClaimed = false
    }

    func observe(generation: UInt64) {
        guard self.generation == generation, !timeoutRecoveryClaimed else { return }
        didObserveDeviceWake = true
        watchdogTask?.cancel()
        watchdogTask = nil
        watchdogGeneration = nil
        watchdogHandler = nil
    }

    func hasObserved(generation: UInt64) -> Bool {
        self.generation == generation && didObserveDeviceWake
    }

    func claimTimeoutRecovery(generation: UInt64) -> Bool {
        guard self.generation == generation,
              !didObserveDeviceWake,
              !timeoutRecoveryClaimed else { return false }
        timeoutRecoveryClaimed = true
        return true
    }

    func wait(generation: UInt64, timeout: Duration) async throws -> Bool {
        try Task.checkCancellation()
        guard self.generation == generation else { return false }
        if didObserveDeviceWake { return true }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(50))
            guard self.generation == generation else { return false }
            if didObserveDeviceWake {
                try Task.checkCancellation()
                return true
            }
        }
        try Task.checkCancellation()
        return didObserveDeviceWake
    }

    func armWatchdog(
        generation: UInt64,
        timeout: Duration,
        onTimeout: @escaping @MainActor @Sendable () -> Void
    ) {
        watchdogTask?.cancel()
        watchdogTask = nil
        watchdogGeneration = nil
        watchdogHandler = nil
        guard self.generation == generation,
              !didObserveDeviceWake,
              !timeoutRecoveryClaimed else { return }

        watchdogGeneration = generation
        watchdogHandler = onTimeout
        watchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.expireWatchdog(generation: generation)
        }
    }

    func expireWatchdog(generation: UInt64) {
        guard self.generation == generation,
              watchdogGeneration == generation,
              claimTimeoutRecovery(generation: generation) else { return }
        let handler = watchdogHandler
        watchdogTask?.cancel()
        watchdogTask = nil
        watchdogGeneration = nil
        watchdogHandler = nil
        handler?()
    }

    func cancelWatchdog(generation: UInt64) {
        guard self.generation == generation else { return }
        watchdogTask?.cancel()
        watchdogTask = nil
        watchdogGeneration = nil
        watchdogHandler = nil
    }
}
