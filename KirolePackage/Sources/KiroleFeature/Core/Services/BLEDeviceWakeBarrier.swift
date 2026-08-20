import Foundation

/// The non-error exit used when a healthy Notify connection has not produced DeviceWake yet.
/// Kept as one small operation so production and tests exercise the same ordering: close the
/// merge window before the async gate release, then release only this sync's freeze lease.
@MainActor
enum BLEDeviceWakeDeferredSyncExit {
    static func finish(
        closeDeviceWakeMergeWindow: () -> Void,
        ownsOfflineWriteSession: Bool,
        endOfflineWriteSession: () async -> Void,
        releaseOfflineFocusFreezeLease: () -> Void
    ) async {
        closeDeviceWakeMergeWindow()
        if ownsOfflineWriteSession {
            await endOfflineWriteSession()
        }
        releaseOfflineFocusFreezeLease()
    }
}

@MainActor
final class BLEDeviceWakeBarrier {
    private var generation: UInt64 = 0
    private var didObserveDeviceWake = false

    func prepare(generation: UInt64) {
        self.generation = generation
        didObserveDeviceWake = false
    }

    func observe(generation: UInt64) {
        guard self.generation == generation else { return }
        didObserveDeviceWake = true
    }

    func hasObserved(generation: UInt64) -> Bool {
        self.generation == generation && didObserveDeviceWake
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
}
