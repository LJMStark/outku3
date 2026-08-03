import Foundation
import Testing
@testable import KiroleFeature

@Suite("Hardware presentation transactions", .serialized)
struct HardwarePresentationTransactionTests {
    @Test("TaskIn completes while full sync is still preparing AI or avatar data")
    @MainActor
    func taskInPreemptsSlowFullSyncPreparation() async throws {
        let fixtures = ProtocolFixtures()
        let gate = HardwarePagePresentationGate()
        let preparation = PresentationTransactionPause()
        let box = PresentationFirmwareBox()
        box.firmware.beginEnterTaskIn(taskID: fixtures.taskId)

        let fullSync = Task { @MainActor in
            // Production performs AI generation, connection and avatar work before asking for the
            // presentation gate. Hold that preparation here while TaskIn commits independently.
            await preparation.stopAfterFirstPagePacket()
            _ = try await gate.performPresentationWrite(
                droppingIfPageTransactionIntervened: false
            ) {
                try box.firmware.receive(BLESimpleEncoder.encode(
                    type: BLEDataType.petStatus.rawValue,
                    payload: BLEDataEncoder.encodePetStatus(
                        fixtures.pet,
                        companionCharacter: .nova,
                        customActive: false
                    )
                ))
                if BLESyncCoordinator.shouldSendPreparedDayPack(
                    requested: true,
                    lastSentFingerprint: nil,
                    preparedFingerprint: "prepared-before-enter",
                    hasActiveFocusSession: true
                ) {
                    try box.firmware.receive(stream: BLEPacketizer.packetize(
                        type: BLEDataType.dayPack.rawValue,
                        messageId: 0x5EFF,
                        payload: BLEDataEncoder.encodeDayPack(
                            dayPack(topTasks: []),
                            screenSize: .fourInch
                        ),
                        maxChunkSize: 24
                    ))
                }
            }
        }
        await preparation.waitUntilStopped()

        await gate.performPageTransaction {
            do {
                try box.firmware.receive(stream: BLEPacketizer.packetize(
                    type: BLEDataType.taskInPage.rawValue,
                    messageId: 0x5F00,
                    payload: BLEDataEncoder.encodeTaskInPage(fixtures.taskInPage),
                    maxChunkSize: 18
                ))
            } catch {
                box.error = error
            }
        }

        try #require(box.error == nil)
        #expect(box.firmware.logicalWireTypes == [.taskInPage])
        #expect(box.firmware.refreshCount == 1)

        await preparation.resumePageTransaction()
        _ = try await fullSync.value
        #expect(box.firmware.logicalWireTypes == [.taskInPage, .petStatus])
        #expect(box.firmware.page == .taskIn)
        #expect(box.firmware.refreshCount == 1)
    }

    @Test("A focus update cannot split the complete TaskIn page transaction")
    @MainActor
    func focusUpdateCannotInterleaveTaskInChunks() async throws {
        let fixtures = ProtocolFixtures()
        let gate = HardwarePagePresentationGate()
        let pause = PresentationTransactionPause()
        let box = PresentationFirmwareBox()
        box.firmware.beginEnterTaskIn(taskID: fixtures.taskId)
        let packets = try BLEPacketizer.packetize(
            type: BLEDataType.taskInPage.rawValue,
            messageId: 0x5F01,
            payload: BLEDataEncoder.encodeTaskInPage(fixtures.taskInPage),
            maxChunkSize: 18
        )

        let page = Task { @MainActor in
            await gate.performPageTransaction {
                do {
                    try box.firmware.receive(packets[0])
                    await pause.stopAfterFirstPagePacket()
                    try box.firmware.receive(stream: Array(packets.dropFirst()))
                } catch {
                    box.error = error
                }
            }
        }
        await pause.waitUntilStopped()

        let focus = Task { @MainActor in
            try await gate.performPresentationWrite(
                droppingIfPageTransactionIntervened: true
            ) {
                try box.firmware.receive(BLESimpleEncoder.encode(
                    type: BLEDataType.focusStatus.rawValue,
                    payload: BLEDataEncoder.encodeFocusStatus(
                        phase: .warmup,
                        energyBottles: 0,
                        elapsedMinutes: 0,
                        taskTitle: fixtures.taskInPage.taskTitle,
                        segmentMinutes: 0
                    )
                ))
            }
        }
        await pause.resumePageTransaction()
        await page.value
        _ = try await focus.value

        try #require(box.error == nil)
        #expect(box.firmware.logicalWireTypes == [.taskInPage])
        #expect(box.firmware.page == .taskIn)
        #expect(box.firmware.refreshCount == 1)
    }

