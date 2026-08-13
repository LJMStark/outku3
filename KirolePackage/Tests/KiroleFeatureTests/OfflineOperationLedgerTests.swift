import Foundation
import Testing
@testable import KiroleFeature

@Suite("Offline operation ledger", .serialized)
struct OfflineOperationLedgerTests {
    @Test("Reserve distinguishes new, resume, duplicate, and payload conflicts")
    func reservationLifecycle() async {
        let ledger = OfflineOperationLedger(persistenceEnabled: false)
        let payload = Data([0x01, 0x02, 0x03])

        let first = await ledger.reserve(
            deviceID: "device-a",
            bootSessionID: 0x1122_3344,
            operationID: 7,
            eventType: 0x11,
            originalPayload: payload
        )
        guard case let .new(newEntry) = first else {
            Issue.record("First reservation should create a pending WAL entry")
            return
        }
        #expect(newEntry.state == .pending)
        #expect(newEntry.eventType == 0x11)
        #expect(newEntry.originalPayload == payload)

        let retry = await ledger.reserve(
            deviceID: "device-a",
            bootSessionID: 0x1122_3344,
            operationID: 7,
            eventType: 0x11,
            originalPayload: payload
        )
        guard case let .resume(pendingEntry) = retry else {
            Issue.record("An exact retry of a pending entry should resume")
            return
        }
        #expect(pendingEntry == newEntry)

        let eventTypeConflict = await ledger.reserve(
            deviceID: "device-a",
            bootSessionID: 0x1122_3344,
            operationID: 7,
            eventType: 0x12,
            originalPayload: payload
        )
        #expect(eventTypeConflict == .conflict)

        let payloadConflict = await ledger.reserve(
            deviceID: "device-a",
            bootSessionID: 0x1122_3344,
            operationID: 7,
            eventType: 0x11,
            originalPayload: Data([0x01, 0x02, 0x04])
        )
        #expect(payloadConflict == .conflict)

        #expect(await ledger.commit(
            deviceID: "device-a",
            bootSessionID: 0x1122_3344,
            operationID: 7,
            eventType: 0x12,
            originalPayload: payload
        ) == false)

        let committed = await ledger.commit(
            deviceID: "device-a",
            bootSessionID: 0x1122_3344,
            operationID: 7,
            eventType: 0x11,
            originalPayload: payload
        )
        #expect(committed)

        let duplicate = await ledger.reserve(
            deviceID: "device-a",
            bootSessionID: 0x1122_3344,
            operationID: 7,
            eventType: 0x11,
            originalPayload: payload
        )
        guard case let .duplicate(committedEntry) = duplicate else {
            Issue.record("An exact retry of a committed entry should be a duplicate")
            return
        }
        #expect(committedEntry.state == .committed)
    }

    @Test("The identity key includes device, boot session, and operation")
    func exactIdentityKey() async {
        let ledger = OfflineOperationLedger(persistenceEnabled: false)
        let payload = Data([0xAA])

        let reservations = await [
            ledger.reserve(
                deviceID: "device-a",
                bootSessionID: 1,
                operationID: 5,
                eventType: 0x11,
                originalPayload: payload
            ),
            ledger.reserve(
                deviceID: "device-b",
                bootSessionID: 1,
                operationID: 5,
                eventType: 0x11,
                originalPayload: payload
            ),
            ledger.reserve(
                deviceID: "device-a",
                bootSessionID: 2,
                operationID: 5,
                eventType: 0x11,
                originalPayload: payload
            ),
            ledger.reserve(
                deviceID: "device-a",
                bootSessionID: 1,
                operationID: 6,
                eventType: 0x11,
                originalPayload: payload
            ),
        ]

        #expect(reservations.allSatisfy {
            if case .new = $0 { return true }
            return false
        })
    }

    @Test("Pending and committed states survive ledger recreation")
    func durableRestartRecovery() async {
        let persistence = OfflineOperationLedgerMemoryPersistence()
        let pendingPayload = Data([0x10, 0x20])
        let committedPayload = Data([0x30, 0x40])
        let firstLedger = OfflineOperationLedger(persistence: persistence)

        _ = await firstLedger.reserve(
            deviceID: "device-a",
            bootSessionID: 100,
            operationID: 1,
            eventType: 0x11,
            originalPayload: pendingPayload
        )
        _ = await firstLedger.reserve(
            deviceID: "device-a",
            bootSessionID: 100,
            operationID: 2,
            eventType: 0x12,
            originalPayload: committedPayload
        )
        #expect(await firstLedger.commit(
            deviceID: "device-a",
            bootSessionID: 100,
            operationID: 2,
            eventType: 0x12,
            originalPayload: committedPayload
        ))

        let restartedLedger = OfflineOperationLedger(persistence: persistence)
        let pendingRetry = await restartedLedger.reserve(
            deviceID: "device-a",
            bootSessionID: 100,
            operationID: 1,
            eventType: 0x11,
            originalPayload: pendingPayload
        )
        let committedRetry = await restartedLedger.reserve(
            deviceID: "device-a",
            bootSessionID: 100,
            operationID: 2,
            eventType: 0x12,
            originalPayload: committedPayload
        )

        guard case .resume = pendingRetry else {
            Issue.record("A durable pending entry should resume after restart")
            return
        }
        guard case .duplicate = committedRetry else {
            Issue.record("A durable committed entry should deduplicate after restart")
            return
        }
    }

    @Test("Load and reserve-save failures are unavailable")
    func unavailablePersistence() async {
        let loadFailure = OfflineOperationLedgerMemoryPersistence(failLoad: true)
        let loadLedger = OfflineOperationLedger(persistence: loadFailure)
        let loadResult = await loadLedger.reserve(
            deviceID: "device-a",
            bootSessionID: 1,
            operationID: 1,
            eventType: 0x11,
            originalPayload: Data([0x01])
        )
        #expect(loadResult == .unavailable)

        let saveFailure = OfflineOperationLedgerMemoryPersistence(failingSaveNumbers: [1])
        let saveLedger = OfflineOperationLedger(persistence: saveFailure)
        let saveResult = await saveLedger.reserve(
            deviceID: "device-a",
            bootSessionID: 1,
            operationID: 1,
            eventType: 0x11,
            originalPayload: Data([0x01])
        )
        #expect(saveResult == .unavailable)

        let resumed = await saveLedger.reserve(
            deviceID: "device-a",
            bootSessionID: 1,
            operationID: 1,
            eventType: 0x11,
            originalPayload: Data([0x01])
        )
        guard case .resume = resumed else {
            Issue.record("An exact retry should durably flush and resume the in-memory pending entry")
            return
        }
    }

    @Test("A failed commit stays pending until a durable retry succeeds")
    func commitFailureRecovery() async {
        let persistence = OfflineOperationLedgerMemoryPersistence(failingSaveNumbers: [2])
        let ledger = OfflineOperationLedger(persistence: persistence)
        let payload = Data([0xFE, 0xED])

        _ = await ledger.reserve(
            deviceID: "device-a",
            bootSessionID: 77,
            operationID: 9,
            eventType: 0x12,
            originalPayload: payload
        )
        #expect(await ledger.commit(
            deviceID: "device-a",
            bootSessionID: 77,
            operationID: 9,
            eventType: 0x12,
            originalPayload: payload
        ) == false)

        let retry = await ledger.reserve(
            deviceID: "device-a",
            bootSessionID: 77,
            operationID: 9,
            eventType: 0x12,
            originalPayload: payload
        )
        guard case .resume = retry else {
            Issue.record("A failed commit must remain resumable")
            return
        }
        #expect(await ledger.commit(
            deviceID: "device-a",
            bootSessionID: 77,
            operationID: 9,
            eventType: 0x12,
            originalPayload: payload
        ))

        let restartedLedger = OfflineOperationLedger(persistence: persistence)
        let duplicate = await restartedLedger.reserve(
            deviceID: "device-a",
            bootSessionID: 77,
            operationID: 9,
            eventType: 0x12,
            originalPayload: payload
        )
        guard case .duplicate = duplicate else {
            Issue.record("The retried commit should be durable")
            return
        }
    }

    @Test("A later save cannot jump past a failed predecessor")
    func failedPredecessorBlocksLaterSnapshotUntilRetry() async {
        let persistence = OfflineOperationLedgerBlockingCommitPersistence()
        let ledger = OfflineOperationLedger(persistence: persistence)
        let firstPayload = Data([0x01])
        let secondPayload = Data([0x02])

        guard case .new = await ledger.reserve(
            deviceID: "device-a",
            bootSessionID: 88,
            operationID: 1,
            eventType: 0x11,
            originalPayload: firstPayload
        ) else {
            Issue.record("The first pending marker should be durable")
            return
        }

        let failingCommit = Task {
            await ledger.commit(
                deviceID: "device-a",
                bootSessionID: 88,
                operationID: 1,
                eventType: 0x11,
                originalPayload: firstPayload
            )
        }
        await persistence.waitForCommitSaveToStart()

        let laterReserve = Task {
            await ledger.reserve(
                deviceID: "device-a",
                bootSessionID: 88,
                operationID: 2,
                eventType: 0x12,
                originalPayload: secondPayload
            )
        }
        await Task.yield()
        #expect(await persistence.saveCountValue() == 2)

        await persistence.failCommitSave()
        #expect(await failingCommit.value == false)
        #expect(await laterReserve.value == .unavailable)

        let diskAfterFailure = await persistence.currentEntries()
        #expect(diskAfterFailure.count == 1)
        #expect(diskAfterFailure.first?.operationID == 1)
        #expect(diskAfterFailure.first?.state == .pending)

        guard case .resume = await ledger.reserve(
            deviceID: "device-a",
            bootSessionID: 88,
            operationID: 1,
            eventType: 0x11,
            originalPayload: firstPayload
        ) else {
            Issue.record("The failed commit should remain resumable")
            return
        }
        #expect(await ledger.commit(
            deviceID: "device-a",
            bootSessionID: 88,
            operationID: 1,
            eventType: 0x11,
            originalPayload: firstPayload
        ))

        guard case .resume = await ledger.reserve(
            deviceID: "device-a",
            bootSessionID: 88,
            operationID: 2,
            eventType: 0x12,
            originalPayload: secondPayload
        ) else {
            Issue.record("The later in-memory pending entry should flush on retry")
            return
        }

        let restarted = OfflineOperationLedger(persistence: persistence)
        guard case .duplicate = await restarted.reserve(
            deviceID: "device-a",
            bootSessionID: 88,
            operationID: 1,
            eventType: 0x11,
            originalPayload: firstPayload
        ) else {
            Issue.record("The recovered commit should be durable")
            return
        }
        guard case .resume = await restarted.reserve(
            deviceID: "device-a",
            bootSessionID: 88,
            operationID: 2,
            eventType: 0x12,
            originalPayload: secondPayload
        ) else {
            Issue.record("The later pending operation should be durable after retry")
            return
        }
    }
}

