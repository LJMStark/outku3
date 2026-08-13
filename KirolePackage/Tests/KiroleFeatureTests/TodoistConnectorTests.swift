import Foundation
import Testing
@testable import KiroleFeature

@Suite("Todoist connector")
struct TodoistConnectorTests {
    @Test("PKCE uses the RFC 7636 S256 transform")
    func pkceChallenge() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        #expect(TodoistPKCE.challenge(for: verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test("Public-client authorization and token exchange never include a client secret")
    func publicClientOAuthRequests() throws {
        let configuration = try TodoistOAuthConfiguration(
            clientID: "https://kirole.example/oauth/todoist-client.json",
            redirectURI: URL(string: "https://kirole.example/oauth/todoist-callback")!
        )
        let authorizationURL = try TodoistOAuthRequestBuilder.authorizationURL(
            configuration: configuration,
            state: "state-123",
            codeChallenge: "challenge-123"
        )
        let query = try #require(URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.contains(URLQueryItem(name: "code_challenge_method", value: "S256")))
        #expect(query.contains(URLQueryItem(name: "state", value: "state-123")))
        #expect(query.first(where: { $0.name == "client_secret" }) == nil)

        let request = try TodoistOAuthRequestBuilder.tokenExchangeRequest(
            configuration: configuration,
            code: "authorization-code",
            verifier: "verifier"
        )
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(body.contains("code_verifier=verifier"))
        #expect(!body.contains("client_secret"))
    }

