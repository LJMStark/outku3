import Foundation
import Testing
@testable import KiroleFeature

@Suite("Microsoft Graph client")
struct MicrosoftGraphClientTests {
    @Test("Calendar delta requests immutable IDs and UTC")
    func calendarDeltaHeaders() async throws {
        let transport = MicrosoftGraphTransportSpy(responses: [
            .json("""
            {"value": [], "@odata.deltaLink": "https://graph.microsoft.com/v1.0/me/calendarView/delta?$deltatoken=done"}
            """)
        ])
        let client = MicrosoftGraphClient(
            transport: transport,
            accessToken: { "token" },
            forceRefreshToken: { "refreshed-token" }
        )
        let start = Date(timeIntervalSince1970: 1_723_420_800)
        let end = start.addingTimeInterval(86_400)

        _ = try await client.fetchDefaultCalendarDelta(
            deltaLink: nil,
            start: start,
            end: end
        )

        let request = try #require(await transport.requests.first)
        #expect(request.url?.path == "/v1.0/me/calendarView/delta")
        let queryItems = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(queryItems?.contains(where: { $0.name == "$select" }) == false)
        #expect(request.value(forHTTPHeaderField: "Prefer")?.contains("IdType=\"ImmutableId\"") == true)
        #expect(request.value(forHTTPHeaderField: "Prefer")?.contains("outlook.timezone=\"UTC\"") == true)
    }

    @Test("To Do task delta requests only fields used by the mapper")
    func todoTaskDeltaSelect() async throws {
        let transport = MicrosoftGraphTransportSpy(responses: [
            .json("""
            {"value": [], "@odata.deltaLink": "https://graph.microsoft.com/v1.0/me/todo/lists/list-1/tasks/delta?$deltatoken=done"}
            """)
        ])
        let client = MicrosoftGraphClient(
            transport: transport,
            accessToken: { "token" },
            forceRefreshToken: { "refreshed-token" }
        )

        _ = try await client.fetchTodoTasksDelta(listID: "list-1", deltaLink: nil)

        let request = try #require(await transport.requests.first)
        let requestURL = try #require(request.url)
        let components = try #require(URLComponents(
            url: requestURL,
            resolvingAgainstBaseURL: false
        ))
        let select = components.queryItems?.first(where: { $0.name == "$select" })?.value
        #expect(select == "id,title,status,dueDateTime,importance,lastModifiedDateTime,body")
        #expect(
            request.value(forHTTPHeaderField: "Prefer")
                == "outlook.timezone=\"UTC\""
        )
    }

    @Test("A stored delta link cannot send bearer tokens to another host")
    func rejectsForeignDeltaHost() async {
        let transport = MicrosoftGraphTransportSpy(responses: [])
        let client = MicrosoftGraphClient(
            transport: transport,
            accessToken: { "token" },
            forceRefreshToken: { "refreshed-token" }
        )

        await #expect(throws: MicrosoftGraphError.self) {
            _ = try await client.fetchDefaultCalendarDelta(
                deltaLink: "https://attacker.example/steal",
                start: Date(),
                end: Date().addingTimeInterval(60)
            )
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test("To Do completion sends the documented partial PATCH without undocumented preconditions")
    func todoCompletionPatch() async throws {
        let transport = MicrosoftGraphTransportSpy(responses: [.json("{}")])
        let client = MicrosoftGraphClient(
            transport: transport,
            accessToken: { "token" },
            forceRefreshToken: { "refreshed-token" }
        )

        try await client.updateTodoTaskStatus(
            listID: "list-1",
            taskID: "task-1",
            status: .completed
        )

        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "PATCH")
        #expect(request.value(forHTTPHeaderField: "If-Match") == nil)
        let body = try #require(request.httpBody)
        #expect(String(decoding: body, as: UTF8.self) == #"{"status":"completed"}"#)
    }

    @Test("A bound operation token never refreshes into another Microsoft account")
    func boundTokenDoesNotRefreshAcrossAccountBoundary() async throws {
        let transport = MicrosoftGraphTransportSpy(responses: [
            .json("{}", statusCode: 401),
        ])
        let refreshes = MicrosoftTokenRefreshSpy()
        let client = MicrosoftGraphClient(
            transport: transport,
            accessToken: { "current-account-token" },
            forceRefreshToken: {
                await refreshes.record()
                return "new-account-token"
            }
        )

        await #expect(throws: MicrosoftGraphError.self) {
            try await client.updateTodoTaskStatus(
                listID: "list-1",
                taskID: "task-1",
                status: .completed,
                accessToken: "operation-account-token"
            )
        }

        #expect(await refreshes.count == 0)
        let request = try #require(await transport.requests.first)
        #expect(
            request.value(forHTTPHeaderField: "Authorization")
                == "Bearer operation-account-token"
        )
    }
}

private actor MicrosoftTokenRefreshSpy {
    private(set) var count = 0

    func record() {
        count += 1
    }
}

private actor MicrosoftGraphTransportSpy: MicrosoftGraphTransport {
    private(set) var requests: [URLRequest] = []
    private var responses: [MicrosoftHTTPResponse]

    init(responses: [MicrosoftHTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> MicrosoftHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else {
            throw MicrosoftGraphError.invalidResponse
        }
        return responses.removeFirst()
    }
}

private extension MicrosoftHTTPResponse {
    static func json(_ json: String, statusCode: Int = 200) -> MicrosoftHTTPResponse {
        MicrosoftHTTPResponse(
            data: Data(json.utf8),
            statusCode: statusCode,
            headers: [:]
        )
    }
}
