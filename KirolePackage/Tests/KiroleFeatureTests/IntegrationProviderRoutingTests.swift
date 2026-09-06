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

    @Test("Connecting Google preserves Apple calendars, reminders and in-flight results")
    @MainActor
    func coexistenceModel() {
        let state = AppState.makeForTesting()
        state.events = [CalendarEvent(id: "apple", title: "Apple", startTime: .now, endTime: .now)]
        state.tasks = [TaskItem(id: "apple-task", title: "Apple", source: .apple)]
        let appleGeneration = state.externalSyncGeneration(for: .apple)

        state.updateIntegrationStatus(.googleCalendar, isConnected: true)
        state.updateIntegrationStatus(.googleTasks, isConnected: true)

        #expect(state.isIntegrationConnected(.appleCalendar))
        #expect(state.isIntegrationConnected(.appleReminders))
        #expect(state.isIntegrationConnected(.googleCalendar))
        #expect(state.isIntegrationConnected(.googleTasks))
        #expect(state.connectedExternalSyncTargets() == [.google, .apple])
        #expect(state.events.map(\.id) == ["apple"])
        #expect(state.tasks.map(\.id) == ["apple-task"])
        #expect(state.canCommitExternalSync(.apple, generation: appleGeneration))
    }

    @Test("Both calendar connection orders survive persistence and disconnect independently",
          arguments: [true, false])
    @MainActor
    func calendarConnectionOrder(googleFirst: Bool) {
        let state = AppState.makeForTesting()
        let order: [IntegrationType] = googleFirst
            ? [.googleCalendar, .appleCalendar] : [.appleCalendar, .googleCalendar]
        for type in order {
            state.integrations = state.integrationCoordinator.setIntegrationStatus(
                integrations: state.integrations, type: type, isConnected: false
            )
        }
        for type in order {
            state.updateIntegrationStatus(type, isConnected: true)
        }
        let states = Dictionary(uniqueKeysWithValues: state.integrations.map { ($0.type.rawValue, $0.isConnected) })
        let restored = state.integrationCoordinator.applyConnectionStates(states, to: Integration.defaultIntegrations)
        for type in order {
            #expect(state.integrationCoordinator.hasIntegration(type, integrations: restored))
        }
        state.events = [
            CalendarEvent(id: "google", title: "G", startTime: .now, endTime: .now, source: .google),
            CalendarEvent(id: "apple", title: "A", startTime: .now, endTime: .now, source: .apple),
        ]
        let disconnected = order[0]
        let survivingSource: EventSource = googleFirst ? .apple : .google
        state.updateIntegrationStatus(disconnected, isConnected: false)
        #expect(!state.isIntegrationConnected(disconnected))
        #expect(state.isIntegrationConnected(order[1]))
        #expect(state.events.map(\.source) == [survivingSource])
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
