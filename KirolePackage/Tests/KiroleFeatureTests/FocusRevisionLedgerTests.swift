import Foundation
import Testing
@testable import KiroleFeature

@Suite("Focus revision ledger")
struct FocusRevisionLedgerTests {
    @Test("First revision starts at one and devices advance independently")
    func firstRevisionIsPerDevice() async throws {
        let persistence = FocusRevisionMemoryPersistence()
        let ledger = FocusRevisionLedger(persistence: persistence)
        let firstDevice = UUID()
        let secondDevice = UUID()
        let fingerprint = Data("active-1".utf8)

        let first = try await ledger.prepare(
            deviceID: firstDevice,
            fingerprint: fingerprint,
            floor: 0
        )
        let duplicate = try await ledger.prepare(
            deviceID: firstDevice,
            fingerprint: fingerprint,
            floor: 0
        )
        let otherDevice = try await ledger.prepare(
            deviceID: secondDevice,
            fingerprint: fingerprint,
            floor: 0
        )

        #expect(first == 1)
        #expect(duplicate == 1)
        #expect(otherDevice == 1)
        #expect(await persistence.saveCount() == 2)
    }

    @Test("First active FocusStatus writes revision one on the wire")
    func firstActiveFocusStatusWireRevisionIsOne() async throws {
        let persistence = FocusRevisionMemoryPersistence()
        let ledger = FocusRevisionLedger(persistence: persistence)
        let deviceID = UUID()
        let sessionID = FocusSessionId(
            bootSessionID: 0x0102_0304,
            startOperationID: 0x0506_0708
        )
        let fingerprint = BLEDataEncoder.encodeFocusStatus(
            phase: .warmup,
            energyBottles: 3,
            elapsedSeconds: 15,
            taskTitle: "First active",
            segmentSeconds: 1_500,
            focusRevision: 1,
            focusSessionId: sessionID,
            focusState: .active
        )

        let revision = try await ledger.prepare(
            deviceID: deviceID,
            fingerprint: fingerprint,
            floor: 0
        )
        let payload = BLEDataEncoder.encodeFocusStatus(
            phase: .warmup,
            energyBottles: 3,
            elapsedSeconds: 15,
            taskTitle: "First active",
            segmentSeconds: 1_500,
            focusRevision: revision,
            focusSessionId: sessionID,
            focusState: .active
        )

        #expect(payload[0] == FocusReconnectCodec.focusStatusSubVersion)
        #expect(payload.bigEndianUInt32(at: 1) == 1)
    }

    @Test("Changed FocusStatus content advances the encoded revision")
    func changedFocusStatusWireRevisionAdvances() async throws {
        let persistence = FocusRevisionMemoryPersistence()
        let ledger = FocusRevisionLedger(persistence: persistence)
        let deviceID = UUID()
        let sessionID = FocusSessionId(bootSessionID: 1, startOperationID: 7)

        func payload(elapsed: UInt32, revision: UInt32) -> Data {
            BLEDataEncoder.encodeFocusStatus(
                phase: .warmup,
                energyBottles: 2,
                elapsedSeconds: elapsed,
                taskTitle: "Monotonic",
                segmentSeconds: 1_500,
                focusRevision: revision,
                focusSessionId: sessionID,
                focusState: .active
            )
        }

        let firstFingerprint = payload(elapsed: 10, revision: 1)
        let firstRevision = try await ledger.prepare(
            deviceID: deviceID,
            fingerprint: firstFingerprint,
            floor: 0
        )
        let secondFingerprint = payload(elapsed: 11, revision: 1)
        let secondRevision = try await ledger.prepare(
            deviceID: deviceID,
            fingerprint: secondFingerprint,
            floor: firstRevision
        )

        #expect(payload(elapsed: 10, revision: firstRevision).bigEndianUInt32(at: 1) == 1)
        #expect(payload(elapsed: 11, revision: secondRevision).bigEndianUInt32(at: 1) == 2)
    }

