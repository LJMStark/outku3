import Foundation
import Testing
@testable import KiroleFeature

@Suite("Complete task-library sync")
struct TaskLibraryFullSyncTests {
    @Test("Every incomplete task is included regardless of date while completed and deleting tasks are excluded")
    func completeLibraryHasNoDateOrDisplayLimit() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let day: TimeInterval = 24 * 60 * 60
        let tasks = [
            TaskItem(id: "today", title: "Today", dueDate: now),
            TaskItem(id: "future", title: "Future", dueDate: now.addingTimeInterval(day * 90)),
            TaskItem(id: "overdue", title: "Overdue", dueDate: now.addingTimeInterval(-day * 90)),
            TaskItem(id: "undated", title: "Undated"),
            TaskItem(id: "done", title: "Done", isCompleted: true),
            TaskItem(id: "deleting", title: "Deleting", pendingDeletion: true)
        ]

        let transaction = try TaskLibraryTransaction.fullLibrary(
            from: tasks,
            version: TaskLibraryVersion(epoch: 5, revision: 1)
        )

        #expect(transaction.records.map(\.taskID) == ["today", "future", "overdue", "undated"])
        #expect(transaction.records.map(\.order) == [0, 1, 2, 3])
    }

    @Test("An empty App library is still a complete zero-record replacement transaction")
    func zeroTaskLibraryIsDeterministic() throws {
        let transaction = try TaskLibraryTransaction.fullLibrary(
            from: [TaskItem(id: "done", title: "Done", isCompleted: true)],
            version: TaskLibraryVersion(epoch: 5, revision: 2)
        )

        let payload = try TaskLibraryCodec.encodeTransaction(transaction)

        #expect(transaction.records.isEmpty)
        #expect(try TaskLibraryCodec.decodeTransaction(payload) == transaction)
    }

    @MainActor
    @Test("More than eight tasks cross multiple BLE chunks without truncation or reordering")
    func largeLibraryCrossesChunksWithoutTruncation() async throws {
        let scenario = AppDeviceScenario(now: Date(timeIntervalSince1970: 1_800_000_000))
        scenario.connect()
        let tasks = (0..<12).map { index in
            TaskItem(
                id: "task-\(index)",
                title: "Task \(index)",
                notes: String(repeating: "detail-\(index) ", count: 8)
            )
        }
        let transaction = try TaskLibraryTransaction.fullLibrary(
            from: tasks,
            version: TaskLibraryVersion(epoch: 6, revision: 1)
        )

        _ = try scenario.sendTaskLibrary(transaction, messageID: 0x6400, maxChunkSize: 32)
        let snapshot = await scenario.snapshot()
        let outbound = try #require(snapshot.outboundTransactions.last)

        #expect(outbound.packetCount > 1)
        #expect(snapshot.taskLibraryRecords.count == 12)
        #expect(snapshot.taskLibraryRecords.map(\.taskID) == tasks.map(\.hardwareIdentifier))
        #expect(snapshot.taskLibraryRecords.map(\.order) == Array(0..<12).map(UInt32.init))
    }

    @Test("Full library sends only for first binding or an explicit device-missing report")
    func fullSyncPolicyDoesNotUnconditionallyResend() {
        let committed = TaskLibraryCommittedState(
            version: TaskLibraryVersion(epoch: 7, revision: 4),
            contentCRC32: 0xCBF4_3926
        )

        #expect(TaskLibraryFullSyncPolicy.shouldSendFullLibrary(
            locallyCommitted: nil,
            deviceInventory: nil,
            hasPendingTransaction: false
        ))
        #expect(TaskLibraryFullSyncPolicy.shouldSendFullLibrary(
            locallyCommitted: committed,
            deviceInventory: .missing,
            hasPendingTransaction: false
        ))
        #expect(TaskLibraryFullSyncPolicy.shouldSendFullLibrary(
            locallyCommitted: nil,
            deviceInventory: .committed(committed),
            hasPendingTransaction: false
        ))
        #expect(!TaskLibraryFullSyncPolicy.shouldSendFullLibrary(
            locallyCommitted: committed,
            deviceInventory: .committed(committed),
            hasPendingTransaction: false
        ))
        #expect(!TaskLibraryFullSyncPolicy.shouldSendFullLibrary(
            locallyCommitted: committed,
            deviceInventory: nil,
            hasPendingTransaction: false
        ))
        #expect(!TaskLibraryFullSyncPolicy.shouldSendFullLibrary(
            locallyCommitted: nil,
            deviceInventory: nil,
            hasPendingTransaction: true
        ))
    }

    @Test("DeviceWake reports either a missing library or an exact committed version")
    func deviceWakeParsesTaskLibraryInventory() throws {
        let committed = TaskLibraryCommittedState(
            version: TaskLibraryVersion(epoch: 8, revision: 3),
            contentCRC32: 0x1234_5678
        )
        let committedEvent = try #require(EventLog.fromBLEPayload(
            type: EventLogType.deviceWake.rawByte,
            payload: makeDeviceWakePayload(inventory: .committed(committed))
        ))
        let missingEvent = try #require(EventLog.fromBLEPayload(
            type: EventLogType.deviceWake.rawByte,
            payload: makeDeviceWakePayload(inventory: .missing)
        ))

        #expect(committedEvent.taskLibraryInventory == .committed(committed))
        #expect(missingEvent.taskLibraryInventory == .missing)
    }

    @Test("Committed task-library state is derived from the exact wire CRC")
    func committedStateMatchesWirePayload() throws {
        let transaction = try TaskLibraryTransaction.fullLibrary(
            from: [TaskItem(id: "wire-state", title: "Wire state")],
            version: TaskLibraryVersion(epoch: 9, revision: 2)
        )
        let payload = try TaskLibraryCodec.encodeTransaction(transaction)

        #expect(try TaskLibraryCodec.committedState(for: transaction) == TaskLibraryCommittedState(
            version: transaction.version,
            contentCRC32: payload.bigEndianUInt32(at: payload.count - 4)
        ))
    }

    @Test("Committed task-library state is isolated per hardware destination")
    func committedStatePersistsPerDestination() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let destinationA = "test-task-library-a-\(UUID().uuidString)"
            let destinationB = "test-task-library-b-\(UUID().uuidString)"
            let stateA = TaskLibraryCommittedState(
                version: TaskLibraryVersion(epoch: 10, revision: 1),
                contentCRC32: 0xAAAA_AAAA
            )
            let stateB = TaskLibraryCommittedState(
                version: TaskLibraryVersion(epoch: 10, revision: 2),
                contentCRC32: 0xBBBB_BBBB
            )

            do {
                try await LocalStorage.shared.saveTaskLibraryCommittedState(stateA, for: destinationA)
                try await LocalStorage.shared.saveTaskLibraryCommittedState(stateB, for: destinationB)

                #expect(try await LocalStorage.shared.loadTaskLibraryCommittedState(for: destinationA) == stateA)
                #expect(try await LocalStorage.shared.loadTaskLibraryCommittedState(for: destinationB) == stateB)

                try await LocalStorage.shared.removeTaskLibraryCommittedState(for: destinationA)
                #expect(try await LocalStorage.shared.loadTaskLibraryCommittedState(for: destinationA) == nil)
                #expect(try await LocalStorage.shared.loadTaskLibraryCommittedState(for: destinationB) == stateB)
            } catch {
                try? await LocalStorage.shared.removeTaskLibraryCommittedState(for: destinationA)
                try? await LocalStorage.shared.removeTaskLibraryCommittedState(for: destinationB)
                throw error
            }
            try await LocalStorage.shared.removeTaskLibraryCommittedState(for: destinationA)
            try await LocalStorage.shared.removeTaskLibraryCommittedState(for: destinationB)
        }
    }

    @MainActor
    @Test("Device inventory and matching ACK advance only the reported destination")
    func inventoryAndAcknowledgementAdvanceExactDestination() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let destination = "test-task-library-ack-\(UUID().uuidString)"
            let stale = TaskLibraryCommittedState(
                version: TaskLibraryVersion(epoch: 11, revision: 1),
                contentCRC32: 0x1111_1111
            )
            let pending = TaskLibraryCommittedState(
                version: TaskLibraryVersion(epoch: 11, revision: 2),
                contentCRC32: 0x2222_2222
            )

            do {
                #expect(await BLESyncCoordinator.shared.reconcileTaskLibraryInventory(
                    .committed(stale),
                    destinationID: destination
                ))
                #expect(try await LocalStorage.shared.loadTaskLibraryCommittedState(for: destination) == nil)

                try await LocalStorage.shared.saveTaskLibraryCommittedState(stale, for: destination)
                #expect(await BLESyncCoordinator.shared.reconcileTaskLibraryInventory(
                    .missing,
                    destinationID: destination
                ))
                #expect(try await LocalStorage.shared.loadTaskLibraryCommittedState(for: destination) == nil)

                BLESyncCoordinator.shared.setPendingTaskLibraryForTesting(
                    pending,
                    destinationID: destination
                )
                await BLESyncCoordinator.shared.handleTaskLibraryCommitAcknowledgement(
                    TaskLibraryCommitAcknowledgement(
                        version: pending.version,
                        result: .committed,
                        contentCRC32: 0xDEAD_BEEF
                    ),
                    destinationID: destination
                )
                #expect(try await LocalStorage.shared.loadTaskLibraryCommittedState(for: destination) == nil)

                await BLESyncCoordinator.shared.handleTaskLibraryCommitAcknowledgement(
                    TaskLibraryCommitAcknowledgement(
                        version: pending.version,
                        result: .committed,
                        contentCRC32: pending.contentCRC32
                    ),
                    destinationID: destination
                )
                #expect(try await LocalStorage.shared.loadTaskLibraryCommittedState(for: destination) == pending)
            } catch {
                BLESyncCoordinator.shared.clearPendingTaskLibraryForTesting(destinationID: destination)
                try? await LocalStorage.shared.removeTaskLibraryCommittedState(for: destination)
                throw error
            }
            BLESyncCoordinator.shared.clearPendingTaskLibraryForTesting(destinationID: destination)
            try await LocalStorage.shared.removeTaskLibraryCommittedState(for: destination)
        }
    }

    @MainActor
    @Test("Unbinding hardware clears every remembered task-library binding")
    func unbindingClearsCommittedDestinations() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let destinationA = "test-task-library-unbind-a-\(UUID().uuidString)"
            let destinationB = "test-task-library-unbind-b-\(UUID().uuidString)"
            let state = TaskLibraryCommittedState(
                version: TaskLibraryVersion(epoch: 12, revision: 1),
                contentCRC32: 0x1212_1212
            )
            try await LocalStorage.shared.saveTaskLibraryCommittedState(state, for: destinationA)
            try await LocalStorage.shared.saveTaskLibraryCommittedState(state, for: destinationB)

            await BLESyncCoordinator.shared.handleAllTaskLibrariesUnbound()

            #expect(try await LocalStorage.shared.loadTaskLibraryCommittedState(for: destinationA) == nil)
            #expect(try await LocalStorage.shared.loadTaskLibraryCommittedState(for: destinationB) == nil)
        }
    }

    private func makeDeviceWakePayload(inventory: TaskLibraryDeviceInventory) -> Data {
        var payload = Data([80, 2, 11, 0, 0])
        payload.append(Data(repeating: 0, count: 16))
        payload.appendBigEndian(UInt32(0))
        payload.appendBigEndian(UInt32(0))
        switch inventory {
        case .missing:
            payload.append(0)
            payload.appendBigEndian(UInt32(0))
            payload.appendBigEndian(UInt32(0))
            payload.appendBigEndian(UInt32(0))
        case let .committed(state):
            payload.append(1)
            payload.appendBigEndian(state.version.epoch)
            payload.appendBigEndian(state.version.revision)
            payload.appendBigEndian(state.contentCRC32)
        }
        return payload
    }
}
