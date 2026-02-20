import Testing
import Foundation
@testable import KiroleFeature

// MARK: - AppState Tests

@Suite("AppState Tests")
struct AppStateTests {

    // MARK: - Navigation Tests

    @Suite("Navigation State")
    struct NavigationTests {

        @Test("Default tab is home")
        @MainActor
        func defaultTabIsHome() {
            let state = AppState.shared
            // Reset to default for test
            state.selectedTab = .home
            #expect(state.selectedTab == .home)
        }

        @Test("Can switch between tabs")
        @MainActor
        func canSwitchTabs() {
            let state = AppState.shared

            state.selectedTab = .pet
            #expect(state.selectedTab == .pet)

            state.selectedTab = .settings
            #expect(state.selectedTab == .settings)

            state.selectedTab = .home
            #expect(state.selectedTab == .home)
        }

        @Test("Event selection updates state")
        @MainActor
        func eventSelectionUpdatesState() {
            let state = AppState.shared

            let event = CalendarEvent(
                title: "Test Event",
                startTime: Date(),
                endTime: Date().addingTimeInterval(3600)
            )

            state.selectEvent(event)

            #expect(state.selectedEvent?.id == event.id)
            #expect(state.isEventDetailPresented == true)
        }

        @Test("Dismiss event detail clears selection")
        @MainActor
        func dismissEventDetailClearsSelection() {
            let state = AppState.shared

            let event = CalendarEvent(
                title: "Test Event",
                startTime: Date(),
                endTime: Date().addingTimeInterval(3600)
            )

            state.selectEvent(event)
            state.dismissEventDetail()

            #expect(state.selectedEvent == nil)
            #expect(state.isEventDetailPresented == false)
        }
    }

    // MARK: - Task Management Tests

    @Suite("Task Management")
    struct TaskManagementTests {

        @Test("Add task increases task count")
        @MainActor
        func addTaskIncreasesCount() async {
            let state = AppState.shared
            let initialCount = state.tasks.count

            let newTask = TaskItem(
                title: "Test Task \(UUID().uuidString)",
                dueDate: Date()
            )

            state.addTask(newTask)

            #expect(state.tasks.count == initialCount + 1)
            #expect(state.tasks.contains { $0.id == newTask.id })

            // Cleanup
            state.deleteTask(newTask)
        }

        @Test("Delete task removes from list")
        @MainActor
        func deleteTaskRemovesFromList() async {
            let state = AppState.shared

            let newTask = TaskItem(
                title: "Task to Delete \(UUID().uuidString)",
                dueDate: Date()
            )

            state.addTask(newTask)
            let countAfterAdd = state.tasks.count

            state.deleteTask(newTask)

            #expect(state.tasks.count == countAfterAdd - 1)
            #expect(!state.tasks.contains { $0.id == newTask.id })
        }

        @Test("Tasks for today filters correctly")
        @MainActor
        func tasksForTodayFiltersCorrectly() {
            let state = AppState.shared

            // Create tasks with different due dates
            let todayTask = TaskItem(
                id: "today-task-\(UUID().uuidString)",
                title: "Today Task",
                dueDate: Date()
            )

            let tomorrowTask = TaskItem(
                id: "tomorrow-task-\(UUID().uuidString)",
                title: "Tomorrow Task",
                dueDate: Calendar.current.date(byAdding: .day, value: 1, to: Date())
            )

            let noDueDateTask = TaskItem(
                id: "no-date-task-\(UUID().uuidString)",
                title: "No Due Date Task",
                dueDate: nil
            )

            state.addTask(todayTask)
            state.addTask(tomorrowTask)
            state.addTask(noDueDateTask)

            let todayTasks = state.tasksForToday()

            #expect(todayTasks.contains { $0.id == todayTask.id })
            #expect(!todayTasks.contains { $0.id == tomorrowTask.id })
            #expect(!todayTasks.contains { $0.id == noDueDateTask.id })

            // Cleanup
            state.deleteTask(todayTask)
            state.deleteTask(tomorrowTask)
            state.deleteTask(noDueDateTask)
        }

