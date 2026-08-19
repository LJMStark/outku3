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
        awaitingFocusResolveResult = true
        expectedSyncID = resolve.resolveID

        let inbound = try await requestFocusResolveCommitted(
            resolve,
            runID: runID
        )
        guard case .result(let result) = inbound else {
            throw BLEOfflineSyncCoordinatorError.invalidInbound
        }
        guard result.syncID == resolve.resolveID,
              result.targetType == .offlineSync,
              result.resultCode == .committed else {
            throw BLEOfflineSyncCoordinatorError.deviceRejected(result.resultCode)
        }

        awaitingFocusResolveResult = false
        if didFreezeFocusStatus {
            dependencies.unfreezeFocusStatus()
            didFreezeFocusStatus = false
        }
        await dependencies.restoreOrdinaryFocusSync(snapshot, resolve)
        return true
    }

    /// Firmware 1.3.1: wait for RESULT/COMMITTED. Timeout retries reuse the same
    /// ResolveID and payload. ACCEPTED keeps the waiter parked.
    private func requestFocusResolveCommitted(
        _ resolve: OfflineFocusResolve,
        runID: UUID
    ) async throws -> OfflineSyncInboundMessage {
        do {
            return try await request(
                .focusResolve(resolve),
                expecting: .committed(syncID: resolve.resolveID),
                runID: runID
            )
        } catch BLEOfflineSyncCoordinatorError.timedOut {
            expectedSyncID = resolve.resolveID
            return try await request(
                .focusResolve(resolve),
                expecting: .committed(syncID: resolve.resolveID),
                runID: runID
            )
        }
    }
}
