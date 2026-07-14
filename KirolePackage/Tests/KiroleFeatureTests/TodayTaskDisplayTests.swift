import Foundation
import Testing
@testable import KiroleFeature

@Suite("Today Hardware Display")
struct TodayTaskDisplayTests {
    private let calendar = Calendar(identifier: .gregorian)

    @Test("A task manually selected today is included without changing its due date")
    func manualTodaySelectionKeepsDueDate() {
        let today = Date(timeIntervalSince1970: 1_721_001_600)
        let futureDueDate = calendar.date(byAdding: .day, value: 5, to: today)!
        let task = TaskItem(
            title: "Prepare samples",
            dueDate: futureDueDate,
            todayDisplayDate: today
        )

        #expect(task.isInTodayDisplay(on: today, calendar: calendar))
        #expect(task.dueDate == futureDueDate)
    }

    @Test("A manually selected undated task expires after its selected day")
    func manualTodaySelectionExpiresAtMidnight() {
        let selectedDay = Date(timeIntervalSince1970: 1_721_001_600)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: selectedDay)!
        let task = TaskItem(
            title: "Buy paper",
            dueDate: nil,
            todayDisplayDate: selectedDay
        )

        #expect(task.isInTodayDisplay(on: selectedDay, calendar: calendar))
        #expect(!task.isInTodayDisplay(on: nextDay, calendar: calendar))
    }

    @Test("A task due today remains included without a manual selection")
    func dueTodayRemainsIncluded() {
        let today = Date(timeIntervalSince1970: 1_721_001_600)
        let task = TaskItem(title: "Ship build", dueDate: today)

        #expect(task.isInTodayDisplay(on: today, calendar: calendar))
        #expect(task.isNaturallyDueToday(on: today, calendar: calendar))
        #expect(!task.isManuallySelectedForToday(on: today, calendar: calendar))
    }

    @Test("Four-inch Day Pack keeps a low-priority manual task ahead of natural due-today tasks")
    @MainActor
    func fourInchDayPackPrioritizesManualTodayTask() async {
        let today = Date()
        let futureDueDate = calendar.date(byAdding: .day, value: 5, to: today)!
        let manualTask = TaskItem(
            id: "manual-low",
            title: "Manual low priority",
            dueDate: futureDueDate,
            priority: .low,
            todayDisplayDate: today
        )
        let naturalTasks = ["natural-c", "natural-a", "natural-b"].map { id in
            TaskItem(
                id: id,
                title: id,
                dueDate: today,
                priority: .high
            )
        }

        let dayPack = await DayPackGenerator.shared.generateDayPack(
            pet: Pet(),
            tasks: [manualTask] + naturalTasks,
            events: [],
            weather: Weather(),
            deviceMode: .interactive,
            screenSize: .fourInch,
            petDialogue: "Ready"
        )

        #expect(dayPack.topTasks.map(\.id) == ["manual-low", "natural-a", "natural-b"])
    }

    @Test("Completed tasks do not offer Show Today")
    func completedTaskCannotShowToday() {
        let today = Date(timeIntervalSince1970: 1_721_001_600)
        let task = TaskItem(title: "Already done", isCompleted: true)

        #expect(!task.canShowTodayDisplayAction(on: today, calendar: calendar))
    }

    @Test("Remove Today is only offered for manual tasks that are not naturally due today")
    func removeTodayRequiresManualOnlyDisplay() {
        let today = Date(timeIntervalSince1970: 1_721_001_600)
        let futureDueDate = calendar.date(byAdding: .day, value: 5, to: today)!
        let manualOnlyTask = TaskItem(
            title: "Manual only",
            dueDate: futureDueDate,
            todayDisplayDate: today
        )
        let manualAndNaturalTask = TaskItem(
            title: "Due and manual",
            dueDate: today,
            todayDisplayDate: today
        )

        #expect(manualOnlyTask.canRemoveTodayDisplayAction(on: today, calendar: calendar))
        #expect(!manualAndNaturalTask.canRemoveTodayDisplayAction(on: today, calendar: calendar))
    }

    @Test("Task manager includes manual selections from any external source")
    @MainActor
    func taskManagerIncludesManualSelections() {
        let today = Date()
        let task = TaskItem(
            title: "Read-only Notion task",
            dueDate: nil,
            source: .notion,
            todayDisplayDate: today
        )

        let result = TaskManager().tasksForToday(tasks: [task], now: today)

        #expect(result.map(\.id) == [task.id])
    }

    @Test("Selecting a task for today does not alter external task fields")
    @MainActor
    func appStateSelectionIsLocalOnly() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let state = AppState.makeForTesting()
            let storage = LocalStorage.shared
            let futureDueDate = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
            let task = TaskItem(
                id: "google-local-today-\(UUID().uuidString)",
                googleTaskId: "remote-task",
                googleTaskListId: "remote-list",
                title: "Keep remote due date",
                dueDate: futureDueDate,
                source: .google,
                syncStatus: .synced,
                remoteUpdatedAt: Date(timeIntervalSince1970: 100)
            )
            try await storage.clearAll()
            state.tasks = [task]

            await state.setTaskDisplayedToday(task, displayed: true)

            let updated = state.tasks.first { $0.id == task.id }
            #expect(updated?.dueDate == futureDueDate)
            #expect(updated?.syncStatus == .synced)
            #expect(updated?.remoteUpdatedAt == task.remoteUpdatedAt)
            #expect(updated?.isManuallySelectedForToday() == true)

            await state.setTaskDisplayedToday(task, displayed: false)
            let removed = state.tasks.first { $0.id == task.id }
            #expect(removed?.todayDisplayDate == nil)
            #expect(removed?.dueDate == futureDueDate)
            #expect(removed?.syncStatus == .synced)

            try await storage.clearAll()
        }
    }

    @Test("Manual today selection survives TaskItem persistence")
    func taskItemPersistenceRoundTrip() throws {
        let selectedDate = Date(timeIntervalSince1970: 1_721_001_600)
        let task = TaskItem(
            id: "persisted-today",
            title: "Persist me",
            dueDate: nil,
            source: .google,
            todayDisplayDate: selectedDate
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(task)
        let decoded = try decoder.decode(TaskItem.self, from: data)

        #expect(decoded.todayDisplayDate == selectedDate)
        #expect(decoded.dueDate == nil)
    }
}
