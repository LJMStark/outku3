import Foundation
import Testing
@testable import KiroleFeature

@Suite("Microsoft Graph models")
struct MicrosoftGraphModelsTests {
    @Test("Outlook event decodes the default-calendar delta shape")
    func outlookEventDecoding() throws {
        let data = try #require(
            """
            {
              "value": [{
                "@odata.etag": "W/\\\"event-etag\\\"",
                "id": "event-1",
                "subject": "Design review",
                "bodyPreview": "Agenda",
                "isAllDay": false,
                "isCancelled": false,
                "lastModifiedDateTime": "2026-08-12T01:02:03Z",
                "start": {"dateTime": "2026-08-12T09:30:00.0000000", "timeZone": "UTC"},
                "end": {"dateTime": "2026-08-12T10:00:00.0000000", "timeZone": "UTC"},
                "location": {"displayName": "Room 1"},
                "attendees": [{"emailAddress": {"name": "Ada", "address": "ada@example.com"}}]
              }],
              "@odata.deltaLink": "https://graph.microsoft.com/v1.0/me/calendarView/delta?$deltatoken=opaque"
            }
            """.data(using: .utf8)
        )

        let page = try JSONDecoder().decode(MicrosoftGraphPage<MicrosoftOutlookEvent>.self, from: data)
        let event = try #require(page.value.first)

        #expect(event.id == "event-1")
        #expect(event.subject == "Design review")
        #expect(event.location?.displayName == "Room 1")
        #expect(event.attendees?.first?.emailAddress.name == "Ada")
        #expect(event.start?.date != nil)
        #expect(page.deltaLink?.contains("$deltatoken=opaque") == true)
    }

    @Test("Microsoft To Do task preserves non-binary Graph status")
    func todoTaskStatusDecoding() throws {
        let data = try #require(
            """
            {
              "id": "task-1",
              "title": "Wait for review",
              "status": "waitingOnOthers",
              "importance": "high",
              "lastModifiedDateTime": "2026-08-12T01:02:03Z",
              "body": {"content": "Details", "contentType": "text"},
              "dueDateTime": {"dateTime": "2026-08-13T09:00:00.0000000", "timeZone": "UTC"}
            }
            """.data(using: .utf8)
        )

        let task = try JSONDecoder().decode(MicrosoftTodoTask.self, from: data)

        #expect(task.status == .waitingOnOthers)
        #expect(task.isCompleted == false)
        #expect(task.importance == .high)
        #expect(task.dueDateTime?.date != nil)
    }

    @Test("Microsoft To Do interprets an offset-free due date in its Windows time zone")
    func todoTaskDueDateUsesGraphTimeZone() throws {
        let data = try #require(
            """
            {
              "id": "task-pacific",
              "title": "Pacific morning",
              "status": "notStarted",
              "dueDateTime": {
                "dateTime": "2026-08-13T09:00:00.0000000",
                "timeZone": "Pacific Standard Time"
              }
            }
            """.data(using: .utf8)
        )
        let expected = try #require(
            ISO8601DateFormatter().date(from: "2026-08-13T16:00:00Z")
        )

        let task = try JSONDecoder().decode(MicrosoftTodoTask.self, from: data)

        #expect(task.dueDateTime?.date == expected)
    }

    @Test("Undo restores the prior Graph status instead of forcing notStarted")
    func completionTargetRestoresPriorStatus() {
        #expect(MicrosoftTodoStatus.targetStatus(
            isCompleted: true,
            previousRemoteStatus: MicrosoftTodoStatus.inProgress.rawValue
        ) == .completed)
        #expect(MicrosoftTodoStatus.targetStatus(
            isCompleted: false,
            previousRemoteStatus: MicrosoftTodoStatus.inProgress.rawValue
        ) == .inProgress)
        #expect(MicrosoftTodoStatus.targetStatus(
            isCompleted: false,
            previousRemoteStatus: nil
        ) == .notStarted)
    }
}
