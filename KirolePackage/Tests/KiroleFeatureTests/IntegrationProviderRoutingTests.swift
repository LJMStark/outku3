import Foundation
import Testing
@testable import KiroleFeature

@Suite("Integration provider routing")
struct IntegrationProviderRoutingTests {
    @Test("Direct providers and Apple-mediated calendars are connectable")
    func supportedIntegrations() {
        #expect(IntegrationType.outlookCalendar.isSupported)
        #expect(IntegrationType.microsoftToDo.isSupported)
        #expect(IntegrationType.todoist.isSupported)
        #expect(IntegrationType.tickTick.isSupported)
        #expect(IntegrationType.caldav.isSupported)
        #expect(IntegrationType.icalWebcal.isSupported)
        #expect(IntegrationType.caldav.connectionMode == .appleCalendarMediated)
        #expect(IntegrationType.icalWebcal.connectionMode == .appleCalendarMediated)
        #expect(IntegrationType.todoist.connectionMode == .direct)
    }

    @Test("Disconnect removes only the selected provider data")
    @MainActor
    func scopedCleanup() {
        let coordinator = IntegrationCoordinator()
        let events = [
            CalendarEvent(
                id: "outlook",
                title: "Outlook",
                startTime: .now,
                endTime: .now,
                source: .outlook
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
            TaskItem(id: "todo", title: "Microsoft", source: .microsoftToDo),
            TaskItem(id: "todoist", title: "Todoist", source: .todoist),
            TaskItem(id: "ticktick", title: "TickTick", source: .tickTick),
        ]

        let cleaned = coordinator.cleanupDisconnectedData(
            for: .microsoftToDo,
            events: events,
            tasks: tasks
        )

        #expect(cleaned.events.map(\.id) == ["outlook", "apple"])
        #expect(cleaned.tasks.map(\.id) == ["todoist", "ticktick"])
    }

    @Test("Read-only provider tasks reject both App and hardware completion")
    @MainActor
    func readOnlyCompletionCapability() {
        let reference = ProviderItemReference(
            provider: .tickTick,
            accountID: "account",
            containerID: "project",
            itemID: "task",
            region: .international,
            allowsContentModifications: false
        )
        let task = TaskItem(
            id: reference.stableLocalID,
            externalReference: reference,
            title: "Read only",
            source: .tickTick
        )
        let event = EventLog(
            eventType: .completeTask,
            taskId: task.hardwareIdentifier,
            operationID: 42,
            timestamp: .now,
            hasDeviceTimestamp: true
        )

        #expect(!task.allowsCompletionChanges)
        #expect(BLEEventHandler.plannedTaskOperationReceipt(event, tasks: [task])?.result == .invalidRequest)
    }
}