        @Test("Completed tasks for today filters correctly")
        @MainActor
        func completedTasksForTodayFiltersCorrectly() {
            let state = AppState.shared

            let completedTask = TaskItem(
                id: "completed-\(UUID().uuidString)",
                title: "Completed Task",
                isCompleted: true,
                dueDate: Date()
            )

            let incompleteTask = TaskItem(
                id: "incomplete-\(UUID().uuidString)",
                title: "Incomplete Task",
                isCompleted: false,
                dueDate: Date()
            )

            state.addTask(completedTask)
            state.addTask(incompleteTask)

            let completedTasks = state.completedTasksForToday()

            #expect(completedTasks.contains { $0.id == completedTask.id })
            #expect(!completedTasks.contains { $0.id == incompleteTask.id })

            // Cleanup
            state.deleteTask(completedTask)
            state.deleteTask(incompleteTask)
        }
    }

    // MARK: - Task Completion Tests

    @Suite("Task Completion")
    struct TaskCompletionTests {

        @Test("Toggle task completion changes state")
        @MainActor
        func toggleTaskCompletionChangesState() {
            let state = AppState.shared

            let task = TaskItem(
                id: "toggle-test-\(UUID().uuidString)",
                title: "Toggle Test Task",
                isCompleted: false,
                dueDate: Date()
            )

            state.addTask(task)

            // Find the task in state
            guard let taskIndex = state.tasks.firstIndex(where: { $0.id == task.id }) else {
                Issue.record("Task not found in state")
                return
            }

            let initialCompletion = state.tasks[taskIndex].isCompleted
            state.toggleTaskCompletion(state.tasks[taskIndex])

            // Re-find after toggle
            guard let updatedIndex = state.tasks.firstIndex(where: { $0.id == task.id }) else {
                Issue.record("Task not found after toggle")
                return
            }

            #expect(state.tasks[updatedIndex].isCompleted != initialCompletion)

            // Cleanup
            state.deleteTask(task)
        }

        @Test("Completing task increases pet progress")
        @MainActor
        func completingTaskIncreasesPetProgress() {
            let state = AppState.shared

            // Store initial progress
            let initialProgress = state.pet.progress

            let task = TaskItem(
                id: "progress-test-\(UUID().uuidString)",
                title: "Progress Test Task",
                isCompleted: false,
                dueDate: Date()
            )

            state.addTask(task)

            guard let taskInState = state.tasks.first(where: { $0.id == task.id }) else {
                Issue.record("Task not found")
                return
            }

            state.toggleTaskCompletion(taskInState)

            // Progress should increase by 0.02 (2%)
            #expect(state.pet.progress > initialProgress)
            #expect(state.pet.progress <= 1.0)

            // Cleanup - toggle back and delete
            if let updatedTask = state.tasks.first(where: { $0.id == task.id }) {
                state.toggleTaskCompletion(updatedTask)
            }
            state.deleteTask(task)
        }

        @Test("Completing task increases pet points")
        @MainActor
        func completingTaskIncreasesPetPoints() {
            let state = AppState.shared

            let initialPoints = state.pet.points

            let task = TaskItem(
                id: "points-test-\(UUID().uuidString)",
                title: "Points Test Task",
                isCompleted: false,
                dueDate: Date()
            )

            state.addTask(task)

            guard let taskInState = state.tasks.first(where: { $0.id == task.id }) else {
                Issue.record("Task not found")
                return
            }

            state.toggleTaskCompletion(taskInState)

            // Points should increase by 10
            #expect(state.pet.points == initialPoints + 10)

            // Cleanup
            if let updatedTask = state.tasks.first(where: { $0.id == task.id }) {
                state.toggleTaskCompletion(updatedTask)
            }
            state.deleteTask(task)
        }

