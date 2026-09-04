import Foundation
import Testing
@testable import KiroleFeature

@Suite("Integration provider routing")
struct IntegrationProviderRoutingTests {
    @Test("Only Apple, Google and Outlook are connectable")
    func supportedIntegrations() {
        #expect(IntegrationType.allCases == [
            .googleCalendar,
            .outlookCalendar,
            .appleCalendar,
            .appleReminders,
            .googleTasks,
            .microsoftToDo,
        ])
        #expect(ExternalSyncTarget.allCases == [.google, .apple, .microsoft])
        #expect(ExternalProvider.allCases == [
            .appleCalendar,
            .appleReminders,
            .googleCalendar,
            .googleTasks,
            .outlook,
            .microsoftToDo,
        ])
    }

    /// Microsoft To Do exists in the model because one MSAL account backs both Microsoft surfaces,
    /// but it is not a shipped integration. `displayOrder` is the single place that decides what a
    /// user can connect, so keeping it out of that list is what makes the decision real.
    @Test("Microsoft To Do is reachable in the model but never connectable")
    @MainActor
    func microsoftTodoIsNotConnectable() {
        #expect(IntegrationType.allCases.contains(.microsoftToDo))
        #expect(!IntegrationType.displayOrder.contains(.microsoftToDo))
        #expect(!IntegrationType.availableDisplayOrder.contains(.microsoftToDo))
        #expect(!Integration.defaultIntegrations.contains { $0.type == .microsoftToDo })
    }

    /// The coexistence model: Google and Apple stay mutually exclusive (an iCloud account commonly
    /// subscribes to the same Google calendar, and the hardware wire only carries 8 events, so
    /// duplicates would evict real ones). Outlook has no such overlap and coexists with either.
    @Test("Outlook coexists with Google and Apple, which stay mutually exclusive")
    @MainActor
    func coexistenceModel() {
        let coordinator = IntegrationCoordinator()

        #expect(coordinator.conflictingIntegration(for: .googleCalendar) == .appleCalendar)
        #expect(coordinator.conflictingIntegration(for: .appleCalendar) == .googleCalendar)
        #expect(coordinator.conflictingIntegration(for: .googleTasks) == .appleReminders)
        #expect(coordinator.conflictingIntegration(for: .appleReminders) == .googleTasks)

        #expect(coordinator.conflictingIntegration(for: .outlookCalendar) == nil)
        #expect(coordinator.conflictingIntegration(for: .microsoftToDo) == nil)
    }

    /// The release gate has to work as a rollback, not just as a launch guard. A device that
    /// connected under `MICROSOFT_OAUTH_ENABLED = 1` keeps its persisted connection switch, so a
    /// later gate-0 build must treat that provider as disconnected — otherwise it would keep
    /// syncing Outlook in the background and still render a Settings row.
    @Test("A closed release gate reads as disconnected, not merely unlistable")
    @MainActor
    func closedGateDisablesExistingConnection() {
        let state = AppState(loadLocalDataOnInit: false)
        state.integrations = IntegrationCoordinator().setIntegrationStatus(
            integrations: Integration.defaultIntegrations,
            type: .outlookCalendar,
            isConnected: true
        )

        // AppSecrets.microsoftOAuthEnabled is false in tests, so the gate is closed.
        #expect(IntegrationType.outlookCalendar.isAvailable == false)
        #expect(state.integrations.contains { $0.type == .outlookCalendar && $0.isConnected })
        #expect(state.isIntegrationConnected(.outlookCalendar) == false)
        #expect(!state.connectedExternalSyncTargets().contains(.microsoft))
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

    @Test("Disconnecting Outlook removes only its events")
    @MainActor
    func outlookScopedCleanup() {
        let coordinator = IntegrationCoordinator()
        let events = [
            CalendarEvent(id: "google", title: "G", startTime: .now, endTime: .now, source: .google),
            CalendarEvent(id: "outlook", title: "O", startTime: .now, endTime: .now, source: .outlook),
            CalendarEvent(id: "apple", title: "A", startTime: .now, endTime: .now, source: .apple),
        ]
        let tasks = [TaskItem(id: "google-task", title: "G", source: .google)]

        let cleaned = coordinator.cleanupDisconnectedData(
            for: .outlookCalendar,
            events: events,
            tasks: tasks
        )

        #expect(cleaned.events.map(\.id) == ["google", "apple"])
        #expect(cleaned.tasks.map(\.id) == ["google-task"])
    }
}