    @Test("A legacy zero entry is upgraded instead of reused")
    func legacyZeroEntryStartsAtOne() async throws {
        let deviceID = UUID()
        let fingerprint = Data("legacy-idle".utf8)
        let persistence = FocusRevisionMemoryPersistence(
            snapshot: FocusRevisionLedgerSnapshot(entries: [
                FocusRevisionLedgerEntry(
                    deviceID: deviceID,
                    revision: 0,
                    fingerprint: fingerprint
                ),
            ])
        )
        let ledger = FocusRevisionLedger(persistence: persistence)

        let revision = try await ledger.prepare(
            deviceID: deviceID,
            fingerprint: fingerprint,
            floor: 0
        )

        #expect(revision == 1)
        #expect(await persistence.snapshot()?.entry(for: deviceID)?.revision == 1)
        #expect(await persistence.saveCount() == 1)
    }

    @Test("Different state advances above both the durable revision and caller floor")
    func changedStateAdvancesAboveFloor() async throws {
        let persistence = FocusRevisionMemoryPersistence()
        let ledger = FocusRevisionLedger(persistence: persistence)
        let deviceID = UUID()
        let firstFingerprint = Data("active-1".utf8)
        let secondFingerprint = Data("active-2".utf8)

        let first = try await ledger.prepare(
            deviceID: deviceID,
            fingerprint: firstFingerprint,
            floor: 7
        )
        let duplicate = try await ledger.prepare(
            deviceID: deviceID,
            fingerprint: firstFingerprint,
            floor: 7
        )
        let changed = try await ledger.prepare(
            deviceID: deviceID,
            fingerprint: secondFingerprint,
            floor: 3
        )
        let raisedFloor = try await ledger.prepare(
            deviceID: deviceID,
            fingerprint: secondFingerprint,
            floor: 12
        )

        #expect(first == 8)
        #expect(duplicate == 8)
        #expect(changed == 9)
        #expect(raisedFloor == 13)
    }

    @Test("Reconnect restore advances when an exact local retry equals the device floor")
    func reconnectRestoreAdvancesAboveEqualDeviceFloor() async throws {
        let ledger = FocusRevisionLedger(persistence: FocusRevisionMemoryPersistence())
        let deviceID = UUID()
        let fingerprint = Data("same-active-state".utf8)
        let localRevision = try await ledger.prepare(
            deviceID: deviceID,
            fingerprint: fingerprint,
            floor: 37
        )

        let restoredRevision = try await ledger.prepareAdvancingAboveFloor(
            deviceID: deviceID,
            fingerprint: fingerprint,
            floor: localRevision
        )
        let retryRevision = try await ledger.prepareAdvancingAboveFloor(
            deviceID: deviceID,
            fingerprint: fingerprint,
            floor: localRevision
        )

        #expect(localRevision == 38)
        #expect(restoredRevision == 39)
        #expect(retryRevision == restoredRevision)
    }

