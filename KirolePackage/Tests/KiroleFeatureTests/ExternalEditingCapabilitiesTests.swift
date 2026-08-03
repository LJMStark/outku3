import Foundation
import Testing
@testable import KiroleFeature

@Suite("Google Calendar Access Level Tests")
struct GoogleCalendarAccessLevelTests {
    @Test("Read-only scope allows reads but blocks writes")
    func readonlyScopeIsReadOnly() {
        let level = GoogleCalendarAccessLevel.from(
            grantedScopes: [GoogleOAuthScope.calendarReadOnly]
        )

        #expect(level.canRead)
        #expect(level.canWrite == false)
    }

    @Test("Calendar events scope allows reads and writes")
    func eventsScopeIsReadWrite() {
        let level = GoogleCalendarAccessLevel.from(
            grantedScopes: [GoogleOAuthScope.calendarEvents]
        )

        #expect(level.canRead)
        #expect(level.canWrite)
    }
}

@Suite("Calendar Event Mapping Tests")
struct CalendarEventMappingTests {
    @Test("Google events preserve source calendar ID for later writes")
    func googleEventMappingKeepsCalendarId() throws {
        let googleEvent = makeGoogleCalendarEvent()

        let event = try #require(
            CalendarEvent.from(googleEvent: googleEvent, googleCalendarId: "team-calendar")
        )

        #expect(event.googleEventId == "evt-123")
        #expect(event.googleCalendarId == "team-calendar")
    }

    @Test("Same Google event ID in different calendars gets distinct local IDs")
    func duplicateRemoteIdsAcrossCalendarsStayDistinct() throws {
        let googleEvent = makeGoogleCalendarEvent()

        let teamEvent = try #require(
            CalendarEvent.from(googleEvent: googleEvent, googleCalendarId: "team-calendar")
        )
        let personalEvent = try #require(
            CalendarEvent.from(googleEvent: googleEvent, googleCalendarId: "personal-calendar")
        )

        #expect(teamEvent.id != personalEvent.id)
        #expect(teamEvent.googleEventId == googleEvent.id)
        #expect(personalEvent.googleEventId == googleEvent.id)
        #expect(teamEvent.googleCalendarId == "team-calendar")
        #expect(personalEvent.googleCalendarId == "personal-calendar")
    }

    @Test("Same Google event in the same calendar keeps a stable local ID")
    func sameRemoteEventKeepsStableLocalId() throws {
        let googleEvent = makeGoogleCalendarEvent()

        let first = try #require(
            CalendarEvent.from(googleEvent: googleEvent, googleCalendarId: "team-calendar")
        )
        let second = try #require(
            CalendarEvent.from(googleEvent: googleEvent, googleCalendarId: "team-calendar")
        )

        #expect(first.id == second.id)
    }

    private func makeGoogleCalendarEvent() -> GoogleCalendarEvent {
        GoogleCalendarEvent(
            id: "evt-123",
            summary: "Planning",
            description: "Roadmap review",
            location: "Room A",
            start: GoogleDateTime(
                dateTime: "2026-04-07T09:00:00Z",
                date: nil,
                timeZone: "UTC"
            ),
            end: GoogleDateTime(
                dateTime: "2026-04-07T10:00:00Z",
                date: nil,
                timeZone: "UTC"
            ),
            attendees: nil,
            status: "confirmed",
            updated: "2026-04-07T08:00:00Z",
            etag: "\"etag-1\""
        )
    }
}

@Suite("Task Edit Capability Tests")
struct TaskEditCapabilityTests {
    @Test("Apple reminders support full task editing")
    func appleTaskSupportsFullEditing() {
        let task = TaskItem(
            appleReminderId: "rem-1",
            title: "Apple Task",
            source: .apple
        )

        let capabilities = task.editCapabilities

        #expect(capabilities.isEditable)
        #expect(capabilities.supportsPriority)
        #expect(capabilities.supportsNotes)
        #expect(capabilities.dueDatePrecision == .dateAndTime)
    }

    @Test("Google tasks do not advertise unsupported priority or time editing")
    func googleTaskCapsMatchRemoteModel() {
        let task = TaskItem(
            googleTaskId: "gtask-1",
            googleTaskListId: "list-1",
            title: "Google Task",
            source: .google
        )

        let capabilities = task.editCapabilities

        #expect(capabilities.isEditable)
        #expect(capabilities.supportsPriority == false)
        #expect(capabilities.supportsNotes)
        #expect(capabilities.dueDatePrecision == .dateOnly)
    }

