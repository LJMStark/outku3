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
        // Live connected focus must not COMMIT: firmware treats COMMIT as an atomic
        // TaskList/Schedule/DayPack switch and leaves TaskIn. FOCUS_RESOLVE restores
        // ordinary 0x14/0x11/0x10/0x03 instead of punching this gate.
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
