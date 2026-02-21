import Foundation
import Testing
@testable import KiroleFeature

@Suite("LocalStorageFailure Tests")
struct LocalStorageFailureTests {
    private enum MockStorageError: Error {
        case diskFull
    }

    @Test("Persistence failure updates lastError with user-facing message")
    @MainActor
    func persistenceFailureSetsLastError() {
        let appState = AppState.shared
        appState.lastError = nil

        appState.reportPersistenceError(MockStorageError.diskFull, operation: "save", target: "tasks.json")

        #expect(appState.lastError == "本地数据保存失败，请稍后重试。")
    }
}

@Suite("GoogleSyncEngineResilience Tests")
struct GoogleSyncEngineResilienceTests {
    @Test("Full sync with no enabled sources keeps current data and returns no warnings")
    func fullSyncWithoutSourcesReturnsCurrentState() async throws {
        let event = CalendarEvent(
            title: "No-op Sync Event",
            startTime: Date(),
            endTime: Date().addingTimeInterval(1800)
        )
        let task = TaskItem(
            id: "sync-noop-task",
            title: "No-op Sync Task",
            dueDate: Date()
        )

        let result = try await GoogleSyncEngine.shared.performFullSync(
            currentEvents: [event],
            currentTasks: [task],
            includeCalendar: false,
            includeTasks: false
        )

        #expect(result.events.count == 1)
        #expect(result.tasks.count == 1)
        #expect(result.warnings.isEmpty)
    }
}

@Suite("FocusSessionPersistence Tests")
struct FocusSessionPersistenceTests {
    @Test("Ending focus session keeps completed session in memory and updates summary")
    @MainActor
    func endingSessionUpdatesInMemoryState() {
        let service = FocusSessionService.shared
        let baseline = service.todaySessions.count

        service.startSession(taskId: "focus-test-\(UUID().uuidString)", taskTitle: "Focus Test Task")
        service.endSession(reason: .completed)

        #expect(service.activeSession == nil)
        #expect(service.todaySessions.count >= baseline + 1)

        let summary = service.generateAttentionSummary()
        #expect(summary.sessionCount >= baseline + 1)
    }
}

@Suite("ConcurrencyIsolation Tests")
struct ConcurrencyIsolationTests {
    @Test("AppState and ThemeManager can be safely accessed on MainActor")
    @MainActor
    func mainActorIsolatedStateAccess() {
        let appState = AppState.shared
        let themeManager = ThemeManager.shared

        appState.selectedTab = .home
        themeManager.setTheme(.classicWarm)

        #expect(appState.selectedTab == .home)
        #expect(themeManager.currentTheme == .classicWarm)
    }
}
