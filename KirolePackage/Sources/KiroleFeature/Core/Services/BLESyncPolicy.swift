import Foundation

// MARK: - BLE Sync Policy

struct BLESyncPolicy {
    func nextSyncTime(now: Date, lastSync: Date?) -> Date {
        let interval = syncInterval(for: now)
        guard let lastSync = lastSync else { return now }
        return lastSync.addingTimeInterval(interval)
    }

    func shouldSync(
        now: Date,
        lastSync: Date?,
        contentChanged: Bool,
        force: Bool,
        hasPriorityCustomAvatarOperation: Bool = false
    ) -> Bool {
        if force || hasPriorityCustomAvatarOperation { return true }
        if contentChanged { return true }
        let next = nextSyncTime(now: now, lastSync: lastSync)
        return now >= next
    }

    func shouldHoldConnectionForCustomAvatar(
        chunkedTransferInFlight: Bool,
        operationState: CustomAvatarOperationState
    ) -> Bool {
        chunkedTransferInFlight || operationState.isInProgress
    }

    private func syncInterval(for date: Date) -> TimeInterval {
        let hour = Calendar.current.component(.hour, from: date)
        if hour >= 23 || hour < 8 {
            return 4 * 60 * 60
        }
        return 60 * 60
    }
}
