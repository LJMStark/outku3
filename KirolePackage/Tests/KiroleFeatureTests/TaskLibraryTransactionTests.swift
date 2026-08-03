import Foundation
import Testing
@testable import KiroleFeature

@Suite("Task library transaction")
struct TaskLibraryTransactionTests {
    @Test("One complete task record round-trips with its version and integrity check")
    func oneTaskRoundTrip() throws {
        let transaction = makeTransaction(
            version: TaskLibraryVersion(epoch: 41, revision: 1),
            title: "Write the protocol",
            detail: "Define the atomic commit contract."
        )

        let payload = try TaskLibraryCodec.encodeTransaction(transaction)
        let decoded = try TaskLibraryCodec.decodeTransaction(payload)

        #expect(decoded == transaction)
        #expect(decoded.version.epoch != 0)
        #expect(decoded.version.revision != 0)
        #expect(decoded.records.count == 1)
        #expect(decoded.records[0].taskID == "task-15")
        #expect(decoded.records[0].order == 7)
        #expect(decoded.records[0].detail == "Define the atomic commit contract.")
        #expect(decoded.records[0].phaseTexts == TaskLibraryPhaseTexts(
            starting: "Choose the first byte.",
            building: "Keep the transaction whole.",
            deep: "Commit only after validation."
        ))
    }

    @Test("Zero versions and corrupted complete payloads are rejected")
    func invalidVersionAndChecksumAreRejected() throws {
        let invalidVersion = makeTransaction(
            version: TaskLibraryVersion(epoch: 0, revision: 1)
        )
        #expect(throws: TaskLibraryCodecError.invalidVersion) {
            try TaskLibraryCodec.encodeTransaction(invalidVersion)
        }

        let valid = try TaskLibraryCodec.encodeTransaction(makeTransaction())
        var corrupted = valid
        corrupted[12] ^= 0x01

        #expect(throws: TaskLibraryCodecError.self) {
            try TaskLibraryCodec.decodeTransaction(corrupted)
        }
    }

    @Test("An impossible record count fails from the payload bytes without reserving attacker-sized memory")
    func impossibleRecordCountIsRejected() {
        var body = Data([TaskLibraryCodec.subVersion])
        body.appendBigEndian(UInt32(1))
        body.appendBigEndian(UInt32(1))
        body.appendBigEndian(UInt32.max)
        var payload = body
        payload.appendBigEndian(CRC32.ieee(body))

        #expect(throws: TaskLibraryCodecError.truncated(field: "records[0].taskID")) {
            try TaskLibraryCodec.decodeTransaction(payload)
        }
    }

    @Test("A commit acknowledgement is bound to the exact transaction version and CRC")
    func acknowledgementRoundTrip() throws {
        let transaction = makeTransaction()
        let payload = try TaskLibraryCodec.encodeTransaction(transaction)
        let acknowledgement = TaskLibraryCommitAcknowledgement(
            version: transaction.version,
            result: .committed,
            contentCRC32: payload.bigEndianUInt32(at: payload.count - 4)
        )

        let encoded = TaskLibraryCodec.encodeAcknowledgement(acknowledgement)

        #expect(try TaskLibraryCodec.decodeAcknowledgement(encoded) == acknowledgement)
        #expect(BLEDataType.taskLibraryTransaction.rawValue == 0x23)
    }

    @MainActor
    @Test("A 0x23 commit result is routed before EventLog parsing")
    func acknowledgementRoutesToBLEService() async {
        let expected = TaskLibraryCommitAcknowledgement(
            version: TaskLibraryVersion(epoch: 9, revision: 3),
            result: .committed,
            contentCRC32: 0xCBF4_3926
        )
        let received = TaskLibraryAcknowledgementBox()
        BLEService.shared.onTaskLibraryCommitAcknowledgement = { received.value = $0 }
        defer { BLEService.shared.onTaskLibraryCommitAcknowledgement = nil }

        await BLEEventHandler.handleReceivedPayload(
            BLEReceivedMessage(
                type: BLEDataType.taskLibraryTransaction.rawValue,
                payload: TaskLibraryCodec.encodeAcknowledgement(expected)
            ),
            service: .shared
        )

        #expect(received.value == expected)
    }

    @MainActor
    @Test("An interrupted replacement keeps the previous committed task visible")
    func interruptedReplacementKeepsCommittedTask() async throws {
        let scenario = AppDeviceScenario(now: Date(timeIntervalSince1970: 1_800_000_000))
        scenario.connect()

        let first = makeTransaction(
            version: TaskLibraryVersion(epoch: 7, revision: 1),
            title: "Committed task",
            detail: "This remains visible."
        )
        _ = try scenario.sendTaskLibrary(first, messageID: 0x6100, maxChunkSize: 24)

        scenario.failNextWrite(atChunk: 1)
        let replacement = makeTransaction(
            version: TaskLibraryVersion(epoch: 7, revision: 2),
            title: "Replacement task",
            detail: String(repeating: "Long pending detail. ", count: 8)
        )
        #expect(throws: AppDeviceScenarioError.chunkWriteFailed(index: 1)) {
            try scenario.sendTaskLibrary(replacement, messageID: 0x6101, maxChunkSize: 24)
        }

        let snapshot = await scenario.snapshot()
        #expect(snapshot.taskLibraryCommittedVersion == first.version)
        #expect(snapshot.taskLibraryPendingVersion == replacement.version)
        #expect(snapshot.taskLibraryRecords == first.records)
    }

    @MainActor
    @Test("The virtual device accepts any non-zero version identity")
    func arbitraryNonZeroVersionIsAccepted() async throws {
        let scenario = AppDeviceScenario(now: Date(timeIntervalSince1970: 1_800_000_000))
        scenario.connect()

        let first = makeTransaction(version: TaskLibraryVersion(epoch: 90, revision: 40))
        let second = makeTransaction(version: TaskLibraryVersion(epoch: 2, revision: 3))

        _ = try scenario.sendTaskLibrary(first, messageID: 0x6110, maxChunkSize: 24)
        _ = try scenario.sendTaskLibrary(second, messageID: 0x6111, maxChunkSize: 24)

        let snapshot = await scenario.snapshot()
        #expect(snapshot.taskLibraryCommittedVersion == second.version)
    }

    @MainActor
    @Test("After commit the device enters from local detail without a TaskIn request")
    func committedTaskEntersLocally() async throws {
        let scenario = AppDeviceScenario(now: Date(timeIntervalSince1970: 1_800_000_000))
        scenario.connect()
        let transaction = makeTransaction()

        let acknowledgement = try scenario.sendTaskLibrary(
            transaction,
            messageID: 0x6200,
            maxChunkSize: 24
        )
        let localRecord = try scenario.enterTaskFromCommittedLibrary(taskID: "task-15")
        let snapshot = await scenario.snapshot()

        #expect(acknowledgement.result == .committed)
        #expect(acknowledgement.version == transaction.version)
        #expect(localRecord == transaction.records[0])
        #expect(snapshot.currentPage == .focus(taskID: "task-15"))
        #expect(snapshot.outboundTransactions.contains { $0.type == BLEDataType.taskLibraryTransaction.rawValue })
        #expect(!snapshot.outboundTransactions.contains { $0.type == BLEDataType.taskInPage.rawValue })
    }

    @MainActor
    @Test("The virtual device selects phase copy at the exact local minute boundaries")
    func localPhaseBoundaries() async throws {
        let scenario = AppDeviceScenario(now: Date(timeIntervalSince1970: 1_800_000_000))
        scenario.connect()
        _ = try scenario.sendTaskLibrary(makeTransaction(), messageID: 0x6250, maxChunkSize: 24)

        #expect(try scenario.taskPhaseText(taskID: "task-15", elapsedMinutes: 0) == "Choose the first byte.")
        #expect(try scenario.taskPhaseText(taskID: "task-15", elapsedMinutes: 5) == "Choose the first byte.")
        #expect(try scenario.taskPhaseText(taskID: "task-15", elapsedMinutes: 6) == "Keep the transaction whole.")
        #expect(try scenario.taskPhaseText(taskID: "task-15", elapsedMinutes: 15) == "Keep the transaction whole.")
        #expect(try scenario.taskPhaseText(taskID: "task-15", elapsedMinutes: 16) == "Commit only after validation.")
    }

    @MainActor
    @Test("The existing Overview acknowledgement path remains available during migration")
    func oldOverviewPathStillWorks() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let scenario = AppDeviceScenario(now: now)
        let task = TaskItem(
            id: "task-15",
            title: "Existing overview",
            todayDisplayDate: now
        )
        await scenario.replaceAppTasks([task])
        scenario.connect()
        _ = try scenario.sendTaskLibrary(makeTransaction(), messageID: 0x6300, maxChunkSize: 24)

        let outcome = try await scenario.deviceRequestsTaskRefresh(operationID: 0x1234_5678)
        let snapshot = await scenario.snapshot()

        #expect(outcome == .sent)
        #expect(snapshot.taskQueue == ["task-15"])
        #expect(snapshot.taskLibraryRecords.map(\.taskID) == ["task-15"])
    }

    private func makeTransaction(
        version: TaskLibraryVersion = TaskLibraryVersion(epoch: 7, revision: 1),
        title: String = "Write the protocol",
        detail: String = "Define the atomic commit contract."
    ) -> TaskLibraryTransaction {
        let task = TaskItem(
            id: "task-15",
            title: title,
            notes: detail
        )
        let record = TaskLibraryRecord(
            task: task,
            order: 7,
            phaseTexts: TaskLibraryPhaseTexts(
                starting: "Choose the first byte.",
                building: "Keep the transaction whole.",
                deep: "Commit only after validation."
            )
        )
        return TaskLibraryTransaction(version: version, records: [record])
    }
}

@MainActor
private final class TaskLibraryAcknowledgementBox {
    var value: TaskLibraryCommitAcknowledgement?
}
