import Foundation
import os

/// 专注重连裁决的取证日志。**不受 `showsHardwareDebugTools` 门控**——客户包也要留痕。
///
/// 这是 AGENTS.md「Release Channel Policy」下**一条经登记的例外**（"Narrow exception —
/// authorised fault records" 的授权记录表），不是那条禁令本身允许的行为：禁令原文要求
/// 内部诊断在 App Store 包中缺席，本记录靠满足四个条件才获批——仅异常路径触发、不含
/// 任何用户文本、不提供任何操作能力、并登记进 `scripts/verify-release-boundary.sh` 的
/// 白名单（未登记的新诊断照样会被门禁拦下）。改动本记录的触发条件或字段前先回读那一节。
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
            && snapshot.hasNoArbitrableFocusContent
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
        if shouldSkipFocusResolve(state: state, snapshot: snapshot) {
            dependencies.abandonPendingFocusResolve()
            releaseFocusResolveWaitIfNeeded()
            return .resolved(false)
        }
        return try await sendFocusResolveOnce(
            state: state,
            snapshot: snapshot,
            allowInvalidStateRetry: allowInvalidStateRetry,
            runID: runID
        )
    }

    /// 裁决被拒时落一行 key=value 取证日志：设备快照的每个字段 + 喂给
    /// `shouldSkipFocusResolve` 的 STATE 字段 + 两个 idle 谓词的结论 + App 实际
    /// 发出的整份裁决 + 设备的结果码。一行读完「设备报了什么 → App 裁决了什么
    /// → 设备为什么拒」。
    ///
    /// **只在 `resultCode != .committed` 时打**——这是 AGENTS.md 授权例外的第 1 个条件
    /// （仅异常路径），不是「因此就合规了」：成功轮次不留痕只是把留痕面缩到最小，
    /// 获批还要同时满足不含用户文本、不提供操作能力、已登记进门禁白名单。异常仍然留痕，
    /// 是因为这类「两端对同一状态理解不一致」的故障只在客户现场出现，而客户包没有任何
    /// 其他 BLE 日志（`BLEService` 的 TX/RX 摘要受 `showsHardwareDebugTools` 门控）。
    ///
    /// 三个 idle 判据分开打是刻意的，它们各管一件事、可以互不一致：
    /// - `noArbitrable` = `hasNoArbitrableFocusContent`，决定**发不发**裁决
    ///   （`shouldSkipFocusResolve` 用它；忽略 revision / lastOperationID 两个水位）
    /// - `arbiterIdle` = `FocusReconnectArbiter` 的 2 条件短路，决定**发什么**
    /// - `wireEmptyIdle` = `isContentEmptyIdleSnapshot`，字节表允许的 rev=0 哨兵形状
    ///   （比前者多要求 `lastOperationID == 0`）
    ///
    /// `noArbitrable=false` + `arbiterIdle=true` 就是 2026-09-03 那次故障的指纹：
    /// App「判定有残留却裁决为空」。`wireEmptyIdle=false` + `noArbitrable=true`
    /// 则说明固件在空闲快照里带了非零 `lastOperationID`——偏离书面合同，
    /// App 侧容忍但需要提给硬件团队。
    ///
    /// 出站侧打**全部** wire 字段：时间戳 / phase / bottles 同样可能是设备拒绝的理由，
    /// 少打一个就可能白跑一轮取证。taskId 只打长度不打内容。整数字段用 `.public`：
    /// 打码后无法比对，取证价值归零；这些是协议整数，不含用户文本。
    private func logRejectedFocusResolve(
        state: OfflineSyncState,
        snapshot: OfflineFocusState,
        resolve: OfflineFocusResolve,
        result: OfflineSyncResult
    ) {
        let arbiterIdle = snapshot.takesIdleShortCircuit
        FocusReconnectLog.logger.notice(
            """
            FocusResolve REJECTED result=0x\(String(format: "%02X", result.resultCode.rawValue), privacy: .public) \
            target=0x\(String(format: "%02X", result.targetType.rawValue), privacy: .public) \
            syncID=\(result.syncID, privacy: .public) \
            | device rev=\(snapshot.focusRevision, privacy: .public) \
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
            | state pending=\(state.pendingCount, privacy: .public) \
            flags=0x\(String(format: "%02X", state.stateFlags.rawValue), privacy: .public) \
            | verdict id=\(resolve.resolveID, privacy: .public) \
            sessionBoot=\(resolve.sessionId.bootSessionID, privacy: .public) \
            sessionOp=\(resolve.sessionId.startOperationID, privacy: .public) \
            state=\(resolve.focusState.rawValue, privacy: .public) \
            result=\(resolve.result.rawValue, privacy: .public) \
            start=\(resolve.startTimestamp, privacy: .public) \
            end=\(resolve.endTimestamp, privacy: .public) \
            elapsed=\(resolve.elapsedSeconds, privacy: .public) \
            rev=\(resolve.focusRevision, privacy: .public) \
            phase=\(resolve.phase.wireByte, privacy: .public) \
            bottles=\(resolve.bottles, privacy: .public) \
            | noArbitrable=\(snapshot.hasNoArbitrableFocusContent, privacy: .public) \
            wireEmptyIdle=\(snapshot.isContentEmptyIdleSnapshot, privacy: .public) \
            arbiterIdle=\(arbiterIdle, privacy: .public)
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
        state: OfflineSyncState,
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
        if result.resultCode != .committed {
            logRejectedFocusResolve(
                state: state,
                snapshot: snapshot,
                resolve: resolve,
                result: result
            )
        }
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
