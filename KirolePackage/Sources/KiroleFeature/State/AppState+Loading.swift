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
                    stage: .baby,
                    progress: 0,
                    weight: 50,
                    height: 5.0,
                    tailLength: 2.0,
                    lastInteraction: Date(),
                    points: 0
                )
            }
        } catch {
            reportPersistenceError(error, operation: "load", target: "pet.json")
        }

        do {
            if let savedStreak = try await localStorage.loadStreak() {
                streak = savedStreak
            }
        } catch {
            reportPersistenceError(error, operation: "load", target: "streak.json")
        }

        do {
            if let savedTasks = try await localStorage.loadTasks() {
                tasks = savedTasks
            }
        } catch {
            reportPersistenceError(error, operation: "load", target: "tasks.json")
        }

        do {
            if let savedEvents = try await localStorage.loadEvents() {
                events = savedEvents
            }
        } catch {
            reportPersistenceError(error, operation: "load", target: "events.json")
        }

        do {
            if let savedProfile = try await localStorage.loadUserProfile() {
                userProfile = savedProfile
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

        focusEnforcementMode = await localStorage.loadFocusEnforcementMode() ?? .standard
        await ScreenTimeFocusGuardService.shared.refreshAuthorizationStatus()
        if focusEnforcementMode == .deepFocus && !ScreenTimeFocusGuardService.shared.canShowDeepFocusEntry {
            focusEnforcementMode = .standard
            await localStorage.saveFocusEnforcementMode(.standard)
        }

        await updatePetState()
        updateStatistics()
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
                ErrorReporter.log(error, context: "AppState.refreshData")
            case .failure(let error):
                let appError = AppError.sync(component: "Supabase", underlying: error.localizedDescription)
                lastError = UserFacingErrorMapper.message(for: appError)
                ErrorReporter.log(appError, context: "AppState.refreshData")
            default:
                break
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
    }

    func updateStatistics() {
        statistics = taskManager.statistics(tasks: tasks)
        widgetDataService.updateFromAppState(pet: pet, streak: streak, statistics: statistics)
    }

    public func loadTodayHaiku() async {
        let context = HaikuContext(
            currentTime: Date(),
            tasksCompletedToday: statistics.todayCompleted,
            totalTasksToday: statistics.todayTotal,
            petMood: pet.mood,
            currentStreak: streak.currentStreak
        )
        currentHaiku = await haikuService.getTodayHaiku(context: context)
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
}
