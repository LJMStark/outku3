import Foundation

extension FocusSessionService {
    // MARK: - Persistence

    func loadTodaySessions() async {
        guard persistenceEnabled else { return }

        do {
            if let sessions = try await focusPersistence.loadSessions() {
                loadedFocusSessionHistory = Dictionary(
                    uniqueKeysWithValues: sessions.map { ($0.id, $0) }
                )
                let calendar = Calendar.current
                let today = calendar.startOfDay(for: Date())
                todaySessions = sessions.filter { session in
                    calendar.isDate(session.startTime, inSameDayAs: today)
                }
                updateStatistics()
            }
        } catch {
            ErrorReporter.log(
                .persistence(
                    operation: "load",
                    target: "focus_sessions.json",
                    underlying: error.localizedDescription
                ),
                context: "FocusSessionService.loadTodaySessions"
            )
        }
    }

    private func saveSessions() async -> Bool {
        guard persistenceEnabled else { return true }

        do {
            try await focusPersistence.saveSessions(todaySessions, date: Date())
            return true
        } catch {
            ErrorReporter.log(
                .persistence(
                    operation: "save",
                    target: "focus_sessions",
                    underlying: error.localizedDescription
                ),
                context: "FocusSessionService.saveSessions"
            )
            return false
        }
    }

    func schedulePendingFocusSettlement() {
        let previousTask = pendingSessionPersistenceTask
        pendingSessionPersistenceTask = Task { @MainActor in
            _ = await previousTask?.result
            return await self.persistPendingFocusSettlement()
        }
    }

    func waitForPendingSessionPersistence() async -> Bool {
        await pendingSessionPersistenceTask?.value ?? true
    }

    func retryPendingFocusSettlementIfNeeded() async -> Bool {
        if await waitForPendingSessionPersistence(), pendingFocusSettlement == nil {
            return true
        }
        guard pendingFocusSettlement != nil else { return true }
        schedulePendingFocusSettlement()
        return await waitForPendingSessionPersistence()
    }

    func waitForPendingPersistenceForTesting() async {
        _ = await waitForPendingSessionPersistence()
    }

    /// BLE task receipts must not become committed while the ended focus session still exists only
    /// in memory. Awaiting the queue gives a post-crash retry a durable session boundary.
    func waitForHardwareTaskEndPersistence() async -> Bool {
        await retryPendingFocusSettlementIfNeeded()
    }

    /// Persists the active session with the interruptions recorded so far, so a crash recovery
    /// settles against the real interruption history instead of assuming an uninterrupted session
    /// (which over-credits bottles). Best practice: persist in-progress state early.
    func persistActiveSessionWithInterruptions(now: Date = Date()) async {
        guard persistenceEnabled, let session = activeSession else { return }
        var snapshot = session
        snapshot.screenUnlockEvents = currentUnlockEvents(until: now)
        await persistActiveSessionIfNeeded(snapshot)
    }

    func persistActiveSessionIfNeeded(_ session: FocusSession) async {
        guard persistenceEnabled else { return }

        do {
            try await focusPersistence.saveActiveSession(session)
        } catch {
            ErrorReporter.log(
                .persistence(
                    operation: "save",
                    target: "focus_session_active.json",
                    underlying: error.localizedDescription
                ),
                context: "FocusSessionService.persistActiveSessionIfNeeded"
            )
        }
    }

    private func clearPersistedActiveSessionIfNeeded() async -> Bool {
        guard persistenceEnabled else { return true }

        do {
            try await focusPersistence.clearActiveSession()
            return true
        } catch {
            ErrorReporter.log(
                .persistence(
                    operation: "delete",
                    target: "focus_session_active.json",
                    underlying: error.localizedDescription
                ),
                context: "FocusSessionService.clearPersistedActiveSessionIfNeeded"
            )
            return false
        }
    }

