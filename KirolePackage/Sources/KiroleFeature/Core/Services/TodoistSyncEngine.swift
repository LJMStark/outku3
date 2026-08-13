import CryptoKit
import Foundation

public struct TodoistSyncState: Codable, Sendable, Equatable {
    public var syncToken: String?
    public var accountID: String?
    public var itemsByID: [String: TodoistItem]
    public var projectsByID: [String: TodoistProject]
    public var outbox: [TodoistOutboxEntry]
    public var lastSyncAt: Date?

    public init(
        syncToken: String? = nil,
        accountID: String? = nil,
        itemsByID: [String: TodoistItem] = [:],
        projectsByID: [String: TodoistProject] = [:],
        outbox: [TodoistOutboxEntry] = [],
        lastSyncAt: Date? = nil
    ) {
        self.syncToken = syncToken
        self.accountID = accountID
        self.itemsByID = itemsByID
        self.projectsByID = projectsByID
        self.outbox = outbox
        self.lastSyncAt = lastSyncAt
    }
}

public actor TodoistSyncStore {
    private let fileURL: URL

    public init(directoryURL: URL? = nil) {
        let directory = directoryURL ?? Self.defaultDirectoryURL()
        fileURL = directory.appendingPathComponent("todoist-sync-state.json")
    }

    public func load() throws -> TodoistSyncState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return TodoistSyncState()
        }
        return try JSONDecoder().decode(TodoistSyncState.self, from: Data(contentsOf: fileURL))
    }

    public func save(_ state: TodoistSyncState) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(state).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    public func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }

    private static func defaultDirectoryURL() -> URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return applicationSupport
            .appendingPathComponent("com.kirole.app", isDirectory: true)
            .appendingPathComponent("ProviderSync", isDirectory: true)
    }
}