    @Test("Task action parks display frames and resumes identity only after 0x1B")
    @MainActor
    func taskActionParksDisplayAndResumesIdentityAfterAcknowledgement() async throws {
        let fixtures = ProtocolFixtures()
        let gate = HardwarePagePresentationGate()
        let pause = PresentationTransactionPause()
        let box = PresentationFirmwareBox()
        box.firmware.beginEnterTaskIn(taskID: fixtures.taskId)
        try box.firmware.receive(stream: BLEPacketizer.packetize(
            type: BLEDataType.taskInPage.rawValue,
            messageId: 0x5F02,
            payload: BLEDataEncoder.encodeTaskInPage(fixtures.taskInPage),
            maxChunkSize: 18
        ))
        try box.firmware.beginTaskAction(action: .completeTask, operationID: 70)
        box.firmware.clearWireLog()
        let refreshBaseline = box.firmware.refreshCount

        let action = Task { @MainActor in
            await gate.performPageTransaction {
                do {
                    try box.firmware.receive(stream: BLEPacketizer.packetize(
                        type: BLEDataType.dayPack.rawValue,
                        messageId: 0x5F03,
                        payload: BLEDataEncoder.encodeDayPack(
                            dayPack(topTasks: []),
                            screenSize: .fourInch
                        ),
                        maxChunkSize: 24
                    ))
                    await pause.stopAfterFirstPagePacket()
                    try box.firmware.receive(BLESimpleEncoder.encode(
                        type: BLEDataType.taskListSnapshotAck.rawValue,
                        payload: BLEDataEncoder.encodeTaskListSnapshotAck(TaskListSnapshotAck(
                            action: .completeTask,
                            operationID: 70,
                            result: .applied,
                            version: TaskListSnapshotVersion(epoch: 1, revision: 1),
                            tasks: []
                        ))
                    ))
                } catch {
                    box.error = error
                }
            }
        }
        await pause.waitUntilStopped()

        let idle = Task { @MainActor in
            try await gate.performPresentationWrite(
                droppingIfPageTransactionIntervened: true
            ) {
                try box.firmware.receive(BLESimpleEncoder.encode(
                    type: BLEDataType.focusStatus.rawValue,
                    payload: BLEDataEncoder.encodeFocusStatus(
                        phase: .idle,
                        energyBottles: 0,
                        elapsedMinutes: 0,
                        taskTitle: nil,
                        segmentMinutes: 0
                    )
                ))
            }
        }
        let scene = Task { @MainActor in
            try await gate.performPresentationWrite(
                droppingIfPageTransactionIntervened: true
            ) {
                try box.firmware.receive(BLESimpleEncoder.encode(
                    type: BLEDataType.sceneUnlock.rawValue,
                    payload: BLEDataEncoder.encodeSceneUnlock(.harbor)
                ))
            }
        }
        let identity = Task { @MainActor in
            try await gate.performPresentationWrite(
                droppingIfPageTransactionIntervened: false
            ) {
                try box.firmware.receive(BLESimpleEncoder.encode(
                    type: BLEDataType.petStatus.rawValue,
                    payload: BLEDataEncoder.encodePetStatus(
                        fixtures.pet,
                        companionCharacter: .nova,
                        customActive: false
                    )
                ))
            }
        }

        await pause.resumePageTransaction()
        await action.value
        _ = try await idle.value
        _ = try await scene.value
        _ = try await identity.value

        try #require(box.error == nil)
        #expect(box.firmware.logicalWireTypes == [
            .dayPack, .taskListSnapshotAck, .petStatus,
        ])
        #expect(box.firmware.page == .overview)
        #expect(box.firmware.refreshCount - refreshBaseline == 1)
    }

    @Test("Production EnterTaskIn sends the complete page before focus starts")
    @MainActor
    func productionEnterTaskInCommitsPageBeforeFocusStart() async throws {
        let fixtures = ProtocolFixtures()
        let task = try #require(fixtures.tasks.first)
        let box = PresentationFirmwareBox()
        box.firmware.beginEnterTaskIn(taskID: task.id)

        let delivered = await BLEEventHandler.performEnterTaskInPresentation(
            task: task,
            pet: fixtures.pet,
            userProfile: UserProfile(),
            sendTaskInPage: { page in
                try box.firmware.receive(stream: BLEPacketizer.packetize(
                    type: BLEDataType.taskInPage.rawValue,
                    messageId: 0x6001,
                    payload: BLEDataEncoder.encodeTaskInPage(page),
                    maxChunkSize: 18
                ))
            },
            startFocus: {
                box.focusStarted = true
                box.wireTypesWhenFocusStarted = box.firmware.logicalWireTypes
                box.refreshCountWhenFocusStarted = box.firmware.refreshCount
                return true
            }
        )

        #expect(delivered == .presented)
        #expect(box.focusStarted)
        #expect(box.wireTypesWhenFocusStarted == [.taskInPage])
        #expect(box.refreshCountWhenFocusStarted == 1)
        #expect(box.firmware.logicalWireTypes == [.taskInPage])
        #expect(box.firmware.page == .taskIn)
        #expect(box.firmware.renderedTaskInPage?.taskId == task.id)
        #expect(box.firmware.renderedTaskInPage?.taskTitle == task.title)
        #expect(box.firmware.renderedTaskInPage?.supportText.isEmpty == false)
        #expect(box.firmware.refreshCount == 1)
    }

    @Test("A stale TaskInPage write never starts focus")
    @MainActor
    func staleTaskInWriteDoesNotStartFocus() async throws {
        let fixtures = ProtocolFixtures()
        let task = try #require(fixtures.tasks.first)
        var focusStarted = false

        let delivered = await BLEEventHandler.performEnterTaskInPresentation(
            task: task,
            pet: fixtures.pet,
            userProfile: UserProfile(),
            sendTaskInPage: { _ in throw BLEError.staleTaskSnapshot },
            startFocus: {
                focusStarted = true
                return true
            }
        )

        #expect(delivered == .pageWriteFailed)
        #expect(!focusStarted)
    }

    @Test("A committed TaskIn page reports failure when App focus cannot start")
    @MainActor
    func focusStartFailureIsVisibleToTheRecoveryPath() async throws {
        let fixtures = ProtocolFixtures()
        let task = try #require(fixtures.tasks.first)
        var pageWasSent = false

        let result = await BLEEventHandler.performEnterTaskInPresentation(
            task: task,
            pet: fixtures.pet,
            userProfile: UserProfile(),
            sendTaskInPage: { _ in pageWasSent = true },
            startFocus: { false }
        )

        #expect(pageWasSent)
        #expect(result == .focusStartFailed)
    }

    @Test("EnterTaskIn renders only after the complete 0x11 payload arrives")
    func enterTaskInCommitsOneCompleteFirstFrame() throws {
        let fixtures = ProtocolFixtures()
        var firmware = SimulatedHardwarePresentation()
        firmware.beginEnterTaskIn(taskID: fixtures.taskId)

        let packets = try BLEPacketizer.packetize(
            type: BLEDataType.taskInPage.rawValue,
            messageId: 0x6101,
            payload: BLEDataEncoder.encodeTaskInPage(fixtures.taskInPage),
            maxChunkSize: 18
        )
        for packet in packets.dropLast() {
            try firmware.receive(packet)
        }

        #expect(firmware.page == .taskInPending)
        #expect(firmware.refreshCount == 0)
        #expect(firmware.logicalWireTypes.isEmpty)

        try firmware.receive(try #require(packets.last))

        #expect(firmware.page == .taskIn)
        #expect(firmware.renderedTaskInPage?.taskId == fixtures.taskId)
        #expect(firmware.renderedTaskInPage?.taskDescription == "Check every packet before hardware.")
        #expect(firmware.renderedTaskInPage?.supportText == "Stay with the next byte.")
        #expect(firmware.logicalWireTypes == [.taskInPage])
        #expect(firmware.refreshCount == 1)
    }

    @Test("Legacy focus-first entry is observable as a partial extra EPD refresh")
    func focusStatusBeforeTaskInWouldRenderTwice() throws {
        let fixtures = ProtocolFixtures()
        var firmware = SimulatedHardwarePresentation()
        firmware.beginEnterTaskIn(taskID: fixtures.taskId)

        try firmware.receive(simplePacket(
            type: .focusStatus,
            payload: BLEDataEncoder.encodeFocusStatus(
                phase: .warmup,
                energyBottles: 0,
                elapsedMinutes: 0,
                taskTitle: fixtures.taskInPage.taskTitle,
                segmentMinutes: 0
            )
        ))
        try firmware.receive(stream: BLEPacketizer.packetize(
            type: BLEDataType.taskInPage.rawValue,
            messageId: 0x6102,
            payload: BLEDataEncoder.encodeTaskInPage(fixtures.taskInPage),
            maxChunkSize: 18
        ))

        #expect(firmware.logicalWireTypes == [.focusStatus, .taskInPage])
        #expect(firmware.refreshCount == 2)
        #expect(firmware.page == .taskIn)
    }

    @Test(
        "Complete and Skip cache DayPack, then 0x1B exits TaskIn with one refresh",
        arguments: [TaskListSnapshotAction.completeTask, .skipTask]
    )
    @MainActor
    func taskActionCommitsDayPackAndOverviewAtomically(
        action: TaskListSnapshotAction
    ) async throws {
        let fixtures = ProtocolFixtures()
        let box = PresentationFirmwareBox()
        box.firmware.beginEnterTaskIn(taskID: fixtures.taskId)
        try box.firmware.receive(stream: BLEPacketizer.packetize(
            type: BLEDataType.taskInPage.rawValue,
            messageId: 0x6201,
            payload: BLEDataEncoder.encodeTaskInPage(fixtures.taskInPage),
            maxChunkSize: 18
        ))
        try box.firmware.beginTaskAction(action: action, operationID: 71)
        box.firmware.clearWireLog()
        let refreshBaseline = box.firmware.refreshCount

        let finalDayPack = dayPack(topTasks: [])
        let sender = FirmwareSnapshotSender(box: box)
        let hardwarePlan = FocusSessionEndHardwarePlan.make(
            defersHardwarePresentationUntilAcknowledgement: true,
            hasNewlyUnlockedScene: true
        )
        let presentation = FirmwareTaskActionPresentation(
            box: box,
            dayPack: finalDayPack,
            hardwarePlan: hardwarePlan
        )
        await BLEEventHandler.respondToLiveTaskOperations(
            [TaskOperationReceipt(action: action, operationID: 71, result: .applied)],
            sender: sender,
            presentationCoordinator: presentation,
            versionProvider: SingleSnapshotVersionProvider(),
            deliveryStore: nil,
            tasksProvider: { [] },
            taskStateVersionProvider: { 0 }
        )

        try #require(box.error == nil)
        #expect(box.firmware.logicalWireTypes == [.dayPack, .taskListSnapshotAck])
        #expect(box.firmware.page == .overview)
        #expect(box.firmware.cachedDayPack == nil)
        #expect(box.firmware.renderedDayPack?.settlementReview == "Final settlement")
        #expect(box.firmware.refreshCount - refreshBaseline == 1)
    }

    @Test("A non-hardware focus end keeps its immediate idle and optional scene updates")
    func manualFocusEndRetainsImmediateHardwareUpdates() {
        let plan = FocusSessionEndHardwarePlan.make(
            defersHardwarePresentationUntilAcknowledgement: false,
            hasNewlyUnlockedScene: true
        )

        #expect(plan.sendsIdleFocusStatus)
        #expect(plan.sendsSelectedScene)
    }

    @Test("Task-switch settlement plan never emits idle 0x14 that could overwrite a new 0x11")
    func taskSwitchSettlementPlanSuppressesIdle() {
        // EnterTaskIn for task B ends task A with suppressHardwarePresentation so the old
        // session's settlement cannot push idle after B's TaskInPage is already on the wire.
        let plan = FocusSessionEndHardwarePlan.make(
            defersHardwarePresentationUntilAcknowledgement: true,
            hasNewlyUnlockedScene: true
        )

        #expect(!plan.sendsIdleFocusStatus)
        #expect(!plan.sendsSelectedScene)
    }

    @Test("identityChange and manual triggers survive task-action presentation cancellation")
    func identityTriggersSurviveTaskActionCancellation() {
        #expect(BLESyncTrigger.identityChange.survivesTaskActionPresentation)
        #expect(BLESyncTrigger.manual.survivesTaskActionPresentation)
        #expect(!BLESyncTrigger.automatic.survivesTaskActionPresentation)
        #expect(!BLESyncTrigger.requestRefresh.survivesTaskActionPresentation)
        #expect(!BLESyncTrigger.deviceWake.survivesTaskActionPresentation)
        #expect(!BLESyncTrigger.background.survivesTaskActionPresentation)
    }

    @Test("Worst-case firmware refreshes three times when idle and scene arrive before 0x1B")
    func preCommitDisplayFramesBreakAtomicExitInWorstCase() throws {
        let fixtures = ProtocolFixtures()
        // 0x17 is not yet contracted to refresh the current page. Count it here only as a
        // conservative firmware model; the confirmed fixed path does not send 0x17 at all.
        var firmware = SimulatedHardwarePresentation(refreshesOnSceneUpdate: true)
        firmware.beginEnterTaskIn(taskID: fixtures.taskId)
        try firmware.receive(stream: BLEPacketizer.packetize(
            type: BLEDataType.taskInPage.rawValue,
            messageId: 0x6301,
            payload: BLEDataEncoder.encodeTaskInPage(fixtures.taskInPage),
            maxChunkSize: 18
        ))
        try firmware.beginTaskAction(action: .completeTask, operationID: 72)
        firmware.clearWireLog()
        let baseline = firmware.refreshCount

        try firmware.receive(simplePacket(
            type: .focusStatus,
            payload: BLEDataEncoder.encodeFocusStatus(
                phase: .idle,
                energyBottles: 0,
                elapsedMinutes: 0,
                taskTitle: nil,
                segmentMinutes: 0
            )
        ))
        try firmware.receive(simplePacket(
            type: .sceneUnlock,
            payload: BLEDataEncoder.encodeSceneUnlock(.harbor)
        ))
        try firmware.receive(stream: BLEPacketizer.packetize(
            type: BLEDataType.dayPack.rawValue,
            messageId: 0x6302,
            payload: BLEDataEncoder.encodeDayPack(dayPack(topTasks: []), screenSize: .fourInch),
            maxChunkSize: 24
        ))
        try firmware.receive(simplePacket(
            type: .taskListSnapshotAck,
            payload: BLEDataEncoder.encodeTaskListSnapshotAck(TaskListSnapshotAck(
                action: .completeTask,
                operationID: 72,
                result: .applied,
                version: TaskListSnapshotVersion(epoch: 1, revision: 1),
                tasks: []
            ))
        ))

        #expect(firmware.logicalWireTypes == [
            .focusStatus, .sceneUnlock, .dayPack, .taskListSnapshotAck,
        ])
        #expect(firmware.refreshCount - baseline == 3)
    }

    private func simplePacket(type: BLEDataType, payload: Data) -> Data {
        BLESimpleEncoder.encode(type: type.rawValue, payload: payload)
    }

    private func dayPack(topTasks: [TaskSummary]) -> DayPack {
        DayPack(
            date: Date(),
            deviceMode: .interactive,
            focusChallengeEnabled: true,
            petDialogue: "Done together.",
            daySummary: "Updated overview",
            firstUp: "Nothing urgent",
            settlementReview: "Final settlement",
            settlementQuote: "One thing finished well.",
            events: [],
            topTasks: topTasks,
            settlementData: SettlementData(
                tasksCompleted: 1,
                tasksTotal: 1,
                pointsEarned: 1,
                petMood: "happy",
                summaryMessage: "",
                encouragementMessage: "",
                totalFocusMinutes: 1,
                focusSessionCount: 1,
                longestFocusMinutes: 1,
                interruptionCount: 0,
                totalEnergyBottles: 0
            )
        )
    }
}

