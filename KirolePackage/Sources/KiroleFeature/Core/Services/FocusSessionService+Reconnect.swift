import Foundation

extension FocusSessionService {
    /// Frozen from DeviceWake until FOCUS_RESOLVE receives RESULT/COMMITTED.
    public var isFocusStatusPushFrozen: Bool {
        get { FocusReconnectFlagStore.flags(for: self).isFocusStatusPushFrozen }
        set { FocusReconnectFlagStore.flags(for: self).isFocusStatusPushFrozen = newValue }
    }

    public var lastAppliedFocusRevision: UInt32 {
        get { FocusReconnectFlagStore.flags(for: self).lastAppliedFocusRevision }
        set { FocusReconnectFlagStore.flags(for: self).lastAppliedFocusRevision = newValue }
    }

    /// When the device snapshot is `endedPending`, replayed EnterTaskIn must not open the focus UI.
    public var suppressVisibleFocusStart: Bool {
        get { FocusReconnectFlagStore.flags(for: self).suppressVisibleFocusStart }
        set { FocusReconnectFlagStore.flags(for: self).suppressVisibleFocusStart = newValue }
    }

    func applyReconnectPreview(_ state: OfflineFocusState) async {
        // Preview must not start, replace, or end a session before OP_BATCH / FOCUS_RESOLVE.
        suppressVisibleFocusStart = state.focusState == .endedPending
    }

    func reuseOrMakeResolveID(
        for sessionId: FocusSessionId,
        proposed: UInt32
    ) -> UInt32 {
        let flags = FocusReconnectFlagStore.flags(for: self)
        if flags.lastResolveID != 0, flags.lastResolveSessionId == sessionId {
            return flags.lastResolveID
        }
        let id = proposed == 0 ? 1 : proposed
        flags.lastResolveID = id
        flags.lastResolveSessionId = sessionId
        return id
    }

    func resolveReconnect(_ state: OfflineFocusState, resolveID: UInt32) async -> OfflineFocusResolve {
        let snapshot = reconnectSnapshot()
        let decision = FocusReconnectArbiter.decide(
            device: state,
            app: snapshot,
            resolveID: reuseOrMakeResolveID(for: state.sessionId, proposed: resolveID)
        )
        await applyReconnectAction(decision.action)
        stampReconnectIdentity(from: state, revision: decision.command.focusRevision)
        suppressVisibleFocusStart = false
        return decision.command
    }

    func restoreOrdinaryFocusSyncAfterResolve(
        _ snapshot: OfflineFocusState,
        resolve: OfflineFocusResolve
    ) async {
        if resolve.focusState == .active {
            await sendTaskInPageForReconnect(taskId: snapshot.taskId)
        }
        await AppState.shared.syncFocusHardwareDisplay(
            session: resolve.focusState == .active ? activeSession : nil
        )
    }

    func reconnectSnapshot() -> FocusReconnectAppSnapshot {
        let progress = progressSnapshot()
        return FocusReconnectAppSnapshot(
            active: activeSession,
            history: todaySessions,
            activeElapsedSeconds: UInt32(clamping: Int(progress.elapsedSeconds)),
            activeSegmentSeconds: UInt32(clamping: Int(progress.segmentSeconds)),
            activePhase: progress.phase,
            activeBottles: UInt8(clamping: FocusEnergyCalculator.displayBottles(
                forEarned: progress.earnedEnergyBottles
            )),
            currentRevision: activeSession?.focusRevision ?? lastAppliedFocusRevision
        )
    }

    func settleHistoricalSession(
        taskId: String,
        taskTitle: String,
        startTime: Date,
        endTime: Date,
        reason: FocusEndReason,
        focusSessionId: FocusSessionId,
        elapsedSeconds: UInt32
    ) {
        guard activeSession == nil else { return }
        var session = FocusSession(
            taskId: taskId,
            taskTitle: taskTitle,
            startTime: startTime,
            focusSessionId: focusSessionId,
            focusRevision: lastAppliedFocusRevision
        )
        session.endTime = max(endTime, startTime)
        session.endReason = reason
        Self.applyAuthoritativeElapsed(&session, elapsedSeconds: elapsedSeconds)
        completeSession(
            session,
            endTime: session.endTime ?? endTime,
            clearPersistedActiveSession: false,
            operationKey: nil
        )
    }