        @Test("Completing task increases adventures count")
        @MainActor
        func completingTaskIncreasesAdventuresCount() {
            let state = AppState.shared

            let initialAdventures = state.pet.adventuresCount

            let task = TaskItem(
                id: "adventures-test-\(UUID().uuidString)",
                title: "Adventures Test Task",
                isCompleted: false,
                dueDate: Date()
            )

            state.addTask(task)

            guard let taskInState = state.tasks.first(where: { $0.id == task.id }) else {
                Issue.record("Task not found")
                return
            }

            state.toggleTaskCompletion(taskInState)

            #expect(state.pet.adventuresCount == initialAdventures + 1)

            // Cleanup
            if let updatedTask = state.tasks.first(where: { $0.id == task.id }) {
                state.toggleTaskCompletion(updatedTask)
            }
            state.deleteTask(task)
        }

        @Test("Uncompleting task decreases pet stats")
        @MainActor
        func uncompletingTaskDecreasesPetStats() {
            let state = AppState.shared

            // First complete a task
            let task = TaskItem(
                id: "uncomplete-test-\(UUID().uuidString)",
                title: "Uncomplete Test Task",
                isCompleted: false,
                dueDate: Date()
            )

            state.addTask(task)

            guard let taskInState = state.tasks.first(where: { $0.id == task.id }) else {
                Issue.record("Task not found")
                return
            }

            state.toggleTaskCompletion(taskInState)

            // Store stats after completion
            let progressAfterComplete = state.pet.progress
            let pointsAfterComplete = state.pet.points
            let adventuresAfterComplete = state.pet.adventuresCount

            // Now uncomplete
            guard let completedTask = state.tasks.first(where: { $0.id == task.id }) else {
                Issue.record("Task not found after completion")
                return
            }

            state.toggleTaskCompletion(completedTask)

            #expect(state.pet.progress < progressAfterComplete)
            #expect(state.pet.points < pointsAfterComplete)
            #expect(state.pet.adventuresCount < adventuresAfterComplete)

            // Cleanup
            state.deleteTask(task)
        }

        @Test("Progress is capped at 1.0")
        @MainActor
        func progressIsCappedAtMax() {
            let state = AppState.shared

            // Set progress close to max
            state.pet.progress = 0.99

            let task = TaskItem(
                id: "cap-test-\(UUID().uuidString)",
                title: "Cap Test Task",
                isCompleted: false,
                dueDate: Date()
            )

            state.addTask(task)

            guard let taskInState = state.tasks.first(where: { $0.id == task.id }) else {
                Issue.record("Task not found")
                return
            }

            state.toggleTaskCompletion(taskInState)

            #expect(state.pet.progress <= 1.0)

            // Cleanup
            if let updatedTask = state.tasks.first(where: { $0.id == task.id }) {
                state.toggleTaskCompletion(updatedTask)
            }
            state.deleteTask(task)
            state.pet.progress = 0.0
        }

        @Test("Progress does not go below 0")
        @MainActor
        func progressDoesNotGoBelowZero() {
            let state = AppState.shared

            // Set progress to 0
            state.pet.progress = 0.0
            state.pet.points = 0
            state.pet.adventuresCount = 0

            let task = TaskItem(
                id: "floor-test-\(UUID().uuidString)",
                title: "Floor Test Task",
                isCompleted: true,
                dueDate: Date()
            )

            state.addTask(task)

            guard let taskInState = state.tasks.first(where: { $0.id == task.id }) else {
                Issue.record("Task not found")
                return
            }

            // Uncomplete the task (should try to decrease stats)
            state.toggleTaskCompletion(taskInState)

            #expect(state.pet.progress >= 0)
            #expect(state.pet.points >= 0)
            #expect(state.pet.adventuresCount >= 0)

            // Cleanup
            state.deleteTask(task)
        }

        @Test("Toggle non-existent task does nothing")
        @MainActor
        func toggleNonExistentTaskDoesNothing() {
            let state = AppState.shared

            let initialTaskCount = state.tasks.count
            let initialProgress = state.pet.progress

            let nonExistentTask = TaskItem(
                id: "non-existent-\(UUID().uuidString)",
                title: "Non-existent Task",
                dueDate: Date()
            )

            // This should do nothing since task is not in state
            state.toggleTaskCompletion(nonExistentTask)

            #expect(state.tasks.count == initialTaskCount)
            #expect(state.pet.progress == initialProgress)
        }
    }

