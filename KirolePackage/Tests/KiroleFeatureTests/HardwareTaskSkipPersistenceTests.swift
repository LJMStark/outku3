import Foundation
import Testing
@testable import KiroleFeature

@Suite("Hardware task skip persistence", .serialized)
struct HardwareTaskSkipPersistenceTests {
    @Test("The skip operation marker survives persistence and remains backward compatible")
    func skipMarkerCodableRoundTrip() throws {
        let task = TaskItem(
            id: "codable-skip",
            title: "Persist marker",
            hardwareSkipOperationKey: "device|18|99"
        )
        let encoded = try JSONEncoder().encode(task)
        let decoded = try JSONDecoder().decode(TaskItem.self, from: encoded)
        #expect(decoded.hardwareSkipOperationKey == "device|18|99")

        var oldObject = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        oldObject.removeValue(forKey: "hardwareSkipOperationKey")
        let oldData = try JSONSerialization.data(withJSONObject: oldObject)
        let oldDecoded = try JSONDecoder().decode(TaskItem.self, from: oldData)
        #expect(oldDecoded.hardwareSkipOperationKey == nil)
    }

    @Test("External task refresh preserves the local skip operation marker")
    func remoteRefreshPreservesSkipMarker() {
        let current = TaskItem(
            id: "remote-skip",
            title: "Current",
            hardwareSkipOperationKey: "device|18|100"
        )
        let remote = TaskItem(id: current.id, title: "Remote")

        let merged = AppState.regraftTodayDisplayDates(onto: [remote], from: [current])

        #expect(merged.first?.title == "Remote")
        #expect(merged.first?.hardwareSkipOperationKey == "device|18|100")
    }

    @Test("A hardware skip moves the task to the queue tail without completing or rewarding it")
    @MainActor
    func skipMovesTaskToTailWithoutReward() async {
        let appState = AppState.makeForTesting()
        let first = TaskItem(id: "skip-first", title: "First")
        let second = TaskItem(id: "skip-second", title: "Second")
        let third = TaskItem(id: "skip-third", title: "Third")
        appState.tasks = [first, second, third]
        let initialPoints = appState.pet.points
        let initialAdventures = appState.pet.adventuresCount
        let persistence = RecordingTaskSkipPersistence()

        let result = await appState.persistHardwareTaskSkip(
            taskID: first.id,
            operationKey: "device|18|1",
            persistence: persistence
        )

        #expect(result == .applied)
        #expect(appState.tasks.map(\.id) == [second.id, third.id, first.id])
        #expect(appState.tasks.last?.hardwareSkipOperationKey == "device|18|1")
        #expect(appState.tasks.last?.isCompleted == false)
        #expect(appState.pet.points == initialPoints)
        #expect(appState.pet.adventuresCount == initialAdventures)
        #expect(await persistence.latestTaskIDs() == [second.id, third.id, first.id])
        #expect(await persistence.petSaveCount() == 0)
    }

    @Test("A hardware queue update is immediate without exposing a staged content edit")
    @MainActor
    func immediateQueueUpdateKeepsEditedContentFrozen() async {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var now = start
        let appState = AppState.makeForTesting()
        appState.taskLibraryNowProvider = { now }
        let first = TaskItem(id: "frozen-first", title: "Before", dueDate: start)
        let second = TaskItem(id: "frozen-second", title: "Second", dueDate: start)
        let third = TaskItem(id: "frozen-third", title: "Third", dueDate: start)
        appState.tasks = [first, second, third]
        appState.taskLibraryStabilityState = TaskLibraryStabilityState()
        appState.taskLibraryHardwareTasksBaseline = nil

        var edited = first
        edited.title = "After"
        appState.tasks = [edited, second, third]
        let originalDeadline = appState.taskLibraryStabilityState.deadline

        let result = await appState.persistHardwareTaskSkip(
            taskID: second.id,
            operationKey: "device|18|2",
            persistence: RecordingTaskSkipPersistence()
        )

        #expect(result == .applied)
        let immediate = appState.taskLibraryPresentationSnapshot()
        #expect(immediate.readyUpdate?.scope == .hardwareQueue)
        #expect(immediate.usesFrozenBaseline)
        #expect(immediate.tasks.map(\.id) == [first.id, third.id, second.id])
        #expect(immediate.tasks.map(\.title) == ["Before", "Third", "Second"])
        #expect(appState.taskLibraryStabilityState.deadline == originalDeadline)

        guard let generation = immediate.readyUpdate?.generation else {
            Issue.record("Expected an immediate hardware queue update")
            return
        }
        appState.markTaskLibraryUpdateCommitted(scope: .hardwareQueue, generation: generation)
        #expect(appState.taskLibraryReadyUpdate() == nil)
        #expect(appState.tasksForHardwarePresentation().map(\.title) == ["Before", "Third", "Second"])

        now = start.addingTimeInterval(TaskLibraryStabilityState.window)
        #expect(appState.taskLibraryReadyUpdate()?.scope == .complete)
        #expect(appState.tasksForHardwarePresentation().map(\.title) == ["After", "Third", "Second"])
        appState.taskLibraryStabilityTask?.cancel()
    }