    static func applyAuthoritativeElapsed(_ session: inout FocusSession, elapsedSeconds: UInt32) {
        session.calculatedFocusTime = TimeInterval(elapsedSeconds)
        session.earnedEnergyBottles = Int(elapsedSeconds / 1_800)
    }

    func retainActiveSessionIfSameFocus(
        _ active: FocusSession,
        incomingSessionId: FocusSessionId?
    ) -> FocusSession? {
        if let incoming = incomingSessionId,
           let current = active.focusSessionId,
           current != incoming {
            return nil
        }
        if active.focusSessionId == nil, let incomingSessionId {
            var updated = active
            updated.focusSessionId = incomingSessionId
            activeSession = updated
            return updated
        }
        return active
    }

    private func stampReconnectIdentity(from state: OfflineFocusState, revision: UInt32) {
        lastAppliedFocusRevision = revision
        let deviceId = BLEService.shared.connectedDeviceID?.uuidString
        func apply(_ session: inout FocusSession) {
            session.focusRevision = revision
            if session.focusSessionId == nil || session.focusSessionId == state.sessionId {
                session.focusSessionId = state.sessionId.isIdle ? session.focusSessionId : state.sessionId
            }
            session.deviceId = deviceId ?? session.deviceId
            session.bootSessionId = state.bootSessionID
            session.startSource = state.startSource
            session.lastOperationId = state.lastOperationID
        }
        if var session = activeSession {
            apply(&session)
            activeSession = session
            return
        }
        if let index = todaySessions.lastIndex(where: { $0.focusSessionId == state.sessionId }) {
            apply(&todaySessions[index])
        }
    }

    private func sendTaskInPageForReconnect(taskId: String) async {
        guard let task = BLEEventHandler.resolveTask(taskId: taskId, in: AppState.shared.tasks) else {
            return
        }
        let page = await DayPackGenerator.shared.generateTaskInPage(
            task: task,
            pet: AppState.shared.pet,
            userProfile: AppState.shared.userProfile
        )
        do {
            try await BLEService.shared.sendTaskInPage(page)
        } catch {
            ErrorReporter.log(
                .sync(component: "FocusReconnect TaskInPage", underlying: error.localizedDescription),
                context: "FocusSessionService.restoreOrdinaryFocusSyncAfterResolve"
            )
        }
    }

    private func applyReconnectAction(_ action: FocusReconnectAction) async {
        switch action {
        case .none, .keepExisting:
            return
        case .adopt(let taskId, let start, let sessionId):
            let title = BLEEventHandler.resolveTask(
                taskId: taskId,
                in: AppState.shared.tasks
            )?.title ?? "Task"
            _ = await startSession(
                taskId: taskId,
                taskTitle: title,
                startTime: start,
                focusSessionId: sessionId
            )
        case .endActive(let reason, let endTime):
            endSession(reason: reason, endTime: endTime)
        case .settleHistorical(
            let taskId, let start, let end, let reason, let sessionId, let elapsed
        ):
            let title = BLEEventHandler.resolveTask(
                taskId: taskId,
                in: AppState.shared.tasks
            )?.title ?? "Task"
            settleHistoricalSession(
                taskId: taskId,
                taskTitle: title,
                startTime: start,
                endTime: end,
                reason: reason,
                focusSessionId: sessionId,
                elapsedSeconds: elapsed
            )
        case .replaceWithDevice(let taskId, let start, let sessionId, let oldEnd):
            if activeSession != nil {
                endSession(reason: .timeout, endTime: oldEnd)
            }
            let title = BLEEventHandler.resolveTask(
                taskId: taskId,
                in: AppState.shared.tasks
            )?.title ?? "Task"
            _ = await startSession(
                taskId: taskId,
                taskTitle: title,
                startTime: start,
                focusSessionId: sessionId
            )
        }
    }
}
