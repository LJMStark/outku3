import Foundation
@testable import KiroleFeature

actor ScenarioAppPersistence: HardwareTaskStatePersisting {
    private var storedTasks: [TaskItem] = []
    private var storedPet: Pet?

    func replace(tasks: [TaskItem], pet: Pet) {
        storedTasks = tasks
        storedPet = pet
    }

    func load() -> (tasks: [TaskItem], pet: Pet?) {
        (storedTasks, storedPet)
    }

    func saveTasks(_ tasks: [TaskItem]) async throws {
        storedTasks = tasks
    }

    func savePet(_ pet: Pet) async throws {
        storedPet = pet
    }
}

actor ScenarioFocusPersistence: FocusSessionPersisting {
    private var storedSessions: [FocusSession] = []
    private var storedActiveSession: FocusSession?
    private var energyReceipts: [UUID: Int] = [:]
    private var storedEnergyTotal = 0

    func loadSessions() async throws -> [FocusSession]? {
        storedSessions
    }

    func saveSessions(_ sessions: [FocusSession], date: Date) async throws {
        storedSessions = sessions
    }

    func loadActiveSession() async throws -> FocusSession? {
        storedActiveSession
    }

    func saveActiveSession(_ session: FocusSession) async throws {
        storedActiveSession = session
    }

    func clearActiveSession() async throws {
        storedActiveSession = nil
    }

    func applyEnergyReward(receiptID: UUID, bottles: Int) async throws -> Int {
        if let previousTotal = energyReceipts[receiptID] {
            storedEnergyTotal = max(storedEnergyTotal, previousTotal)
            return storedEnergyTotal
        }
        let nextTotal = storedEnergyTotal + max(0, bottles)
        energyReceipts[receiptID] = nextTotal
        storedEnergyTotal = nextTotal
        return nextTotal
    }

    func activeSession() -> FocusSession? {
        storedActiveSession
    }

    func sessions() -> [FocusSession] {
        storedSessions
    }
}

actor ScenarioTaskOperationPersistence: TaskOperationLedgerPersisting {
    private var storedEntries: [TaskOperationLedgerEntry] = []

    func loadTaskOperationLedger() async throws -> [TaskOperationLedgerEntry]? {
        storedEntries
    }

    func saveTaskOperationLedger(_ entries: [TaskOperationLedgerEntry]) async throws {
        storedEntries = entries
    }

    func entries() -> [TaskOperationLedgerEntry] {
        storedEntries
    }
}

actor InMemoryTaskListSnapshotDeliveryStore: TaskListSnapshotDeliveryStoring {
    private struct Reservation {
        let key: TaskListSnapshotRequestKey
        let version: TaskListSnapshotVersion
    }

    private struct StoredResponse {
        let response: FrozenTaskListSnapshotResponse
        var isAttempted: Bool
    }

    private struct DestinationState {
        var lastFrozenVersion: TaskListSnapshotVersion?
        var reservation: Reservation?
        var response: StoredResponse?
    }

    private let versionProvider: any TaskListSnapshotVersionProviding
    private var destinations: [String: DestinationState] = [:]

    init(versionProvider: any TaskListSnapshotVersionProviding) {
        self.versionProvider = versionProvider
    }

    func prepareTaskListSnapshotDelivery(
        for key: TaskListSnapshotRequestKey
    ) async throws -> TaskListSnapshotDeliveryPreparation {
        var destination = destinations[key.destinationID]
        if let stored = destination?.response {
            if stored.isAttempted {
                guard stored.response.key == key else {
                    throw SimulationError.invalidSnapshotState
                }
                return .frozen(stored.response)
            }
            destination?.response = nil
            destination?.reservation = Reservation(
                key: key,
                version: stored.response.version
            )
            destinations[key.destinationID] = destination
            return .reserved(stored.response.version)
        }
        if let reservation = destination?.reservation {
            destination?.reservation = Reservation(key: key, version: reservation.version)
            destinations[key.destinationID] = destination
            return .reserved(reservation.version)
        }
        let version: TaskListSnapshotVersion
        if let lastVersion = destination?.lastFrozenVersion {
            guard lastVersion.revision < UInt32.max else {
                throw SimulationError.invalidSnapshotState
            }
            version = TaskListSnapshotVersion(
                epoch: lastVersion.epoch,
                revision: lastVersion.revision + 1
            )
        } else {
            let seed = try await versionProvider.nextTaskListSnapshotVersion()
            var epoch = max(seed.epoch, 1)
            let usedEpochs = Set(destinations.values.compactMap {
                $0.lastFrozenVersion?.epoch ?? $0.reservation?.version.epoch
            })
            while usedEpochs.contains(epoch) {
                epoch = epoch == UInt32.max ? 1 : epoch + 1
            }
            version = TaskListSnapshotVersion(epoch: epoch, revision: 1)
        }
        destination = DestinationState(
            lastFrozenVersion: destination?.lastFrozenVersion,
            reservation: Reservation(key: key, version: version),
            response: nil
        )
        destinations[key.destinationID] = destination
        return .reserved(version)
    }

    func freezeTaskListSnapshotDelivery(
        _ response: FrozenTaskListSnapshotResponse
    ) throws {
        guard var destination = destinations[response.key.destinationID],
              destination.reservation?.key == response.key,
              destination.reservation?.version == response.version else {
            throw SimulationError.invalidSnapshotState
        }
        destination.response = StoredResponse(response: response, isAttempted: false)
        destination.lastFrozenVersion = response.version
        destination.reservation = nil
        destinations[response.key.destinationID] = destination
    }

    func markTaskListSnapshotDeliveryAttempted(
        _ response: FrozenTaskListSnapshotResponse
    ) throws {
        guard var destination = destinations[response.key.destinationID],
              var stored = destination.response,
              stored.response == response else {
            throw SimulationError.invalidSnapshotState
        }
        stored.isAttempted = true
        destination.response = stored
        destinations[response.key.destinationID] = destination
    }

    func rewindUnwrittenTaskListSnapshotDelivery(
        _ response: FrozenTaskListSnapshotResponse
    ) throws {
        guard var destination = destinations[response.key.destinationID] else {
            throw SimulationError.invalidSnapshotState
        }
        if destination.reservation?.key == response.key,
           destination.reservation?.version == response.version {
            return
        }
        guard destination.response?.response == response else {
            throw SimulationError.invalidSnapshotState
        }
        destination.response = nil
        destination.reservation = Reservation(
            key: response.key,
            version: response.version
        )
        destinations[response.key.destinationID] = destination
    }

    func completeTaskListSnapshotDelivery(
        _ response: FrozenTaskListSnapshotResponse
    ) {
        guard var destination = destinations[response.key.destinationID],
              destination.response?.response == response else { return }
        destination.response = nil
        destinations[response.key.destinationID] = destination
    }

    func frozenResponseCount() -> Int {
        destinations.values.reduce(into: 0) { count, destination in
            if destination.response != nil { count += 1 }
        }
    }

    func preparedDestinationIDs() -> Set<String> {
        Set(destinations.keys)
    }
}