private enum OfflineOperationLedgerTestError: Error {
    case injected
}

private actor OfflineOperationLedgerMemoryPersistence: OfflineOperationLedgerPersisting {
    private let failLoad: Bool
    private let failingSaveNumbers: Set<Int>
    private var saveCount = 0
    private var entries: [OfflineOperationLedgerEntry] = []

    init(
        failLoad: Bool = false,
        failingSaveNumbers: Set<Int> = []
    ) {
        self.failLoad = failLoad
        self.failingSaveNumbers = failingSaveNumbers
    }

    func loadOfflineOperationLedger() async throws -> [OfflineOperationLedgerEntry]? {
        if failLoad {
            throw OfflineOperationLedgerTestError.injected
        }
        return entries
    }

    func saveOfflineOperationLedger(_ entries: [OfflineOperationLedgerEntry]) async throws {
        saveCount += 1
        if failingSaveNumbers.contains(saveCount) {
            throw OfflineOperationLedgerTestError.injected
        }
        self.entries = entries
    }
}

private actor OfflineOperationLedgerBlockingCommitPersistence: OfflineOperationLedgerPersisting {
    private var saveCount = 0
    private var entries: [OfflineOperationLedgerEntry] = []
    private var commitSaveStarted = false
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var failureContinuation: CheckedContinuation<Void, Never>?

    func loadOfflineOperationLedger() async throws -> [OfflineOperationLedgerEntry]? {
        entries
    }

    func saveOfflineOperationLedger(_ entries: [OfflineOperationLedgerEntry]) async throws {
        saveCount += 1
        if saveCount == 2 {
            commitSaveStarted = true
            startContinuation?.resume()
            startContinuation = nil
            await withCheckedContinuation { continuation in
                failureContinuation = continuation
            }
            throw OfflineOperationLedgerTestError.injected
        }
        self.entries = entries
    }

    func waitForCommitSaveToStart() async {
        guard !commitSaveStarted else { return }
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
    }

    func failCommitSave() {
        failureContinuation?.resume()
        failureContinuation = nil
    }

    func saveCountValue() -> Int { saveCount }

    func currentEntries() -> [OfflineOperationLedgerEntry] { entries }
}
