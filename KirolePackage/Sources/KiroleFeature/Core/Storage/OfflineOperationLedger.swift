import Foundation

/// Durable state for one device-originated offline operation.
enum OfflineOperationLedgerState: String, Codable, Sendable, Equatable {
    /// The operation identity and original bytes are durable, but its App mutation is not yet
    /// known to be durable. An exact retry must resume instead of being acknowledged as done.
    case pending
    /// The App mutation is durable. An exact retry is a duplicate and must not run again.
    case committed
}

/// The protocol-defined idempotency identity. Event type and payload are deliberately excluded:
/// reusing this exact key with different operation bytes is a conflict, not a second operation.
struct OfflineOperationLedgerKey: Codable, Hashable, Sendable {
    let deviceID: String
    let bootSessionID: UInt32
    let operationID: UInt32
}

/// Write-ahead record preserving the original device operation bytes for conflict detection.
struct OfflineOperationLedgerEntry: Codable, Sendable, Equatable {
    let deviceID: String
    let bootSessionID: UInt32
    let operationID: UInt32
    let eventType: UInt8
    let originalPayload: Data
    let state: OfflineOperationLedgerState
    let recordedAt: Date

    init(
        deviceID: String,
        bootSessionID: UInt32,
        operationID: UInt32,
        eventType: UInt8,
        originalPayload: Data,
        state: OfflineOperationLedgerState,
        recordedAt: Date
    ) {
        self.deviceID = deviceID
        self.bootSessionID = bootSessionID
        self.operationID = operationID
        self.eventType = eventType
        self.originalPayload = originalPayload
        self.state = state
        self.recordedAt = recordedAt
    }

    var key: OfflineOperationLedgerKey {
        OfflineOperationLedgerKey(
            deviceID: deviceID,
            bootSessionID: bootSessionID,
            operationID: operationID
        )
    }

    func matches(eventType: UInt8, originalPayload: Data) -> Bool {
        self.eventType == eventType && self.originalPayload == originalPayload
    }

    func withState(_ state: OfflineOperationLedgerState) -> OfflineOperationLedgerEntry {
        OfflineOperationLedgerEntry(
            deviceID: deviceID,
            bootSessionID: bootSessionID,
            operationID: operationID,
            eventType: eventType,
            originalPayload: originalPayload,
            state: state,
            recordedAt: recordedAt
        )
    }
}

enum OfflineOperationLedgerReservation: Sendable, Equatable {
    /// A pending marker was written before the caller may mutate App state.
    case new(OfflineOperationLedgerEntry)
    /// An exact operation already has a pending marker and must resume idempotently.
    case resume(OfflineOperationLedgerEntry)
    /// An exact operation is durably committed and must not run again.
    case duplicate(OfflineOperationLedgerEntry)
    /// The key exists, but event type or the original payload differs.
    case conflict
    /// The ledger could not be loaded or made durable, so no App mutation may run.
    case unavailable
}

protocol OfflineOperationLedgerPersisting: Sendable {
    func loadOfflineOperationLedger() async throws -> [OfflineOperationLedgerEntry]?
    func saveOfflineOperationLedger(_ entries: [OfflineOperationLedgerEntry]) async throws
}

private struct LocalOfflineOperationLedgerPersistence: OfflineOperationLedgerPersisting {
    func loadOfflineOperationLedger() async throws -> [OfflineOperationLedgerEntry]? {
        try await LocalStorage.shared.loadOfflineOperationLedger()
    }

    func saveOfflineOperationLedger(_ entries: [OfflineOperationLedgerEntry]) async throws {
        try await LocalStorage.shared.saveOfflineOperationLedger(entries)
    }
}