    @Test("A crash-pending skip retry does not disturb queue changes made after its first write")
    @MainActor
    func pendingRetryDoesNotMoveTaskTwice() async {
        let appState = AppState.makeForTesting()
        let first = TaskItem(id: "retry-first", title: "First")
        let second = TaskItem(id: "retry-second", title: "Second")
        let third = TaskItem(id: "retry-third", title: "Third")
        appState.tasks = [first, second, third]
        let persistence = RecordingTaskSkipPersistence(failingTaskSaves: 1)

        let failed = await appState.persistHardwareTaskSkip(
            taskID: first.id,
            operationKey: "device|18|11",
            persistence: persistence
        )
        #expect(failed == .persistenceFailed)
        #expect(appState.tasks.map(\.id) == [second.id, third.id, first.id])

        let later = await appState.persistHardwareTaskSkip(
            taskID: second.id,
            operationKey: "device|18|12",
            persistence: persistence
        )
        #expect(later == .applied)
        #expect(appState.tasks.map(\.id) == [third.id, first.id, second.id])

        let retry = await appState.persistHardwareTaskSkip(
            taskID: first.id,
            operationKey: "device|18|11",
            persistence: persistence
        )
        #expect(retry == .applied)
        #expect(appState.tasks.map(\.id) == [third.id, first.id, second.id])
        #expect(await persistence.latestTaskIDs() == [third.id, first.id, second.id])
    }

    @Test("A failed skip write leaves the ledger pending and its retry commits once")
    @MainActor
    func processorKeepsFailedSkipPending() async {
        let appState = AppState.makeForTesting()
        let first = TaskItem(id: "processor-first", title: "First")
        let second = TaskItem(id: "processor-second", title: "Second")
        appState.tasks = [first, second]
        let persistence = RecordingTaskSkipPersistence(failingTaskSaves: 1)
        let ledger = TaskOperationLedger(persistenceEnabled: false)
        let focus = makeFocusService()
        let event = EventLog(
            eventType: .skipTask,
            taskId: first.id,
            operationID: 31,
            timestamp: Date(timeIntervalSince1970: 1_700_000_031),
            hasDeviceTimestamp: true
        )
        let planned = TaskOperationReceipt(action: .skipTask, operationID: 31, result: .applied)

        let failed = await BLETaskOperationProcessor.process(
            event,
            plannedReceipt: planned,
            deviceID: "processor-device",
            focusService: focus,
            isReplay: true,
            operationLedger: ledger,
            appState: appState,
            hardwareTaskPersistence: persistence
        )

        #expect(failed.result == .internalError)
        #expect(await ledger.decision(for: event, deviceID: "processor-device") == .resume(.applied))
        #expect(appState.tasks.map(\.id) == [second.id, first.id])

        let retry = await BLETaskOperationProcessor.process(
            event,
            plannedReceipt: planned,
            deviceID: "processor-device",
            focusService: focus,
            isReplay: true,
            operationLedger: ledger,
            appState: appState,
            hardwareTaskPersistence: persistence
        )

        #expect(retry.result == .applied)
        #expect(await ledger.decision(for: event, deviceID: "processor-device") == .duplicate(.applied))
        #expect(appState.tasks.map(\.id) == [second.id, first.id])
    }

    @Test("Skip order and operation marker both advance task state without App supersede")
    @MainActor
    func skipAdvancesTaskStateVersion() async {
        let appState = AppState.makeForTesting()
        let first = TaskItem(id: "version-first", title: "First")
        let second = TaskItem(id: "version-second", title: "Second")
        appState.tasks = [first, second]
        let versionBeforeSkip = appState.taskStateVersion

        let result = await appState.persistHardwareTaskSkip(
            taskID: first.id,
            operationKey: "device|18|41",
            persistence: RecordingTaskSkipPersistence()
        )

        #expect(result == .applied)
        #expect(appState.taskStateVersion > versionBeforeSkip)
        #expect(appState.taskMutationGeneration(for: first.id) == 1)
    }

    @MainActor
    private func makeFocusService() -> FocusSessionService {
        FocusSessionService.makeForTesting(
            focusGuardService: HardwareTaskSkipFocusGuardStub(),
            persistenceEnabled: false
        )
    }
}

private actor RecordingTaskSkipPersistence: HardwareTaskStatePersisting {
    private var remainingFailingTaskSaves: Int
    private var taskSnapshots: [[TaskItem]] = []
    private var savedPets: [Pet] = []

    init(failingTaskSaves: Int = 0) {
        remainingFailingTaskSaves = failingTaskSaves
    }

    func saveTasks(_ tasks: [TaskItem]) async throws {
        if remainingFailingTaskSaves > 0 {
            remainingFailingTaskSaves -= 1
            throw TaskSkipPersistenceError.injectedFailure
        }
        taskSnapshots.append(tasks)
    }

    func savePet(_ pet: Pet) async throws {
        savedPets.append(pet)
    }

    func latestTaskIDs() -> [String] {
        taskSnapshots.last?.map(\.id) ?? []
    }

    func petSaveCount() -> Int { savedPets.count }
}

private enum TaskSkipPersistenceError: Error {
    case injectedFailure
}

@MainActor
private final class HardwareTaskSkipFocusGuardStub: FocusGuardService {
    var authorizationStatus: FocusAuthorizationStatus = .notDetermined
    var isDeepFocusFeatureEnabled = false
    var isDeepFocusCapable = false
    var canShowDeepFocusEntry: Bool { false }
    var selectedApplicationCount = 0
    var isPickerPresented = false

    func refreshAuthorizationStatus() async {}
    func requestAuthorization() async -> FocusAuthorizationStatus { .notDetermined }
    func presentAppPicker() {}
    func applyShield(selection: FocusAppSelection) throws {}
    func clearShield() {}
    func currentSelection() -> FocusAppSelection? { nil }
}
