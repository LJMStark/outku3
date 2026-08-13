import Foundation

struct MicrosoftSyncState: Codable, Sendable, Equatable {
    var accountID: String?
    var outlookWindowStart: Date?
    var outlookWindowEnd: Date?
    var outlookDeltaLink: String?
    var todoListsDeltaLink: String?
    var todoListIDs: [String]
    var todoTaskDeltaLinks: [String: String]

    init(
        accountID: String? = nil,
        outlookWindowStart: Date? = nil,
        outlookWindowEnd: Date? = nil,
        outlookDeltaLink: String? = nil,
        todoListsDeltaLink: String? = nil,
        todoListIDs: [String] = [],
        todoTaskDeltaLinks: [String: String] = [:]
    ) {
        self.accountID = accountID
        self.outlookWindowStart = outlookWindowStart
        self.outlookWindowEnd = outlookWindowEnd
        self.outlookDeltaLink = outlookDeltaLink
        self.todoListsDeltaLink = todoListsDeltaLink
        self.todoListIDs = todoListIDs
        self.todoTaskDeltaLinks = todoTaskDeltaLinks
    }
}

struct MicrosoftTodoOutboxEntry: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let accountID: String
    let listID: String
    let taskID: String
    let targetStatus: MicrosoftTodoStatus
    let createdAt: Date
    var retryCount: Int

    init(
        id: UUID = UUID(),
        accountID: String,
        listID: String,
        taskID: String,
        targetStatus: MicrosoftTodoStatus,
        createdAt: Date = Date(),
        retryCount: Int = 0
    ) {
        self.id = id
        self.accountID = accountID
        self.listID = listID
        self.taskID = taskID
        self.targetStatus = targetStatus
        self.createdAt = createdAt
        self.retryCount = retryCount
    }
}

