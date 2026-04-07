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
        let googleEvent = GoogleCalendarEvent(
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

        let event = try #require(
            CalendarEvent.from(googleEvent: googleEvent, googleCalendarId: "team-calendar")
        )

        #expect(event.googleEventId == "evt-123")
        #expect(event.googleCalendarId == "team-calendar")
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
