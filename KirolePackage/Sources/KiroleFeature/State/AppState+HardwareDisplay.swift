import Foundation

extension AppState {
    func registerUsageActivity(now: Date = Date()) async {
        let savedConsecutiveDays = await localStorage.loadConsecutiveDays()
        let savedLastUsageDate = await localStorage.loadLastUsageDate()
        let currentCharacter = userProfile.companionCharacter

        var overallUsage = ConsecutiveUsageProgress(
            currentStreak: savedConsecutiveDays,
            lastUsedDate: savedLastUsageDate
        )
        let didAdvanceOverallUsage = overallUsage.registerUse(on: now)
        if didAdvanceOverallUsage {
            await localStorage.saveConsecutiveDays(overallUsage.currentStreak)
            await localStorage.saveLastUsageDate(overallUsage.lastUsedDate)
        }

        // 读失败（文件存在但读取/解码失败）必须早退：若拿零值状态继续，下面的 save 会把
        // streak=1 覆盖掉用户积累的天数，IntimacyStage 重算还会把亲密度降回 acquaintance。
        // 宁可丢一次活跃登记。文件不存在（首次使用）返回 nil，正常走新建分支。
        var usageState: CompanionUsageState
        do {
            usageState = try await localStorage.loadCompanionUsageState() ?? CompanionUsageState()
        } catch {
            reportPersistenceError(error, operation: "read", target: "companion_usage_state.json")
            return
        }
        var characterUsage = usageState.progress(for: currentCharacter)
        let didAdvanceCharacterUsage = characterUsage.registerUse(on: now)
        if didAdvanceCharacterUsage {
            usageState.setProgress(characterUsage, for: currentCharacter)
            do {
                try await localStorage.saveCompanionUsageState(usageState)
            } catch {
                reportPersistenceError(error, operation: "save", target: "companion_usage_state.json")
            }
        }

        // Binding-day driven intimacy escalation is a 3-IP-only mechanic: there is no
        // designed progression model for custom companions yet, and `userProfile.companionCharacter`
        // still points at the user's last built-in pick (so we can snap back on switch).
        // Without this guard, switching to a custom companion and backgrounding the app would
        // immediately re-apply the prior built-in's closeFriend stage and overwrite the
        // acquaintance reset that selectCustomCompanion just performed.
        guard userProfile.customCompanionId == nil else { return }

        let updatedStage = IntimacyStage.from(bindingDays: characterUsage.totalUsedDays)
        if userProfile.intimacyStage != updatedStage {
            var updatedProfile = userProfile
            updatedProfile.intimacyStage = updatedStage
            userProfile = updatedProfile
            do {
                try await localStorage.saveUserProfile(updatedProfile)
            } catch {
                reportPersistenceError(error, operation: "save", target: "user_profile.json")
            }
        }
    }

    func currentDisplaySceneId(totalEnergyBottles: Int? = nil) async -> String {
        // User's explicit pick from Settings → Scenes wins. nil → harbor (always-unlocked default).
        // Energy bottles only gate which scenes the Settings UI unlocks for selection — bottles
        // never auto-apply a scene to hardware. The `totalEnergyBottles` parameter is retained
        // for call-site compatibility but is intentionally unused.
        _ = totalEnergyBottles
        guard let stored = userProfile.selectedSceneId else {
            return DisplayScene.harbor.rawValue
        }
        if DisplayScene(rawValue: stored) != nil {
            return stored
        }
        // Stored value doesn't match any known DisplayScene (stale data / version mismatch).
        // Fall back to harbor so the hardware always gets a valid scene, log so this surfaces.
        ErrorReporter.log(
            .sync(component: "DisplayScene", underlying: "unknown selectedSceneId '\(stored)', falling back to harbor"),
            context: "AppState.currentDisplaySceneId"
        )
        return DisplayScene.harbor.rawValue
    }

    func handleAppDidBecomeActive(now: Date = Date()) async {
        await registerUsageActivity(now: now)
        // Re-fetch weather so users who granted location after first launch,
        // or recovered network after a failed cold-start fetch, see the chip
        // without having to fully relaunch. WeatherService's 15-minute cache
        // prevents frequent re-hits to WeatherKit when toggling foreground.
        await refreshWeather()
        if FocusSessionService.shared.activeSession == nil {
            await syncIdleHardwareDisplay()
        } else {
            await syncFocusHardwareDisplay(session: FocusSessionService.shared.activeSession, now: now)
        }
    }

    func handleHardwareWake(now: Date = Date()) async {
        await registerUsageActivity(now: now)
        if FocusSessionService.shared.activeSession == nil {
            await syncIdleHardwareDisplay()
        } else {
            await syncFocusHardwareDisplay(session: FocusSessionService.shared.activeSession, now: now)
        }
    }

    func handleHardwareSleep(now: Date = Date()) async {
        let usageDays = await localStorage.loadConsecutiveDays()
        let sceneId = await currentDisplaySceneId()
        let topTaskTitles = tasksForToday()
            .filter { !$0.isCompleted }
            .prefix(3)
            .map(\.title)
        let upcomingEventTitles = events
            .filter { $0.startTime >= now }
            .sorted { $0.startTime < $1.startTime }
            .prefix(2)
            .map(\.title)
        let config = await ScreensaverService.shared.getScreensaverConfig(
            usageDays: usageDays,
            currentSceneId: sceneId,
            userProfile: userProfile,
            topTaskTitles: topTaskTitles,
            upcomingEventTitles: upcomingEventTitles,
            customCompanion: activeCustomCompanion
        )

        if BLEService.shared.connectionState.isConnected {
            do {
                try await BLEService.shared.sendScreensaverConfig(config)
            } catch {
                ErrorReporter.log(
                    .sync(component: "BLE ScreensaverConfig", underlying: error.localizedDescription),
                    context: "AppState.handleHardwareSleep"
                )
            }
        }

        #if DEBUG
        if !SimulatorBridge.shared.isConnected {
            SimulatorBridge.shared.connect()
        }
        SimulatorBridge.shared.sendScreensaver(config: config)
        #endif
    }

