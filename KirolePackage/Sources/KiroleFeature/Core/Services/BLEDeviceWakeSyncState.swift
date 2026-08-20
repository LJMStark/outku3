import Foundation

struct BLEDeviceWakeSyncState {
    struct Request: Equatable {
        let force: Bool
        let hardwareWakeDate: Date?
    }

    enum DeviceWakeDecision: Equatable {
        case startDedicatedSync
        case mergeIntoActiveSync
        case enqueueForcedSync
    }

    private struct ActiveSync {
        var acceptsDeviceWake = true
        var hadMergedDeviceWake = false
        var hardwareWakeDate: Date?
    }

    private var activeSync: ActiveSync?
    private(set) var pendingRequest: Request?

    var isSyncing: Bool { activeSync != nil }
    var activeSyncHadMergedWake: Bool { activeSync?.hadMergedDeviceWake == true }
    var activeHardwareWakeDate: Date? { activeSync?.hardwareWakeDate }

    mutating func beginSync(
        force: Bool,
        hardwareWakeDate: Date?,
        taskActionBlocked: Bool
    ) -> Bool {
        guard activeSync == nil, !taskActionBlocked else {
            enqueue(force: force, hardwareWakeDate: hardwareWakeDate)
            return false
        }
        activeSync = ActiveSync(hardwareWakeDate: hardwareWakeDate)
        return true
    }

    mutating func handleDeviceWake(
        at date: Date,
        taskActionBlocked: Bool
    ) -> DeviceWakeDecision {
        if var activeSync {
            guard activeSync.acceptsDeviceWake, !taskActionBlocked else {
                enqueue(force: true, hardwareWakeDate: date)
                return .enqueueForcedSync
            }
            activeSync.hadMergedDeviceWake = true
            activeSync.hardwareWakeDate = latestDate(activeSync.hardwareWakeDate, date)
            self.activeSync = activeSync
            return .mergeIntoActiveSync
        }

        guard !taskActionBlocked else {
            enqueue(force: true, hardwareWakeDate: date)
            return .enqueueForcedSync
        }

        activeSync = ActiveSync(hardwareWakeDate: date)
        return .startDedicatedSync
    }

    mutating func closeDeviceWakeMergeWindow() {
        activeSync?.acceptsDeviceWake = false
    }

    mutating func finishActiveSync(
        transactionCommitted: Bool,
        retryMergedWake: Bool = true
    ) {
        guard let activeSync else { return }
        if activeSync.hadMergedDeviceWake, !transactionCommitted, retryMergedWake {
            enqueue(force: true, hardwareWakeDate: activeSync.hardwareWakeDate)
        }
        self.activeSync = nil
    }

    mutating func enqueue(force: Bool, hardwareWakeDate: Date?) {
        pendingRequest = Request(
            force: force || pendingRequest?.force == true,
            hardwareWakeDate: latestDate(pendingRequest?.hardwareWakeDate, hardwareWakeDate)
        )
    }

    /// Takes the pending request and reserves the next active slot before its Task is scheduled.
    /// A DeviceWake arriving in that scheduling gap therefore merges into this reserved run.
    mutating func reservePendingSyncIfPossible(taskActionBlocked: Bool) -> Request? {
        guard activeSync == nil, !taskActionBlocked, let pendingRequest else { return nil }
        self.pendingRequest = nil
        activeSync = ActiveSync(hardwareWakeDate: pendingRequest.hardwareWakeDate)
        return pendingRequest
    }

    mutating func resetForDisconnectedConnection() {
        activeSync = nil
        pendingRequest = nil
    }

    private func latestDate(_ existing: Date?, _ candidate: Date?) -> Date? {
        switch (existing, candidate) {
        case let (existing?, candidate?):
            return max(existing, candidate)
        case let (existing?, nil):
            return existing
        case let (nil, candidate?):
            return candidate
        case (nil, nil):
            return nil
        }
    }
}