actor PresentationTransactionPause {
    private var stopped = false
    private var stoppedWaiter: CheckedContinuation<Void, Never>?
    private var resumeWaiter: CheckedContinuation<Void, Never>?

    func stopAfterFirstPagePacket() async {
        stopped = true
        stoppedWaiter?.resume()
        stoppedWaiter = nil
        await withCheckedContinuation { continuation in
            resumeWaiter = continuation
        }
    }

    func waitUntilStopped() async {
        guard !stopped else { return }
        await withCheckedContinuation { continuation in
            stoppedWaiter = continuation
        }
    }

    func resumePageTransaction() {
        resumeWaiter?.resume()
        resumeWaiter = nil
    }
}

enum SimulatedHardwarePage: Equatable {
    case overview
    case taskInPending
    case taskIn
}

enum PresentationSimulationError: Error {
    case unexpectedTaskIn
    case missingFinalDayPack
    case mismatchedFinalSnapshot
}

struct SimulatedHardwarePresentation {
    private var transport = SimulatedHardware()
    private var snapshot = SimulatedTaskListSnapshotFirmware()
    private var expectedTaskID: String?
    private let refreshesOnSceneUpdate: Bool

    private(set) var page: SimulatedHardwarePage = .overview
    private(set) var renderedTaskInPage: SimulatedTaskInPage?
    private(set) var renderedDayPack: SimulatedDayPack?
    private(set) var cachedDayPack: SimulatedDayPack?
    private(set) var activeScene = DisplayScene.harbor
    private(set) var refreshCount = 0
    private(set) var logicalWireTypes: [BLEDataType] = []

