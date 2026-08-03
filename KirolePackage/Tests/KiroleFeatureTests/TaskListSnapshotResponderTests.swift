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
            tasksProvider: { tasks },
            taskStateVersionProvider: { 0 }
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
                tasksProvider: { source.tasks },
                taskStateVersionProvider: { 0 }
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

    @Test("An attempted response stale before its first write is rebuilt for the same request")
    @MainActor
    func attemptedResponseStaleBeforeFirstWriteIsRebuilt() async throws {
        let now = Date()
        let deliveryVersion = TaskListSnapshotVersion(epoch: 51, revision: 7)
        let deliveryStore = TaskListSnapshotDeliveryStoreSpy(version: deliveryVersion)
        let taskVersion = TaskStateVersionSource(70)
        let sender = TaskListSnapshotSenderSpy(
            screenSize: .fourInch,
            blockFirstWriteAfterAttempt: true,
            taskStateVersionProvider: { taskVersion.value }
        )
        let source = TaskListSource([
            TaskItem(id: "version-70", title: "Version 70", dueDate: now),
        ])
        let receipt = TaskOperationReceipt(
            action: .completeTask,
            operationID: 913,
            result: .applied
        )
        let firstResponse = Task { @MainActor in
            await TaskListSnapshotResponder.respond(
                to: [receipt],
                sender: sender,
                deliveryStore: deliveryStore,
                tasksProvider: { source.tasks },
                nowProvider: { now },
                expectedTaskStateVersion: 70,
                taskStateVersionProvider: { taskVersion.value }
            )
        }
        try await sender.waitUntilFirstWriteIsBlocked()
        #expect(await deliveryStore.invocationCounts() == [1, 0, 1])
        #expect(sender.sentPayloads.isEmpty)
        taskVersion.value = 71
        source.tasks = [
            TaskItem(id: "version-71", title: "Version 71", dueDate: now),
        ]
        sender.releaseFirstWrite()
        let staleOutcome = await firstResponse.value
        #expect(staleOutcome == .staleTaskState)
        #expect(sender.sentPayloads.isEmpty)
        let recoveredOutcome = await TaskListSnapshotResponder.respond(
            to: [receipt],
            sender: sender,
            deliveryStore: deliveryStore,
            tasksProvider: { source.tasks },
            nowProvider: { now },
            expectedTaskStateVersion: 71,
            taskStateVersionProvider: { taskVersion.value }
        )
        let expected = encodedAck(
            operationID: 913,
            version: deliveryVersion,
            tasks: [
                TaskSummary(
                    id: "version-71",
                    title: "Version 71",
                    isCompleted: false,
                    priority: 1
                ),
            ]
        )

        #expect(recoveredOutcome == .sent)
        #expect(sender.sentPayloads == [expected])
        #expect(await deliveryStore.invocationCounts() == [2, 1, 2])
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
                },
                taskStateVersionProvider: { 0 }
            )
        }
        await sender.waitForFirstAttempt()
        let dayPack = Task { @MainActor in try await sender.simulateDayPackWrite() }
        _ = await response.value
        try await dayPack.value

        #expect(sender.wireOrder == ["ack", "ack", "dayPack"])
        #expect(sender.attemptedPayloads.count == 2)
        if sender.attemptedPayloads.count == 2 {
            #expect(sender.attemptedPayloads[0] == sender.attemptedPayloads[1])
        }
    }

    @Test("A later response for the same operation reuses the durable frozen bytes")
    @MainActor
    func laterResponseReusesDurableFrozenBytes() async {
        let sender = RecoveringTaskListSnapshotSender(
            screenSize: .fourInch,
            failuresRemaining: 2
        )
        let versions = TaskListSnapshotVersionSequence([
            TaskListSnapshotVersion(epoch: 40, revision: 1),
            TaskListSnapshotVersion(epoch: 40, revision: 2),
        ])
        let frozenResponses = InMemoryTaskListSnapshotDeliveryStore(
            versionProvider: versions
        )
        let source = TaskListSource([
            TaskItem(id: "first", title: "First", dueDate: Date()),
        ])
        let receipt = TaskOperationReceipt(
            action: .requestRefresh,
            operationID: 61,
            result: .applied
        )

        let failed = await TaskListSnapshotResponder.respond(
            to: [receipt],
            sender: sender,
            versionProvider: versions,
            deliveryStore: frozenResponses,
            tasksProvider: { source.tasks },
            retrySleeper: { _ in },
            taskStateVersionProvider: { 0 }
        )
        source.tasks = [TaskItem(id: "changed", title: "Changed", dueDate: Date())]
        let recovered = await TaskListSnapshotResponder.respond(
            to: [receipt],
            sender: sender,
            versionProvider: versions,
            deliveryStore: frozenResponses,
            tasksProvider: { source.tasks },
            retrySleeper: { _ in },
            taskStateVersionProvider: { 0 }
        )

        #expect(failed == .failed)
        #expect(recovered == .sent)
        #expect(sender.attemptedPayloads.count == 3)
        #expect(sender.attemptedPayloads.allSatisfy {
            $0 == sender.attemptedPayloads.first
        })
        #expect(await versions.requestCount() == 1)
        #expect(await frozenResponses.frozenResponseCount() == 0)
    }

    @Test("A cleanup save failure after delivery does not block the next operation")
    @MainActor
    func cleanupFailureDoesNotBlockNextOperation() async {
        let firstVersion = TaskListSnapshotVersion(epoch: 52, revision: 7)
        let deliveryStore = TaskListSnapshotDeliveryStoreSpy(
            version: firstVersion,
            completionFailuresRemaining: 1
        )
        let sender = TaskListSnapshotSenderSpy(screenSize: .fourInch)

        let firstOutcome = await TaskListSnapshotResponder.respond(
            to: [
                TaskOperationReceipt(
                    action: .completeTask,
                    operationID: 914,
                    result: .applied
                ),
            ],
            sender: sender,
            deliveryStore: deliveryStore,
            tasksProvider: { [] },
            retrySleeper: { _ in },
            taskStateVersionProvider: { 0 }
        )
        let secondOutcome = await TaskListSnapshotResponder.respond(
            to: [
                TaskOperationReceipt(
                    action: .completeTask,
                    operationID: 915,
                    result: .applied
                ),
            ],
            sender: sender,
            deliveryStore: deliveryStore,
            tasksProvider: { [] },
            retrySleeper: { _ in },
            taskStateVersionProvider: { 0 }
        )

        #expect(firstOutcome == .sent)
        #expect(secondOutcome == .sent)
        #expect(sender.sentPayloads == [
            encodedAck(operationID: 914, version: firstVersion, tasks: []),
            encodedAck(
                operationID: 915,
                version: TaskListSnapshotVersion(epoch: firstVersion.epoch, revision: 8),
                tasks: []
            ),
        ])
    }

    @Test("A transient delivery-marker failure retries persistence without resending ACK bytes")
    @MainActor
    func deliveryMarkerRetryDoesNotResendAcknowledgement() async {
        let deliveryStore = TaskListSnapshotDeliveryStoreSpy(
            version: TaskListSnapshotVersion(epoch: 53, revision: 1),
            deliveryConfirmationFailuresRemaining: 1
        )
        let sender = TaskListSnapshotSenderSpy(screenSize: .fourInch)
        let retrySleeps = DurationRecorder()

        let outcome = await TaskListSnapshotResponder.respond(
            to: [
                TaskOperationReceipt(
                    action: .requestRefresh,
                    operationID: 916,
                    result: .applied
                ),
            ],
            sender: sender,
            deliveryStore: deliveryStore,
            tasksProvider: { [] },
            retrySleeper: { _ in },
            deliveryConfirmationAttempts: 2,
            deliveryConfirmationRetrySleeper: { duration in
                await retrySleeps.record(duration)
            },
            taskStateVersionProvider: { 0 }
        )

        #expect(outcome == .sent)
        #expect(sender.sentPayloads.count == 1)
        #expect(await deliveryStore.deliveryConfirmationInvocationCount() == 2)
        #expect(await retrySleeps.snapshot() == [.milliseconds(250)])
    }

    @Test("Exhausted delivery-marker retries fail closed without resending ACK bytes")
    @MainActor
    func exhaustedDeliveryMarkerRetriesStayAttempted() async throws {
        let destinationID = "single-active-device"
        let deliveryStore = TaskListSnapshotDeliveryStoreSpy(
            version: TaskListSnapshotVersion(epoch: 54, revision: 1),
            deliveryConfirmationFailuresRemaining: 2
        )
        let sender = TaskListSnapshotSenderSpy(screenSize: .fourInch)
        let retrySleeps = DurationRecorder()

        let outcome = await TaskListSnapshotResponder.respond(
            to: [
                TaskOperationReceipt(
                    action: .requestRefresh,
                    operationID: 917,
                    result: .applied
                ),
            ],
            sender: sender,
            deliveryStore: deliveryStore,
            tasksProvider: { [] },
            retrySleeper: { _ in },
            deliveryConfirmationAttempts: 2,
            deliveryConfirmationRetrySleeper: { duration in
                await retrySleeps.record(duration)
            },
            taskStateVersionProvider: { 0 }
        )

        #expect(outcome == .failed)
        #expect(sender.sentPayloads.count == 1)
        #expect(await deliveryStore.deliveryConfirmationInvocationCount() == 2)
        #expect(await retrySleeps.snapshot() == [.milliseconds(250)])
        #expect(try await deliveryStore.hasAttemptedTaskListSnapshotDelivery(
            for: destinationID
        ))
    }

    @Test("Every higher revision resamples the current task list")
    @MainActor
    func eachRevisionResamplesTasks() async {
        let source = TaskListSource([TaskItem(id: "first", title: "First", dueDate: Date())])
        let sender = TaskListSnapshotSenderSpy(screenSize: .fourInch, afterWrite: {
            if source.tasks.first?.id == "first" {
                source.tasks = [TaskItem(id: "second", title: "Second", dueDate: Date())]
            }
        })
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
            tasksProvider: { source.tasks },
            taskStateVersionProvider: { 0 }
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

    @Test("Offline replay acknowledges every record directly in wire order")
    @MainActor
    func replayUsesOrderedAcknowledgementsWithoutDayPackPresentation() async {
        let sender = TaskListSnapshotSenderSpy(screenSize: .fourInch)
        let versions = TaskListSnapshotVersionSequence([
            TaskListSnapshotVersion(epoch: 30, revision: 1),
            TaskListSnapshotVersion(epoch: 30, revision: 2),
        ])

        let outcome = await BLEEventHandler.respondToReplayedTaskOperations(
            [
                TaskOperationReceipt(action: .completeTask, operationID: 501, result: .applied),
                TaskOperationReceipt(action: .skipTask, operationID: 502, result: .alreadyApplied),
            ],
            sender: sender,
            versionProvider: versions,
            deliveryStore: nil,
            tasksProvider: { [] },
            taskStateVersionProvider: { 0 }
        )

        #expect(outcome == .sent)
        #expect(sender.sentPayloads == [
            BLEDataEncoder.encodeTaskListSnapshotAck(TaskListSnapshotAck(
                action: .completeTask,
                operationID: 501,
                result: .applied,
                version: TaskListSnapshotVersion(epoch: 30, revision: 1),
                tasks: []
            )),
            BLEDataEncoder.encodeTaskListSnapshotAck(TaskListSnapshotAck(
                action: .skipTask,
                operationID: 502,
                result: .alreadyApplied,
                version: TaskListSnapshotVersion(epoch: 30, revision: 2),
                tasks: []
            )),
        ])
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
            tasksProvider: { [] },
            taskStateVersionProvider: { 0 }
        )
        try await sender.simulateDayPackWrite()

        #expect(sender.attemptedPayloads.isEmpty)
        #expect(sender.wireOrder == ["dayPack"])
    }

    @Test("Snapshot delivery versions advance independently for each destination")
    func deliveryStateIsPartitionedByDestination() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            try await withCleanTaskListSnapshotDeliveryFile { storage in
                let deviceAFirst = try await persistSuccessfulDelivery(
                    storage: storage,
                    destinationID: "device-a",
                    operationID: 1,
                    payloadByte: 0xA1
                )
                let deviceASecond = try await persistSuccessfulDelivery(
                    storage: storage,
                    destinationID: "device-a",
                    operationID: 2,
                    payloadByte: 0xA2
                )
                let deviceBFirst = try await persistSuccessfulDelivery(
                    storage: storage,
                    destinationID: "device-b",
                    operationID: 1,
                    payloadByte: 0xB1
                )

                #expect(deviceAFirst.revision == 1)
                #expect(deviceASecond == TaskListSnapshotVersion(
                    epoch: deviceAFirst.epoch,
                    revision: 2
                ))
                #expect(deviceBFirst.revision == 1)
                #expect(deviceBFirst.epoch != deviceAFirst.epoch)
            }
        }
    }

    @Test("Snapshot reservation, frozen bytes, and version share one durable document")
    func deliveryStatePersistsAtomically() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            try await withCleanTaskListSnapshotDeliveryFile { storage in
                try await storage.saveTaskListSnapshotVersion(
                    TaskListSnapshotVersion(epoch: 42, revision: 8)
                )
                let key = TaskListSnapshotRequestKey(
                    destinationID: "delivery-state-test",
                    action: .requestRefresh,
                    operationID: 700
                )

                let preparation = try await storage.prepareTaskListSnapshotDelivery(for: key)
                guard case .reserved(let firstVersion) = preparation else {
                    throw SnapshotResponderTestError.invalidDeliveryState
                }
                #expect(firstVersion.revision == 1)
                #expect(firstVersion.epoch != 42)
                let response = FrozenTaskListSnapshotResponse(
                    key: key,
                    version: firstVersion,
                    payload: Data([0x01, 0x20, 0xAA])
                )
                try await storage.freezeTaskListSnapshotDelivery(response)
                try await storage.markTaskListSnapshotDeliveryAttempted(response)

                #expect(try await storage.loadTaskListSnapshotVersion() == TaskListSnapshotVersion(
                    epoch: 42,
                    revision: 8
                ))
                #expect(
                    try await storage.prepareTaskListSnapshotDelivery(for: key) == .frozen(response)
                )
                // The wire contract does not make OperationID globally monotonic. A numerically
                // larger different key must not supersede an uncertain response.
                let numericallyHigherKey = TaskListSnapshotRequestKey(
                    destinationID: "delivery-state-test",
                    action: .requestRefresh,
                    operationID: 701
                )
                await #expect(throws: (any Error).self) {
                    try await storage.prepareTaskListSnapshotDelivery(for: numericallyHigherKey)
                }
                try await storage.markTaskListSnapshotDeliveryDelivered(response)
                #expect(
                    try await storage.prepareTaskListSnapshotDelivery(for: key) == .frozen(response)
                )

                let nextKey = TaskListSnapshotRequestKey(
                    destinationID: "delivery-state-test",
                    action: .requestRefresh,
                    operationID: 701
                )
                #expect(
                    try await storage.prepareTaskListSnapshotDelivery(for: nextKey) == .reserved(
                        TaskListSnapshotVersion(epoch: firstVersion.epoch, revision: 2)
                    )
                )
            }
        }
    }

    @Test("Attempted-delivery lookup is durable per destination and propagates decode errors")
    func attemptedDeliveryLookupFailsClosed() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            try await withCleanTaskListSnapshotDeliveryFile { storage in
                let destinationID = "attempted-query-device"
                let key = TaskListSnapshotRequestKey(
                    destinationID: destinationID,
                    action: .requestRefresh,
                    operationID: 720
                )

                #expect(try await storage.hasAttemptedTaskListSnapshotDelivery(
                    for: destinationID
                ) == false)
                guard case .reserved(let version) = try await storage
                    .prepareTaskListSnapshotDelivery(for: key) else {
                    throw SnapshotResponderTestError.invalidDeliveryState
                }
                let response = FrozenTaskListSnapshotResponse(
                    key: key,
                    version: version,
                    payload: Data([0x01, 0x20, 0xBB])
                )
                try await storage.freezeTaskListSnapshotDelivery(response)
                #expect(try await storage.hasAttemptedTaskListSnapshotDelivery(
                    for: destinationID
                ) == false)
                try await storage.markTaskListSnapshotDeliveryAttempted(response)
                #expect(try await storage.hasAttemptedTaskListSnapshotDelivery(
                    for: destinationID
                ))
                #expect(try await storage.hasAttemptedTaskListSnapshotDelivery(
                    for: "other-device"
                ) == false)
                try await storage.markTaskListSnapshotDeliveryDelivered(response)
                #expect(try await storage.hasAttemptedTaskListSnapshotDelivery(
                    for: destinationID
                ) == false)

                try Data([0xFF, 0x00, 0xAA]).write(
                    to: try taskListSnapshotDeliveryFileURL(),
                    options: .atomic
                )
                await #expect(throws: (any Error).self) {
                    try await storage.hasAttemptedTaskListSnapshotDelivery(
                        for: destinationID
                    )
                }
            }
        }
    }

    @MainActor
    private func withCleanTaskListSnapshotDeliveryFile<T>(
        _ operation: (LocalStorage) async throws -> T
    ) async throws -> T {
        let storage = LocalStorage.shared
        let fileURL = try taskListSnapshotDeliveryFileURL()
        let originalData = FileManager.default.fileExists(atPath: fileURL.path)
            ? try Data(contentsOf: fileURL)
            : nil
        try await storage.deleteFile(named: fileURL.lastPathComponent)
        do {
            let result = try await operation(storage)
            try restoreTaskListSnapshotDeliveryFile(originalData, at: fileURL)
            return result
        } catch {
            try restoreTaskListSnapshotDeliveryFile(originalData, at: fileURL)
            throw error
        }
    }

    private func taskListSnapshotDeliveryFileURL() throws -> URL {
        let documentsDirectory = try #require(FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first)
        return documentsDirectory.appendingPathComponent("task_list_snapshot_version.json")
    }

    private func restoreTaskListSnapshotDeliveryFile(
        _ originalData: Data?,
        at fileURL: URL
    ) throws {
        if let originalData {
            try originalData.write(to: fileURL, options: .atomic)
        } else if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    private func persistSuccessfulDelivery(
        storage: LocalStorage,
        destinationID: String,
        operationID: UInt32,
        payloadByte: UInt8
    ) async throws -> TaskListSnapshotVersion {
        let key = TaskListSnapshotRequestKey(
            destinationID: destinationID,
            action: .requestRefresh,
            operationID: operationID
        )
        guard case .reserved(let version) = try await storage
            .prepareTaskListSnapshotDelivery(for: key) else {
            throw SnapshotResponderTestError.invalidDeliveryState
        }
        let response = FrozenTaskListSnapshotResponse(
            key: key,
            version: version,
            payload: Data([payloadByte])
        )
        try await storage.freezeTaskListSnapshotDelivery(response)
        try await storage.markTaskListSnapshotDeliveryAttempted(response)
        try await storage.markTaskListSnapshotDeliveryDelivered(response)
        try await storage.completeTaskListSnapshotDelivery(response)
        return version
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
    private let blockFirstWriteAfterAttempt: Bool
    private let taskStateVersionProvider: (@MainActor () -> UInt64)?
    private let afterWrite: (@MainActor () -> Void)?
    private var didBlockFirstWrite = false
    private var isFirstWriteReleased = false

    init(
        screenSize: ScreenSize,
        blockFirstWriteAfterAttempt: Bool = false,
        taskStateVersionProvider: (@MainActor () -> UInt64)? = nil,
        afterWrite: (@MainActor () -> Void)? = nil
    ) {
        self.hardwareScreenSize = screenSize
        self.blockFirstWriteAfterAttempt = blockFirstWriteAfterAttempt
        self.taskStateVersionProvider = taskStateVersionProvider
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

    func writeTaskListSnapshotAckPayload(
        _ payload: Data,
        expectedTaskStateVersion: UInt64?,
        beforeFirstWrite: @escaping @MainActor @Sendable () async throws -> Void
    ) async throws {
        try await beforeFirstWrite()
        if blockFirstWriteAfterAttempt, !didBlockFirstWrite {
            didBlockFirstWrite = true
            let deadline = ContinuousClock.now + .seconds(1)
            while !isFirstWriteReleased {
                guard ContinuousClock.now < deadline else {
                    throw SnapshotResponderTestError.firstWriteWaitTimedOut
                }
                try await Task.sleep(for: .milliseconds(5))
            }
        }
        if let expectedTaskStateVersion,
           let currentTaskStateVersion = taskStateVersionProvider?(),
           currentTaskStateVersion != expectedTaskStateVersion {
            throw TaskListSnapshotWriteError.staleBeforeFirstWrite
        }
        try await writeTaskListSnapshotAckPayload(
            payload,
            expectedTaskStateVersion: expectedTaskStateVersion
        )
    }

    func waitUntilFirstWriteIsBlocked(timeout: Duration = .seconds(1)) async throws {
        let deadline = ContinuousClock.now + timeout
        while !didBlockFirstWrite {
            guard ContinuousClock.now < deadline else {
                throw SnapshotResponderTestError.firstWriteWaitTimedOut
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    func releaseFirstWrite() {
        isFirstWriteReleased = true
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

@MainActor
private final class RecoveringTaskListSnapshotSender: TaskListSnapshotSending {
    let hardwareScreenSize: ScreenSize
    private var failuresRemaining: Int
    private(set) var attemptedPayloads: [Data] = []

    init(screenSize: ScreenSize, failuresRemaining: Int) {
        self.hardwareScreenSize = screenSize
        self.failuresRemaining = failuresRemaining
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
        attemptedPayloads.append(payload)
        guard failuresRemaining > 0 else { return }
        failuresRemaining -= 1
        throw SnapshotResponderTestError.lostWriteCallback
    }
}

private actor TaskListSnapshotVersionSequence: TaskListSnapshotVersionProviding {
    private var versions: [TaskListSnapshotVersion]
    private var requests = 0

    init(_ versions: [TaskListSnapshotVersion]) {
        self.versions = versions
    }

    func nextTaskListSnapshotVersion() throws -> TaskListSnapshotVersion {
        guard !versions.isEmpty else { throw SnapshotResponderTestError.noVersion }
        requests += 1
        return versions.removeFirst()
    }

    func requestCount() -> Int {
        requests
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

private actor TaskListSnapshotDeliveryStoreSpy: TaskListSnapshotDeliveryStoring {
    private struct Reservation {
        let key: TaskListSnapshotRequestKey
        let version: TaskListSnapshotVersion
    }

    private var completionFailuresRemaining: Int
    private var deliveryConfirmationFailuresRemaining: Int
    private var reservation: Reservation?
    private var preparedResponse: FrozenTaskListSnapshotResponse?
    private var attemptedResponse: FrozenTaskListSnapshotResponse?
    private var deliveredResponse: FrozenTaskListSnapshotResponse?
    private var nextVersion: TaskListSnapshotVersion
    private var freezeInvocations = 0
    private var rewindInvocations = 0
    private var attemptInvocations = 0
    private var deliveryConfirmationInvocations = 0

    init(
        version: TaskListSnapshotVersion,
        completionFailuresRemaining: Int = 0,
        deliveryConfirmationFailuresRemaining: Int = 0
    ) {
        self.completionFailuresRemaining = completionFailuresRemaining
        self.deliveryConfirmationFailuresRemaining = deliveryConfirmationFailuresRemaining
        self.nextVersion = version
    }
    func prepareTaskListSnapshotDelivery(
        for key: TaskListSnapshotRequestKey
    ) throws -> TaskListSnapshotDeliveryPreparation {
        if let attemptedResponse {
            guard attemptedResponse.key == key else {
                throw SnapshotResponderTestError.invalidDeliveryState
            }
            return .frozen(attemptedResponse)
        }
        if let deliveredResponse {
            if deliveredResponse.key == key {
                return .frozen(deliveredResponse)
            }
            self.deliveredResponse = nil
        }
        guard preparedResponse == nil else {
            throw SnapshotResponderTestError.unwrittenDeliveryWasNotRewound
        }
        if let reservation {
            guard reservation.key == key else {
                throw SnapshotResponderTestError.invalidDeliveryState
            }
            return .reserved(reservation.version)
        }
        reservation = Reservation(key: key, version: nextVersion)
        return .reserved(nextVersion)
    }
    func freezeTaskListSnapshotDelivery(
        _ response: FrozenTaskListSnapshotResponse
    ) throws {
        guard reservation?.key == response.key,
              reservation?.version == response.version else {
            throw SnapshotResponderTestError.invalidDeliveryState
        }
        reservation = nil
        preparedResponse = response
        if response.version.revision < UInt32.max {
            nextVersion = TaskListSnapshotVersion(
                epoch: response.version.epoch,
                revision: response.version.revision + 1
            )
        }
        freezeInvocations += 1
    }
    func markTaskListSnapshotDeliveryAttempted(
        _ response: FrozenTaskListSnapshotResponse
    ) throws {
        if attemptedResponse == response { return }
        guard preparedResponse == response else {
            throw SnapshotResponderTestError.invalidDeliveryState
        }
        preparedResponse = nil
        attemptedResponse = response
        attemptInvocations += 1
    }

    func rewindUnwrittenTaskListSnapshotDelivery(
        _ response: FrozenTaskListSnapshotResponse
    ) throws {
        guard preparedResponse == response || attemptedResponse == response else {
            throw SnapshotResponderTestError.invalidDeliveryState
        }
        preparedResponse = nil
        attemptedResponse = nil
        reservation = Reservation(key: response.key, version: response.version)
        rewindInvocations += 1
    }

    func markTaskListSnapshotDeliveryDelivered(
        _ response: FrozenTaskListSnapshotResponse
    ) throws {
        deliveryConfirmationInvocations += 1
        if deliveryConfirmationFailuresRemaining > 0 {
            deliveryConfirmationFailuresRemaining -= 1
            throw SnapshotResponderTestError.deliveryConfirmationPersistenceFailed
        }
        if deliveredResponse == response { return }
        guard attemptedResponse == response else {
            throw SnapshotResponderTestError.invalidDeliveryState
        }
        attemptedResponse = nil
        deliveredResponse = response
    }

    func completeTaskListSnapshotDelivery(
        _ response: FrozenTaskListSnapshotResponse
    ) throws {
        guard deliveredResponse == response else {
            throw SnapshotResponderTestError.invalidDeliveryState
        }
        if completionFailuresRemaining > 0 {
            completionFailuresRemaining -= 1
            throw SnapshotResponderTestError.cleanupPersistenceFailed
        }
        deliveredResponse = nil
    }

    func invocationCounts() -> [Int] {
        [freezeInvocations, rewindInvocations, attemptInvocations]
    }

    func deliveryConfirmationInvocationCount() -> Int {
        deliveryConfirmationInvocations
    }

    func hasAttemptedTaskListSnapshotDelivery(
        for destinationID: String
    ) async throws -> Bool {
        attemptedResponse?.key.destinationID == destinationID
    }
}

private actor DurationRecorder {
    private var durations: [Duration] = []

    func record(_ duration: Duration) {
        durations.append(duration)
    }

    func snapshot() -> [Duration] {
        durations
    }
}

private struct FailingTaskListSnapshotVersionProvider: TaskListSnapshotVersionProviding {
    func nextTaskListSnapshotVersion() async throws -> TaskListSnapshotVersion {
        throw SnapshotResponderTestError.versionPersistenceFailed
    }
}

private enum SnapshotResponderTestError: Error {
    case cleanupPersistenceFailed
    case deliveryConfirmationPersistenceFailed
    case firstWriteWaitTimedOut
    case invalidDeliveryState
    case lostWriteCallback
    case noVersion
    case unwrittenDeliveryWasNotRewound
    case versionPersistenceFailed
}
