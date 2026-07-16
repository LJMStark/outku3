import Foundation
import Testing
@testable import KiroleFeature

@Suite("LocalStorageFailure Tests", .serialized)
struct LocalStorageFailureTests {
    private enum MockStorageError: Error {
        case diskFull
    }

    @Test("Persistence failure updates lastError with user-facing message")
    @MainActor
    func persistenceFailureSetsLastError() {
        let appState = AppState.makeForTesting()
        appState.lastError = nil

        appState.reportPersistenceError(MockStorageError.diskFull, operation: "save", target: "tasks.json")

        #expect(appState.lastError == "Couldn't save your data locally. Please try again.")
    }
}

@Suite("GoogleSyncEngineResilience Tests", .serialized)
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

@Suite("FocusSessionPersistence Tests", .serialized)
struct FocusSessionPersistenceTests {
    @Test("Ending focus session keeps completed session in memory and updates summary")
    @MainActor
    func endingSessionUpdatesInMemoryState() async {
        // 与 BLEServiceManualDisconnectTests 共用真单例：必须同拿一把锁，
        // 否则套件间并行互相收割对方的 activeSession（.serialized 不跨 suite）。
        await SharedPersistenceTestLock.shared.withLock {
            let service = FocusSessionService.shared
            let baseline = service.todaySessions.count

            await service.startSession(taskId: "focus-test-\(UUID().uuidString)", taskTitle: "Focus Test Task")
            service.endSession(reason: .completed)

            #expect(service.activeSession == nil)
            #expect(service.todaySessions.count >= baseline + 1)

            let summary = service.generateAttentionSummary()
            #expect(summary.sessionCount >= baseline + 1)
        }
    }
}

@Suite("ConcurrencyIsolation Tests", .serialized)
struct ConcurrencyIsolationTests {
    @Test("AppState and ThemeManager can be safely accessed on MainActor")
    @MainActor
    func mainActorIsolatedStateAccess() {
        let appState = AppState.makeForTesting()
        let themeManager = ThemeManager.shared

        appState.selectedTab = .home
        themeManager.setTheme(.classicWarm)

        #expect(appState.selectedTab == .home)
        #expect(themeManager.currentTheme == .classicWarm)
    }
}