    @Test("Public clients reject custom-scheme redirects")
    func publicClientRequiresHTTPSRedirect() {
        #expect(throws: TodoistAuthError.invalidConfiguration) {
            _ = try TodoistOAuthConfiguration(
                clientID: "https://kirole.example/oauth/todoist-client.json",
                redirectURI: URL(string: "kirole://todoist-callback")!
            )
        }
    }

    @Test("Todoist public clients use an HTTPS metadata document instead of a registered ID")
    func publicClientRequiresMetadataDocumentClientID() throws {
        _ = try TodoistOAuthConfiguration(
            clientID: "https://kirole.example/.well-known/todoist-oauth-client.json",
            redirectURI: URL(string: "https://kirole.example/oauth/todoist-callback")!
        )

        #expect(throws: TodoistAuthError.invalidConfiguration) {
            _ = try TodoistOAuthConfiguration(
                clientID: "0123456789abcdef",
                redirectURI: URL(string: "https://kirole.example/oauth/todoist-callback")!
            )
        }
    }

    @Test("Sync items keep provider-native due and recurrence data")
    func decodeSyncItem() throws {
        let data = Data(
            """
            {
              "sync_token": "next-token",
              "full_sync": true,
              "items": [{
                "id": "task-1",
                "project_id": "project-1",
                "parent_id": null,
                "content": "Prepare launch",
                "description": "Keep this note",
                "checked": false,
                "is_deleted": false,
                "priority": 4,
                "updated_at": "2026-08-12T08:30:00Z",
                "due": {
                  "date": "2026-08-13T09:15:00",
                  "timezone": "Asia/Shanghai",
                  "string": "every weekday at 9:15",
                  "lang": "en",
                  "is_recurring": true
                }
              }]
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(TodoistSyncResponse.self, from: data)
        let item = try #require(response.items.first)
        #expect(item.priority == 4)
        #expect(item.due?.isRecurring == true)
        #expect(item.due?.timezone == "Asia/Shanghai")
        #expect(item.isRootTask)
    }

    @Test("Completion outbox keeps the same UUID across retries")
    func stableOutboxUUID() {
        let entry = TodoistOutboxEntry(accountID: "account", itemID: "task-1", completed: true)
        let first = entry.command
        let retried = entry.retrying(after: Date(timeIntervalSince1970: 100)).command

        #expect(first.uuid == retried.uuid)
        #expect(first.type == "item_close")
        #expect(
            TodoistOutboxEntry(accountID: "account", itemID: "task-1", completed: false).command.type
                == "item_uncomplete"
        )
    }

    @Test("Full sync is followed immediately by an incremental catch-up")
    func fullThenIncrementalSync() async throws {
        let service = TodoistSyncServiceSpy(responses: [
            TodoistSyncResponse(syncToken: "identity-token", fullSync: true, user: TodoistUser(id: "account")),
            TodoistSyncResponse(syncToken: "full-token", fullSync: true, items: [
                .fixture(id: "old", content: "Old")
            ], user: TodoistUser(id: "account")),
            TodoistSyncResponse(syncToken: "incremental-token", fullSync: false, items: [
                .fixture(id: "new", content: "New")
            ], user: TodoistUser(id: "account")),
        ])
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = TodoistSyncStore(directoryURL: directory)
        let engine = TodoistSyncEngine(service: service, store: store)

        let result = try await engine.synchronize(accessToken: "token")

        #expect(result.map(\.id).sorted() == ["new", "old"])
        #expect(await service.requestedTokens() == ["*", "*", "full-token"])
        #expect(try await store.load().syncToken == "incremental-token")
    }

    @Test("A different Todoist account clears snapshots but quarantines queued writes")
    func accountChangeResetsProviderState() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = TodoistSyncStore(directoryURL: directory)
        try await store.save(TodoistSyncState(
            syncToken: "old-token",
            accountID: "old-account",
            itemsByID: ["old": .fixture(id: "old", content: "Old")],
            projectsByID: ["old-project": TodoistProject(id: "old-project", name: "Old", isDeleted: false, isArchived: false)],
            outbox: [TodoistOutboxEntry(accountID: "old-account", itemID: "old", completed: true)]
        ))
        let service = TodoistSyncServiceSpy(responses: [
            TodoistSyncResponse(
                syncToken: "identity-token",
                fullSync: true,
                user: TodoistUser(id: "new-account")
            ),
            TodoistSyncResponse(
                syncToken: "new-token",
                fullSync: true,
                items: [.fixture(id: "new", content: "New")],
                user: TodoistUser(id: "new-account")
            ),
            TodoistSyncResponse(
                syncToken: "new-catchup-token",
                fullSync: false,
                user: TodoistUser(id: "new-account")
            ),
        ])
        let engine = TodoistSyncEngine(service: service, store: store)

        let items = try await engine.synchronize(accessToken: "new-token")
        let state = try await store.load()

        #expect(items.map(\.id) == ["new"])
        #expect(state.accountID == "new-account")
        #expect(state.itemsByID["old"] == nil)
        #expect(state.outbox.map(\.accountID) == ["old-account"])
    }

    @Test("Missing account identity never flushes a queued command")
    func missingIdentityDoesNotFlushOutbox() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = TodoistSyncStore(directoryURL: directory)
        try await store.save(TodoistSyncState(
            accountID: "old-account",
            outbox: [TodoistOutboxEntry(accountID: "old-account", itemID: "old-task", completed: true)]
        ))
        let service = TodoistSyncServiceSpy(responses: [
            TodoistSyncResponse(syncToken: "identity-token", fullSync: true, user: nil),
        ])
        let engine = TodoistSyncEngine(service: service, store: store)

        await #expect(throws: TodoistSyncEngineError.missingAccountID) {
            _ = try await engine.synchronize(accessToken: "new-token")
        }
        #expect(await service.requestedCommandCounts() == [0])
        #expect(try await store.load().outbox.count == 1)
    }

    @Test("A newly authorized token for the same account preserves and flushes queued writes")
    func sameAccountReauthorizationPreservesOutbox() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = TodoistSyncStore(directoryURL: directory)
        let entry = TodoistOutboxEntry(
            accountID: "account",
            itemID: "task-1",
            completed: true
        )
        try await store.save(TodoistSyncState(
            syncToken: "existing",
            accountID: "account",
            outbox: [entry]
        ))
        let service = TodoistSyncServiceSpy(steps: [
            .success(TodoistSyncResponse(
                syncToken: "identity-token",
                fullSync: true,
                user: TodoistUser(id: "account")
            )),
            .success(TodoistSyncResponse(
                syncToken: "",
                fullSync: false,
                syncStatus: [entry.command.uuid: .ok]
            )),
            .success(TodoistSyncResponse(
                syncToken: "pulled",
                fullSync: false,
                user: TodoistUser(id: "account")
            )),
        ])
        let engine = TodoistSyncEngine(service: service, store: store)

        _ = try await engine.synchronize(accessToken: "newly-authorized-token")

        #expect(await service.requestedCommandCounts() == [0, 1, 0])
        #expect(await service.requestedTokens() == ["*", "existing", "existing"])
        #expect(try await store.load().outbox.isEmpty)
    }

    @Test("Explicit command rejection is persisted and reported after the pull completes")
    func explicitCommandFailurePropagates() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = TodoistSyncStore(directoryURL: directory)
        try await store.save(TodoistSyncState(syncToken: "existing", accountID: "account"))
        let service = TodoistSyncServiceSpy(steps: [
            .success(TodoistSyncResponse(
                syncToken: "identity-token",
                fullSync: true,
                user: TodoistUser(id: "account")
            )),
            .success(TodoistSyncResponse(
                syncToken: "",
                fullSync: false,
                syncStatus: [:]
            )),
            .success(TodoistSyncResponse(
                syncToken: "pulled",
                fullSync: false,
                items: [.fixture(id: "remote", content: "Remote")],
                user: TodoistUser(id: "account")
            )),
        ])
        let engine = TodoistSyncEngine(service: service, store: store)

        await #expect(throws: TodoistSyncEngineError.self) {
            try await engine.pushCompletion(
                itemID: "task-1",
                accountID: "account",
                completed: true,
                accessToken: "token",
                now: Date(timeIntervalSince1970: 1_000)
            )
        }

        let state = try await store.load()
        #expect(state.itemsByID["remote"] != nil)
        #expect(state.outbox.count == 1)
        #expect(state.outbox.first?.retryCount == 1)
        #expect(state.outbox.first?.nextAttemptAt != nil)
    }

    @Test("Command request failure is persisted and reported without losing the command")
    func commandRequestFailurePropagates() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = TodoistSyncStore(directoryURL: directory)
        try await store.save(TodoistSyncState(syncToken: "existing", accountID: "account"))
        let service = TodoistSyncServiceSpy(steps: [
            .success(TodoistSyncResponse(
                syncToken: "identity-token",
                fullSync: true,
                user: TodoistUser(id: "account")
            )),
            .failure(.network),
            .success(TodoistSyncResponse(
                syncToken: "pulled",
                fullSync: false,
                user: TodoistUser(id: "account")
            )),
        ])
        let engine = TodoistSyncEngine(service: service, store: store)

        await #expect(throws: TodoistSyncEngineError.self) {
            try await engine.pushCompletion(
                itemID: "task-1",
                accountID: "account",
                completed: true,
                accessToken: "token",
                now: Date(timeIntervalSince1970: 1_000)
            )
        }

        let entry = try #require(try await store.load().outbox.first)
        #expect(entry.retryCount == 1)
        #expect(entry.nextAttemptAt != nil)
    }

    @Test("An outbox entry remains after the old retry limit and uses capped backoff")
    func retryLimitDoesNotDeleteOutbox() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = TodoistSyncStore(directoryURL: directory)
        try await store.save(TodoistSyncState(
            syncToken: "existing",
            accountID: "account",
            outbox: [TodoistOutboxEntry(
                accountID: "account",
                itemID: "task-1",
                completed: true,
                retryCount: 5,
                nextAttemptAt: now
            )]
        ))
        let service = TodoistSyncServiceSpy(steps: [
            .success(TodoistSyncResponse(
                syncToken: "identity-token",
                fullSync: true,
                user: TodoistUser(id: "account")
            )),
            .success(TodoistSyncResponse(syncToken: "", fullSync: false)),
            .success(TodoistSyncResponse(
                syncToken: "pulled",
                fullSync: false,
                user: TodoistUser(id: "account")
            )),
        ])
        let engine = TodoistSyncEngine(service: service, store: store)

        _ = try await engine.synchronize(accessToken: "token", now: now)

        let entry = try #require(try await store.load().outbox.first)
        #expect(entry.retryCount == 6)
        #expect(try #require(entry.nextAttemptAt).timeIntervalSince(now) <= 15 * 60)
    }

    @Test("A queued command is never sent through a different Todoist account")
    func accountMismatchDoesNotFlush() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = TodoistSyncStore(directoryURL: directory)
        let service = TodoistSyncServiceSpy(responses: [
            TodoistSyncResponse(
                syncToken: "identity-token",
                fullSync: true,
                user: TodoistUser(id: "new-account")
            ),
            TodoistSyncResponse(
                syncToken: "full-token",
                fullSync: true,
                user: TodoistUser(id: "new-account")
            ),
            TodoistSyncResponse(
                syncToken: "catchup-token",
                fullSync: false,
                user: TodoistUser(id: "new-account")
            ),
        ])
        let engine = TodoistSyncEngine(service: service, store: store)
        try await engine.reset()

        await #expect(throws: TodoistSyncEngineError.self) {
            try await engine.pushCompletion(
                itemID: "old-task",
                accountID: "old-account",
                completed: true,
                accessToken: "new-token"
            )
        }

        #expect(await service.requestedCommandCounts() == [0, 0, 0])
        let entry = try #require(try await store.load().outbox.first)
        #expect(entry.accountID == "old-account")
        #expect(entry.retryCount == 0)
    }

    @Test("Concurrent writes for different tasks are serialized without losing either command")
    func concurrentTaskWritesAreSerialized() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = TodoistSyncStore(directoryURL: directory)
        try await store.save(TodoistSyncState(syncToken: "existing", accountID: "account"))
        let service = TodoistBlockingSyncService()
        let engine = TodoistSyncEngine(service: service, store: store)

        let first = Task {
            try await engine.pushCompletion(
                itemID: "task-1",
                accountID: "account",
                completed: true,
                accessToken: "token"
            )
        }
        await service.waitUntilFirstCommandStarts()
        let second = Task {
            try await engine.pushCompletion(
                itemID: "task-2",
                accountID: "account",
                completed: true,
                accessToken: "token"
            )
        }

        #expect(await service.commandItemIDs() == ["task-1"])
        await service.releaseFirstCommand()
        try await first.value
        try await second.value

        #expect(await service.commandItemIDs() == ["task-1", "task-2"])
        #expect(try await store.load().outbox.isEmpty)
    }

    @Test("An in-flight completion is followed by the newer opposite target state")
    func inFlightReverseStateIsNotOverwritten() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = TodoistSyncStore(directoryURL: directory)
        try await store.save(TodoistSyncState(syncToken: "existing", accountID: "account"))
        let service = TodoistBlockingSyncService()
        let engine = TodoistSyncEngine(service: service, store: store)

        let close = Task {
            try await engine.pushCompletion(
                itemID: "task-1",
                accountID: "account",
                completed: true,
                accessToken: "token"
            )
        }
        await service.waitUntilFirstCommandStarts()
        let reopen = Task {
            try await engine.pushCompletion(
                itemID: "task-1",
                accountID: "account",
                completed: false,
                accessToken: "token"
            )
        }

        await service.releaseFirstCommand()
        try await close.value
        try await reopen.value

        #expect(await service.commandTypes() == ["item_close", "item_uncomplete"])
        #expect(try await store.load().outbox.isEmpty)
    }

    @Test("A completion queued before reset cannot recreate cleared sync state")
    func queuedCompletionCannotWriteAfterReset() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = TodoistSyncStore(directoryURL: directory)
        try await store.save(TodoistSyncState(syncToken: "existing", accountID: "account"))
        let service = TodoistBlockingSyncService()
        let engine = TodoistSyncEngine(service: service, store: store)

        let active = Task {
            try await engine.pushCompletion(
                itemID: "active-task",
                accountID: "account",
                completed: true,
                accessToken: "token"
            )
        }
        await service.waitUntilFirstCommandStarts()

        let stale = Task {
            try await engine.pushCompletion(
                itemID: "stale-task",
                accountID: "account",
                completed: true,
                accessToken: "token"
            )
        }
        #expect(await waitForExclusiveWaiterCount(1, engine: engine))
        let reset = Task {
            try await engine.reset()
        }
        #expect(await waitForExclusiveWaiterCount(2, engine: engine))

        await service.releaseFirstCommand()
        try await active.value
        try await reset.value
        await #expect(throws: TodoistSyncEngineError.staleOperation) {
            try await stale.value
        }

        #expect(try await store.load() == TodoistSyncState())
        #expect(await service.commandItemIDs() == ["active-task"])
    }

    private func waitForExclusiveWaiterCount(
        _ expectedCount: Int,
        engine: TodoistSyncEngine
    ) async -> Bool {
        for _ in 0..<1_000 {
            if await engine.exclusiveSyncWaiterCount() == expectedCount {
                return true
            }
            await Task.yield()
        }
        return false
    }
}

private enum TodoistSyncTestFailure: Error {
    case network
}

private actor TodoistSyncServiceSpy: TodoistSyncServing {
    private var steps: [Result<TodoistSyncResponse, TodoistSyncTestFailure>]
    private var tokens: [String] = []
    private var commandCounts: [Int] = []

    init(responses: [TodoistSyncResponse]) {
        steps = responses.map(Result.success)
    }

    init(steps: [Result<TodoistSyncResponse, TodoistSyncTestFailure>]) {
        self.steps = steps
    }

    func sync(
        accessToken: String,
        syncToken: String,
        resourceTypes: [String],
        commands: [TodoistCommand]
    ) async throws -> TodoistSyncResponse {
        tokens.append(syncToken)
        commandCounts.append(commands.count)
        return try steps.removeFirst().get()
    }

    func requestedTokens() -> [String] { tokens }
    func requestedCommandCounts() -> [Int] { commandCounts }
}

private actor TodoistBlockingSyncService: TodoistSyncServing {
    private var commands: [TodoistCommand] = []
    private var firstCommandStarted = false
    private var firstCommandStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstCommandRelease: CheckedContinuation<Void, Never>?

    func sync(
        accessToken: String,
        syncToken: String,
        resourceTypes: [String],
        commands incomingCommands: [TodoistCommand]
    ) async throws -> TodoistSyncResponse {
        if resourceTypes == ["user"] {
            return TodoistSyncResponse(
                syncToken: "identity",
                fullSync: true,
                user: TodoistUser(id: "account")
            )
        }
        if !incomingCommands.isEmpty {
            commands.append(contentsOf: incomingCommands)
            if !firstCommandStarted {
                firstCommandStarted = true
                let waiters = firstCommandStartWaiters
                firstCommandStartWaiters.removeAll()
                waiters.forEach { $0.resume() }
                await withCheckedContinuation { continuation in
                    firstCommandRelease = continuation
                }
            }
            return TodoistSyncResponse(
                syncToken: "",
                fullSync: false,
                syncStatus: Dictionary(
                    uniqueKeysWithValues: incomingCommands.map { ($0.uuid, .ok) }
                )
            )
        }
        return TodoistSyncResponse(
            syncToken: "next",
            fullSync: false,
            user: TodoistUser(id: "account")
        )
    }

    func waitUntilFirstCommandStarts() async {
        guard !firstCommandStarted else { return }
        await withCheckedContinuation { continuation in
            firstCommandStartWaiters.append(continuation)
        }
    }

    func releaseFirstCommand() {
        firstCommandRelease?.resume()
        firstCommandRelease = nil
    }

    func commandItemIDs() -> [String] {
        commands.compactMap { $0.args["id"] }
    }

    func commandTypes() -> [String] {
        commands.map(\.type)
    }
}

private extension TodoistItem {
    static func fixture(id: String, content: String) -> TodoistItem {
        TodoistItem(
            id: id,
            projectID: "project",
            parentID: nil,
            content: content,
            description: "",
            checked: false,
            isDeleted: false,
            priority: 1,
            due: nil,
            updatedAt: nil
        )
    }
}