    func syncFocusHardwareDisplay(session: FocusSession?, now: Date = Date()) async {
        let elapsedMinutes: Int
        let segmentMinutes: Int
        let focusPhase: FocusPhase
        let focusBottles: Int

        if let session {
            // Two distinct counters per the focus-status protocol (v2.5.5):
            // - `elapsedMinutes` (ElapsedTime): total wall-clock minutes since the session began,
            //   a monotonic "focused N minutes" counter that does NOT reset on interruption.
            // - `segmentMinutes` (SegmentMinutes): minutes into the CURRENT uninterrupted segment,
            //   which resets to zero after each interruption and drives the on-device fill bar.
            // `focusBottles`/`focusPhase` follow the segment so the banked count matches what
            // endSession settles and the visual stage resets together with the fill.
            let unlockEvents = FocusSessionService.shared.currentUnlockEvents(until: now)
            let segmentStart = FocusTimeCalculator.currentSegmentStart(
                sessionStart: session.startTime,
                now: now,
                screenUnlockEvents: unlockEvents
            )
            elapsedMinutes = max(0, Int(now.timeIntervalSince(session.startTime) / 60))
            segmentMinutes = max(0, Int(now.timeIntervalSince(segmentStart) / 60))
            focusPhase = FocusPhase.from(elapsedMinutes: segmentMinutes)
            focusBottles = FocusTimeCalculator.countableBottles(
                sessionStart: session.startTime,
                sessionEnd: now,
                screenUnlockEvents: unlockEvents
            )
        } else {
            elapsedMinutes = 0
            segmentMinutes = 0
            focusPhase = .idle
            focusBottles = 0
        }

        // Real BLE push (all builds)
        if BLEService.shared.connectionState.isConnected {
            do {
                try await BLEService.shared.sendFocusStatus(
                    phase: focusPhase,
                    energyBottles: focusBottles,
                    elapsedMinutes: elapsedMinutes,
                    taskTitle: session?.taskTitle,
                    segmentMinutes: segmentMinutes
                )
            } catch {
                ErrorReporter.log(
                    .sync(component: "BLE FocusStatus", underlying: error.localizedDescription),
                    context: "AppState.syncFocusHardwareDisplay"
                )
            }
        }

        #if DEBUG
        if !SimulatorBridge.shared.isConnected {
            SimulatorBridge.shared.connect()
        }
        SimulatorBridge.shared.sendFocusState(
            session: session,
            energyBottles: focusBottles,
            focusPhase: focusPhase,
            elapsedMinutes: elapsedMinutes,
            taskTitle: session?.taskTitle
        )
        #endif
    }

    func syncIdleHardwareDisplay(totalEnergyBottles: Int? = nil) async {
        let sceneId = await currentDisplaySceneId(totalEnergyBottles: totalEnergyBottles)
        if BLEService.shared.connectionState.isConnected,
           let displayScene = DisplayScene(rawValue: sceneId) {
            do {
                try await BLEService.shared.sendDisplayScene(displayScene)
            } catch {
                ErrorReporter.log(
                    .sync(component: "BLE DisplayScene", underlying: error.localizedDescription),
                    context: "AppState.syncIdleHardwareDisplay"
                )
            }
        }

        #if DEBUG
        if !SimulatorBridge.shared.isConnected {
            SimulatorBridge.shared.connect()
        }
        SimulatorBridge.shared.sendPetStatus(
            petName: userProfile.companionCharacter.displayName,
            petMood: pet.mood.rawValue,
            sceneId: sceneId,
            characterId: userProfile.companionCharacter.rawValue
        )
        #endif
    }

    func handleFocusSessionDidEnd(
        totalEnergyBottles: Int,
        newlyUnlocked: [String] = [],
        now: Date = Date()
    ) async {
        await syncFocusHardwareDisplay(session: nil, now: now)

        #if DEBUG
        if !SimulatorBridge.shared.isConnected {
            SimulatorBridge.shared.connect()
        }
        let unlocks = SceneUnlockService.shared.fetchAvailableScenes(energyBottles: totalEnergyBottles, now: now)
        SimulatorBridge.shared.sendSceneUnlocks(unlocks: unlocks)
        #endif

        await syncIdleHardwareDisplay(totalEnergyBottles: totalEnergyBottles)

        if let celebrated = newlyUnlocked.last {
            celebrateSceneUnlock(sceneId: celebrated, at: now)
        }
    }

    /// 触发跨阈值庆祝：触觉 + 庆祝音效 + 通过 @Observable 信号唤醒 HomeView。
    /// 多通道并发，单一通道失败不影响其他（静音用户仍有触觉 + 视觉；Reduce Motion 跳过 confetti 但横幅仍展示）。
    private func celebrateSceneUnlock(sceneId: String, at now: Date) {
        SoundService.shared.playWithHaptic(.sceneMilestone, haptic: .success)
        pendingSceneCelebration = SceneCelebration(sceneId: sceneId, presentedAt: now)
    }
}