    init(refreshesOnSceneUpdate: Bool = false) {
        self.refreshesOnSceneUpdate = refreshesOnSceneUpdate
    }

    mutating func beginEnterTaskIn(taskID: String) {
        expectedTaskID = taskID
        page = .taskInPending
    }

    mutating func beginTaskAction(
        action: TaskListSnapshotAction,
        operationID: UInt32
    ) throws {
        try snapshot.beginPending(action: action, operationID: operationID)
    }

    mutating func clearWireLog() {
        logicalWireTypes = []
    }

    mutating func receive(stream: [Data]) throws {
        for packet in stream {
            try receive(packet)
        }
    }

    mutating func receive(_ packet: Data) throws {
        guard let message = try transport.receiveAppPacket(packet) else { return }
        guard let type = BLEDataType(rawValue: message.type) else { return }
        logicalWireTypes.append(type)

        switch type {
        case .taskInPage:
            let taskIn = try message.parseTaskInPage()
            guard page == .taskInPending, taskIn.taskId == expectedTaskID else {
                throw PresentationSimulationError.unexpectedTaskIn
            }
            renderedTaskInPage = taskIn
            page = .taskIn
            refreshCount += 1

        case .dayPack:
            let dayPack = try message.parseDayPack()
            if snapshot.pendingOperationID != nil {
                cachedDayPack = dayPack
            } else {
                renderedDayPack = dayPack
                page = .overview
                refreshCount += 1
            }

        case .taskListSnapshotAck:
            let acknowledgement = try message.parseTaskListSnapshotAck()
            let finalDayPack = try requireFinalDayPack(matching: acknowledgement)
            try snapshot.apply(acknowledgement, screenSize: .fourInch)
            renderedDayPack = finalDayPack
            cachedDayPack = nil
            renderedTaskInPage = nil
            page = .overview
            refreshCount += 1

        case .focusStatus:
            let focus = try message.parseFocusStatus()
            if focus.phase == .idle {
                renderedTaskInPage = nil
                page = .overview
            }
            refreshCount += 1

        case .sceneUnlock:
            activeScene = try message.parseDisplayScene()
            if refreshesOnSceneUpdate {
                refreshCount += 1
            }

        default:
            break
        }
    }