public actor TodoistSyncEngine {
    public static let shared = TodoistSyncEngine()

    private let service: any TodoistSyncServing
    private let store: TodoistSyncStore
    private let maxBackoffExponent: Int
    private var isSyncing = false
    private var exclusiveSyncWaiters: [CheckedContinuation<Void, Never>] = []
    private var verifiedAccessTokenDigest: Data?
    private var operationGeneration: UInt64 = 0
    private var isResetting = false

    public init(
        service: any TodoistSyncServing = TodoistAPI.shared,
        store: TodoistSyncStore = TodoistSyncStore(),
        maxBackoffExponent: Int = 8
    ) {
        self.service = service
        self.store = store
        self.maxBackoffExponent = max(1, maxBackoffExponent)
    }

    /// Returns provider records so callers can map them with the authenticated account ID.
    /// The first full response is immediately followed by an incremental catch-up because
    /// Todoist documents that large-account full snapshots may lag recent writes.
    public func synchronize(accessToken: String, now: Date = Date()) async throws -> [TodoistItem] {
        guard !isSyncing else {
            return try await currentItems()
        }
        isSyncing = true
        defer { releaseExclusiveSyncSlot() }
        return try await performSynchronization(
            accessToken: accessToken,
            now: now,
            requiringCommandID: nil
        )
    }

    private func performSynchronization(
        accessToken: String,
        now: Date,
        requiringCommandID: UUID?
    ) async throws -> [TodoistItem] {
        var state = try await store.load()
        // Verify each access token once per process before it may flush writes. This catches an
        // account switch while avoiding a rate-limited full `user` request on every foreground
        // refresh. A refreshed/re-authorized token has a different digest and is verified again.
        let tokenDigest = Data(SHA256.hash(data: Data(accessToken.utf8)))
        if verifiedAccessTokenDigest != tokenDigest || state.accountID == nil {
            let identity = try await service.sync(
                accessToken: accessToken,
                syncToken: "*",
                resourceTypes: ["user"],
                commands: []
            )
            guard let remoteAccountID = identity.user?.id, !remoteAccountID.isEmpty else {
                throw TodoistSyncEngineError.missingAccountID
            }
            Self.reconcileAccount(remoteAccountID, state: &state)
            try await store.save(state)
            verifiedAccessTokenDigest = tokenDigest
        }
        let flushResult = try await flushOutbox(state, accessToken: accessToken, now: now)
        state = flushResult.state

        let requestedToken = state.syncToken ?? "*"
        let first = try await service.sync(
            accessToken: accessToken,
            syncToken: requestedToken,
            resourceTypes: ["items", "projects", "user"],
            commands: []
        )
        Self.apply(first, to: &state)

        if requestedToken == "*" {
            let catchUp = try await service.sync(
                accessToken: accessToken,
                syncToken: first.syncToken,
                resourceTypes: ["items", "projects", "user"],
                commands: []
            )
            Self.apply(catchUp, to: &state)
        }

        state.lastSyncAt = now
        try await store.save(state)
        if let requiringCommandID,
           let commandFailure = flushResult.failuresByEntryID[requiringCommandID] {
            throw commandFailure
        }
        return Self.visibleItems(in: state)
    }

    public func taskItems(
        accessToken: String,
        selectedProjectIDs: Set<String>? = nil,
        now: Date = Date()
    ) async throws -> [TaskItem] {
        let items = try await synchronize(accessToken: accessToken, now: now)
        let state = try await store.load()
        guard let accountID = state.accountID else { throw TodoistSyncEngineError.missingAccountID }
        return items
            .filter { selectedProjectIDs?.contains($0.projectID) ?? true }
            .map { $0.taskItem(accountID: accountID) }
    }

    public func currentProjects() async throws -> [TodoistProject] {
        let state = try await store.load()
        return state.projectsByID.values
            .filter { !$0.isDeleted && !$0.isArchived }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func enqueueCompletion(
        itemID: String,
        accountID: String,
        completed: Bool
    ) async throws -> UUID {
        var state = try await store.load()
        if let existing = state.outbox.last(where: {
            $0.accountID == accountID && $0.itemID == itemID
        }), existing.completed == completed {
            return existing.id
        }
        state.outbox.removeAll { $0.accountID == accountID && $0.itemID == itemID }
        let entry = TodoistOutboxEntry(
            accountID: accountID,
            itemID: itemID,
            completed: completed
        )
        state.outbox.append(entry)
        try await store.save(state)
        return entry.id
    }

    /// Persists the desired completion state before attempting the network request, then only
    /// returns after this exact idempotent command is acknowledged by the authenticated account.
    public func pushCompletion(
        itemID: String,
        accountID: String,
        completed: Bool,
        accessToken: String,
        now: Date = Date()
    ) async throws {
        let capturedGeneration = operationGeneration
        guard !isResetting else { throw TodoistSyncEngineError.staleOperation }
        await acquireExclusiveSyncSlot()
        defer { releaseExclusiveSyncSlot() }
        guard capturedGeneration == operationGeneration,
              !isResetting else {
            throw TodoistSyncEngineError.staleOperation
        }

        let commandID = try await enqueueCompletion(
            itemID: itemID,
            accountID: accountID,
            completed: completed
        )
        _ = try await performSynchronization(
            accessToken: accessToken,
            now: now,
            requiringCommandID: commandID
        )
    }

    public func currentItems() async throws -> [TodoistItem] {
        Self.visibleItems(in: try await store.load())
    }

    public func reset() async throws {
        operationGeneration &+= 1
        isResetting = true
        defer { isResetting = false }
        await acquireExclusiveSyncSlot()
        defer { releaseExclusiveSyncSlot() }
        verifiedAccessTokenDigest = nil
        try await store.clear()
    }

    private func acquireExclusiveSyncSlot() async {
        while isSyncing {
            await withCheckedContinuation { continuation in
                exclusiveSyncWaiters.append(continuation)
            }
        }
        isSyncing = true
    }

    private func releaseExclusiveSyncSlot() {
        isSyncing = false
        let waiters = exclusiveSyncWaiters
        exclusiveSyncWaiters.removeAll(keepingCapacity: true)
        waiters.forEach { $0.resume() }
    }

    func exclusiveSyncWaiterCount() -> Int {
        exclusiveSyncWaiters.count
    }

    private struct OutboxFlushResult {
        let state: TodoistSyncState
        let failuresByEntryID: [UUID: TodoistSyncEngineError]
    }

    private func flushOutbox(
        _ input: TodoistSyncState,
        accessToken: String,
        now: Date
    ) async throws -> OutboxFlushResult {
        var state = input
        var failuresByEntryID: [UUID: TodoistSyncEngineError] = [:]
        let authenticatedAccountID = state.accountID
        for entry in state.outbox where entry.accountID != authenticatedAccountID {
            failuresByEntryID[entry.id] = .commandAccountMismatch(
                expected: entry.accountID,
                authenticated: authenticatedAccountID
            )
        }
        for entry in state.outbox
        where entry.accountID == authenticatedAccountID
            && (entry.nextAttemptAt ?? .distantPast) > now {
            failuresByEntryID[entry.id] = .commandDeferred(until: entry.nextAttemptAt ?? now)
        }

        let dueEntries = state.outbox.filter {
            $0.accountID == authenticatedAccountID
                && ($0.nextAttemptAt ?? .distantPast) <= now
        }
        guard !dueEntries.isEmpty else {
            return OutboxFlushResult(state: state, failuresByEntryID: failuresByEntryID)
        }

        do {
            let response = try await service.sync(
                accessToken: accessToken,
                syncToken: state.syncToken ?? "*",
                resourceTypes: [],
                commands: dueEntries.map(\.command)
            )
            let dueIDs = Set(dueEntries.map(\.id))
            var retryByID: [UUID: TodoistOutboxEntry] = [:]
            for entry in dueEntries {
                let status = response.syncStatus[entry.command.uuid]
                if status?.isSuccess != true {
                    retryByID[entry.id] = entry.retrying(
                        after: now,
                        maxBackoffExponent: maxBackoffExponent
                    )
                    failuresByEntryID[entry.id] = .commandRejected(
                        message: Self.commandFailureDescription(status)
                    )
                }
            }
            state.outbox = state.outbox.compactMap { entry in
                guard dueIDs.contains(entry.id) else { return entry }
                return retryByID[entry.id]
            }
        } catch {
            let dueIDs = Set(dueEntries.map(\.id))
            state.outbox = state.outbox.map { entry in
                guard dueIDs.contains(entry.id) else { return entry }
                failuresByEntryID[entry.id] = .commandRequestFailed(
                    message: error.localizedDescription
                )
                return entry.retrying(
                    after: now,
                    maxBackoffExponent: maxBackoffExponent
                )
            }
        }

        try await store.save(state)
        return OutboxFlushResult(state: state, failuresByEntryID: failuresByEntryID)
    }

    private static func apply(_ response: TodoistSyncResponse, to state: inout TodoistSyncState) {
        reconcileAccount(response.user?.id, state: &state)
        if response.fullSync {
            state.itemsByID.removeAll(keepingCapacity: true)
            state.projectsByID.removeAll(keepingCapacity: true)
        }
        for project in response.projects {
            if project.isDeleted || project.isArchived {
                state.projectsByID.removeValue(forKey: project.id)
            } else {
                state.projectsByID[project.id] = project
            }
        }
        for item in response.items {
            if item.isDeleted {
                state.itemsByID.removeValue(forKey: item.id)
            } else {
                state.itemsByID[item.id] = item
            }
        }
        state.syncToken = response.syncToken
    }

    private static func reconcileAccount(_ remoteAccountID: String?, state: inout TodoistSyncState) {
        guard let remoteAccountID else { return }
        if let persistedAccountID = state.accountID, remoteAccountID != persistedAccountID {
            state.syncToken = nil
            state.itemsByID.removeAll(keepingCapacity: false)
            state.projectsByID.removeAll(keepingCapacity: false)
        }
        state.accountID = remoteAccountID
    }

    private static func commandFailureDescription(_ result: TodoistCommandResult?) -> String {
        guard let result else { return "Todoist did not acknowledge the command" }
        switch result {
        case .ok:
            return "Todoist rejected the command"
        case .error(let code, let message):
            let codeDescription = code.map { "code \($0)" } ?? "unknown code"
            return message.map { "\(codeDescription): \($0)" } ?? codeDescription
        }
    }

    private static func visibleItems(in state: TodoistSyncState) -> [TodoistItem] {
        state.itemsByID.values
            .filter { $0.isRootTask && !$0.isDeleted }
            .sorted { lhs, rhs in
                let lhsDue = lhs.due?.resolvedDate ?? .distantFuture
                let rhsDue = rhs.due?.resolvedDate ?? .distantFuture
                if lhsDue != rhsDue { return lhsDue < rhsDue }
                return lhs.id < rhs.id
            }
    }
}

public enum TodoistSyncEngineError: LocalizedError, Sendable, Equatable {
    case staleOperation
    case missingAccountID
    case commandRejected(message: String)
    case commandRequestFailed(message: String)
    case commandAccountMismatch(expected: String, authenticated: String?)
    case commandDeferred(until: Date)

    public var errorDescription: String? {
        switch self {
        case .staleOperation:
            "Todoist operation was invalidated by a local reset"
        case .missingAccountID:
            "Todoist sync did not return an account identifier"
        case .commandRejected(let message):
            "Todoist rejected the queued change: \(message)"
        case .commandRequestFailed(let message):
            "Todoist could not send the queued change: \(message)"
        case .commandAccountMismatch(let expected, let authenticated):
            "Todoist queued change belongs to account \(expected), not \(authenticated ?? "the authenticated account")"
        case .commandDeferred(let until):
            "Todoist queued change is waiting to retry after \(until.formatted())"
        }
    }
}