    func recoverSessionOnLaunchIfNeeded() async {
        guard persistenceEnabled else {
            preRecoveryInterruptions.removeAll()
            hasCompletedLaunchRecovery = true
            return
        }

        let wasShieldActive = await localStorage.loadDeepFocusShieldActive()
        if wasShieldActive {
            focusGuardService.clearShield()
            await localStorage.saveDeepFocusShieldActive(false)
        }

        let recovered: FocusSession?
        do {
            recovered = try await focusPersistence.loadActiveSession()
        } catch {
            ErrorReporter.log(
                .persistence(operation: "load", target: "active_focus_session", underlying: error.localizedDescription),
                context: "FocusSessionService.recoverSessionOnLaunchIfNeeded"
            )
            recovered = nil
        }
        let pendingInterruptions = takeLaunchRecoveryInterruptions()
        guard let recovered else {
            hasCompletedLaunchRecovery = await repairLoadedEnergyRewards()
            return
        }

        let pendingLookup = await taskOperationLedger.latestPendingOperation(for: recovered.taskId)
        guard pendingLookup != .unavailable else {
            // Preserve the in-memory and on-disk active session. A transient ledger read failure
            // must not erase the only recovery source or let a new session overwrite it.
            activeSession = recovered
            sessionInterruptions = recovered.screenUnlockEvents
            return
        }

        if let endedHistory = loadedFocusSessionHistory[recovered.id],
           let originalEndTime = endedHistory.endTime {
            activeSession = nil
            sessionInterruptions.removeAll()
            let operationKey: String?
            if case .found(let entry) = pendingLookup {
                operationKey = entry.operationKey
            } else {
                operationKey = nil
            }
            pendingFocusSettlement = PendingFocusSettlement(
                session: endedHistory,
                endTime: originalEndTime,
                clearPersistedActiveSession: true,
                operationKey: operationKey,
                historyAlreadyPersisted: true
            )
            schedulePendingFocusSettlement()
            let settlementPersisted = await waitForPendingSessionPersistence()
            let rewardsRepaired = settlementPersisted
                ? await repairLoadedEnergyRewards()
                : false
            hasCompletedLaunchRecovery = settlementPersisted && rewardsRepaired
            return
        }
        let recovery = launchRecoveryResolution(
            for: recovered,
            pendingLookup: pendingLookup,
            now: Date()
        )

        applyRecoveredSession(
            recovered,
            pendingInterruptions: pendingInterruptions,
            wasShieldActive: wasShieldActive,
            endTime: recovery.endTime,
            endReason: recovery.endReason,
            operationKey: recovery.operationKey
        )
        hasCompletedLaunchRecovery = await waitForPendingSessionPersistence()
    }

    func recoverPersistedSessionForTesting(
        _ persistedSession: FocusSession,
        wasShieldActive: Bool,
        endTime: Date = Date()
    ) {
        if wasShieldActive {
            focusGuardService.clearShield()
        }
        let pendingInterruptions = takeLaunchRecoveryInterruptions()
        applyRecoveredSession(
            persistedSession,
            pendingInterruptions: pendingInterruptions,
            wasShieldActive: wasShieldActive,
            endTime: endTime,
            endReason: .recoveredOnLaunch,
            operationKey: nil
        )
        hasCompletedLaunchRecovery = true
    }

    private func takeLaunchRecoveryInterruptions() -> [ScreenUnlockEvent] {
        let pending = preRecoveryInterruptions + interruptionDetector.takePendingInterruptions()
        preRecoveryInterruptions.removeAll()
        return pending
    }

    private func applyRecoveredSession(
        _ persistedSession: FocusSession,
        pendingInterruptions: [ScreenUnlockEvent],
        wasShieldActive: Bool,
        endTime: Date,
        endReason: FocusEndReason,
        operationKey: String?
    ) {
        var recovered = persistedSession
        recovered.endTime = endTime
        recovered.endReason = endReason
        let recoveredUnlocks = mergeRecoveredInterruptions(
            persisted: persistedSession.screenUnlockEvents,
            pending: pendingInterruptions,
            sessionStart: recovered.startTime,
            sessionEnd: endTime
        )
        recovered.screenUnlockEvents = recoveredUnlocks
        recovered.calculatedFocusTime = calculateFocusTime(
            sessionStart: recovered.startTime,
            sessionEnd: endTime,
            screenUnlockEvents: recoveredUnlocks
        )
        recovered.earnedEnergyBottles = FocusTimeCalculator.countableBottles(
            sessionStart: recovered.startTime,
            sessionEnd: endTime,
            screenUnlockEvents: recoveredUnlocks
        )
        if wasShieldActive || recovered.protectionState == .protected {
            recovered.mode = .standard
            recovered.protectionState = .fallback
            recovered.interruptionSource = .recoveredOnLaunch
        }

        completeSession(
            recovered,
            endTime: endTime,
            clearPersistedActiveSession: true,
            operationKey: operationKey
        )
    }

    private struct LaunchRecoveryResolution {
        let endTime: Date
        let endReason: FocusEndReason
        let operationKey: String?
    }

