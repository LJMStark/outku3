import Foundation
import Testing
@testable import KiroleFeature

@Suite("TickTick and Dida connector")
struct TickTickConnectorTests {
    @Test("Changing accounts clears cached project snapshots")
    func accountChangeClearsSnapshots() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = TickTickSyncStore(directoryURL: directory, region: .international)
        let service = TickTickReadServiceSpy()
        let engine = TickTickSyncEngine(
            region: .international,
            service: service,
            store: store,
            minimumPollInterval: 60
        )
        let first = TickTickTokenSet(
            accessToken: "first-token",
            expiresAt: nil,
            scope: "tasks:read",
            accountID: "first-account",
            region: .international,
            ownerUserID: "user-1"
        )
        let second = TickTickTokenSet(
            accessToken: "second-token",
            expiresAt: nil,
            scope: "tasks:read",
            accountID: "second-account",
            region: .international,
            ownerUserID: "user-1"
        )

        _ = try await engine.taskItems(
            credentials: first,
            selectedProjectIDs: ["p1"],
            now: Date(timeIntervalSince1970: 100),
            force: true
        )
        _ = try await engine.taskItems(
            credentials: second,
            selectedProjectIDs: [],
            now: Date(timeIntervalSince1970: 200),
            force: false
        )

        let state = try await store.load()
        #expect(state.accountID == "second-account")
        #expect(state.snapshots.isEmpty)
        #expect(state.selectedProjectIDs.isEmpty)
    }

    @Test("International and China regions never share API or OAuth hosts")
    func endpointsAreRegionBound() {
        #expect(TickTickRegion.international.apiBaseURL.host == "api.ticktick.com")
        #expect(TickTickRegion.china.apiBaseURL.host == "api.dida365.com")
        #expect(TickTickRegion.international.authorizationEndpoint.host == "ticktick.com")
        #expect(TickTickRegion.china.authorizationEndpoint.host == "dida365.com")
    }

    @Test("OAuth transaction requests never carry provider credentials or authorization codes")
    func backendTransactionRequests() throws {
        let configuration = try TickTickOAuthConfiguration(
            backendEndpoint: URL(string: "https://api.kirole.example/functions/v1/ticktick-oauth")!,
            returnURI: URL(string: "https://kirole.681023.xyz/oauth/ticktick-return")!,
            region: .international,
            backendAPIKey: "public-anon-key"
        )
        let request = try TickTickBackendRequestBuilder.request(
            configuration: configuration,
            action: .start,
            userAccessToken: "user-jwt"
        )
        #expect(request.url?.host == "api.kirole.example")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer user-jwt")
        #expect(request.value(forHTTPHeaderField: "apikey") == "public-anon-key")
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(body.contains("\"action\":\"start\""))
        #expect(body.contains("\"region\":\"international\""))
        #expect(!body.localizedCaseInsensitiveContains("code"))
        #expect(!body.localizedCaseInsensitiveContains("client_id"))
        #expect(!body.localizedCaseInsensitiveContains("client_secret"))
        #expect(!body.localizedCaseInsensitiveContains("redirect_uri"))
    }

    @Test("Token is persisted in pending Keychain storage before delivery acknowledgement")
    func deliveryIsDurableBeforeAcknowledgement() async throws {
        let audit = TickTickOAuthAudit()
        let pendingStore = TickTickPendingStoreSpy(audit: audit)
        let tokenStore = TickTickTokenStoreSpy(audit: audit)
        let backend = TickTickOAuthBackendSpy(audit: audit)
        let gate = OAuthCredentialOperationGate()
        let manager = TickTickCredentialManager(
            region: .international,
            ownerUserID: "user-1",
            backend: backend,
            tokenStore: tokenStore,
            pendingStore: pendingStore,
            operationGate: gate
        )
        let operation = try #require(gate.beginOperation())
        defer { gate.endOperation(operation) }
        let pending = TickTickPendingAuthorization(
            attemptID: "attempt-1",
            claimSecret: "claim-secret",
            region: .international,
            ownerUserID: "user-1",
            expiresAt: Date().addingTimeInterval(600),
            delivery: nil
        )
        try await pendingStore.save(pending)

        let tokens = try await manager.claimAndAcknowledge(
            attemptID: "attempt-1",
            operation: operation
        )

        #expect(tokens.accountID == "connection-1")
        #expect(await audit.events() == ["pending", "claim", "pending-delivery", "ack", "token", "pending-clear"])
        #expect(try await pendingStore.load() == nil)
        #expect(try await tokenStore.load() == tokens)
    }

    @Test("Failed acknowledgement keeps the delivered token recoverable and does not connect")
    func failedAcknowledgementKeepsPendingDelivery() async throws {
        let audit = TickTickOAuthAudit()
        let pendingStore = TickTickPendingStoreSpy(audit: audit)
        let tokenStore = TickTickTokenStoreSpy(audit: audit)
        let backend = TickTickOAuthBackendSpy(audit: audit, failAcknowledgement: true)
        let gate = OAuthCredentialOperationGate()
        let manager = TickTickCredentialManager(
            region: .international,
            ownerUserID: "user-1",
            backend: backend,
            tokenStore: tokenStore,
            pendingStore: pendingStore,
            operationGate: gate
        )
        let operation = try #require(gate.beginOperation())
        defer { gate.endOperation(operation) }
        try await pendingStore.save(TickTickPendingAuthorization(
            attemptID: "attempt-1",
            claimSecret: "claim-secret",
            region: .international,
            ownerUserID: "user-1",
            expiresAt: Date().addingTimeInterval(600),
            delivery: nil
        ))

        await #expect(throws: TickTickAuthError.deliveryAcknowledgementFailed) {
            _ = try await manager.claimAndAcknowledge(
                attemptID: "attempt-1",
                operation: operation
            )
        }

        #expect(try await pendingStore.load()?.delivery?.deliveryID == "delivery-1")
        #expect(try await tokenStore.load() == nil)
    }

    @Test("Pending authorization recovers the ready server delivery before claim response")
    func pendingAuthorizationRecoversReadyDelivery() async throws {
        let audit = TickTickOAuthAudit()
        let pendingStore = TickTickPendingStoreSpy(audit: audit)
        let tokenStore = TickTickTokenStoreSpy(audit: audit)
        let backend = TickTickOAuthBackendSpy(audit: audit)
        let gate = OAuthCredentialOperationGate()
        let manager = TickTickCredentialManager(
            region: .international,
            ownerUserID: "user-1",
            backend: backend,
            tokenStore: tokenStore,
            pendingStore: pendingStore,
            operationGate: gate
        )
        let operation = try #require(gate.beginOperation())
        defer { gate.endOperation(operation) }
        try await pendingStore.save(TickTickPendingAuthorization(
            attemptID: "attempt-1",
            claimSecret: "claim-secret",
            region: .international,
            ownerUserID: "user-1",
            expiresAt: .distantPast,
            delivery: nil
        ))

        let recovered = try await manager.recoverPendingDelivery(operation: operation)

        #expect(recovered?.ownerUserID == "user-1")
        #expect(await audit.events().contains("claim"))
    }

    @Test("Credentials from another Kirole account are erased and rejected")
    func crossUserCredentialsAreRejected() async throws {
        let audit = TickTickOAuthAudit()
        let pendingStore = TickTickPendingStoreSpy(audit: audit)
        let tokenStore = TickTickTokenStoreSpy(audit: audit)
        let backend = TickTickOAuthBackendSpy(audit: audit)
        try await tokenStore.save(TickTickTokenSet(
            accessToken: "user-one-token",
            expiresAt: nil,
            scope: "tasks:read",
            accountID: "connection-1",
            region: .international,
            ownerUserID: "user-1"
        ))
        let operationGate = OAuthCredentialOperationGate()
        let manager = TickTickCredentialManager(
            region: .international,
            ownerUserID: "user-2",
            backend: backend,
            tokenStore: tokenStore,
            pendingStore: pendingStore,
            operationGate: operationGate
        )
        let operation = try #require(operationGate.beginOperation())
        defer { operationGate.endOperation(operation) }

        await #expect(throws: TickTickAuthError.accountMismatch) {
            _ = try await manager.credentials(operation: operation)
        }
        #expect(try await tokenStore.load() == nil)
    }

    @Test("Offline disconnect always erases local credentials")
    func offlineDisconnectClearsLocalCredentials() async throws {
        let audit = TickTickOAuthAudit()
        let pendingStore = TickTickPendingStoreSpy(audit: audit)
        let tokenStore = TickTickTokenStoreSpy(audit: audit)
        let backend = TickTickOAuthBackendSpy(audit: audit, failCleanup: true)
        try await tokenStore.save(TickTickTokenSet(
            accessToken: "user-token",
            expiresAt: nil,
            scope: "tasks:read",
            accountID: "connection-1",
            region: .international,
            ownerUserID: "user-1"
        ))
        let manager = TickTickCredentialManager(
            region: .international,
            ownerUserID: "user-1",
            backend: backend,
            tokenStore: tokenStore,
            pendingStore: pendingStore,
            operationGate: OAuthCredentialOperationGate()
        )

        await #expect(throws: TickTickAuthError.serverCleanupPending) {
            try await manager.disconnect()
        }

        #expect(try await tokenStore.load() == nil)
        #expect(try await pendingStore.load() == nil)
    }

    @Test("Read-only task response preserves provider fields")
    func decodeProjectData() throws {
        let data = Data(
            """
            {
              "project": {"id":"p1","name":"Work","closed":false,"groupId":"g1","viewMode":"list","permission":"read"},
              "tasks": [{
                "id":"t1",
                "projectId":"p1",
                "title":"Review contract",
                "content":"Keep formatting",
                "desc":"Legal",
                "isAllDay":false,
                "startDate":"2026-08-12T01:00:00.000+0000",
                "dueDate":"2026-08-12T02:00:00.000+0000",
                "timeZone":"Asia/Shanghai",
                "repeatFlag":"RRULE:FREQ=WEEKLY",
                "priority":5,
                "status":0,
                "sortOrder":12
              }],
              "columns": []
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(TickTickProjectData.self, from: data)
        let task = try #require(response.tasks.first)
        #expect(task.repeatFlag == "RRULE:FREQ=WEEKLY")
        #expect(task.timeZone == "Asia/Shanghai")
        #expect(task.isCompleted == false)
    }

    @Test("A task without modifiedTime cannot masquerade as a fresh remote edit")
    func missingModifiedTimeUsesDistantPast() {
        let task = TickTickTask.fixture.taskItem(
            accountID: "account",
            region: .international
        )

        #expect(task.remoteUpdatedAt == nil)
        #expect(task.lastModified == .distantPast)
    }

    @Test("Polling honors minimum interval and reuses snapshots on 304")
    func conservativePollingAndETag() async throws {
        let service = TickTickReadServiceSpy()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = TickTickSyncStore(directoryURL: directory, region: .international)
        let engine = TickTickSyncEngine(
            region: .international,
            service: service,
            store: store,
            minimumPollInterval: 15 * 60
        )
        let firstDate = Date(timeIntervalSince1970: 1_000)

        let first = try await engine.synchronize(accessToken: "token", selectedProjectIDs: ["p1"], now: firstDate)
        let cached = try await engine.synchronize(accessToken: "token", selectedProjectIDs: ["p1"], now: firstDate.addingTimeInterval(60))
        let conditional = try await engine.synchronize(
            accessToken: "token",
            selectedProjectIDs: ["p1"],
            now: firstDate.addingTimeInterval(901)
        )

        #expect(first.map(\.id) == ["t1"])
        #expect(cached == first)
        #expect(conditional == first)
        #expect(await service.projectDataCalls() == 2)
        #expect(await service.receivedETags() == [nil, "etag-1"])
    }

    @Test("Reset invalidates an older sync before its network response can restore the cache")
    func resetPreventsInFlightSyncFromRestoringCache() async throws {
        let service = TickTickResetRaceService()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = TickTickSyncStore(directoryURL: directory, region: .international)
        let engine = TickTickSyncEngine(
            region: .international,
            service: service,
            store: store,
            minimumPollInterval: 60
        )
        let resetEngine = TickTickSyncEngine(
            region: .international,
            service: service,
            store: TickTickSyncStore(directoryURL: directory, region: .international),
            minimumPollInterval: 60
        )

        let oldSync = Task {
            try await engine.synchronize(
                accessToken: "old-token",
                selectedProjectIDs: ["p1"],
                force: true
            )
        }
        await service.waitUntilOldProjectsRequestStarts()

        try await resetEngine.reset()
        await service.releaseOldProjectsRequest()
        _ = try await oldSync.value

        let state = try await store.load()
        #expect(state.snapshots.isEmpty)
        #expect(state.selectedProjectIDs.isEmpty)
        #expect(state.lastPollAt == nil)
    }

    @Test("A same-account reconnect cannot be overwritten by the pre-reset account generation")
    func resetPreventsSameAccountABAOverwrite() async throws {
        let service = TickTickResetRaceService()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = TickTickSyncStore(directoryURL: directory, region: .international)
        let engine = TickTickSyncEngine(
            region: .international,
            service: service,
            store: store,
            minimumPollInterval: 60
        )
        let oldCredentials = TickTickTokenSet(
            accessToken: "old-token",
            expiresAt: nil,
            scope: "tasks:read",
            accountID: "same-account",
            region: .international,
            ownerUserID: "user-1"
        )
        let newCredentials = TickTickTokenSet(
            accessToken: "new-token",
            expiresAt: nil,
            scope: "tasks:read",
            accountID: "same-account",
            region: .international,
            ownerUserID: "user-1"
        )

        let oldSync = Task {
            try await engine.taskItems(
                credentials: oldCredentials,
                selectedProjectIDs: ["p1"],
                now: Date(timeIntervalSince1970: 100),
                force: true
            )
        }
        await service.waitUntilOldProjectsRequestStarts()

        try await engine.reset()
        let newItems = try await engine.taskItems(
            credentials: newCredentials,
            selectedProjectIDs: ["p1"],
            now: Date(timeIntervalSince1970: 200),
            force: true
        )
        await service.releaseOldProjectsRequest()
        _ = try await oldSync.value

        let state = try await store.load()
        #expect(newItems.compactMap { $0.externalReference?.itemID } == ["new-task"])
        #expect(state.accountID == "same-account")
        #expect(state.snapshots["p1"]?.tasks.map(\.id) == ["new-task"])
        #expect(state.lastPollAt == Date(timeIntervalSince1970: 200))
    }
}

private actor TickTickOAuthAudit {
    private var values: [String] = []

    func append(_ value: String) { values.append(value) }
    func events() -> [String] { values }
}

private actor TickTickPendingStoreSpy: TickTickPendingAuthorizationStoring {
    private var value: TickTickPendingAuthorization?
    private let audit: TickTickOAuthAudit

    init(audit: TickTickOAuthAudit) { self.audit = audit }

    func load() async throws -> TickTickPendingAuthorization? { value }

    func save(_ pending: TickTickPendingAuthorization) async throws {
        value = pending
        await audit.append(pending.delivery == nil ? "pending" : "pending-delivery")
    }

    func clear() async throws {
        value = nil
        await audit.append("pending-clear")
    }
}

private actor TickTickTokenStoreSpy: TickTickTokenStoring {
    private var value: TickTickTokenSet?
    private let audit: TickTickOAuthAudit

    init(audit: TickTickOAuthAudit) { self.audit = audit }

    func load() async throws -> TickTickTokenSet? { value }

    func save(_ tokens: TickTickTokenSet) async throws {
        value = tokens
        await audit.append("token")
    }

    func clear() async throws { value = nil }
}

private actor TickTickOAuthBackendSpy: TickTickOAuthBackendServing {
    private let audit: TickTickOAuthAudit
    private let failAcknowledgement: Bool
    private let failCleanup: Bool

    init(
        audit: TickTickOAuthAudit,
        failAcknowledgement: Bool = false,
        failCleanup: Bool = false
    ) {
        self.audit = audit
        self.failAcknowledgement = failAcknowledgement
        self.failCleanup = failCleanup
    }

    func start(region: TickTickRegion) async throws -> TickTickAuthorizationStart {
        fatalError("Not used")
    }

    func claim(attemptID: String, claimSecret: String) async throws -> TickTickTokenDelivery {
        await audit.append("claim")
        return TickTickTokenDelivery(
            deliveryID: "delivery-1",
            tokens: TickTickTokenSet(
                accessToken: "token",
                expiresAt: nil,
                scope: "tasks:read",
                accountID: "connection-1",
                region: .international,
                ownerUserID: ""
            )
        )
    }

    func acknowledge(attemptID: String, claimSecret: String, deliveryID: String) async throws {
        await audit.append("ack")
        if failAcknowledgement { throw TickTickAuthError.deliveryAcknowledgementFailed }
    }

    func cancel(attemptID: String, claimSecret: String) async throws {
        if failCleanup { throw URLError(.notConnectedToInternet) }
    }

    func disconnect(connectionID: String) async throws {
        if failCleanup { throw URLError(.notConnectedToInternet) }
    }
}

private actor TickTickReadServiceSpy: TickTickReadServing {
    private var calls = 0
    private var etags: [String?] = []

    func projects(accessToken: String) async throws -> [TickTickProject] {
        [TickTickProject(id: "p1", name: "Work", color: nil, sortOrder: 0, closed: false, groupID: nil, viewMode: "list", permission: "write")]
    }

    func projectData(
        projectID: String,
        accessToken: String,
        ifNoneMatch: String?
    ) async throws -> TickTickConditionalProjectData {
        calls += 1
        etags.append(ifNoneMatch)
        if calls > 1 { return .notModified }
        return .modified(
            data: TickTickProjectData(
                project: TickTickProject(id: "p1", name: "Work", color: nil, sortOrder: 0, closed: false, groupID: nil, viewMode: "list", permission: "write"),
                tasks: [.fixture],
                columns: []
            ),
            etag: "etag-1"
        )
    }

    func projectDataCalls() -> Int { calls }
    func receivedETags() -> [String?] { etags }
}

private actor TickTickResetRaceService: TickTickReadServing {
    private var oldProjectsRelease: CheckedContinuation<Void, Never>?
    private var oldProjectsStartWaiters: [CheckedContinuation<Void, Never>] = []

    func projects(accessToken: String) async throws -> [TickTickProject] {
        if accessToken == "old-token" {
            await withCheckedContinuation { continuation in
                oldProjectsRelease = continuation
                let waiters = oldProjectsStartWaiters
                oldProjectsStartWaiters.removeAll(keepingCapacity: true)
                waiters.forEach { $0.resume() }
            }
        }
        return [Self.project]
    }

    func projectData(
        projectID: String,
        accessToken: String,
        ifNoneMatch: String?
    ) async throws -> TickTickConditionalProjectData {
        let task = TickTickTask(
            id: accessToken == "old-token" ? "old-task" : "new-task",
            projectID: projectID,
            title: "Task",
            content: nil,
            description: nil,
            isAllDay: true,
            startDate: nil,
            dueDate: nil,
            timeZone: nil,
            repeatFlag: nil,
            priority: 0,
            status: 0,
            sortOrder: 0,
            modifiedTime: nil,
            etag: nil
        )
        return .modified(
            data: TickTickProjectData(project: Self.project, tasks: [task], columns: []),
            etag: accessToken
        )
    }

    func waitUntilOldProjectsRequestStarts() async {
        guard oldProjectsRelease == nil else { return }
        await withCheckedContinuation { continuation in
            oldProjectsStartWaiters.append(continuation)
        }
    }

    func releaseOldProjectsRequest() {
        let continuation = oldProjectsRelease
        oldProjectsRelease = nil
        continuation?.resume()
    }

    private static let project = TickTickProject(
        id: "p1",
        name: "Work",
        color: nil,
        sortOrder: 0,
        closed: false,
        groupID: nil,
        viewMode: "list",
        permission: "write"
    )
}

private extension TickTickTask {
    static let fixture = TickTickTask(
        id: "t1",
        projectID: "p1",
        title: "Task",
        content: nil,
        description: nil,
        isAllDay: true,
        startDate: nil,
        dueDate: nil,
        timeZone: nil,
        repeatFlag: nil,
        priority: 0,
        status: 0,
        sortOrder: 0,
        modifiedTime: nil,
        etag: nil
    )
}
