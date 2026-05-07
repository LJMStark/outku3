import Testing
import Foundation
@testable import KiroleFeature

// MARK: - PetStateService Tests

@Suite("PetStateService Tests")
struct PetStateServiceTests {

    // MARK: - Mood Calculation Tests

    @Test("Sleepy mood during night hours (22:00-06:00)")
    func sleepyMoodAtNight() async {
        let service = PetStateService.shared

        // Test at 23:00
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 23
        components.minute = 0
        let nightTime = Calendar.current.date(from: components)!

        let mood = await service.calculateMood(
            lastInteraction: Date(),
            tasksCompletedToday: 5,
            totalTasksToday: 10,
            currentTime: nightTime
        )

        #expect(mood == .sleepy)
    }

    @Test("Sleepy mood during early morning (before 6:00)")
    func sleepyMoodEarlyMorning() async {
        let service = PetStateService.shared

        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 4
        components.minute = 0
        let earlyMorning = Calendar.current.date(from: components)!

        let mood = await service.calculateMood(
            lastInteraction: Date(),
            tasksCompletedToday: 0,
            totalTasksToday: 0,
            currentTime: earlyMorning
        )

        #expect(mood == .sleepy)
    }

    @Test("Missing mood when no interaction for 24+ hours")
    func missingMoodAfter24Hours() async {
        let service = PetStateService.shared

        // Create a specific current time at noon
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 12
        components.minute = 0
        components.second = 0
        let currentTime = Calendar.current.date(from: components)!

        // Set last interaction to 25 hours before the current time
        let lastInteraction = Calendar.current.date(byAdding: .hour, value: -25, to: currentTime)!

        let mood = await service.calculateMood(
            lastInteraction: lastInteraction,
            tasksCompletedToday: 0,
            totalTasksToday: 0,
            currentTime: currentTime
        )

        #expect(mood == .missing)
    }

    @Test("Excited mood when task completion rate >= 80%")
    func excitedMoodHighCompletion() async {
        let service = PetStateService.shared

        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 14
        let afternoonTime = Calendar.current.date(from: components)!

        let mood = await service.calculateMood(
            lastInteraction: Date(),
            tasksCompletedToday: 8,
            totalTasksToday: 10,
            currentTime: afternoonTime
        )

        #expect(mood == .excited)
    }

    @Test("Focused mood during work hours with pending tasks")
    func focusedMoodDuringWorkHours() async {
        let service = PetStateService.shared

        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 10
        let workTime = Calendar.current.date(from: components)!

        let mood = await service.calculateMood(
            lastInteraction: Date(),
            tasksCompletedToday: 3,
            totalTasksToday: 10,
            currentTime: workTime
        )

        #expect(mood == .focused)
    }

    @Test("Happy mood as default")
    func happyMoodDefault() async {
        let service = PetStateService.shared

        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 19
        let eveningTime = Calendar.current.date(from: components)!

        let mood = await service.calculateMood(
            lastInteraction: Date(),
            tasksCompletedToday: 0,
            totalTasksToday: 0,
            currentTime: eveningTime
        )

        #expect(mood == .happy)
    }

    // MARK: - Scene Calculation Tests

    @Test("Night scene during night hours (21:00-06:00)")
    func nightSceneAtNight() async {
        let service = PetStateService.shared

        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 22
        let nightTime = Calendar.current.date(from: components)!

        let scene = await service.calculateScene(currentTime: nightTime, hasTasks: true)

        #expect(scene == .night)
    }

    @Test("Work scene during work hours with tasks")
    func workSceneDuringWorkHours() async {
        let service = PetStateService.shared

        // Find a weekday
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 10

        // Ensure it's a weekday (Monday = 2)
        var testDate = Calendar.current.date(from: components)!
        while Calendar.current.component(.weekday, from: testDate) == 1 ||
              Calendar.current.component(.weekday, from: testDate) == 7 {
            testDate = Calendar.current.date(byAdding: .day, value: 1, to: testDate)!
        }

        let scene = await service.calculateScene(currentTime: testDate, hasTasks: true)

        #expect(scene == .work)
    }

    @Test("Indoor scene as default")
    func indoorSceneDefault() async {
        let service = PetStateService.shared

        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 19

        // Find a weekday
        var testDate = Calendar.current.date(from: components)!
        while Calendar.current.component(.weekday, from: testDate) == 1 ||
              Calendar.current.component(.weekday, from: testDate) == 7 {
            testDate = Calendar.current.date(byAdding: .day, value: 1, to: testDate)!
        }

        let scene = await service.calculateScene(currentTime: testDate, hasTasks: false)

        #expect(scene == .indoor)
    }

}

