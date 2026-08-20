import Foundation
import Testing
@testable import KiroleFeature

@Suite("Integration provider routing")
struct IntegrationProviderRoutingTests {
    @Test("Only the four accepted Apple and Google sources are exposed")
    func supportedIntegrations() {
        #expect(IntegrationType.allCases == [
            .googleCalendar,
            .appleCalendar,
            .appleReminders,
            .googleTasks,
        ])
        #expect(IntegrationType.displayOrder == IntegrationType.allCases)
        #expect(ExternalSyncTarget.allCases == [.google, .apple])
        #expect(ExternalProvider.allCases == [
            .appleCalendar,
            .appleReminders,
            .googleCalendar,
            .googleTasks,
        ])
    }

    @Test("Disconnect removes only the selected Apple source data")
    @MainActor
    func scopedCleanup() {
        let coordinator = IntegrationCoordinator()
        let events = [
            CalendarEvent(
                id: "google",
                title: "Google",
                startTime: .now,
                endTime: .now,
                source: .google
            ),
            CalendarEvent(
                id: "apple",
                title: "Apple",
                startTime: .now,
                endTime: .now,
                source: .apple
            ),
        ]
        let tasks = [
            TaskItem(id: "google-task", title: "Google", source: .google),
            TaskItem(id: "apple-reminder", title: "Apple", source: .apple),
        ]

        let cleaned = coordinator.cleanupDisconnectedData(
            for: .appleReminders,
            events: events,
            tasks: tasks
        )

        #expect(cleaned.events.map(\.id) == ["google", "apple"])
        #expect(cleaned.tasks.map(\.id) == ["google-task"])
    }
}
