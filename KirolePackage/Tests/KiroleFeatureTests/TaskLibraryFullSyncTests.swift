import Foundation
import Testing
@testable import KiroleFeature

@Suite("Complete task-library sync")
struct TaskLibraryFullSyncTests {
    private enum SnapshotValidationError: Error {
        case companionChanged
    }

    @Test("The device library contains only today's tasks, including manual today selections")
    func deviceLibraryContainsOnlyTodaysTasks() throws {
        // 2026-08-04 客户拍板：只发当天（dueDate 严格今天 ∪ 手动设为今天的无日期任务）。
        // 未来、过期、未手动选入的无日期任务不进设备任务库；条数仍不设上限。
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let calendar = Self.makeShanghaiCalendar()
        let day: TimeInterval = 24 * 60 * 60
        let tasks = [
            TaskItem(id: "today", title: "Today", dueDate: now),
            TaskItem(id: "manual-today", title: "Manual today", todayDisplayDate: now),
            TaskItem(id: "future", title: "Future", dueDate: now.addingTimeInterval(day * 90)),
            TaskItem(id: "overdue", title: "Overdue", dueDate: now.addingTimeInterval(-day * 90)),
            TaskItem(id: "undated", title: "Undated"),
            TaskItem(id: "done", title: "Done", isCompleted: true, dueDate: now),
            TaskItem(id: "deleting", title: "Deleting", dueDate: now, pendingDeletion: true)
        ]

        let transaction = try TaskLibraryTransaction.fullLibrary(
            from: tasks,
            version: TaskLibraryVersion(epoch: 5, revision: 1),
            now: now,
            calendar: calendar
        )

        #expect(transaction.records.map(\.taskID) == ["today", "manual-today"])
        #expect(transaction.records.map(\.order) == [0, 1])
    }

    static let libraryNow = Date(timeIntervalSince1970: 1_800_000_000)