    @Test("Notion tasks stay read-only until full field sync exists")
    func notionTaskStaysReadOnly() {
        let task = TaskItem(
            notionPageId: "page-1",
            title: "Notion Task",
            source: .notion
        )

        #expect(task.editCapabilities.isEditable == false)
    }

    @Test("Taskade tasks stay read-only until full field sync exists")
    func taskadeTaskStaysReadOnly() {
        let task = TaskItem(
            taskadeTaskId: "task-1",
            taskadeProjectId: "project-1",
            title: "Taskade Task",
            source: .taskade
        )

        #expect(task.editCapabilities.isEditable == false)
    }

    @Test("Connected focus locks only the active canonical task")
    func connectedFocusLocksActiveTask() {
        let activeTask = TaskItem(id: "active-task", title: "Active", source: .apple)
        let otherTask = TaskItem(id: "other-task", title: "Other", source: .apple)
        let context = TaskEditingContext(
            isDeviceConnected: true,
            activeFocusTaskID: activeTask.id
        )

        let activeCapabilities = activeTask.editCapabilities(in: context)

        #expect(activeCapabilities.isEditable == false)
        #expect(activeCapabilities.guidance == TaskEditingError.activeOnConnectedDevice.errorDescription)
        #expect(otherTask.editCapabilities(in: context).isEditable)
    }

    @Test("Disconnecting unlocks the active task for editing")
    func disconnectedFocusDoesNotLockTask() {
        let task = TaskItem(id: "active-task", title: "Active", source: .apple)
        let context = TaskEditingContext(
            isDeviceConnected: false,
            activeFocusTaskID: task.id
        )

        #expect(task.editCapabilities(in: context).isEditable)
    }

    @Test("Accessibility status clearly describes focus lock transitions")
    func accessibilityStatusDescribesLockAndUnlock() {
        let task = TaskItem(id: "active-task", title: "Active", source: .apple)
        let connectedContext = TaskEditingContext(
            isDeviceConnected: true,
            activeFocusTaskID: task.id
        )
        let disconnectedContext = TaskEditingContext(
            isDeviceConnected: false,
            activeFocusTaskID: task.id
        )

        #expect(
            task.editCapabilities(in: connectedContext).accessibilityStatus
                == "Editing locked. This task is active on your Kirole device. End focus or disconnect the device before editing it."
        )
        #expect(
            task.editCapabilities(in: disconnectedContext).accessibilityStatus
                == "Editing unlocked. You can edit this task."
        )
    }

    @Test("A wire identifier is not treated as the canonical focus task ID")
    func wireIdentifierDoesNotLockCanonicalTask() {
        let task = TaskItem(
            id: "long-unicode-task-你好-🚀-abcdefghijklmnopqrstuvwxyz",
            title: "Active",
            source: .apple
        )
        let context = TaskEditingContext(
            isDeviceConnected: true,
            activeFocusTaskID: task.hardwareIdentifier
        )

        #expect(task.hardwareIdentifier != task.id)
        #expect(task.editCapabilities(in: context).isEditable)
    }

    @Test("A focus lock never replaces permanent source read-only guidance")
    func sourceReadOnlyGuidanceTakesPriorityOverFocusLock() {
        let context = TaskEditingContext(
            isDeviceConnected: true,
            activeFocusTaskID: "active-task"
        )
        let expectations: [(EventSource, String)] = [
            (.notion, "Notion tasks are read-only in Kirole. Edit them in Notion."),
            (.taskade, "Taskade tasks are read-only in Kirole. Edit them in Taskade."),
            (.todoist, "Writing back to Todoist isn't supported yet. Edit it in Todoist.")
        ]

        for (source, expectedGuidance) in expectations {
            let task = TaskItem(id: "active-task", title: "Active", source: source)
            let capabilities = task.editCapabilities(in: context)

            #expect(capabilities.isEditable == false)
            #expect(capabilities.guidance == expectedGuidance)
            #expect(capabilities.accessibilityStatus == "Editing unavailable. \(expectedGuidance)")
        }
    }
}

@Suite("Event Edit Capability Tests")
struct EventEditCapabilityTests {
    @Test("Google events require write access before editing")
    func googleEventNeedsWriteAccess() {
        let event = CalendarEvent(
            googleEventId: "evt-1",
            googleCalendarId: "team-calendar",
            title: "Google Event",
            startTime: Date(),
            endTime: Date().addingTimeInterval(1800),
            source: .google
        )

        #expect(event.editCapabilities(googleCalendarWriteAccess: false).isEditable == false)
        #expect(event.editCapabilities(googleCalendarWriteAccess: true).isEditable)
    }
}