/// Actor-isolated, atomically written provider state. OAuth credentials remain in Keychain;
/// opaque delta links and idempotent target-state outbox entries live in app Documents storage.
actor MicrosoftSyncStateStore {
    static let shared = MicrosoftSyncStateStore()

    private let directoryURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var stateCache: MicrosoftSyncState?
    private var outboxCache: [MicrosoftTodoOutboxEntry]?
    private var operationEpoch: UInt64 = 0

    private var stateURL: URL {
        directoryURL.appendingPathComponent("microsoft_sync_state.json", isDirectory: false)
    }

    private var outboxURL: URL {
        directoryURL.appendingPathComponent("microsoft_todo_outbox.json", isDirectory: false)
    }

    init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func loadState() throws -> MicrosoftSyncState {
        if let stateCache { return stateCache }
        let state = try load(MicrosoftSyncState.self, from: stateURL) ?? MicrosoftSyncState()
        stateCache = state
        return state
    }

    func saveState(_ state: MicrosoftSyncState) throws {
        try save(state, to: stateURL)
        stateCache = state
    }

    func saveState(_ state: MicrosoftSyncState, expectedEpoch: UInt64) throws {
        try requireCurrentEpoch(expectedEpoch)
        try saveState(state)
    }

    func loadOutbox() throws -> [MicrosoftTodoOutboxEntry] {
        if let outboxCache { return outboxCache }
        let outbox = try load([MicrosoftTodoOutboxEntry].self, from: outboxURL) ?? []
        outboxCache = outbox
        return outbox
    }

    func saveOutbox(_ outbox: [MicrosoftTodoOutboxEntry]) throws {
        try save(outbox, to: outboxURL)
        outboxCache = outbox
    }

    func enqueue(_ entry: MicrosoftTodoOutboxEntry) throws {
        var outbox = try loadOutbox()
        // A status patch is an idempotent target-state write. Keep only the newest intended state
        // for one task; repeated UI actions must not replay stale completion state later.
        outbox.removeAll {
            $0.accountID == entry.accountID
                && $0.listID == entry.listID
                && $0.taskID == entry.taskID
        }
        outbox.append(entry)
        try saveOutbox(outbox)
    }

    func enqueue(_ entry: MicrosoftTodoOutboxEntry, expectedEpoch: UInt64) throws {
        try requireCurrentEpoch(expectedEpoch)
        try enqueue(entry)
    }

    /// Atomically drops previous-account writes. Keeping load + save inside one actor turn avoids
    /// overwriting a current-account entry enqueued while the sync engine is suspended elsewhere.
    func retainOutbox(forAccountID accountID: String) throws {
        let outbox: [MicrosoftTodoOutboxEntry]
        do {
            outbox = try loadOutbox()
        } catch {
            throw MicrosoftSyncStoreIOFailure(
                operation: .loadOutbox,
                underlyingDescription: error.localizedDescription
            )
        }
        do {
            try saveOutbox(outbox.filter { $0.accountID == accountID })
        } catch {
            throw MicrosoftSyncStoreIOFailure(
                operation: .saveOutbox,
                underlyingDescription: error.localizedDescription
            )
        }
    }

    func retainOutbox(forAccountID accountID: String, expectedEpoch: UInt64) throws {
        try requireCurrentEpoch(expectedEpoch)
        try retainOutbox(forAccountID: accountID)
    }

    /// Commits one network attempt without erasing an intent enqueued while that request awaited.
    /// A newer entry for the same task wins over the retry copy from the older attempt.
    func commitOutboxAttempt(
        attempted: [MicrosoftTodoOutboxEntry],
        retrying: [MicrosoftTodoOutboxEntry]
    ) throws {
        let attemptedIDs = Set(attempted.map(\.id))
        var outbox = try loadOutbox().filter { !attemptedIDs.contains($0.id) }
        for retry in retrying {
            let hasNewerIntent = outbox.contains {
                $0.accountID == retry.accountID
                    && $0.listID == retry.listID
                    && $0.taskID == retry.taskID
            }
            if !hasNewerIntent {
                outbox.append(retry)
            }
        }
        try saveOutbox(outbox)
    }

    func commitOutboxAttempt(
        attempted: [MicrosoftTodoOutboxEntry],
        retrying: [MicrosoftTodoOutboxEntry],
        expectedEpoch: UInt64
    ) throws {
        try requireCurrentEpoch(expectedEpoch)
        try commitOutboxAttempt(attempted: attempted, retrying: retrying)
    }

    /// Removes only the confirmed target state. A newer opposite toggle for the same task remains.
    func removeOutboxEntries(matching successful: MicrosoftTodoOutboxEntry) throws {
        let outbox = try loadOutbox()
        try saveOutbox(outbox.filter {
            !($0.accountID == successful.accountID
                && $0.listID == successful.listID
                && $0.taskID == successful.taskID
                && $0.targetStatus == successful.targetStatus)
        })
    }

    func removeOutboxEntries(
        matching successful: MicrosoftTodoOutboxEntry,
        expectedEpoch: UInt64
    ) throws {
        try requireCurrentEpoch(expectedEpoch)
        try removeOutboxEntries(matching: successful)
    }

    func currentOperationEpoch() -> UInt64 {
        operationEpoch
    }

    func invalidateOperations() {
        operationEpoch &+= 1
    }

    func reset() throws {
        invalidateOperations()
        stateCache = MicrosoftSyncState()
        outboxCache = []
        try removeIfPresent(stateURL)
        try removeIfPresent(outboxURL)
    }

    private func requireCurrentEpoch(_ expectedEpoch: UInt64) throws {
        guard operationEpoch == expectedEpoch else {
            throw MicrosoftSyncStoreEpochMismatch()
        }
    }

    private func save<Value: Encodable>(_ value: Value, to url: URL) throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func load<Value: Decodable>(_ type: Value.Type, from url: URL) throws -> Value? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(type, from: data)
    }

    private func removeIfPresent(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}

struct MicrosoftSyncStoreIOFailure: LocalizedError, Sendable {
    let operation: MicrosoftSyncStateIOOperation
    let underlyingDescription: String

    var errorDescription: String? {
        "Microsoft sync store I/O failed during \(operation.rawValue): \(underlyingDescription)"
    }
}

struct MicrosoftSyncStoreEpochMismatch: Error, Sendable {}