    private func requireFinalDayPack(
        matching acknowledgement: SimulatedTaskListSnapshotAck
    ) throws -> SimulatedDayPack {
        guard let cachedDayPack else {
            throw PresentationSimulationError.missingFinalDayPack
        }
        let dayPackTasks = cachedDayPack.topTasks.map {
            ($0.id, $0.title, $0.isCompleted, $0.priority)
        }
        let acknowledgementTasks = acknowledgement.tasks.map {
            ($0.id, $0.title, $0.isCompleted, $0.priority)
        }
        guard dayPackTasks.elementsEqual(acknowledgementTasks, by: { lhs, rhs in
            lhs.0 == rhs.0 && lhs.1 == rhs.1 && lhs.2 == rhs.2 && lhs.3 == rhs.3
        }) else {
            throw PresentationSimulationError.mismatchedFinalSnapshot
        }
        return cachedDayPack
    }
}

@MainActor
final class PresentationFirmwareBox {
    var firmware = SimulatedHardwarePresentation()
    var error: Error?
    var focusStarted = false
    var wireTypesWhenFocusStarted: [BLEDataType] = []
    var refreshCountWhenFocusStarted = 0
}

@MainActor
private final class FirmwareSnapshotSender: TaskListSnapshotSending {
    let hardwareScreenSize: ScreenSize = .fourInch
    private let box: PresentationFirmwareBox