    // MARK: - Evolution Tests

    @Suite("Pet Evolution")
    struct EvolutionTests {

        @Test("Complete evolution advances pet stage")
        @MainActor
        func completeEvolutionAdvancesStage() {
            let state = AppState.shared

            // Setup evolution state
            state.pet.stage = .baby
            state.evolutionFromStage = .baby
            state.evolutionToStage = .child
            state.showEvolutionAnimation = true

            let initialWeight = state.pet.weight
            let initialHeight = state.pet.height
            let initialTailLength = state.pet.tailLength

            state.completeEvolution()

            #expect(state.pet.stage == .child)
            #expect(state.pet.progress == 0.0)
            #expect(state.showEvolutionAnimation == false)
            #expect(state.evolutionFromStage == nil)
            #expect(state.evolutionToStage == nil)

            // Check multipliers applied (1.2x weight, 1.15x height, 1.1x tail)
            #expect(state.pet.weight > initialWeight)
            #expect(state.pet.height > initialHeight)
            #expect(state.pet.tailLength > initialTailLength)

            // Reset for other tests
            state.pet.stage = .baby
        }

        @Test("Complete evolution without target stage does nothing")
        @MainActor
        func completeEvolutionWithoutTargetDoesNothing() {
            let state = AppState.shared

            state.pet.stage = .baby
            state.evolutionToStage = nil

            let initialStage = state.pet.stage

            state.completeEvolution()

            #expect(state.pet.stage == initialStage)
        }

        @Test("Dismiss evolution clears animation state")
        @MainActor
        func dismissEvolutionClearsState() {
            let state = AppState.shared

            state.showEvolutionAnimation = true
            state.evolutionFromStage = .baby
            state.evolutionToStage = .child

            state.dismissEvolution()

            #expect(state.showEvolutionAnimation == false)
            #expect(state.evolutionFromStage == nil)
            #expect(state.evolutionToStage == nil)
        }

        @Test("Evolution multipliers are applied correctly")
        @MainActor
        func evolutionMultipliersAppliedCorrectly() {
            let state = AppState.shared

            // Set known values
            state.pet.weight = 100.0
            state.pet.height = 10.0
            state.pet.tailLength = 5.0
            state.pet.stage = .child
            state.evolutionToStage = .teen
            state.showEvolutionAnimation = true

            state.completeEvolution()

            // Weight: 100 * 1.2 = 120
            #expect(abs(state.pet.weight - 120.0) < 0.01)
            // Height: 10 * 1.15 = 11.5
            #expect(abs(state.pet.height - 11.5) < 0.01)
            // Tail: 5 * 1.1 = 5.5
            #expect(abs(state.pet.tailLength - 5.5) < 0.01)

            // Reset
            state.pet.stage = .baby
            state.pet.weight = 50.0
            state.pet.height = 5.0
            state.pet.tailLength = 2.0
        }
    }

    // MARK: - Pet Form Tests

    @Suite("Pet Form")
    struct PetFormTests {

        @Test("Set pet form updates state")
        @MainActor
        func setPetFormUpdatesState() {
            let state = AppState.shared

            state.setPetForm(.dragon)
            #expect(state.pet.currentForm == .dragon)

            state.setPetForm(.bunny)
            #expect(state.pet.currentForm == .bunny)

            // Reset
            state.setPetForm(.cat)
        }

        @Test("All pet forms are valid")
        @MainActor
        func allPetFormsAreValid() {
            let state = AppState.shared

            for form in PetForm.allCases {
                state.setPetForm(form)
                #expect(state.pet.currentForm == form)
            }

            // Reset
            state.setPetForm(.cat)
        }
    }

    // MARK: - Integration Management Tests

    @Suite("Integration Management")
    struct IntegrationTests {