    static func makeShanghaiCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return calendar
    }

    @Test("An empty App library is still a complete zero-record replacement transaction")
    func zeroTaskLibraryIsDeterministic() throws {
        let transaction = try TaskLibraryTransaction.fullLibrary(
            from: [TaskItem(id: "done", title: "Done", isCompleted: true)],
            version: TaskLibraryVersion(epoch: 5, revision: 2),
            now: Self.libraryNow,
            calendar: Self.makeShanghaiCalendar()
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
                dueDate: Date(timeIntervalSince1970: 1_800_000_000),
                notes: String(repeating: "detail-\(index) ", count: 8)
            )
        }
        let transaction = try TaskLibraryTransaction.fullLibrary(
            from: tasks,
            version: TaskLibraryVersion(epoch: 6, revision: 1),
            now: Self.libraryNow,
            calendar: Self.makeShanghaiCalendar()
        )

        _ = try scenario.sendTaskLibrary(transaction, messageID: 0x6400, maxChunkSize: 32)
        let snapshot = await scenario.snapshot()
        let outbound = try #require(snapshot.outboundTransactions.last)

        #expect(outbound.packetCount > 1)
        #expect(snapshot.taskLibraryRecords.count == 12)
        #expect(snapshot.taskLibraryRecords.map(\.taskID) == tasks.map(\.hardwareIdentifier))
        #expect(snapshot.taskLibraryRecords.map(\.order) == Array(0..<12).map(UInt32.init))
    }

    @MainActor
    @Test("A changed companion snapshot rejects the task library before transport")
    func changedCompanionSnapshotRejectsSend() async throws {
        let transaction = try TaskLibraryTransaction.fullLibrary(
            from: [TaskItem(id: "stale-persona", title: "Stale persona", dueDate: Self.libraryNow)],
            version: TaskLibraryVersion(epoch: 6, revision: 2),
            now: Self.libraryNow,
            calendar: Self.makeShanghaiCalendar()
        )

        await #expect(throws: SnapshotValidationError.self) {
            try await BLEService.shared.sendTaskLibraryTransaction(
                transaction,
                expectedTaskStateVersion: AppState.shared.taskStateVersion,
                validateAdditionalSnapshot: {
                    throw SnapshotValidationError.companionChanged
                }
            )
        }
    }

    @MainActor
    @Test("A task library cannot cross from its captured destination to another device")
    func changedDestinationRejectsSend() async throws {
        let transaction = try TaskLibraryTransaction.fullLibrary(
            from: [TaskItem(id: "device-bound", title: "Device bound", dueDate: Self.libraryNow)],
            version: TaskLibraryVersion(epoch: 6, revision: 3),
            now: Self.libraryNow,
            calendar: Self.makeShanghaiCalendar()
        )

        await #expect(throws: BLEPresentationDestinationError.self) {
            try await BLEService.shared.sendTaskLibraryTransaction(
                transaction,
                expectedTaskStateVersion: AppState.shared.taskStateVersion,
                expectedDestinationID: "a-different-device"
            )
        }
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
        #expect(TaskLibraryFullSyncPolicy.shouldSendFullLibrary(
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
            from: [TaskItem(id: "wire-state", title: "Wire state", dueDate: Self.libraryNow)],
            version: TaskLibraryVersion(epoch: 9, revision: 2),
            now: Self.libraryNow,
            calendar: Self.makeShanghaiCalendar()
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
    @Test("Reconnect inventory promotes an exact lost-ACK target snapshot")
    func reconnectInventoryPromotesLostAcknowledgementSnapshot() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let destination = "test-task-library-lost-ack-\(UUID().uuidString)"
            let phaseTexts = TaskLibraryPhaseTexts(
                starting: "Start",
                building: "Build",
                deep: "Deep"
            )
            let oldTransaction = try TaskLibraryTransaction.fullLibrary(
                from: [TaskItem(id: "task", title: "Before", dueDate: Self.libraryNow)],
                version: TaskLibraryVersion(epoch: 10, revision: 3),
                now: Self.libraryNow,
                calendar: Self.makeShanghaiCalendar(),
                phaseTexts: { _ in phaseTexts }
            )
            let oldState = try TaskLibraryCodec.committedState(for: oldTransaction)
            let newRecord = TaskLibraryRecord(
                taskID: "task",
                order: 0,
                title: "After",
                detail: "Detail",
                dueTimestamp: nil,
                priority: .high,
                phaseTexts: phaseTexts
            )
            let newTransaction = TaskLibraryTransaction.incremental(
                from: oldState,
                to: TaskLibraryVersion(epoch: 10, revision: 4),
                upserts: [newRecord],
                deletions: []
            )
            let newState = try TaskLibraryCodec.committedState(for: newTransaction)
            let pending = TaskLibraryPendingDelivery(
                transaction: newTransaction,
                sourceFingerprint: "frozen-source",
                targetRecords: [newRecord],
                phaseSourceFingerprints: ["task": "phase-source"],
                validation: .completeSource("not-current"),
                personaFingerprint: "persona"
            )
            let oldSnapshot = TaskLibraryCommittedSnapshot(
                state: oldState,
                records: oldTransaction.records,
                phaseSourceFingerprints: ["task": "old-phase"],
                personaFingerprint: "persona"
            )

            do {
                try await LocalStorage.shared.saveTaskLibraryCommittedSnapshot(
                    oldSnapshot,
                    for: destination
                )
                try await LocalStorage.shared.saveTaskLibraryPendingDelivery(
                    pending,
                    for: destination
                )

                #expect(!(await BLESyncCoordinator.shared.reconcileTaskLibraryInventory(
                    .committed(newState),
                    destinationID: destination
                )))
                let promoted = try await LocalStorage.shared.loadTaskLibraryCommittedSnapshot(
                    for: destination
                )
                #expect(promoted?.state == newState)
                #expect(promoted?.records == [newRecord])
                #expect(promoted?.phaseSourceFingerprints == ["task": "phase-source"])
                #expect(promoted?.personaFingerprint == "persona")
                #expect(try await LocalStorage.shared.loadTaskLibraryPendingDelivery(
                    for: destination
                ) == nil)
            } catch {
                try? await LocalStorage.shared.removeTaskLibraryPendingDelivery(for: destination)
                try? await LocalStorage.shared.removeTaskLibraryCommittedState(for: destination)
                throw error
            }
            try await LocalStorage.shared.removeTaskLibraryPendingDelivery(for: destination)
            try await LocalStorage.shared.removeTaskLibraryCommittedState(for: destination)
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
    @Test("Rejected and disconnected deliveries remain durable until an exact commit")
    func failedDeliveryRemainsPendingUntilCommit() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let destination = "test-task-library-durable-\(UUID().uuidString)"
            let transaction = try TaskLibraryTransaction.fullLibrary(
                from: [TaskItem(id: "durable", title: "Durable pending", dueDate: Self.libraryNow)],
                version: TaskLibraryVersion(epoch: 12, revision: 8),
            now: Self.libraryNow,
            calendar: Self.makeShanghaiCalendar()
        )
            let state = try TaskLibraryCodec.committedState(for: transaction)
            let appState = AppState.shared
            let delivery = TaskLibraryPendingDelivery(
                transaction: transaction,
                sourceFingerprint: TaskLibrarySourceFingerprint.make(
                    tasks: appState.tasks,
                    userProfile: appState.userProfile,
                    customCompanions: appState.customCompanions
                )
            )

            do {
                try await LocalStorage.shared.saveTaskLibraryPendingDelivery(
                    delivery,
                    for: destination
                )
                BLESyncCoordinator.shared.setPendingTaskLibraryForTesting(
                    state,
                    destinationID: destination
                )
                await BLESyncCoordinator.shared.handleTaskLibraryCommitAcknowledgement(
                    TaskLibraryCommitAcknowledgement(
                        version: state.version,
                        result: .capacityExceeded,
                        contentCRC32: state.contentCRC32
                    ),
                    destinationID: destination
                )
                BLESyncCoordinator.shared.handleTaskLibraryDisconnected(
                    destinationID: destination
                )

                #expect(try await LocalStorage.shared.loadTaskLibraryPendingDelivery(
                    for: destination
                ) == delivery)
                #expect(try await LocalStorage.shared.loadTaskLibraryCommittedState(
                    for: destination
                ) == nil)

                BLESyncCoordinator.shared.setPendingTaskLibraryForTesting(
                    state,
                    destinationID: destination
                )
                await BLESyncCoordinator.shared.handleTaskLibraryCommitAcknowledgement(
                    TaskLibraryCommitAcknowledgement(
                        version: state.version,
                        result: .committed,
                        contentCRC32: state.contentCRC32
                    ),
                    destinationID: destination
                )

                #expect(try await LocalStorage.shared.loadTaskLibraryPendingDelivery(
                    for: destination
                ) == nil)
                #expect(try await LocalStorage.shared.loadTaskLibraryCommittedState(
                    for: destination
                ) == state)
            } catch {
                BLESyncCoordinator.shared.clearPendingTaskLibraryForTesting(destinationID: destination)
                try? await LocalStorage.shared.removeTaskLibraryPendingDelivery(for: destination)
                try? await LocalStorage.shared.removeTaskLibraryCommittedState(for: destination)
                throw error
            }
            BLESyncCoordinator.shared.clearPendingTaskLibraryForTesting(destinationID: destination)
            try await LocalStorage.shared.removeTaskLibraryPendingDelivery(for: destination)
            try await LocalStorage.shared.removeTaskLibraryCommittedState(for: destination)
        }
    }

    @MainActor
    @Test("A late commit after timeout records device state without clearing a changed source")
    func lateCommitAfterTimeoutPreservesChangedSource() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let destination = "test-task-library-late-\(UUID().uuidString)"
            let transaction = try TaskLibraryTransaction.fullLibrary(
                from: [TaskItem(id: "late", title: "Old source", dueDate: Self.libraryNow)],
                version: TaskLibraryVersion(epoch: 12, revision: 10),
            now: Self.libraryNow,
            calendar: Self.makeShanghaiCalendar()
        )
            let state = try TaskLibraryCodec.committedState(for: transaction)
            let delivery = TaskLibraryPendingDelivery(
                transaction: transaction,
                sourceFingerprint: "source-that-is-no-longer-current"
            )

            do {
                try await LocalStorage.shared.saveTaskLibraryPendingDelivery(
                    delivery,
                    for: destination
                )
                BLESyncCoordinator.shared.setPendingTaskLibraryForTesting(
                    state,
                    destinationID: destination
                )

                await BLESyncCoordinator.shared.handleTaskLibraryCommitAcknowledgement(
                    TaskLibraryCommitAcknowledgement(
                        version: state.version,
                        result: .committed,
                        contentCRC32: state.contentCRC32
                    ),
                    destinationID: destination
                )

                #expect(try await LocalStorage.shared.loadTaskLibraryCommittedState(
                    for: destination
                ) == state)
                #expect(try await LocalStorage.shared.loadTaskLibraryPendingDelivery(
                    for: destination
                ) == delivery)
            } catch {
                BLESyncCoordinator.shared.clearPendingTaskLibraryForTesting(destinationID: destination)
                try? await LocalStorage.shared.removeTaskLibraryPendingDelivery(for: destination)
                try? await LocalStorage.shared.removeTaskLibraryCommittedState(for: destination)
                throw error
            }
            BLESyncCoordinator.shared.clearPendingTaskLibraryForTesting(destinationID: destination)
            try await LocalStorage.shared.removeTaskLibraryPendingDelivery(for: destination)
            try await LocalStorage.shared.removeTaskLibraryCommittedState(for: destination)
        }
    }

    @MainActor
    @Test("A late old commit cannot clear a newer durable transaction before its marker updates")
    func lateOldCommitPreservesNewerDurableTransaction() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let destination = "test-task-library-late-version-\(UUID().uuidString)"
            let oldTransaction = try TaskLibraryTransaction.fullLibrary(
                from: [TaskItem(id: "old", title: "Old frozen source", dueDate: Self.libraryNow)],
                version: TaskLibraryVersion(epoch: 12, revision: 11),
            now: Self.libraryNow,
            calendar: Self.makeShanghaiCalendar()
        )
            let newTransaction = try TaskLibraryTransaction.fullLibrary(
                from: [TaskItem(id: "new", title: "New frozen source", dueDate: Self.libraryNow)],
                version: TaskLibraryVersion(epoch: 12, revision: 12),
            now: Self.libraryNow,
            calendar: Self.makeShanghaiCalendar()
        )
            let oldState = try TaskLibraryCodec.committedState(for: oldTransaction)
            let appState = AppState.shared
            let newDelivery = TaskLibraryPendingDelivery(
                transaction: newTransaction,
                sourceFingerprint: TaskLibrarySourceFingerprint.make(
                    tasks: appState.tasks,
                    userProfile: appState.userProfile,
                    customCompanions: appState.customCompanions
                )
            )

            do {
                // Reproduce the narrow window after the new durable write but before the
                // connection-only marker advances from the old transaction.
                try await LocalStorage.shared.saveTaskLibraryPendingDelivery(
                    newDelivery,
                    for: destination
                )
                BLESyncCoordinator.shared.setPendingTaskLibraryForTesting(
                    oldState,
                    destinationID: destination
                )

                await BLESyncCoordinator.shared.handleTaskLibraryCommitAcknowledgement(
                    TaskLibraryCommitAcknowledgement(
                        version: oldState.version,
                        result: .committed,
                        contentCRC32: oldState.contentCRC32
                    ),
                    destinationID: destination
                )

                #expect(try await LocalStorage.shared.loadTaskLibraryCommittedState(
                    for: destination
                ) == oldState)
                #expect(try await LocalStorage.shared.loadTaskLibraryPendingDelivery(
                    for: destination
                ) == newDelivery)
            } catch {
                BLESyncCoordinator.shared.clearPendingTaskLibraryForTesting(destinationID: destination)
                try? await LocalStorage.shared.removeTaskLibraryPendingDelivery(for: destination)
                try? await LocalStorage.shared.removeTaskLibraryCommittedState(for: destination)
                throw error
            }
            BLESyncCoordinator.shared.clearPendingTaskLibraryForTesting(destinationID: destination)
            try await LocalStorage.shared.removeTaskLibraryPendingDelivery(for: destination)
            try await LocalStorage.shared.removeTaskLibraryCommittedState(for: destination)
        }
    }

    @MainActor
    @Test("A duplicate commit ACK cannot clear pending while source validation is unfinished")
    func duplicateCommitCannotWinSourceValidationRace() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let destination = "test-task-library-duplicate-\(UUID().uuidString)"
            let transaction = try TaskLibraryTransaction.fullLibrary(
                from: [TaskItem(id: "duplicate", title: "Old frozen source", dueDate: Self.libraryNow)],
                version: TaskLibraryVersion(epoch: 12, revision: 9),
            now: Self.libraryNow,
            calendar: Self.makeShanghaiCalendar()
        )
            let state = try TaskLibraryCodec.committedState(for: transaction)
            let delivery = TaskLibraryPendingDelivery(
                transaction: transaction,
                sourceFingerprint: "old-source"
            )
            let acknowledgement = TaskLibraryCommitAcknowledgement(
                version: state.version,
                result: .committed,
                contentCRC32: state.contentCRC32
            )

            do {
                try await LocalStorage.shared.saveTaskLibraryPendingDelivery(
                    delivery,
                    for: destination
                )
                BLESyncCoordinator.shared.setPendingTaskLibraryForTesting(
                    state,
                    destinationID: destination
                )
                BLESyncCoordinator.shared.registerTaskLibraryAcknowledgementForTesting(
                    state,
                    destinationID: destination
                )

                await BLESyncCoordinator.shared.handleTaskLibraryCommitAcknowledgement(
                    acknowledgement,
                    destinationID: destination
                )
                await BLESyncCoordinator.shared.handleTaskLibraryCommitAcknowledgement(
                    acknowledgement,
                    destinationID: destination
                )

                #expect(try await LocalStorage.shared.loadTaskLibraryPendingDelivery(
                    for: destination
                ) == delivery)
                #expect(try await LocalStorage.shared.loadTaskLibraryCommittedState(
                    for: destination
                ) == nil)
            } catch {
                BLESyncCoordinator.shared.clearPendingTaskLibraryForTesting(destinationID: destination)
                try? await LocalStorage.shared.removeTaskLibraryPendingDelivery(for: destination)
                try? await LocalStorage.shared.removeTaskLibraryCommittedState(for: destination)
                throw error
            }
            BLESyncCoordinator.shared.clearPendingTaskLibraryForTesting(destinationID: destination)
            try await LocalStorage.shared.removeTaskLibraryPendingDelivery(for: destination)
            try? await LocalStorage.shared.removeTaskLibraryCommittedState(for: destination)
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
            try await LocalStorage.shared.saveTaskLibraryPendingDelivery(
                TaskLibraryPendingDelivery(
                    transaction: TaskLibraryTransaction(version: state.version, records: []),
                    sourceFingerprint: "pending"
                ),
                for: destinationA
            )

            await BLESyncCoordinator.shared.handleAllTaskLibrariesUnbound()

            #expect(try await LocalStorage.shared.loadTaskLibraryCommittedState(for: destinationA) == nil)
            #expect(try await LocalStorage.shared.loadTaskLibraryCommittedState(for: destinationB) == nil)
            #expect(try await LocalStorage.shared.loadTaskLibraryPendingDelivery(for: destinationA) == nil)
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
