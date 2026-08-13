import Foundation
import os

private final class TickTickSyncOperationGate: Sendable {
    private struct State: Sendable {
        var generation: UInt64 = 0
        var resettingGeneration: UInt64?
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    func beginOperation() -> UInt64 {
        lock.withLock { $0.generation }
    }

    func isCurrent(_ generation: UInt64) -> Bool {
        lock.withLock {
            $0.generation == generation && $0.resettingGeneration == nil
        }
    }

    func beginReset() -> UInt64 {
        lock.withLock { state in
            state.generation &+= 1
            state.resettingGeneration = state.generation
            return state.generation
        }
    }

    func withLock<T: Sendable>(_ operation: @Sendable () throws -> T) rethrows -> T {
        try lock.withLock { _ in try operation() }
    }

    func writeIfCurrent(
        _ generation: UInt64,
        operation: @Sendable () throws -> Void
    ) throws -> Bool {
        try lock.withLock { state in
            guard state.generation == generation,
                  state.resettingGeneration == nil else {
                return false
            }
            try operation()
            return true
        }
    }

    func completeReset(
        _ generation: UInt64,
        operation: @Sendable () throws -> Void
    ) throws {
        try lock.withLock { state in
            guard state.generation == generation,
                  state.resettingGeneration == generation else {
                return
            }
            defer { state.resettingGeneration = nil }
            try operation()
        }
    }
}

private enum TickTickSyncOperationGateRegistry {
    private static let lock = OSAllocatedUnfairLock(
        initialState: [String: TickTickSyncOperationGate]()
    )

    static func gate(for fileURL: URL) -> TickTickSyncOperationGate {
        let key = fileURL.standardizedFileURL.path
        return lock.withLock { gates in
            if let existing = gates[key] { return existing }
            let gate = TickTickSyncOperationGate()
            gates[key] = gate
            return gate
        }
    }
}

public struct TickTickProjectSnapshot: Codable, Sendable, Equatable {
    public let project: TickTickProject
    public let tasks: [TickTickTask]
    public let etag: String?

    public init(project: TickTickProject, tasks: [TickTickTask], etag: String?) {
        self.project = project
        self.tasks = tasks
        self.etag = etag
    }
}

public struct TickTickSyncState: Codable, Sendable, Equatable {
    public var region: TickTickRegion
    public var accountID: String?
    public var selectedProjectIDs: Set<String>
    public var snapshots: [String: TickTickProjectSnapshot]
    public var lastPollAt: Date?

    public init(
        region: TickTickRegion,
        accountID: String? = nil,
        selectedProjectIDs: Set<String> = [],
        snapshots: [String: TickTickProjectSnapshot] = [:],
        lastPollAt: Date? = nil
    ) {
        self.region = region
        self.accountID = accountID
        self.selectedProjectIDs = selectedProjectIDs
        self.snapshots = snapshots
        self.lastPollAt = lastPollAt
    }
}

public actor TickTickSyncStore {
    private let fileURL: URL
    private let region: TickTickRegion
    private let operationGate: TickTickSyncOperationGate

    public init(directoryURL: URL? = nil, region: TickTickRegion) {
        self.region = region
        let directory = directoryURL ?? Self.defaultDirectoryURL()
        let fileURL = directory.appendingPathComponent("ticktick-\(region.rawValue)-sync-state.json")
        self.fileURL = fileURL
        operationGate = TickTickSyncOperationGateRegistry.gate(for: fileURL)
    }

    public func load() throws -> TickTickSyncState {
        let fileURL = fileURL
        let region = region
        return try operationGate.withLock {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                return TickTickSyncState(region: region)
            }
            let state = try JSONDecoder().decode(TickTickSyncState.self, from: Data(contentsOf: fileURL))
            guard state.region == region else { throw TickTickSyncError.regionMismatch }
            return state
        }
    }