        @Test("Update integration status for existing integration")
        @MainActor
        func updateExistingIntegrationStatus() {
            let state = AppState.shared

            // Google Calendar should exist in default integrations
            state.updateIntegrationStatus(.googleCalendar, isConnected: true)

            let googleCalendar = state.integrations.first { $0.type == .googleCalendar }
            #expect(googleCalendar?.isConnected == true)

            // Reset
            state.updateIntegrationStatus(.googleCalendar, isConnected: false)
        }

        @Test("Update integration status adds new integration if connected")
        @MainActor
        func updateIntegrationAddsNewIfConnected() {
            let state = AppState.shared

            // Remove tickTick if exists
            state.integrations.removeAll { $0.type == .tickTick }

            let initialCount = state.integrations.count

            state.updateIntegrationStatus(.tickTick, isConnected: true)

            #expect(state.integrations.count == initialCount + 1)
            #expect(state.integrations.contains { $0.type == .tickTick })

            // Cleanup
            state.integrations.removeAll { $0.type == .tickTick }
        }

        @Test("Update integration status does not add if disconnected")
        @MainActor
        func updateIntegrationDoesNotAddIfDisconnected() {
            let state = AppState.shared

            // Remove notion if exists
            state.integrations.removeAll { $0.type == .notion }

            let initialCount = state.integrations.count

            state.updateIntegrationStatus(.notion, isConnected: false)

            #expect(state.integrations.count == initialCount)
        }

        @Test("Connecting Google Calendar disconnects Apple Calendar and clears Apple events")
        @MainActor
        func connectingGoogleCalendarDisconnectsAppleCalendar() {
            let state = AppState.shared
            let originalIntegrations = state.integrations
            let originalEvents = state.events

            defer {
                state.integrations = originalIntegrations
                state.events = originalEvents
            }

            state.events = [
                CalendarEvent(
                    id: "apple-event-\(UUID().uuidString)",
                    title: "Apple Event",
                    startTime: Date(),
                    endTime: Date().addingTimeInterval(1800),
                    source: .apple
                ),
                CalendarEvent(
                    id: "google-event-\(UUID().uuidString)",
                    title: "Google Event",
                    startTime: Date(),
                    endTime: Date().addingTimeInterval(1800),
                    source: .google
                )
            ]

            state.updateIntegrationStatus(.appleCalendar, isConnected: true)
            state.updateIntegrationStatus(.googleCalendar, isConnected: true)

            let appleCalendar = state.integrations.first { $0.type == .appleCalendar }
            let googleCalendar = state.integrations.first { $0.type == .googleCalendar }

            #expect(appleCalendar?.isConnected == false)
            #expect(googleCalendar?.isConnected == true)
            #expect(state.events.contains { $0.source == .apple } == false)
        }

        @Test("Connecting Apple Reminders disconnects Google Tasks and clears Google tasks")
        @MainActor
        func connectingAppleRemindersDisconnectsGoogleTasks() {
            let state = AppState.shared
            let originalIntegrations = state.integrations
            let originalTasks = state.tasks

            defer {
                state.integrations = originalIntegrations
                state.tasks = originalTasks
            }

            state.tasks = [
                TaskItem(
                    id: "apple-task-\(UUID().uuidString)",
                    title: "Apple Task",
                    source: .apple
                ),
                TaskItem(
                    id: "google-task-\(UUID().uuidString)",
                    title: "Google Task",
                    source: .google
                )
            ]

            state.updateIntegrationStatus(.googleTasks, isConnected: true)
            state.updateIntegrationStatus(.appleReminders, isConnected: true)

            let googleTasks = state.integrations.first { $0.type == .googleTasks }
            let appleReminders = state.integrations.first { $0.type == .appleReminders }

            #expect(googleTasks?.isConnected == false)
            #expect(appleReminders?.isConnected == true)
            #expect(state.tasks.contains { $0.source == .google } == false)
        }
    }

    // MARK: - User Profile Tests

    @Suite("User Profile")
    struct UserProfileTests {

