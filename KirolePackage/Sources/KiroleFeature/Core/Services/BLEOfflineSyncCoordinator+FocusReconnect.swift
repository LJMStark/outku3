import Foundation
import os

/// 专注重连裁决的取证日志。**不受 `showsHardwareDebugTools` 门控**——客户包也要留痕。
///
/// 起因（2026-09-03）：客户设备陷入「连上 ~10 秒即断、反复重连」。固件日志显示
/// FOCUS_RESOLVE 被回 `INVALID_STATE(0x10)`，但固件的 hex dump 每帧只打 32 字节，
/// 而 `0x83 FOCUS_STATE` 整帧 39 字节——末尾 7 字节（elapsedSeconds 低半、
/// lastOperationID、endReason）恰好被截断，而它们正是 `isContentEmptyIdleSnapshot`
/// 的判据。App 这一侧本就把整帧解码成了结构体，落一行日志即可定案，
/// 不必等固件改打印。
///
/// Console.app 过滤：subsystem `com.kirole.app` + category `FocusReconnect`。
private enum FocusReconnectLog {
    static let logger = Logger(subsystem: "com.kirole.app", category: "FocusReconnect")
}

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
        state.pendingCount == 0
            && !state.stateFlags.contains(.focusSyncPending)
            && snapshot.isContentEmptyIdleSnapshot
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
            try await dependencies.previewFocusState(focusSnapshot)
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
        let skip = shouldSkipFocusResolve(state: state, snapshot: snapshot)
        logFocusSnapshot(state: state, snapshot: snapshot, skipped: skip)
        if skip {
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

    /// 落一行 key=value 取证日志：设备快照的**每个**字段 + 喂给 `shouldSkipFocusResolve`
    /// 的 STATE 字段 + 两个 idle 谓词的结论。
    ///
    /// `contentEmptyIdle` 与 `arbiterIdle` 分开打是刻意的——前者是 8 条件的
    /// `isContentEmptyIdleSnapshot`（决定发不发裁决），后者是 `FocusReconnectArbiter`
    /// 短路用的 2 条件（决定裁决内容）。两者不一致时 App 会「判定有残留却裁决为空」，
    /// 这一行日志能直接把这种组合钉出来。
    ///
    /// taskId 只打长度不打内容：它是任务标识而非标题，但日志不需要它的值。
    private func logFocusSnapshot(
        state: OfflineSyncState,
        snapshot: OfflineFocusState,
        skipped: Bool
    ) {
        let arbiterIdle = snapshot.focusState == .idle && snapshot.sessionId.isIdle
        FocusReconnectLog.logger.notice(
            """
            FocusState rev=\(snapshot.focusRevision, privacy: .public) \
            boot=\(snapshot.bootSessionID, privacy: .public) \
            sessionBoot=\(snapshot.sessionId.bootSessionID, privacy: .public) \
            sessionOp=\(snapshot.sessionId.startOperationID, privacy: .public) \
            state=\(snapshot.focusState.rawValue, privacy: .public) \
            startSrc=\(snapshot.startSource.rawValue, privacy: .public) \
            taskIdLen=\(snapshot.taskId.count, privacy: .public) \
            start=\(snapshot.startTimestamp, privacy: .public) \
            end=\(snapshot.endTimestamp, privacy: .public) \
            elapsed=\(snapshot.elapsedSeconds, privacy: .public) \
            lastOpID=\(snapshot.lastOperationID, privacy: .public) \
            endReason=\(snapshot.endReason.rawValue, privacy: .public) \
            | pending=\(state.pendingCount, privacy: .public) \
            flags=0x\(String(format: "%02X", state.stateFlags.rawValue), privacy: .public) \
            | contentEmptyIdle=\(snapshot.isContentEmptyIdleSnapshot, privacy: .public) \
            arbiterIdle=\(arbiterIdle, privacy: .public) \
            skipResolve=\(skipped, privacy: .public)
            """
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
        let resolve = try await dependencies.resolveFocus(snapshot)
        awaitingFocusResolveResult = true
        expectedSyncID = resolve.resolveID

        let inbound = try await requestFocusResolveOutcome(resolve, runID: runID)
        guard case .result(let result) = inbound else {
            throw BLEOfflineSyncCoordinatorError.invalidInbound
        }
        // 配对取证：把 App 发出去的裁决和设备回的结果码打在一起。日志里
        // `FocusResolve -> result=0x10` 紧跟前一行 `FocusState ...`，即可判定
        // 「设备报了什么 → App 裁决了什么 → 设备为什么拒」这条完整因果。
        FocusReconnectLog.logger.notice(
            """
            FocusResolve id=\(resolve.resolveID, privacy: .public) \
            verdictState=\(resolve.focusState.rawValue, privacy: .public) \
            verdictResult=\(resolve.result.rawValue, privacy: .public) \
            verdictRev=\(resolve.focusRevision, privacy: .public) \
            sessionBoot=\(resolve.sessionId.bootSessionID, privacy: .public) \
            sessionOp=\(resolve.sessionId.startOperationID, privacy: .public) \
            -> syncID=\(result.syncID, privacy: .public) \
            target=0x\(String(format: "%02X", result.targetType.rawValue), privacy: .public) \
            result=0x\(String(format: "%02X", result.resultCode.rawValue), privacy: .public)
            """
        )
        if result.syncID == resolve.resolveID,
           result.targetType == .offlineSync,
           result.resultCode == .committed {
            // Applying and durably storing the committed identity is part of the barrier. If it
            // fails, keep ordinary 0x14 frozen and let the outer transaction disconnect/reconcile.
            try await dependencies.restoreOrdinaryFocusSync(snapshot, resolve)
            awaitingFocusResolveResult = false
            if didFreezeFocusStatus {
                dependencies.unfreezeFocusStatus()
                didFreezeFocusStatus = false
            }
            return .resolved(true)
        }
        if result.resultCode == .invalidState, allowInvalidStateRetry {
            return .invalidStateRequery
        }
        dependencies.abandonPendingFocusResolve()
        throw BLEOfflineSyncCoordinatorError.deviceRejected(result.resultCode)
    }

    private func recoverAfterInvalidFocusResolve(runID: UUID) async throws -> PostQueryPhase {
        dependencies.invalidatePendingFocusResolve()
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
