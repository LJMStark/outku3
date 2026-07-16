import Foundation

extension AppState {
    public func tasksForToday() -> [TaskItem] {
        taskManager.tasksForToday(tasks: tasks)
    }

    public func completedTasksForToday() -> [TaskItem] {
        taskManager.completedTasksForToday(tasks: tasks)
    }

    func loadLocalData() async {
        do {
            if let savedPet = try await localStorage.loadPet() {
                pet = savedPet
            } else {
                pet = Pet(
                    name: "Baby Waffle",
                    pronouns: .theyThem,
                    adventuresCount: 0,
                    age: 0,
                    status: .happy,
                    mood: .happy,
                    scene: .indoor,
                    lastInteraction: Date(),
                    points: 0
                )
            }
        } catch {
            reportPersistenceError(error, operation: "load", target: "pet.json")
            await quarantineCorruptDataFile("pet.json")
        }

        do {
            if let savedTasks = try await localStorage.loadTasks() {
                tasks = savedTasks
            }
        } catch {
            reportPersistenceError(error, operation: "load", target: "tasks.json")
            await quarantineCorruptDataFile("tasks.json")
        }

        do {
            if let savedEvents = try await localStorage.loadEvents() {
                events = savedEvents
            }
        } catch {
            reportPersistenceError(error, operation: "load", target: "events.json")
            await quarantineCorruptDataFile("events.json")
        }

        do {
            if let savedProfile = try await localStorage.loadUserProfile() {
                userProfile = savedProfile
                if savedProfile.onboardingCompletedAt != nil {
                    UserDefaults.standard.set(true, forKey: "isOnboardingCompleted")
                }
            }
        } catch {
            reportPersistenceError(error, operation: "load", target: "user_profile.json")
        }

        do {
            if let savedOnboardingProfile = try await localStorage.loadOnboardingProfile() {
                onboardingProfile = savedOnboardingProfile
            }
        } catch {
            reportPersistenceError(error, operation: "load", target: "onboarding_profile.json")
        }

        // Restore the user's per-integration connection toggles over defaultIntegrations so a
        // disconnect survives relaunch (Apple Calendar/Reminders default to connected). A saved
        // switch also wins over an existing OAuth scope, so disabled providers stay disabled.
        do {
            if let savedConnections = try await localStorage.loadIntegrationConnections() {
                integrations = integrationCoordinator.applyConnectionStates(savedConnections, to: integrations)
                hasExplicitIntegrationConnectionPreferences = true
            }
        } catch {
            reportPersistenceError(error, operation: "load", target: "integration_connections.json")
        }

        do {
            let storedCompanions = try await localStorage.loadCustomCompanions()
            var retainedCompanions: [CustomCompanion] = []
            var purgedCompanionIDs: [UUID] = []

            for companion in storedCompanions {
                let imageData = await localStorage.loadCustomCompanionImageData(id: companion.id)
                guard Self.shouldPurgeStoredCustomCompanion(imageData: imageData) else {
                    retainedCompanions.append(companion)
                    continue
                }
                purgedCompanionIDs.append(companion.id)
                do {
                    try await localStorage.deleteCustomCompanionAssets(id: companion.id)
                } catch {
                    reportPersistenceError(error, operation: "delete", target: "custom_companion_assets")
                }
            }

            customCompanions = retainedCompanions
            if !purgedCompanionIDs.isEmpty {
                do {
                    try await localStorage.saveCustomCompanions(retainedCompanions)
                } catch {
                    reportPersistenceError(error, operation: "save", target: "custom_companions.json")
                }
                if let activeID = userProfile.customCompanionId,
                   purgedCompanionIDs.contains(activeID) {
                    userProfile.customCompanionId = nil
                    do {
                        try await localStorage.saveUserProfile(userProfile)
                    } catch {
                        reportPersistenceError(error, operation: "save", target: "user_profile.json")
                    }
                    await localStorage.clearPendingCustomCompanionPush()
                }
                ErrorReporter.log(
                    .sync(
                        component: "CustomCompanion Load",
                        underlying: "Purged \(purgedCompanionIDs.count) legacy non-PNG avatar asset(s); falling back to built-in identity when active"
                    ),
                    context: "AppState.loadLocalData"
                )
            }
        } catch {
            reportPersistenceError(error, operation: "load", target: "custom_companions.json")
        }

        do {
            integrationLastSyncedAt = try await localStorage.loadIntegrationSyncTimes()
        } catch {
            reportPersistenceError(error, operation: "load", target: "integration_sync_times.json")
        }

        isCustomAvatarPendingBLEPush = await localStorage.loadPendingCustomCompanionPush() != nil

        // focusEnforcementMode is loaded by FocusSessionService.loadFocusEnforcementMode() on its init.
        await ScreenTimeFocusGuardService.shared.refreshAuthorizationStatus()

        await updatePetState()
        updateStatistics()
    }