    @Test("A new ledger instance reuses the durable fingerprint and revision")
    func restartReusesDurableRevision() async throws {
        let persistence = FocusRevisionMemoryPersistence()
        let deviceID = UUID()
        let fingerprint = Data("idle".utf8)
        let firstLedger = FocusRevisionLedger(persistence: persistence)

        #expect(try await firstLedger.prepare(
            deviceID: deviceID,
            fingerprint: fingerprint,
            floor: 0
        ) == 1)

        let restartedLedger = FocusRevisionLedger(persistence: persistence)
        #expect(try await restartedLedger.prepare(
            deviceID: deviceID,
            fingerprint: fingerprint,
            floor: 0
        ) == 1)
        #expect(try await restartedLedger.prepare(
            deviceID: deviceID,
            fingerprint: Data("active".utf8),
            floor: 0
        ) == 2)
    }

    @Test("Maximum revision permits only an exact fingerprint retry")
    func maximumRevisionFailsClosedForChangedState() async throws {
        let deviceID = UUID()
        let fingerprint = Data("at-max".utf8)
        let initial = FocusRevisionLedgerSnapshot(entries: [
            FocusRevisionLedgerEntry(
                deviceID: deviceID,
                revision: .max,
                fingerprint: fingerprint
            ),
        ])
        let persistence = FocusRevisionMemoryPersistence(snapshot: initial)
        let ledger = FocusRevisionLedger(persistence: persistence)

        #expect(try await ledger.prepare(
            deviceID: deviceID,
            fingerprint: fingerprint,
            floor: .max
        ) == UInt32.max)
        await #expect(throws: FocusRevisionLedgerError.revisionExhausted) {
            _ = try await ledger.prepare(
                deviceID: deviceID,
                fingerprint: Data("changed".utf8),
                floor: 0
            )
        }
        await #expect(throws: FocusRevisionLedgerError.revisionExhausted) {
            _ = try await ledger.prepare(
                deviceID: UUID(),
                fingerprint: Data("new-device".utf8),
                floor: .max
            )
        }

        #expect(await persistence.snapshot() == initial)
        #expect(await persistence.saveCount() == 0)
    }

    @Test("A failed save does not publish or consume the next revision")
    func failedPersistenceDoesNotAdvance() async throws {
        let deviceID = UUID()
        let original = FocusRevisionLedgerSnapshot(entries: [
            FocusRevisionLedgerEntry(
                deviceID: deviceID,
                revision: 4,
                fingerprint: Data("before".utf8)
            ),
        ])
        let persistence = FocusRevisionMemoryPersistence(snapshot: original)
        let ledger = FocusRevisionLedger(persistence: persistence)
        await persistence.failNextSave()

        await #expect(throws: FocusRevisionPersistenceTestError.injectedSaveFailure) {
            _ = try await ledger.prepare(
                deviceID: deviceID,
                fingerprint: Data("after".utf8),
                floor: 0
            )
        }
        #expect(await persistence.snapshot() == original)

        let retry = try await ledger.prepare(
            deviceID: deviceID,
            fingerprint: Data("after".utf8),
            floor: 0
        )
        #expect(retry == 5)
    }

    @Test("A corrupt ledger waits for a device snapshot before rebuilding above its floor")
    func corruptLedgerRequiresDeviceFloor() async throws {
        let persistence = CorruptFocusRevisionPersistence()
        let ledger = FocusRevisionLedger(persistence: persistence)
        let deviceID = UUID()
        let fingerprint = Data("device-authority".utf8)

        await #expect(throws: DecodingError.self) {
            _ = try await ledger.prepare(
                deviceID: deviceID,
                fingerprint: fingerprint,
                floor: 0
            )
        }

        let recovered = try await ledger.prepareAfterDeviceSnapshot(
            deviceID: deviceID,
            fingerprint: fingerprint,
            floor: 41
        )
        #expect(recovered == 42)
        #expect(await persistence.savedSnapshot()?.entry(for: deviceID)?.revision == 42)
    }

    @Test("A validated all-zero idle snapshot recovers corruption before the first valid payload")
    func idleDeviceSnapshotRecoversCorruptLedgerAtZero() async throws {
        let persistence = CorruptFocusRevisionPersistence()
        let ledger = FocusRevisionLedger(persistence: persistence)
        let deviceID = UUID()

        try await ledger.recoverCorruptStoreAfterDeviceSnapshot(deviceID: deviceID, floor: 0)
        let firstValid = try await ledger.prepare(
            deviceID: deviceID,
            fingerprint: Data("first-valid".utf8),
            floor: 0
        )

        #expect(firstValid == 1)
        #expect(await persistence.savedSnapshot()?.entry(for: deviceID)?.revision == 1)
    }

    @Test("Concurrent preparations serialize one durable revision sequence")
    func concurrentPreparationsAreAtomic() async throws {
        let persistence = FocusRevisionMemoryPersistence(saveDelay: .milliseconds(2))
        let ledger = FocusRevisionLedger(persistence: persistence)
        let deviceID = UUID()

        let revisions = try await withThrowingTaskGroup(of: UInt32.self) { group in
            for index in 0..<12 {
                group.addTask {
                    try await ledger.prepare(
                        deviceID: deviceID,
                        fingerprint: Data("state-\(index)".utf8),
                        floor: 0
                    )
                }
            }
            var values: [UInt32] = []
            for try await value in group {
                values.append(value)
            }
            return values
        }

        #expect(Set(revisions) == Set((1...12).map(UInt32.init)))
        #expect(await persistence.saveCount() == 12)
        let stored = try #require(await persistence.snapshot())
        #expect(stored.entries.count == 1)
        #expect(stored.entries.first?.deviceID == deviceID)
        #expect(stored.entries.first?.revision == 12)
    }

    @Test("Concurrent exact retries share one persisted revision")
    func concurrentExactRetriesReuseRevision() async throws {
        let persistence = FocusRevisionMemoryPersistence(saveDelay: .milliseconds(2))
        let ledger = FocusRevisionLedger(persistence: persistence)
        let deviceID = UUID()
        let fingerprint = Data("same-state".utf8)

        let revisions = try await withThrowingTaskGroup(of: UInt32.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    try await ledger.prepare(
                        deviceID: deviceID,
                        fingerprint: fingerprint,
                        floor: 0
                    )
                }
            }
            var values: [UInt32] = []
            for try await value in group {
                values.append(value)
            }
            return values
        }

        #expect(revisions.allSatisfy { $0 == 1 })
        #expect(await persistence.saveCount() == 1)
    }
}

