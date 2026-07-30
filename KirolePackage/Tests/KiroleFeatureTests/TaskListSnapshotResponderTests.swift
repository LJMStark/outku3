import Foundation
import Testing
@testable import KiroleFeature

@Suite("Task-list snapshot responder", .serialized)
struct TaskListSnapshotResponderTests {
    @Test("Responder sends the latest Overview tasks without waiting for DayPack")
    @MainActor
    func responderSendsCurrentTasks() async {
        let sender = TaskListSnapshotSenderSpy(screenSize: .fourInch)
        let versions = TaskListSnapshotVersionSequence([
            TaskListSnapshotVersion(epoch: 7, revision: 8),
        ])
        let tasks = [
            TaskItem(id: "done", title: "Done", isCompleted: true, dueDate: Date()),
            TaskItem(id: "open", title: "Open", isCompleted: false, dueDate: Date()),
        ]

        _ = await TaskListSnapshotResponder.respond(
            to: [TaskOperationReceipt(action: .completeTask, operationID: 5, result: .applied)],
            sender: sender,
            versionProvider: versions,
            tasksProvider: { tasks }
        )

        let expected = encodedAck(
            operationID: 5,
            version: TaskListSnapshotVersion(epoch: 7, revision: 8),
            tasks: [TaskSummary(id: "open", title: "Open", isCompleted: false, priority: 1)]
        )
        #expect(sender.sentPayloads == [expected])
    }

    @Test("Snapshot is sampled after the durable version wait while the message gate is held")
    @MainActor
    func snapshotIsReadAfterVersionWait() async {
        let sender = TaskListSnapshotSenderSpy(screenSize: .fourInch)
        let versions = BlockingTaskListSnapshotVersionProvider(
            version: TaskListSnapshotVersion(epoch: 11, revision: 12)
        )
        let source = TaskListSource([
            TaskItem(id: "old", title: "Old", dueDate: Date()),
        ])

        let response = Task { @MainActor in
            await TaskListSnapshotResponder.respond(
                to: [TaskOperationReceipt(action: .completeTask, operationID: 12, result: .applied)],
                sender: sender,
                versionProvider: versions,
                tasksProvider: { source.tasks }
            )
        }
        await versions.waitUntilBlocked()
        source.tasks = [TaskItem(id: "new", title: "New", dueDate: Date())]
        await versions.release()
        _ = await response.value

        let expected = encodedAck(
            operationID: 12,
            version: TaskListSnapshotVersion(epoch: 11, revision: 12),
            tasks: [TaskSummary(id: "new", title: "New", isCompleted: false, priority: 1)]
        )
        #expect(sender.sentPayloads == [expected])
    }

    @Test("A task-version change during acknowledgement preparation sends no stale snapshot")
    @MainActor
    func taskVersionChangeRejectsAcknowledgement() async {
        let sender = TaskListSnapshotSenderSpy(screenSize: .fourInch)
        let versions = BlockingTaskListSnapshotVersionProvider(
            version: TaskListSnapshotVersion(epoch: 11, revision: 13)
        )
        let taskVersion = TaskStateVersionSource(21)

        let response = Task { @MainActor in
            await TaskListSnapshotResponder.respond(
                to: [TaskOperationReceipt(action: .completeTask, operationID: 13, result: .applied)],
                sender: sender,
                versionProvider: versions,
                tasksProvider: { [] },
                expectedTaskStateVersion: 21,
                taskStateVersionProvider: { taskVersion.value }
            )
        }
        await versions.waitUntilBlocked()
        taskVersion.value = 22
        await versions.release()
        let outcome = await response.value

        #expect(outcome == .staleTaskState)
        #expect(sender.sentPayloads.isEmpty)
    }

