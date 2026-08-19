import Foundation

extension BLEOfflineSyncCoordinator {
    func receiveFocusStateIfNeeded(
        state: OfflineSyncState,
        runID: UUID
    ) async throws -> OfflineFocusState? {
        guard state.stateFlags.contains(.focusSyncPending) else { return nil }
        let inbound = try await waitForMessage(
            expecting: .focusState(bootSessionID: state.bootSessionID),
            runID: runID
        )
        guard case .focusState(let snapshot) = inbound else {
            throw BLEOfflineSyncCoordinatorError.invalidInbound
        }
        return snapshot
    }

    func sendFocusResolveIfNeeded(
        state: OfflineSyncState,
        snapshot: OfflineFocusState?,
        runID: UUID
    ) async throws -> Bool {
        guard state.stateFlags.contains(.focusSyncPending) else { return false }
        guard let snapshot else {
            throw BLEOfflineSyncCoordinatorError.invalidInbound
        }
        let resolve = await dependencies.resolveFocus(snapshot)
        // Firmware 1.3.0: FOCUS_RESOLVE is a 33-byte command with no RESULT row.
        try await sendCommand(.focusResolve(resolve), runID: runID)
        if didFreezeFocusStatus {
            dependencies.unfreezeFocusStatus()
            didFreezeFocusStatus = false
        }
        await dependencies.restoreOrdinaryFocusSync(snapshot, resolve)
        return true
    }
}