    init(box: PresentationFirmwareBox) {
        self.box = box
    }

    func withTaskStateMessageGate(
        _ operation: @MainActor () async throws -> Void
    ) async throws {
        try await operation()
    }

    func writeTaskListSnapshotAckPayload(
        _ payload: Data,
        expectedTaskStateVersion: UInt64?
    ) async throws {
        try box.firmware.receive(BLESimpleEncoder.encode(
            type: BLEDataType.taskListSnapshotAck.rawValue,
            payload: payload
        ))
    }
}

@MainActor
private final class FirmwareTaskActionPresentation: TaskActionPresentationCoordinating {
    private let box: PresentationFirmwareBox
    private let dayPack: DayPack
    private let hardwarePlan: FocusSessionEndHardwarePlan

    init(
        box: PresentationFirmwareBox,
        dayPack: DayPack,
        hardwarePlan: FocusSessionEndHardwarePlan
    ) {
        self.box = box
        self.dayPack = dayPack
        self.hardwarePlan = hardwarePlan
    }

    func sendFinalDayPackBeforeAcknowledgement(
        _ acknowledgement: @MainActor @Sendable (UInt64) async -> TaskListSnapshotResponder.Outcome
    ) async {
        do {
            if hardwarePlan.sendsIdleFocusStatus {
                try box.firmware.receive(BLESimpleEncoder.encode(
                    type: BLEDataType.focusStatus.rawValue,
                    payload: BLEDataEncoder.encodeFocusStatus(
                        phase: .idle,
                        energyBottles: 0,
                        elapsedMinutes: 0,
                        taskTitle: nil,
                        segmentMinutes: 0
                    )
                ))
            }
            if hardwarePlan.sendsSelectedScene {
                try box.firmware.receive(BLESimpleEncoder.encode(
                    type: BLEDataType.sceneUnlock.rawValue,
                    payload: BLEDataEncoder.encodeSceneUnlock(.harbor)
                ))
            }
            try box.firmware.receive(stream: BLEPacketizer.packetize(
                type: BLEDataType.dayPack.rawValue,
                messageId: 0x6401,
                payload: BLEDataEncoder.encodeDayPack(dayPack, screenSize: .fourInch),
                maxChunkSize: 24
            ))
            _ = await acknowledgement(0)
        } catch {
            box.error = error
        }
    }
}

private actor SingleSnapshotVersionProvider: TaskListSnapshotVersionProviding {
    func nextTaskListSnapshotVersion() async throws -> TaskListSnapshotVersion {
        TaskListSnapshotVersion(epoch: 1, revision: 1)
    }
}
