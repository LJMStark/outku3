import Foundation

enum FocusRevisionLedgerError: Error, Equatable, Sendable {
    case revisionExhausted
}

struct FocusRevisionLedgerEntry: Codable, Equatable, Sendable {
    let deviceID: UUID
    let revision: UInt32
    let fingerprint: Data
}

struct FocusRevisionLedgerSnapshot: Codable, Equatable, Sendable {
    let entries: [FocusRevisionLedgerEntry]

    init(entries: [FocusRevisionLedgerEntry] = []) {
        self.entries = entries
    }

    func entry(for deviceID: UUID) -> FocusRevisionLedgerEntry? {
        entries.last { $0.deviceID == deviceID }
    }

    func replacing(_ entry: FocusRevisionLedgerEntry) -> FocusRevisionLedgerSnapshot {
        FocusRevisionLedgerSnapshot(
            entries: entries.filter { $0.deviceID != entry.deviceID } + [entry]
        )
    }
}

protocol FocusRevisionLedgerPersisting: Sendable {
    func loadFocusRevisionLedger() async throws -> FocusRevisionLedgerSnapshot?
    func saveFocusRevisionLedger(_ snapshot: FocusRevisionLedgerSnapshot) async throws
}

actor VolatileFocusRevisionLedgerPersistence: FocusRevisionLedgerPersisting {
    private var snapshot: FocusRevisionLedgerSnapshot?

    func loadFocusRevisionLedger() -> FocusRevisionLedgerSnapshot? {
        snapshot
    }

    func saveFocusRevisionLedger(_ snapshot: FocusRevisionLedgerSnapshot) {
        self.snapshot = snapshot
    }
}

/// Allocates the durable monotonic revision attached to one device's authoritative focus state.
/// The fingerprint must describe the frozen semantic payload without its revision field.
actor FocusRevisionLedger {
    static let shared = FocusRevisionLedger()

    private let persistence: any FocusRevisionLedgerPersisting
    private let preparationGate = FocusRevisionPreparationGate()

    init(persistence: any FocusRevisionLedgerPersisting = LocalStorage.shared) {
        self.persistence = persistence
    }

    /// Returns the existing revision for an exact retry, or durably reserves the next revision.
    /// `floor` is the highest revision already known from another authority, usually firmware.
    func prepare(
        deviceID: UUID,
        fingerprint: Data,
        floor: UInt32
    ) async throws -> UInt32 {
        try await prepare(
            deviceID: deviceID,
            fingerprint: fingerprint,
            floor: floor,
            recoverCorruptStore: false
        )
    }

    /// A corrupt file may only be rebuilt after the device has supplied FOCUS_STATE. Its revision
    /// is the lower bound, so recovery never silently restarts at one.
    func prepareAfterDeviceSnapshot(
        deviceID: UUID,
        fingerprint: Data,
        floor: UInt32
    ) async throws -> UInt32 {
        try await prepare(
            deviceID: deviceID,
            fingerprint: fingerprint,
            floor: floor,
            recoverCorruptStore: true
        )
    }

    /// Marks a corrupt store as recovered only after a validated device snapshot is available.
    /// The next semantic payload advances above this floor; an all-zero idle snapshot therefore
    /// restores the empty baseline and lets the first valid App payload start at revision one.
    func recoverCorruptStoreAfterDeviceSnapshot(
        deviceID: UUID,
        floor: UInt32
    ) async throws {
        await preparationGate.acquire()
        do {
            do {
                _ = try await persistence.loadFocusRevisionLedger()
            } catch is DecodingError {
                let recovered = FocusRevisionLedgerSnapshot(entries: [
                    FocusRevisionLedgerEntry(
                        deviceID: deviceID,
                        revision: floor,
                        fingerprint: Data()
                    ),
                ])
                try await persistence.saveFocusRevisionLedger(recovered)
            }
            await preparationGate.release()
        } catch {
            await preparationGate.release()
            throw error
        }
    }

    private func prepare(
        deviceID: UUID,
        fingerprint: Data,
        floor: UInt32,
        recoverCorruptStore: Bool
    ) async throws -> UInt32 {
        await preparationGate.acquire()
        do {
            try Task.checkCancellation()
            let revision = try await prepareWhileHoldingGate(
                deviceID: deviceID,
                fingerprint: fingerprint,
                floor: floor,
                recoverCorruptStore: recoverCorruptStore
            )
            await preparationGate.release()
            return revision
        } catch {
            await preparationGate.release()
            throw error
        }
    }

    private func prepareWhileHoldingGate(
        deviceID: UUID,
        fingerprint: Data,
        floor: UInt32,
        recoverCorruptStore: Bool
    ) async throws -> UInt32 {
        let snapshot: FocusRevisionLedgerSnapshot
        do {
            snapshot = try await persistence.loadFocusRevisionLedger()
                ?? FocusRevisionLedgerSnapshot()
        } catch is DecodingError where recoverCorruptStore {
            snapshot = FocusRevisionLedgerSnapshot()
        }
        let existing = snapshot.entry(for: deviceID)

        if let existing,
           existing.revision > 0,
           existing.fingerprint == fingerprint,
           existing.revision >= floor {
            return existing.revision
        }

        let currentRevision = max(existing?.revision ?? 0, floor)
        guard currentRevision < UInt32.max else {
            throw FocusRevisionLedgerError.revisionExhausted
        }
        let nextRevision = currentRevision + 1
        let updated = snapshot.replacing(
            FocusRevisionLedgerEntry(
                deviceID: deviceID,
                revision: nextRevision,
                fingerprint: fingerprint
            )
        )
        try await persistence.saveFocusRevisionLedger(updated)
        return nextRevision
    }
}

/// Swift actors are reentrant at each await. This gate keeps the ledger's load/modify/save sequence
/// indivisible even when the injected persistence actor suspends during disk I/O or a test delay.
private actor FocusRevisionPreparationGate {
    private var isPreparing = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard isPreparing else {
            isPreparing = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        guard let next = waiters.first else {
            isPreparing = false
            return
        }
        waiters.removeFirst()
        next.resume()
    }
}