// MARK: - Model Tests

@Suite("Model Tests")
struct ModelTests {

    @Test("CalendarEvent duration text")
    func calendarEventDurationText() {
        let startTime = Date()
        let endTime = Calendar.current.date(byAdding: .hour, value: 1, to: startTime)!

        let event = CalendarEvent(
            title: "Test Event",
            startTime: startTime,
            endTime: endTime,
            source: .google
        )

        #expect(event.durationText == "1h")
    }

    @Test("CalendarEvent duration text with minutes")
    func calendarEventDurationTextWithMinutes() {
        let startTime = Date()
        let endTime = Calendar.current.date(byAdding: .minute, value: 90, to: startTime)!

        let event = CalendarEvent(
            title: "Test Event",
            startTime: startTime,
            endTime: endTime,
            source: .google
        )

        #expect(event.durationText == "1h 30m")
    }

    @Test("Participant initials")
    func participantInitials() {
        let participant = Participant(name: "John Doe")
        #expect(participant.initials == "JD")

        let singleName = Participant(name: "Alice")
        #expect(singleName.initials == "AL") // Takes first 2 characters for single names
    }

    @Test("TaskItem from GoogleTask conversion")
    func taskItemFromGoogleTask() {
        let googleTask = GoogleTask(
            id: "task123",
            title: "Test Task",
            notes: "Some notes",
            status: "needsAction",
            due: nil,
            completed: nil,
            updated: nil,
            position: nil,
            etag: nil,
            deleted: nil
        )

        let taskItem = TaskItem.from(googleTask: googleTask, taskListId: "list123")

        #expect(taskItem.id == "task123")
        #expect(taskItem.title == "Test Task")
        #expect(taskItem.googleTaskId == "task123")
        #expect(taskItem.googleTaskListId == "list123")
        #expect(taskItem.source == .google)
        #expect(taskItem.isCompleted == false)
    }

}

// MARK: - HaikuService Tests

@Suite("HaikuService Tests")
struct HaikuServiceTests {

    @Test("Seasonal haiku returns valid haiku")
    func seasonalHaikuReturnsValidHaiku() async {
        let service = HaikuService.shared

        let haiku = await service.getSeasonalHaiku()

        #expect(haiku.lines.count == 3)
        #expect(!haiku.lines[0].isEmpty)
        #expect(!haiku.lines[1].isEmpty)
        #expect(!haiku.lines[2].isEmpty)
    }
}

// MARK: - SyncModels Tests

@Suite("SyncModels Tests")
struct SyncModelsTests {

    @Test("SyncResult success case")
    func syncResultSuccess() {
        let result = SyncResult.success(itemsSynced: 5)

        if case .success(let count) = result {
            #expect(count == 5)
        } else {
            Issue.record("Expected success case")
        }
    }

    @Test("SyncResult partial case")
    func syncResultPartial() {
        let result = SyncResult.partial(synced: 3, failed: 2)

        if case .partial(let synced, let failed) = result {
            #expect(synced == 3)
            #expect(failed == 2)
        } else {
            Issue.record("Expected partial case")
        }
    }

    @Test("SyncState default values")
    func syncStateDefaults() {
        let state = SyncState()

        #expect(state.pendingChanges == 0)
        #expect(state.status == .synced)
    }
}

// MARK: - Theme Tests

@Suite("Theme Tests")
struct ThemeTests {

    @Test("All themes have required colors")
    func allThemesHaveRequiredColors() {
        let themes: [AppTheme] = [.classicWarm, .elegantPurple, .modernTeal]

        for theme in themes {
            let colors = theme.colors

            // Verify all required colors exist (they're non-optional)
            _ = colors.background
            _ = colors.cardBackground
            _ = colors.primaryText
            _ = colors.secondaryText
            _ = colors.accent
            _ = colors.timeline
            _ = colors.sunrise
            _ = colors.sunset
            _ = colors.taskComplete
        }
    }

    @Test("ThemeManager singleton exists")
    @MainActor
    func themeManagerSingletonExists() {
        let manager = ThemeManager.shared
        // currentTheme is non-optional, just verify it exists
        _ = manager.currentTheme
    }
}