    /// v2.5.24 前的 4bpp 文件“存在但不是 PNG”时才清理；资产暂时缺失不在这里误删元数据。
    nonisolated static func shouldPurgeStoredCustomCompanion(imageData: Data?) -> Bool {
        guard let imageData else { return false }
        return !AvatarImageProcessor.isPNGData(imageData)
    }

    public func refreshData(userId: String?) async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        if let userId {
            switch await syncManager.performFullSync(userId: userId) {
            case .partial(_, let failed) where failed > 0:
                let error = AppError.sync(component: "Supabase", underlying: "Some data failed to sync")
                lastError = UserFacingErrorMapper.message(for: error)
                // lastError 在 Release 无人读取——云备份失败必须进横幅（key 渲染为 "Cloud sync failed"）。
                remoteSyncErrors["Cloud"] = UserFacingErrorMapper.message(for: error)
                ErrorReporter.log(error, context: "AppState.refreshData")
            case .failure(let error):
                let appError = AppError.sync(component: "Supabase", underlying: error.localizedDescription)
                lastError = UserFacingErrorMapper.message(for: appError)
                remoteSyncErrors["Cloud"] = UserFacingErrorMapper.message(for: appError)
                ErrorReporter.log(appError, context: "AppState.refreshData")
            default:
                remoteSyncErrors.removeValue(forKey: "Cloud")
            }
        }

        await loadLocalData()
    }

    func updatePetState() async {
        pet = await petManager.updatePetState(
            pet: pet,
            tasks: tasks,
            petStateService: petStateService
        )
        // 重算后的 mood/scene 必须落盘，否则强杀后磁盘上是 stale mood（UI 与硬件推送用内存值）。
        await persistPet(pet, context: "AppState.updatePetState")
    }

    func updateStatistics() {
        statistics = taskManager.statistics(tasks: tasks)
    }

    public func loadTodayHaiku(now: Date = Date()) async {
        let context = HaikuContext(
            currentTime: now,
            tasksCompletedToday: statistics.todayCompleted,
            totalTasksToday: statistics.todayTotal,
            petMood: pet.mood
        )
        currentHaiku = await haikuService.getTodayHaiku(context: context)
    }

    public func refreshWeather() async {
        #if os(iOS)
        weather = await weatherService.fetchWeather()
        // 天气已移出 DayPack 指纹，改由 BLESyncCoordinator 的 weatherChanged 放行轮次；
        // 这里请求一轮让变化尽快上硬件顶栏——天气没变时该轮会被节流拦下，无害。
        requestBLESync(reason: "weatherRefresh")
        #endif
    }

    func reportPersistenceError(_ error: Error, operation: String, target: String) {
        let appError = AppError.persistence(
            operation: operation,
            target: target,
            underlying: error.localizedDescription
        )
        ErrorReporter.log(appError, context: "AppState")
        lastError = UserFacingErrorMapper.message(for: appError)
    }

    /// 读取/解码失败后把损坏文件改名留底，避免随后的默认/残缺数据静默覆盖原始数据。
    /// 仅在解码/读取失败（抛错）时调用——文件不存在走 load() 返回 nil 的正常默认路径，不会到这里。
    func quarantineCorruptDataFile(_ filename: String) async {
        do {
            try await localStorage.quarantineCorruptFile(named: filename)
        } catch {
            reportPersistenceError(error, operation: "quarantine", target: filename)
        }
    }
}
