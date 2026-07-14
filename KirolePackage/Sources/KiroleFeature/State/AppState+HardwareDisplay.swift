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
            // 后台唤醒先补取挂起期间累积的打断，专注快照才不漏归零（息屏后台链路）。
            FocusSessionService.shared.refreshInterruptionsFromAppGroup()
            await syncFocusHardwareDisplay(session: FocusSessionService.shared.activeSession, now: now)
        }
    }

    /// 硬件在专注会话进行中周期性发 0x20（notify）唤醒被 iOS 挂起的 App，推送最新专注状态
    /// （息屏后台链路——挂起时进程内定时器停摆，唯一可靠的后台唤醒是外设 notify）。
    /// 只在有活跃会话时做事：抽取挂起期间的打断 → 现算并推 0x14。整轮 sync 与本方法解耦，
    /// 仍走 BLEEventHandler 里的 60s 合并闸。
    func handleFocusRefreshRequest(now: Date = Date()) async {
        guard let session = FocusSessionService.shared.activeSession else { return }
        FocusSessionService.shared.refreshInterruptionsFromAppGroup()
        await syncFocusHardwareDisplay(session: session, now: now)
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
        // 专注页、硬件帧和结束结算读同一个快照，调试倍率与手动快进因此不会只作用在界面上。
        // session == nil 时服务返回 idle 快照，保留原有的空闲状态推送。
        let progress = FocusSessionService.shared.progressSnapshot(for: session, now: now)
        let elapsedMinutes = progress.elapsedMinutes
        let segmentMinutes = progress.segmentMinutes
        let focusPhase = progress.phase
        let focusBottles = progress.earnedEnergyBottles

        // Real BLE push (all builds)
        // 短窗同内容去重，防前台化双观察者背靠背推同帧：见 AppState.lastFocusStatusDedupKey。
        let dedupKey = "\(focusPhase)|\(focusBottles)|\(elapsedMinutes)|\(segmentMinutes)|\(session?.taskTitle ?? "")"
        let isDuplicateWithinWindow = dedupKey == lastFocusStatusDedupKey
            && lastFocusStatusSentAt.map { now.timeIntervalSince($0) < 2.0 } == true
        if BLEService.shared.connectionState.isConnected, !isDuplicateWithinWindow {
            // 先占住去重窗再 await：设备唤醒、定时器、打断恢复可能并发进入，若成功后才写标记，
            // 同一帧会在首个 0x14 仍发送中时重复排队。失败时撤销占位，让下一次立即重试。
            lastFocusStatusDedupKey = dedupKey
            lastFocusStatusSentAt = now
            do {
                try await BLEService.shared.sendFocusStatus(
                    phase: focusPhase,
                    energyBottles: focusBottles,
                    elapsedMinutes: elapsedMinutes,
                    taskTitle: session?.taskTitle,
                    segmentMinutes: segmentMinutes
                )
            } catch {
                lastFocusStatusDedupKey = nil
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
        // 0x14(idle) 是"退出专注态"的状态信号，必须立即发（固件靠它离开态 C）。
        await syncFocusHardwareDisplay(session: nil, now: now)

        #if DEBUG
        if !SimulatorBridge.shared.isConnected {
            SimulatorBridge.shared.connect()
        }
        let unlocks = SceneUnlockService.shared.fetchAvailableScenes(energyBottles: totalEnergyBottles, now: now)
        SimulatorBridge.shared.sendSceneUnlocks(unlocks: unlocks)
        #endif

        // 场景帧(0x17)只在有新解锁时立即推（配合庆祝时刻）。无解锁时场景没变，重发只是多一次
        // 刷屏——此前无条件推，叠加任务完成路径 1.5s 后的 DayPack 全刷，硬件上"完成聚焦任务"
        // 连刷三次（0x14+0x17+DayPack）。内容更新由下方 requestBLESync 的 DayPack 轮承载
        // （2026-07-04 审计 B1）。
        if !newlyUnlocked.isEmpty {
            await syncIdleHardwareDisplay(totalEnergyBottles: totalEnergyBottles)
        }

        if let celebrated = newlyUnlocked.last {
            celebrateSceneUnlock(sceneId: celebrated, at: now)
        }

        // 会话结束改变结算数据（focusMinutes/sessionCount/longestFocus/interruptions，均在
        // DayPack wire+指纹），请求一轮同步让硬件结算面板跟上；任务完成路径上
        // toggleTaskCompletion 也会请求，debounce 合并为同一轮（2026-07-04 审计 F4 顺手修）。
        requestBLESync(reason: "focusSessionEnd")
    }

    /// 触发跨阈值庆祝：触觉 + 庆祝音效 + 通过 @Observable 信号唤醒 HomeView。
    /// 多通道并发，单一通道失败不影响其他（静音用户仍有触觉 + 视觉；Reduce Motion 跳过 confetti 但横幅仍展示）。
    private func celebrateSceneUnlock(sceneId: String, at now: Date) {
        SoundService.shared.playWithHaptic(.sceneMilestone, haptic: .success)
        pendingSceneCelebration = SceneCelebration(sceneId: sceneId, presentedAt: now)
    }
}