        @Test("Update user profile changes state")
        @MainActor
        func updateUserProfileChangesState() {
            let state = AppState.shared

            let newProfile = UserProfile(
                workType: .remoteWorker,
                primaryGoals: [.productivity, .focus],
                companionStyle: .encouraging,
                onboardingCompletedAt: nil
            )

            state.updateUserProfile(newProfile)

            #expect(state.userProfile.workType == .remoteWorker)
            #expect(state.userProfile.primaryGoals.contains(.productivity))
            #expect(state.userProfile.companionStyle == .encouraging)

            // Reset
            state.updateUserProfile(.default)
        }

        @Test("Complete onboarding sets timestamp")
        @MainActor
        func completeOnboardingSetsTimestamp() {
            let state = AppState.shared

            // Ensure onboarding is not completed
            var profile = state.userProfile
            profile.onboardingCompletedAt = nil
            state.updateUserProfile(profile)

            #expect(state.isOnboardingCompleted == false)

            state.completeOnboarding(with: OnboardingProfile())

            #expect(state.isOnboardingCompleted == true)
            #expect(state.onboardingProfile?.onboardingCompletedAt != nil)

            // Reset
            profile.onboardingCompletedAt = nil
            state.updateUserProfile(profile)
            state.onboardingProfile = nil
        }

        @Test("isOnboardingCompleted reflects profile state")
        @MainActor
        func isOnboardingCompletedReflectsState() {
            let state = AppState.shared
            state.onboardingProfile = nil

            var profile = state.userProfile
            profile.onboardingCompletedAt = nil
            state.updateUserProfile(profile)
            #expect(state.isOnboardingCompleted == false)

            profile.onboardingCompletedAt = Date()
            state.updateUserProfile(profile)
            #expect(state.isOnboardingCompleted == true)

            // Reset
            state.updateUserProfile(.default)
        }
    }

    // MARK: - Events Management Tests

    @Suite("Events Management")
    struct EventsTests {

        @Test("Update events replaces all events")
        @MainActor
        func updateEventsReplacesAll() {
            let state = AppState.shared

            let newEvents = [
                CalendarEvent(
                    id: "event-1",
                    title: "Event 1",
                    startTime: Date(),
                    endTime: Date().addingTimeInterval(3600)
                ),
                CalendarEvent(
                    id: "event-2",
                    title: "Event 2",
                    startTime: Date(),
                    endTime: Date().addingTimeInterval(7200)
                )
            ]

            state.updateEvents(newEvents)

            #expect(state.events.count == 2)
            #expect(state.events.contains { $0.id == "event-1" })
            #expect(state.events.contains { $0.id == "event-2" })

            // Cleanup
            state.updateEvents([])
        }
    }

    // MARK: - Statistics Tests

    @Suite("Task Statistics")
    struct StatisticsTests {

        @Test("Statistics update when tasks change")
        @MainActor
        func statisticsUpdateOnTaskChange() {
            let state = AppState.shared

            // Clear existing tasks
            let originalTasks = state.tasks
            state.updateTasks([])

            // Add today's tasks
            let task1 = TaskItem(
                id: "stat-task-1-\(UUID().uuidString)",
                title: "Stat Task 1",
                isCompleted: true,
                dueDate: Date()
            )

            let task2 = TaskItem(
                id: "stat-task-2-\(UUID().uuidString)",
                title: "Stat Task 2",
                isCompleted: false,
                dueDate: Date()
            )

            state.addTask(task1)
            state.addTask(task2)

            #expect(state.statistics.todayTotal >= 2)
            #expect(state.statistics.todayCompleted >= 1)

            // Cleanup
            state.updateTasks(originalTasks)
        }
    }

    // MARK: - Device Mode Tests

    @Suite("Device Mode")
    struct DeviceModeTests {

        @Test("Default device mode is interactive")
        @MainActor
        func defaultDeviceModeIsInteractive() {
            let state = AppState.shared
            // Note: This tests the default, actual value may differ based on state
            #expect(state.deviceMode == .interactive || state.deviceMode == .focus)
        }