    public func save(_ state: TickTickSyncState) throws {
        guard state.region == region else { throw TickTickSyncError.regionMismatch }
        let fileURL = fileURL
        try operationGate.withLock {
            try Self.persist(state, to: fileURL)
        }
    }

    func save(_ state: TickTickSyncState, ifCurrent generation: UInt64) throws -> Bool {
        guard state.region == region else { throw TickTickSyncError.regionMismatch }
        let fileURL = fileURL
        return try operationGate.writeIfCurrent(generation) {
            try Self.persist(state, to: fileURL)
        }
    }

    nonisolated func beginOperation() -> UInt64 {
        operationGate.beginOperation()
    }

    nonisolated func isCurrentOperation(_ generation: UInt64) -> Bool {
        operationGate.isCurrent(generation)
    }

    nonisolated func beginReset() -> UInt64 {
        operationGate.beginReset()
    }

    func completeReset(_ generation: UInt64) throws {
        let fileURL = fileURL
        try operationGate.completeReset(generation) {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    private nonisolated static func persist(_ state: TickTickSyncState, to fileURL: URL) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(state).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    public func clear() throws {
        let resetGeneration = operationGate.beginReset()
        let fileURL = fileURL
        try operationGate.completeReset(resetGeneration) {
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    private static func defaultDirectoryURL() -> URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return applicationSupport
            .appendingPathComponent("com.kirole.app", isDirectory: true)
            .appendingPathComponent("ProviderSync", isDirectory: true)
    }
}

public actor TickTickSyncEngine {
    public let region: TickTickRegion

    private let service: any TickTickReadServing
    private let store: TickTickSyncStore
    private let minimumPollInterval: TimeInterval
    private var synchronizingGeneration: UInt64?

    public init(
        region: TickTickRegion,
        service: (any TickTickReadServing)? = nil,
        store: TickTickSyncStore? = nil,
        minimumPollInterval: TimeInterval = 15 * 60
    ) {
        self.region = region
        self.service = service ?? TickTickAPI(region: region)
        self.store = store ?? TickTickSyncStore(region: region)
        self.minimumPollInterval = max(60, minimumPollInterval)
    }

    /// TickTick/Dida currently has no documented cursor or webhook contract. Use a bounded
    /// project snapshot, conditional ETags when available, and conservative polling instead.
    public func synchronize(
        accessToken: String,
        selectedProjectIDs: Set<String>,
        now: Date = Date(),
        force: Bool = false
    ) async throws -> [TickTickTask] {
        let operationGeneration = store.beginOperation()
        return try await synchronize(
            accessToken: accessToken,
            selectedProjectIDs: selectedProjectIDs,
            now: now,
            force: force,
            operationGeneration: operationGeneration
        )
    }

    private func synchronize(
        accessToken: String,
        selectedProjectIDs: Set<String>,
        now: Date,
        force: Bool,
        operationGeneration: UInt64
    ) async throws -> [TickTickTask] {
        guard store.isCurrentOperation(operationGeneration) else {
            return try await currentItems()
        }
        guard synchronizingGeneration != operationGeneration else {
            return try await currentItems()
        }
        synchronizingGeneration = operationGeneration
        defer {
            if synchronizingGeneration == operationGeneration {
                synchronizingGeneration = nil
            }
        }

        var state = try await store.load()
        guard store.isCurrentOperation(operationGeneration) else {
            return try await currentItems()
        }
        let selectionUnchanged = state.selectedProjectIDs == selectedProjectIDs
        if !force,
           selectionUnchanged,
           let lastPollAt = state.lastPollAt,
           now.timeIntervalSince(lastPollAt) < minimumPollInterval {
            return Self.visibleItems(in: state)
        }

        let projects = try await service.projects(accessToken: accessToken)
        guard store.isCurrentOperation(operationGeneration) else {
            return try await currentItems()
        }
        let available = projects.filter { $0.closed != true }
        let requestedIDs = selectedProjectIDs.intersection(available.map(\.id))

        var nextSnapshots: [String: TickTickProjectSnapshot] = [:]
        for project in available where requestedIDs.contains(project.id) {
            guard store.isCurrentOperation(operationGeneration) else {
                return try await currentItems()
            }
            let previous = state.snapshots[project.id]
            let response = try await service.projectData(
                projectID: project.id,
                accessToken: accessToken,
                ifNoneMatch: previous?.etag
            )
            guard store.isCurrentOperation(operationGeneration) else {
                return try await currentItems()
            }
            switch response {
            case .modified(let data, let etag):
                nextSnapshots[project.id] = TickTickProjectSnapshot(
                    project: data.project,
                    tasks: data.tasks,
                    etag: etag
                )
            case .notModified:
                guard let previous else { throw TickTickSyncError.missingSnapshotForNotModified(project.id) }
                nextSnapshots[project.id] = previous
            }
        }

        state.selectedProjectIDs = selectedProjectIDs
        state.snapshots = nextSnapshots
        state.lastPollAt = now
        guard try await store.save(state, ifCurrent: operationGeneration) else {
            return try await currentItems()
        }
        return Self.visibleItems(in: state)
    }

    public func taskItems(
        credentials: TickTickTokenSet,
        selectedProjectIDs: Set<String>,
        now: Date = Date(),
        force: Bool = false
    ) async throws -> [TaskItem] {
        guard credentials.region == region else { throw TickTickSyncError.regionMismatch }
        let operationGeneration = store.beginOperation()
        var state = try await store.load()
        guard store.isCurrentOperation(operationGeneration) else {
            return try await currentItems().map {
                $0.taskItem(accountID: credentials.accountID, region: region)
            }
        }
        if state.accountID != credentials.accountID {
            state = TickTickSyncState(region: region, accountID: credentials.accountID)
            guard try await store.save(state, ifCurrent: operationGeneration) else {
                return try await currentItems().map {
                    $0.taskItem(accountID: credentials.accountID, region: region)
                }
            }
        }
        return try await synchronize(
            accessToken: credentials.accessToken,
            selectedProjectIDs: selectedProjectIDs,
            now: now,
            force: force,
            operationGeneration: operationGeneration
        ).map { $0.taskItem(accountID: credentials.accountID, region: region) }
    }

    public func availableProjects(accessToken: String) async throws -> [TickTickProject] {
        let projects = try await service.projects(accessToken: accessToken)
        return projects
            .filter { $0.closed != true }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder { return (lhs.sortOrder ?? 0) < (rhs.sortOrder ?? 0) }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    public func currentItems() async throws -> [TickTickTask] {
        Self.visibleItems(in: try await store.load())
    }

    public func reset() async throws {
        let resetGeneration = store.beginReset()
        synchronizingGeneration = nil
        try await store.completeReset(resetGeneration)
    }

    private static func visibleItems(in state: TickTickSyncState) -> [TickTickTask] {
        state.snapshots.values
            .flatMap(\.tasks)
            .sorted { lhs, rhs in
                let lhsDue = lhs.resolvedDueDate ?? .distantFuture
                let rhsDue = rhs.resolvedDueDate ?? .distantFuture
                if lhsDue != rhsDue { return lhsDue < rhsDue }
                if lhs.sortOrder != rhs.sortOrder { return (lhs.sortOrder ?? 0) < (rhs.sortOrder ?? 0) }
                return lhs.id < rhs.id
            }
    }
}

public enum TickTickSyncError: LocalizedError, Sendable, Equatable {
    case regionMismatch
    case missingSnapshotForNotModified(String)

    public var errorDescription: String? {
        switch self {
        case .regionMismatch:
            "TickTick region does not match the saved account"
        case .missingSnapshotForNotModified(let projectID):
            "TickTick returned not-modified without a local snapshot for project \(projectID)"
        }
    }
}