/// Durable write-ahead ledger for the `0x25 OP_BATCH` business operations.
///
/// Entries stay on disk because the protocol does not provide a safe expiry point. Removing one
/// could turn an arbitrarily delayed device retry into a second App mutation.
actor OfflineOperationLedger {
    static let shared = OfflineOperationLedger()

    private let persistenceEnabled: Bool
    private let persistence: any OfflineOperationLedgerPersisting
    private var entries: [OfflineOperationLedgerEntry]?
    private var loadingTask: Task<[OfflineOperationLedgerEntry], any Error>?
    private var pendingPersistenceTask: Task<Void, any Error>?
    private var persistenceGeneration: UInt64 = 0

    init(
        persistenceEnabled: Bool = true,
        initialEntries: [OfflineOperationLedgerEntry]? = nil,
        persistence: any OfflineOperationLedgerPersisting = LocalOfflineOperationLedgerPersistence()
    ) {
        self.persistenceEnabled = persistenceEnabled
        self.entries = initialEntries
        self.persistence = persistence
    }

    /// Atomically checks the full operation identity and writes a pending marker before returning
    /// `.new`. The caller must not change App state for `.conflict` or `.unavailable`.
    func reserve(
        deviceID: String,
        bootSessionID: UInt32,
        operationID: UInt32,
        eventType: UInt8,
        originalPayload: Data,
        now: Date = Date()
    ) async -> OfflineOperationLedgerReservation {
        guard await loadIfNeeded() else { return .unavailable }
        let key = OfflineOperationLedgerKey(
            deviceID: deviceID,
            bootSessionID: bootSessionID,
            operationID: operationID
        )

        if let existing = entry(for: key) {
            guard existing.matches(eventType: eventType, originalPayload: originalPayload) else {
                return .conflict
            }

            if existing.state == .committed {
                do {
                    try await awaitLatestPersistenceIfNeeded()
                } catch {
                    reportPersistenceFailure(error, operation: "duplicate")
                    return .unavailable
                }

                // A failed concurrent commit restores pending state after its save fails. Re-read
                // after suspension instead of acknowledging an in-memory-only committed marker.
                guard let durableEntry = entry(for: key),
                      durableEntry.matches(
                          eventType: eventType,
                          originalPayload: originalPayload
                      ) else {
                    return .conflict
                }
                if durableEntry.state == .committed {
                    return .duplicate(durableEntry)
                }
            }

            do {
                // A prior reserve may have failed after publishing its pending marker in memory.
                // An exact retry flushes the current snapshot before it is allowed to resume.
                try await persistCurrentEntriesIfNeeded()
            } catch {
                reportPersistenceFailure(error, operation: "resume")
                return .unavailable
            }
            guard let pendingEntry = entry(for: key),
                  pendingEntry.matches(eventType: eventType, originalPayload: originalPayload) else {
                return .conflict
            }
            return pendingEntry.state == .committed
                ? .duplicate(pendingEntry)
                : .resume(pendingEntry)
        }

        let newEntry = OfflineOperationLedgerEntry(
            deviceID: deviceID,
            bootSessionID: bootSessionID,
            operationID: operationID,
            eventType: eventType,
            originalPayload: originalPayload,
            state: .pending,
            recordedAt: now
        )
        entries?.append(newEntry)

        // Publish pending in actor state before suspension. Re-entrant calls can now only observe
        // resume/duplicate/conflict; they cannot reserve the same identity as a second new entry.
        do {
            try await persistCurrentEntriesIfNeeded()
        } catch {
            // Keep pending in memory. An exact retry will attempt to flush it before resuming.
            reportPersistenceFailure(error, operation: "reserve")
            return .unavailable
        }
        return .new(newEntry)
    }

    /// Marks an operation committed only after the caller has durably applied its App mutation.
    /// Returns false for missing/conflicting operations or any persistence failure.
    func commit(
        deviceID: String,
        bootSessionID: UInt32,
        operationID: UInt32,
        eventType: UInt8,
        originalPayload: Data
    ) async -> Bool {
        guard await loadIfNeeded() else { return false }
        let key = OfflineOperationLedgerKey(
            deviceID: deviceID,
            bootSessionID: bootSessionID,
            operationID: operationID
        )
        guard let existing = entry(for: key),
              existing.matches(eventType: eventType, originalPayload: originalPayload) else {
            return false
        }

        if existing.state == .committed {
            do {
                try await awaitLatestPersistenceIfNeeded()
                return entry(for: key)?.state == .committed
            } catch {
                reportPersistenceFailure(error, operation: "commit")
                return false
            }
        }

        guard let index = entries?.lastIndex(where: { $0.key == key }) else { return false }
        let committedEntry = existing.withState(.committed)
        entries?[index] = committedEntry
        do {
            try await persistCurrentEntriesIfNeeded()
            return true
        } catch {
            // The disk still contains pending. Restore pending in memory so a retry cannot be
            // mistaken for a committed duplicate that exists only in this process.
            if entries?[index] == committedEntry {
                entries?[index] = existing
            }
            reportPersistenceFailure(error, operation: "commit")
            return false
        }
    }

    private func entry(for key: OfflineOperationLedgerKey) -> OfflineOperationLedgerEntry? {
        entries?.last(where: { $0.key == key })
    }

    private func loadIfNeeded() async -> Bool {
        if entries != nil { return true }
        guard persistenceEnabled else {
            entries = []
            return true
        }

        let task: Task<[OfflineOperationLedgerEntry], any Error>
        if let loadingTask {
            task = loadingTask
        } else {
            let persistence = self.persistence
            task = Task {
                try await persistence.loadOfflineOperationLedger() ?? []
            }
            loadingTask = task
        }

        do {
            let loaded = try await task.value
            // Another waiter can reserve while this actor call is suspended. Never replace a
            // newer in-memory snapshot with the same older disk load.
            if entries == nil {
                entries = loaded
            }
            loadingTask = nil
            return true
        } catch {
            loadingTask = nil
            ErrorReporter.log(
                .persistence(
                    operation: "load",
                    target: "offline_operation_ledger.json",
                    underlying: error.localizedDescription
                ),
                context: "OfflineOperationLedger.load"
            )
            return false
        }
    }

    private func persistCurrentEntriesIfNeeded() async throws {
        guard persistenceEnabled else { return }
        let snapshot = entries ?? []
        let predecessor = pendingPersistenceTask
        let persistence = self.persistence
        persistenceGeneration &+= 1
        let generation = persistenceGeneration
        let task = Task {
            if let predecessor {
                // Never write a newer snapshot after an earlier durability boundary failed.
                // The caller will leave the in-memory entries resumable and a later retry starts
                // a fresh chain from the last known durable file.
                try await predecessor.value
            }
            try await persistence.saveOfflineOperationLedger(snapshot)
        }
        pendingPersistenceTask = task
        do {
            try await task.value
            if persistenceGeneration == generation {
                pendingPersistenceTask = nil
            }
        } catch {
            if persistenceGeneration == generation {
                pendingPersistenceTask = nil
            }
            throw error
        }
    }

    private func awaitLatestPersistenceIfNeeded() async throws {
        guard persistenceEnabled, let pendingPersistenceTask else { return }
        try await pendingPersistenceTask.value
    }

    private func reportPersistenceFailure(_ error: Error, operation: String) {
        ErrorReporter.log(
            .persistence(
                operation: "save",
                target: "offline_operation_ledger.json",
                underlying: error.localizedDescription
            ),
            context: "OfflineOperationLedger.\(operation)"
        )
    }
}