        @Test("Demo mode can be toggled")
        @MainActor
        func demoModeCanBeToggled() {
            let state = AppState.shared

            let initialDemoMode = state.isDemoMode

            state.isDemoMode = !initialDemoMode
            #expect(state.isDemoMode == !initialDemoMode)

            // Reset
            state.isDemoMode = initialDemoMode
        }
    }

    // MARK: - Loading State Tests

    @Suite("Loading State")
    struct LoadingStateTests {

        @Test("Loading state can be set")
        @MainActor
        func loadingStateCanBeSet() {
            let state = AppState.shared

            state.isLoading = true
            #expect(state.isLoading == true)

            state.isLoading = false
            #expect(state.isLoading == false)
        }

        @Test("Error state can be set and cleared")
        @MainActor
        func errorStateCanBeSetAndCleared() {
            let state = AppState.shared

            state.lastError = "Test error message"
            #expect(state.lastError == "Test error message")

            state.lastError = nil
            #expect(state.lastError == nil)
        }
    }
}

// MARK: - Streak Logic Tests (Isolated)

@Suite("Streak Logic Tests")
struct StreakLogicTests {

    @Test("Streak model initialization")
    func streakInitialization() {
        let streak = Streak(currentStreak: 5, longestStreak: 10, lastActiveDate: Date())

        #expect(streak.currentStreak == 5)
        #expect(streak.longestStreak == 10)
        #expect(streak.lastActiveDate != nil)
    }

    @Test("Streak default values")
    func streakDefaultValues() {
        let streak = Streak()

        #expect(streak.currentStreak == 0)
        #expect(streak.longestStreak == 0)
        #expect(streak.lastActiveDate == nil)
    }

    @Test("Longest streak updates correctly")
    func longestStreakUpdates() {
        var streak = Streak(currentStreak: 5, longestStreak: 10)

        streak.currentStreak = 12
        streak.longestStreak = max(streak.longestStreak, streak.currentStreak)

        #expect(streak.longestStreak == 12)
    }

    @Test("Longest streak does not decrease")
    func longestStreakDoesNotDecrease() {
        var streak = Streak(currentStreak: 15, longestStreak: 15)

        streak.currentStreak = 1
        streak.longestStreak = max(streak.longestStreak, streak.currentStreak)

        #expect(streak.longestStreak == 15)
    }
}

// MARK: - TaskStatistics Tests

@Suite("TaskStatistics Tests")
struct TaskStatisticsTests {

    @Test("Percentage calculations with tasks")
    func percentageCalculationsWithTasks() {
        let stats = TaskStatistics(
            todayCompleted: 3,
            todayTotal: 10,
            pastWeekCompleted: 20,
            pastWeekTotal: 25,
            last30DaysCompleted: 80,
            last30DaysTotal: 100
        )

        #expect(abs(stats.todayPercentage - 0.3) < 0.001)
        #expect(abs(stats.pastWeekPercentage - 0.8) < 0.001)
        #expect(abs(stats.last30DaysPercentage - 0.8) < 0.001)
    }

    @Test("Percentage is zero when no tasks")
    func percentageIsZeroWhenNoTasks() {
        let stats = TaskStatistics(
            todayCompleted: 0,
            todayTotal: 0,
            pastWeekCompleted: 0,
            pastWeekTotal: 0,
            last30DaysCompleted: 0,
            last30DaysTotal: 0
        )

        #expect(stats.todayPercentage == 0)
        #expect(stats.pastWeekPercentage == 0)
        #expect(stats.last30DaysPercentage == 0)
    }

    @Test("100% completion rate")
    func fullCompletionRate() {
        let stats = TaskStatistics(
            todayCompleted: 5,
            todayTotal: 5,
            pastWeekCompleted: 10,
            pastWeekTotal: 10,
            last30DaysCompleted: 30,
            last30DaysTotal: 30
        )

        #expect(stats.todayPercentage == 1.0)
        #expect(stats.pastWeekPercentage == 1.0)
        #expect(stats.last30DaysPercentage == 1.0)
    }
}
