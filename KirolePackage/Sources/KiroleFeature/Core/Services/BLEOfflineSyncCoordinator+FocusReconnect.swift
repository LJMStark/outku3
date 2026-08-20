import Foundation

extension BLEOfflineSyncCoordinator {
    func receiveFocusStateIfNeeded(
        state: OfflineSyncState,
        runID: UUID
    ) async throws -> OfflineFocusState? {
        guard shouldAwaitFocusSnapshot(state) else { return nil }
        awaitingFocusResolveResult = true
        let inbound = try await waitForMessage(
            expecting: .focusState(bootSessionID: state.bootSessionID),
            runID: runID
        )
        guard case .focusState(let snapshot) = inbound else {
            throw BLEOfflineSyncCoordinatorError.invalidInbound
        }
        return snapshot
    }

    func shouldAwaitFocusSnapshot(_ state: OfflineSyncState) -> Bool {
        if state.stateFlags.contains(.focusSyncPending) { return true }
        if hasActiveFocusSession() { return true }
        return mailbox.contains { message in
            guard case .focusState(let snapshot) = message else { return false }
            return snapshot.bootSessionID == state.bootSessionID
                && !snapshot.isMeaninglessIdleSnapshot
        }
    }

    func shouldSkipFocusResolve(
        state: OfflineSyncState,
        snapshot: OfflineFocusState
    ) -> Bool {
        !state.stateFlags.contains(.focusSyncPending)
            && !hasActiveFocusSession()
            && snapshot.isMeaninglessIdleSnapshot
    }

    struct PostQueryPhase: Equatable {
        var state: OfflineSyncState
        var processedCount: Int
        var didResolveFocus: Bool
    }

    enum FocusResolveStepResult: Equatable {
        case resolved(Bool)
        case invalidStateRequery
    }

    func runPostQueryPhase(
        _ initialState: OfflineSyncState,
        allowInvalidStateRetry: Bool,
        runID: UUID
    ) async throws -> PostQueryPhase {
        let state = try await recoverOpenTransactionIfNeeded(
            initialState,
            runID: runID
        )
        let focusSnapshot = try await receiveFocusStateIfNeeded(state: state, runID: runID)
        if let focusSnapshot {
            await dependencies.previewFocusState(focusSnapshot)
        }
        let processedCount = try await drainOperations(
            state: state,
            runID: runID
        )
        let step = try await sendFocusResolveIfNeeded(
            state: state,
            snapshot: focusSnapshot,
            allowInvalidStateRetry: allowInvalidStateRetry,
            runID: runID
        )
        switch step {
        case .resolved(let didResolveFocus):
            return PostQueryPhase(
                state: state,
                processedCount: processedCount,
                didResolveFocus: didResolveFocus
            )
        case .invalidStateRequery:
            return try await recoverAfterInvalidFocusResolve(runID: runID)
        }
    }

    func sendFocusResolveIfNeeded(
        state: OfflineSyncState,
        snapshot: OfflineFocusState?,
        allowInvalidStateRetry: Bool,
        runID: UUID
    ) async throws -> FocusResolveStepResult {
        guard let snapshot else {
            if state.stateFlags.contains(.focusSyncPending) {
                throw BLEOfflineSyncCoordinatorError.invalidInbound
            }
            dependencies.abandonPendingFocusResolve()
            releaseFocusResolveWaitIfNeeded()
            return .resolved(false)
        }
        if shouldSkipFocusResolve(state: state, snapshot: snapshot) {
            dependencies.abandonPendingFocusResolve()
            releaseFocusResolveWaitIfNeeded()
            return .resolved(false)
        }
        return try await sendFocusResolveOnce(
            snapshot: snapshot,
            allowInvalidStateRetry: allowInvalidStateRetry,
            runID: runID
        )
    }

    /// Firmware 1.3.1: wait for RESULT/COMMITTED or INVALID_STATE. Timeout
    /// retries reuse the same ResolveID and payload. ACCEPTED keeps the waiter
    /// parked. 0x10 is never treated as committed.
    private func requestFocusResolveOutcome(
        _ resolve: OfflineFocusResolve,
        runID: UUID
    ) async throws -> OfflineSyncInboundMessage {
        do {
            return try await request(
                .focusResolve(resolve),
                expecting: .focusResolveOutcome(syncID: resolve.resolveID),
                runID: runID
            )
        } catch BLEOfflineSyncCoordinatorError.timedOut {
            expectedSyncID = resolve.resolveID
            return try await request(
                .focusResolve(resolve),
                expecting: .focusResolveOutcome(syncID: resolve.resolveID),
                runID: runID
            )
        }
    }

    private func sendFocusResolveOnce(
        snapshot: OfflineFocusState,
        allowInvalidStateRetry: Bool,
        runID: UUID
    ) async throws -> FocusResolveStepResult {
        let resolve = await dependencies.resolveFocus(snapshot)
        awaitingFocusResolveResult = true
        expectedSyncID = resolve.resolveID

        let inbound = try await requestFocusResolveOutcome(resolve, runID: runID)
        guard case .result(let result) = inbound else {
            throw BLEOfflineSyncCoordinatorError.invalidInbound
        }
        if result.syncID == resolve.resolveID,
           result.targetType == .offlineSync,
           result.resultCode == .committed {
            awaitingFocusResolveResult = false
            if didFreezeFocusStatus {
                dependencies.unfreezeFocusStatus()
                didFreezeFocusStatus = false
            }
            await dependencies.restoreOrdinaryFocusSync(snapshot, resolve)
            return .resolved(true)
        }
        if result.resultCode == .invalidState, allowInvalidStateRetry {
            return .invalidStateRequery
        }
        dependencies.abandonPendingFocusResolve()
        throw BLEOfflineSyncCoordinatorError.deviceRejected(result.resultCode)
    }

    private func recoverAfterInvalidFocusResolve(runID: UUID) async throws -> PostQueryPhase {
        dependencies.abandonPendingFocusResolve()
        mailbox.removeAll(keepingCapacity: true)
        // STATE has no request ID. Drop the previous QUERY's boot and ResolveID
        // so this re-query is a fresh STATE → FOCUS_STATE → OP_BATCH → RESOLVE.
        expectedBootSessionID = nil
        expectedSyncID = nil
        let stateMessage = try await request(
            .query,
            expecting: .state,
            runID: runID
        )
        guard case .state(let newState) = stateMessage else {
            throw BLEOfflineSyncCoordinatorError.invalidInbound
        }
        return try await runPostQueryPhase(
            newState,
            allowInvalidStateRetry: false,
            runID: runID
        )
    }

    private func releaseFocusResolveWaitIfNeeded() {
        awaitingFocusResolveResult = false
        if didFreezeFocusStatus {
            dependencies.unfreezeFocusStatus()
            didFreezeFocusStatus = false
        }
    }
}