    @Test("A lost callback retries frozen bytes without letting DayPack enter the gate")
    @MainActor
    func retryKeepsGateAndFrozenBytes() async throws {
        let sender = CoordinatedTaskListSnapshotSender(screenSize: .fourInch)
        let versions = TaskListSnapshotVersionSequence([
            TaskListSnapshotVersion(epoch: 9, revision: 10),
        ])

        let response = Task { @MainActor in
            await TaskListSnapshotResponder.respond(
                to: [TaskOperationReceipt(action: .completeTask, operationID: 7, result: .applied)],
                sender: sender,
                versionProvider: versions,
                tasksProvider: {
                    [TaskItem(id: "frozen", title: "Frozen", dueDate: Date())]
                }
            )
        }
        await sender.waitForFirstAttempt()
        let dayPack = Task { @MainActor in try await sender.simulateDayPackWrite() }
        _ = await response.value
        try await dayPack.value

        #expect(sender.wireOrder == ["ack", "ack", "dayPack"])
        #expect(sender.attemptedPayloads.count == 2)
        #expect(sender.attemptedPayloads[0] == sender.attemptedPayloads[1])
    }

    @Test("Every higher revision resamples the current task list")
    @MainActor
    func eachRevisionResamplesTasks() async {
        let source = TaskListSource([TaskItem(id: "first", title: "First", dueDate: Date())])
        let sender = TaskListSnapshotSenderSpy(screenSize: .fourInch) {
            if source.tasks.first?.id == "first" {
                source.tasks = [TaskItem(id: "second", title: "Second", dueDate: Date())]
            }
        }
        let versions = TaskListSnapshotVersionSequence([
            TaskListSnapshotVersion(epoch: 20, revision: 1),
            TaskListSnapshotVersion(epoch: 20, revision: 2),
        ])

        _ = await TaskListSnapshotResponder.respond(
            to: [
                TaskOperationReceipt(action: .completeTask, operationID: 1, result: .applied),
                TaskOperationReceipt(action: .skipTask, operationID: 2, result: .applied),
            ],
            sender: sender,
            versionProvider: versions,
            tasksProvider: { source.tasks }
        )

        #expect(sender.sentPayloads.count == 2)
        #expect(sender.sentPayloads[0] == encodedAck(
            operationID: 1,
            version: TaskListSnapshotVersion(epoch: 20, revision: 1),
            tasks: [TaskSummary(id: "first", title: "First", isCompleted: false, priority: 1)]
        ))
        #expect(sender.sentPayloads[1] == BLEDataEncoder.encodeTaskListSnapshotAck(TaskListSnapshotAck(
            action: .skipTask,
            operationID: 2,
            result: .applied,
            version: TaskListSnapshotVersion(epoch: 20, revision: 2),
            tasks: [TaskSummary(id: "second", title: "Second", isCompleted: false, priority: 1)]
        )))
    }

    @Test("A version persistence failure sends nothing and releases the message gate")
    @MainActor
    func versionFailureReleasesGate() async throws {
        let sender = CoordinatedTaskListSnapshotSender(
            screenSize: .fourInch,
            failFirstWrite: false
        )

        _ = await TaskListSnapshotResponder.respond(
            to: [TaskOperationReceipt(action: .requestRefresh, operationID: 33, result: .applied)],
            sender: sender,
            versionProvider: FailingTaskListSnapshotVersionProvider(),
            tasksProvider: { [] }
        )
        try await sender.simulateDayPackWrite()

        #expect(sender.attemptedPayloads.isEmpty)
        #expect(sender.wireOrder == ["dayPack"])
    }

    @Test("Snapshot epoch and revision advance in one durable document")
    func versionPersistsAtomically() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let storage = LocalStorage.shared
            let original = try await storage.loadTaskListSnapshotVersion()
            try await storage.saveTaskListSnapshotVersion(
                TaskListSnapshotVersion(epoch: 42, revision: 8)
            )

            let next = try await storage.nextTaskListSnapshotVersion()
            let persisted = try await storage.loadTaskListSnapshotVersion()
            #expect(next == TaskListSnapshotVersion(epoch: 42, revision: 9))
            #expect(persisted == next)

            if let original {
                try await storage.saveTaskListSnapshotVersion(original)
            } else {
                try await storage.deleteFile(named: "task_list_snapshot_version.json")
            }
        }
    }

    private func encodedAck(
        operationID: UInt32,
        version: TaskListSnapshotVersion,
        tasks: [TaskSummary]
    ) -> Data {
        BLEDataEncoder.encodeTaskListSnapshotAck(TaskListSnapshotAck(
            action: .completeTask,
            operationID: operationID,
            result: .applied,
            version: version,
            tasks: tasks
        ))
    }
}

