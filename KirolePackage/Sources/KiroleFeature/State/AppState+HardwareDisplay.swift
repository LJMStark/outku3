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

        var usageState = (try? await localStorage.loadCompanionUsageState()) ?? CompanionUsageState()
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
            upcomingEventTitles: upcomingEventTitles
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
        let focusPhase: FocusPhase
        let focusBottles: Int

        if let session {
            elapsedMinutes = max(0, Int(now.timeIntervalSince(session.startTime) / 60))
            focusPhase = FocusPhase.from(elapsedMinutes: elapsedMinutes)
            focusBottles = FocusEnergyCalculator.bottlesEarned(minutes: elapsedMinutes)
        } else {
            elapsedMinutes = 0
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
                    taskTitle: session?.taskTitle
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