@Suite("Focus revision LocalStorage", .serialized)
struct FocusRevisionLocalStorageTests {
    @Test("Ledger snapshot round-trips through one atomic document")
    func snapshotRoundTrip() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let storage = LocalStorage.shared
            let original = try await storage.loadFocusRevisionLedger()
            let snapshot = FocusRevisionLedgerSnapshot(entries: [
                FocusRevisionLedgerEntry(
                    deviceID: UUID(),
                    revision: 9,
                    fingerprint: Data("persisted".utf8)
                ),
            ])

            try await storage.saveFocusRevisionLedger(snapshot)
            #expect(try await storage.loadFocusRevisionLedger() == snapshot)

            if let original {
                try await storage.saveFocusRevisionLedger(original)
            } else {
                try await storage.deleteFile(named: "focus_revision_ledger.json")
            }
        }
    }
}

private actor FocusRevisionMemoryPersistence: FocusRevisionLedgerPersisting {
    private var storedSnapshot: FocusRevisionLedgerSnapshot?
    private var remainingSaveFailures = 0
    private var saves = 0
    private let saveDelay: Duration?

    init(
        snapshot: FocusRevisionLedgerSnapshot? = nil,
        saveDelay: Duration? = nil
    ) {
        storedSnapshot = snapshot
        self.saveDelay = saveDelay
    }

    func loadFocusRevisionLedger() async throws -> FocusRevisionLedgerSnapshot? {
        storedSnapshot
    }

    func saveFocusRevisionLedger(_ snapshot: FocusRevisionLedgerSnapshot) async throws {
        if let saveDelay {
            try await Task.sleep(for: saveDelay)
        }
        if remainingSaveFailures > 0 {
            remainingSaveFailures -= 1
            throw FocusRevisionPersistenceTestError.injectedSaveFailure
        }
        storedSnapshot = snapshot
        saves += 1
    }

    func failNextSave() {
        remainingSaveFailures += 1
    }

    func snapshot() -> FocusRevisionLedgerSnapshot? {
        storedSnapshot
    }

    func saveCount() -> Int {
        saves
    }
}

private enum FocusRevisionPersistenceTestError: Error {
    case injectedSaveFailure
}

private actor CorruptFocusRevisionPersistence: FocusRevisionLedgerPersisting {
    private var isCorrupt = true
    private var saved: FocusRevisionLedgerSnapshot?

    func loadFocusRevisionLedger() throws -> FocusRevisionLedgerSnapshot? {
        if isCorrupt {
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "corrupt test ledger")
            )
        }
        return saved
    }

    func saveFocusRevisionLedger(_ snapshot: FocusRevisionLedgerSnapshot) {
        isCorrupt = false
        saved = snapshot
    }

    func savedSnapshot() -> FocusRevisionLedgerSnapshot? {
        saved
    }
}