@MainActor
private final class TaskListSource {
    var tasks: [TaskItem]

    init(_ tasks: [TaskItem]) {
        self.tasks = tasks
    }
}

@MainActor
private final class TaskStateVersionSource {
    var value: UInt64

    init(_ value: UInt64) {
        self.value = value
    }
}

@MainActor
private final class TaskListSnapshotSenderSpy: TaskListSnapshotSending {
    let hardwareScreenSize: ScreenSize
    private(set) var sentPayloads: [Data] = []
    private let afterWrite: (@MainActor () -> Void)?

    init(screenSize: ScreenSize, afterWrite: (@MainActor () -> Void)? = nil) {
        self.hardwareScreenSize = screenSize
        self.afterWrite = afterWrite
    }

    func withTaskStateMessageGate(
        _ operation: @MainActor @Sendable () async throws -> Void
    ) async throws {
        try await operation()
    }

    func writeTaskListSnapshotAckPayload(
        _ payload: Data,
        expectedTaskStateVersion: UInt64?
    ) async throws {
        sentPayloads.append(payload)
        afterWrite?()
    }
}

@MainActor
private final class CoordinatedTaskListSnapshotSender: TaskListSnapshotSending {
    let hardwareScreenSize: ScreenSize
    private let gate = BLEWriteGate()
    private let failFirstWrite: Bool
    private var firstAttemptContinuation: CheckedContinuation<Void, Never>?
    private(set) var attemptedPayloads: [Data] = []
    private(set) var wireOrder: [String] = []

    init(screenSize: ScreenSize, failFirstWrite: Bool = true) {
        self.hardwareScreenSize = screenSize
        self.failFirstWrite = failFirstWrite
    }

    func withTaskStateMessageGate(
        _ operation: @MainActor @Sendable () async throws -> Void
    ) async throws {
        try await gate.acquire()
        do {
            try await operation()
        } catch {
            await gate.release()
            throw error
        }
        await gate.release()
    }

    func writeTaskListSnapshotAckPayload(
        _ payload: Data,
        expectedTaskStateVersion: UInt64?
    ) async throws {
        attemptedPayloads.append(payload)
        wireOrder.append("ack")
        if attemptedPayloads.count == 1 {
            firstAttemptContinuation?.resume()
            firstAttemptContinuation = nil
            if failFirstWrite {
                throw SnapshotResponderTestError.lostWriteCallback
            }
        }
    }

    func waitForFirstAttempt() async {
        guard attemptedPayloads.isEmpty else { return }
        await withCheckedContinuation { continuation in
            firstAttemptContinuation = continuation
        }
    }

    func simulateDayPackWrite() async throws {
        try await gate.acquire()
        wireOrder.append("dayPack")
        await gate.release()
    }
}

private actor TaskListSnapshotVersionSequence: TaskListSnapshotVersionProviding {
    private var versions: [TaskListSnapshotVersion]

    init(_ versions: [TaskListSnapshotVersion]) {
        self.versions = versions
    }

    func nextTaskListSnapshotVersion() throws -> TaskListSnapshotVersion {
        guard !versions.isEmpty else { throw SnapshotResponderTestError.noVersion }
        return versions.removeFirst()
    }
}

private actor BlockingTaskListSnapshotVersionProvider: TaskListSnapshotVersionProviding {
    private let version: TaskListSnapshotVersion
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var isBlocked = false

    init(version: TaskListSnapshotVersion) {
        self.version = version
    }

    func nextTaskListSnapshotVersion() async throws -> TaskListSnapshotVersion {
        isBlocked = true
        startedContinuation?.resume()
        startedContinuation = nil
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
        return version
    }

    func waitUntilBlocked() async {
        guard !isBlocked else { return }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private struct FailingTaskListSnapshotVersionProvider: TaskListSnapshotVersionProviding {
    func nextTaskListSnapshotVersion() async throws -> TaskListSnapshotVersion {
        throw SnapshotResponderTestError.versionPersistenceFailed
    }
}

private enum SnapshotResponderTestError: Error {
    case lostWriteCallback
    case noVersion
    case versionPersistenceFailed
}