    private func launchRecoveryResolution(
        for session: FocusSession,
        pendingLookup: TaskOperationLedgerPendingLookup,
        now: Date
    ) -> LaunchRecoveryResolution {
        guard case .found(let entry) = pendingLookup else {
            return LaunchRecoveryResolution(
                endTime: now,
                endReason: .recoveredOnLaunch,
                operationKey: nil
            )
        }
        let eventTime = Date(timeIntervalSince1970: TimeInterval(entry.deviceTimestamp))
        let orderingTolerance: TimeInterval = 2
        let futureTolerance: TimeInterval = 5 * 60
        guard entry.recordedAt.addingTimeInterval(orderingTolerance) >= session.startTime,
              eventTime.addingTimeInterval(orderingTolerance) >= session.startTime,
              eventTime <= entry.recordedAt.addingTimeInterval(futureTolerance) else {
            return LaunchRecoveryResolution(
                endTime: now,
                endReason: .recoveredOnLaunch,
                operationKey: nil
            )
        }
        let endReason: FocusEndReason = entry.action == .completeTask ? .completed : .skipped
        return LaunchRecoveryResolution(
            endTime: max(session.startTime, min(eventTime, min(entry.recordedAt, now))),
            endReason: endReason,
            operationKey: entry.operationKey
        )
    }

    private func mergeRecoveredInterruptions(
        persisted: [ScreenUnlockEvent],
        pending: [ScreenUnlockEvent],
        sessionStart: Date,
        sessionEnd: Date
    ) -> [ScreenUnlockEvent] {
        let pendingInSession = pending.filter {
            $0.timestamp >= sessionStart && $0.timestamp <= sessionEnd
        }
        var seenTimestampSeconds = Set<Int64>()
        return (persisted + pendingInSession)
            .sorted { $0.timestamp < $1.timestamp }
            .filter {
                let timestampSecond = Int64($0.timestamp.timeIntervalSince1970.rounded(.down))
                return seenTimestampSeconds.insert(timestampSecond).inserted
            }
    }

    /// Durable order is history first, active marker last. If either step fails, the settlement
    /// remains in memory and the exact hardware retry runs this idempotent function again.
    private func persistPendingFocusSettlement() async -> Bool {
        guard let pending = pendingFocusSettlement else { return true }
        if !pending.historyAlreadyPersisted, !(await saveSessions()) { return false }
        if pending.clearPersistedActiveSession,
           !(await clearPersistedActiveSessionIfNeeded()) {
            return false
        }

        guard pendingFocusSettlement?.session.id == pending.session.id else { return false }
        guard let reward = await updateStoredEnergyBottles(for: pending.session) else {
            return false
        }
        pendingFocusSettlement = nil

        await AppState.shared.handleFocusSessionDidEnd(
            totalEnergyBottles: reward.total,
            newlyUnlocked: reward.newlyUnlocked,
            now: pending.endTime
        )
        return true
    }

    /// 累加能量瓶并诊断"这次累加是否跨过了未庆祝的解锁阈值"。
    private func updateStoredEnergyBottles(
        for session: FocusSession
    ) async -> (total: Int, newlyUnlocked: [String])? {
        guard persistenceEnabled else { return (0, []) }
        guard let receiptID = session.energyAwardReceiptID else {
            return (await localStorage.loadEnergyBottles(), [])
        }

        let after: Int
        do {
            after = try await focusPersistence.applyEnergyReward(
                receiptID: receiptID,
                bottles: session.earnedEnergyBottles
            )
        } catch {
            ErrorReporter.log(
                .persistence(
                    operation: "save",
                    target: "focus_energy_award_receipts.json",
                    underlying: error.localizedDescription
                ),
                context: "FocusSessionService.updateStoredEnergyBottles"
            )
            return nil
        }

        let alreadyCelebrated = await localStorage.loadLastCelebratedUnlockCount()
        let totalUnlockedNow = DisplayScene.unlockedScenes(for: after).count
        guard totalUnlockedNow > alreadyCelebrated else {
            return (after, [])
        }

        let newlyUnlocked = Array(
            DisplayScene.allCases
                .dropFirst(alreadyCelebrated)
                .prefix(totalUnlockedNow - alreadyCelebrated)
        ).map(\.rawValue)
        await localStorage.saveLastCelebratedUnlockCount(totalUnlockedNow)
        return (after, newlyUnlocked)
    }

    private func repairLoadedEnergyRewards() async -> Bool {
        let endedSessions = loadedFocusSessionHistory.values
            .filter { $0.endTime != nil && $0.energyAwardReceiptID != nil }
            .sorted { ($0.endTime ?? $0.startTime) < ($1.endTime ?? $1.startTime) }
        for session in endedSessions {
            guard await updateStoredEnergyBottles(for: session) != nil else { return false }
        }
        return true
    }
}
