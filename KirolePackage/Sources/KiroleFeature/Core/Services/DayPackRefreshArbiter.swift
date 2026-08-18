import Foundation

/// Decides whether an OfflineSync round should BEGIN/COMMIT TaskList+Schedule+DayPack.
///
/// Phone dialogue refresh is never a commit reason. A commit happens when the task bar
/// or schedule actually changed, or when an idle force refresh (wake / physical 0x20)
/// asked for a full snapshot. Focus heartbeats must not COMMIT — firmware treats
/// COMMIT as an atomic dataset switch and will leave TaskIn.
enum DayPackRefreshArbiter {
    static func shouldCommitDatasets(
        structuralChanged: Bool,
        force: Bool,
        hasActiveFocusSession: Bool
    ) -> Bool {
        // COMMIT is an atomic TaskList/Schedule/DayPack switch. Current firmware leaves
        // TaskIn when that happens, so focus may only COMMIT when the device itself
        // reports NeedsFullSync / invalid / expired ValidUntil (handled by the coordinator).
        if hasActiveFocusSession { return false }
        if structuralChanged { return true }
        return force
    }

    /// DeviceWake must run Time/QUERY/ops immediately, but must not treat the wake
    /// itself as a screen-refresh. Physical 0x20, Settings sync, and focus-end still force COMMIT.
    static func shouldForceCommit(force: Bool, isHardwareWake: Bool) -> Bool {
        force && !isHardwareWake
    }
}
