import Foundation
@testable import KiroleFeature

enum ScenarioConnectionState: Equatable {
    case disconnected
    case connected
}

enum ScenarioTransactionResult: Equatable {
    case delivered
    case failed(chunkIndex: Int)
}

struct ScenarioOutboundTransaction {
    let type: UInt8
    let messageID: UInt16
    let packetCount: Int
    let writtenPacketCount: Int
    let result: ScenarioTransactionResult
    let receivedPacket: SimulatedAppPacket?
}

struct AppDeviceScenarioSnapshot {
    let now: Date
    let connectionState: ScenarioConnectionState
    let appTasks: [TaskItem]
    let executedSyncTriggers: [BLESyncTrigger]
    let outboundTransactions: [ScenarioOutboundTransaction]
    let committedVersion: TaskListSnapshotVersion?
    let pendingVersion: TaskListSnapshotVersion?
    let taskQueue: [String]
    let focus: FocusProgressSnapshot?
    let currentPage: ScenarioDevicePage
    let deviceFocus: ScenarioDeviceFocus?
    let offlineActions: [EventLog]
    let appOperationLedger: [TaskOperationLedgerEntry]
    let focusHistory: [FocusSession]
}

enum AppDeviceScenarioError: Error, Equatable {
    case disconnected
    case chunkWriteFailed(index: Int)
    case chunkIndexOutOfRange(index: Int, packetCount: Int)
    case invalidOfflineTaskAction
    case malformedOfflineEvent
}

@MainActor
final class AppDeviceScenario {
    private(set) var appState: AppState

    private let clock: any ScenarioClock
    private let ai: ScriptedScenarioAI
    private let taskSnapshotVersionProvider: ScenarioTaskSnapshotVersionProvider
    private let appPersistence: ScenarioAppPersistence
    private let focusPersistence: ScenarioFocusPersistence
    private let operationPersistence: ScenarioTaskOperationPersistence
    private let frozenTaskSnapshotPersistence: InMemoryTaskListSnapshotDeliveryStore
    private var taskOperationLedger: TaskOperationLedger
    private var focusService: FocusSessionService
    private var currentDate: Date
    private var connectionState: ScenarioConnectionState = .disconnected
    private var executedSyncTriggers: [BLESyncTrigger] = []
    private var hardware = SimulatedHardware()
    private var appInboundAssembler = BLEPacketAssembler()
    private var taskSnapshotFirmware = SimulatedTaskListSnapshotFirmware()
    private var outboundTransactions: [ScenarioOutboundTransaction] = []
    private var failedChunkIndexes: [Int] = []
    private var taskSnapshotMaxWriteLength = 185
    private var nextTaskSnapshotMessageID: UInt16 = 0x7000
    private var nextDeviceMessageID: UInt16 = 0x5000
    private var currentPage: ScenarioDevicePage = .overview
    private var deviceFocus: ScenarioDeviceFocus?
    private var offlineEventRecords: [Data] = []

    init(now: Date, aiResponses: [ScenarioAIResponse] = []) {
        let clock = MutableScenarioClock(now: now)
        let appPersistence = ScenarioAppPersistence()
        let focusPersistence = ScenarioFocusPersistence()
        let operationPersistence = ScenarioTaskOperationPersistence()
        let taskSnapshotVersionProvider = ScenarioTaskSnapshotVersionProvider()
        let frozenTaskSnapshotPersistence = InMemoryTaskListSnapshotDeliveryStore(
            versionProvider: taskSnapshotVersionProvider
        )
        let taskOperationLedger = TaskOperationLedger(
            persistenceEnabled: true,
            persistence: operationPersistence
        )
        self.clock = clock
        self.ai = ScriptedScenarioAI(responses: aiResponses)
        self.taskSnapshotVersionProvider = taskSnapshotVersionProvider
        self.appPersistence = appPersistence
        self.focusPersistence = focusPersistence
        self.operationPersistence = operationPersistence
        self.frozenTaskSnapshotPersistence = frozenTaskSnapshotPersistence
        self.taskOperationLedger = taskOperationLedger
        self.currentDate = now
        self.appState = AppState.makeForTesting()
        self.focusService = FocusSessionService.makeForTesting(
            focusGuardService: ScenarioFocusGuard(),
            persistenceEnabled: true,
            focusPersistence: focusPersistence,
            taskOperationLedger: taskOperationLedger
        )
        installAppBoundaries()
    }

    func connect() {
        connectionState = .connected
    }

    func disconnect() {
        connectionState = .disconnected
        hardware = SimulatedHardware()
        appInboundAssembler = BLEPacketAssembler()
    }

    func reconnect() {
        connectionState = .connected
    }

    func replaceAppTasks(_ tasks: [TaskItem]) async {
        appState.tasks = tasks
        await appPersistence.replace(tasks: tasks, pet: appState.pet)
    }

    func restartApp() async {
        connectionState = .disconnected
        hardware = SimulatedHardware()
        appInboundAssembler = BLEPacketAssembler()
        let pendingTask = appState.pendingBLESyncTask
        appState.cancelPendingBLESync()
        await pendingTask?.value
        await ai.cancelAllSuspendedRequests()

        let persistedAppState = await appPersistence.load()
        let persistedFocus = await focusPersistence.activeSession()
        focusService.stopRuntimeForTesting()
        taskOperationLedger = TaskOperationLedger(
            persistenceEnabled: true,
            persistence: operationPersistence
        )
        focusService = FocusSessionService.makeForTesting(
            focusGuardService: ScenarioFocusGuard(),
            persistenceEnabled: true,
            focusPersistence: focusPersistence,
            taskOperationLedger: taskOperationLedger
        )
        if let persistedFocus {
            focusService.recoverPersistedSessionForTesting(
                persistedFocus,
                wasShieldActive: false,
                endTime: currentDate
            )
            await focusService.waitForPendingPersistenceForTesting()
        }

        appState = AppState.makeForTesting()
        appState.tasks = persistedAppState.tasks
        if let pet = persistedAppState.pet {
            appState.pet = pet
        }
        installAppBoundaries()
    }

    func restartDevice() {
        connectionState = .disconnected
        hardware = SimulatedHardware()
        appInboundAssembler = BLEPacketAssembler()
        taskSnapshotFirmware.simulatePowerCycle()
        failedChunkIndexes.removeAll()
    }

    func showDevicePage(_ page: ScenarioDevicePage) {
        currentPage = page
    }

    func setDeviceFocus(_ focus: ScenarioDeviceFocus?) {
        deviceFocus = focus
    }

    func recordOfflineTaskAction(
        _ action: TaskListSnapshotAction,
        task: TaskItem,
        operationID: UInt32,
        at timestamp: Date
    ) throws {
        guard connectionState == .disconnected,
              action == .completeTask || action == .skipTask else {
            throw AppDeviceScenarioError.invalidOfflineTaskAction
        }
        let record = try ScenarioDeviceEventCodec.taskOperationRecord(
            action: action,
            taskID: task.hardwareIdentifier,
            operationID: operationID,
            timestamp: timestamp
        )
        guard BLEEventHandler.parseEventLogRecord(from: record) != nil else {
            throw AppDeviceScenarioError.malformedOfflineEvent
        }
        offlineEventRecords.append(record)
    }

    func configureTaskSnapshotTransport(maxWriteLength: Int) {
        taskSnapshotMaxWriteLength = max(maxWriteLength, BLEPacketizer.headerSize + 1)
    }

    func failNextWrite(atChunk index: Int) {
        failedChunkIndexes.append(index)
    }

    func deviceRequestsTaskRefresh(
        operationID: UInt32
    ) async throws -> TaskListSnapshotResponder.Outcome {
        guard connectionState == .connected else {
            throw AppDeviceScenarioError.disconnected
        }
        try taskSnapshotFirmware.beginPending(
            action: .requestRefresh,
            operationID: operationID
        )
        return await TaskListSnapshotResponder.respond(
            to: [TaskOperationReceipt(
                action: .requestRefresh,
                operationID: operationID,
                result: .applied
            )],
            sender: self,
            versionProvider: taskSnapshotVersionProvider,
            deliveryStore: frozenTaskSnapshotPersistence,
            tasksProvider: { [weak self] in self?.appState.tasks ?? [] },
            nowProvider: { [weak self] in self?.currentDate ?? Date() },
            retrySleeper: { _ in },
            taskStateVersionProvider: { [weak self] in
                self?.appState.taskStateVersion ?? 0
            }
        )
    }

    @discardableResult
    func replayOfflineActions() async throws -> TaskListSnapshotResponder.Outcome {
        guard connectionState == .connected else {
            throw AppDeviceScenarioError.disconnected
        }
        var overallOutcome: TaskListSnapshotResponder.Outcome = .sent
        var acknowledgedRecordCounts: [String: Int] = [:]

        for recordBatch in offlineEventRecords.chunked(maxCount: Int(UInt8.max)) {
            var batchPayload = Data([UInt8(recordBatch.count)])
            recordBatch.forEach { batchPayload.append($0) }
            let packets = try BLEPacketizer.packetize(
                type: BLEDataType.eventLogBatch.rawValue,
                messageId: allocateDeviceMessageID(),
                payload: batchPayload,
                maxChunkSize: 24
            )
            var receivedMessage: BLEReceivedMessage?
            for packet in packets {
                if let message = appInboundAssembler.append(packetData: packet, now: currentDate) {
                    receivedMessage = message
                }
            }
            guard let receivedMessage,
                  receivedMessage.type == BLEDataType.eventLogBatch.rawValue else {
                throw AppDeviceScenarioError.malformedOfflineEvent
            }
            let logs = BLEEventHandler.parseEventLogBatchPayload(receivedMessage.payload)
            guard logs.count == recordBatch.count else {
                throw AppDeviceScenarioError.malformedOfflineEvent
            }
            let processing = await BLEEventHandler.processEventLogs(
                logs,
                service: nil,
                focusService: focusService,
                isReplay: true,
                lastTimestampOverride: 0,
                tasksOverride: appState.tasks,
                persistLogs: false,
                operationLedger: taskOperationLedger,
                deviceIDOverride: "scenario-device",
                appState: appState,
                hardwareTaskPersistence: appPersistence,
                nowProvider: { [weak self] in self?.currentDate ?? Date() }
            )

            let taskOperationLogs = processing.logs.filter {
                $0.eventType == .completeTask || $0.eventType == .skipTask
            }
            guard taskOperationLogs.count == processing.taskOperationReceipts.count else {
                throw AppDeviceScenarioError.malformedOfflineEvent
            }
            for (log, receipt) in zip(
                taskOperationLogs,
                processing.taskOperationReceipts
            ) {
                try taskSnapshotFirmware.beginPending(
                    action: receipt.action,
                    operationID: receipt.operationID
                )
                let outcome = await TaskListSnapshotResponder.respond(
                    to: [receipt],
                    sender: self,
                    versionProvider: taskSnapshotVersionProvider,
                    deliveryStore: frozenTaskSnapshotPersistence,
                    tasksProvider: { [weak self] in self?.appState.tasks ?? [] },
                    nowProvider: { [weak self] in self?.currentDate ?? Date() },
                    retrySleeper: { _ in },
                    taskStateVersionProvider: { [weak self] in
                        self?.appState.taskStateVersion ?? 0
                    }
                )
                guard outcome == .sent else {
                    overallOutcome = outcome
                    break
                }
                guard receipt.result != .internalError else {
                    overallOutcome = .failed
                    break
                }
                acknowledgedRecordCounts[
                    BLEEventHandler.eventContentKey(log),
                    default: 0
                ] += 1
            }
            if overallOutcome != .sent { break }
        }

        offlineEventRecords = offlineEventRecords.filter { record in
            guard let log = BLEEventHandler.parseEventLogRecord(from: record) else {
                return true
            }
            let key = BLEEventHandler.eventContentKey(log)
            guard let count = acknowledgedRecordCounts[key], count > 0 else {
                return true
            }
            acknowledgedRecordCounts[key] = count - 1
            return false
        }
        return overallOutcome
    }

    func requestBLESync(
        reason: String,
        trigger: BLESyncTrigger = .automatic,
        debounce: Duration
    ) async {
        let registration = await clock.latestSleeperRegistration()
        appState.requestBLESync(reason: reason, trigger: trigger, debounce: debounce)
        let pendingSyncTask = appState.pendingBLESyncTask
        await clock.waitUntilSleeperIsScheduled(after: registration)
        if debounce <= .zero {
            await pendingSyncTask?.value
        }
    }

    func advance(by duration: Duration) async {
        let pendingSyncTask = appState.pendingBLESyncTask
        let result = await clock.advance(by: duration)
        currentDate = result.now
        if result.resumedSleeperCount > 0 {
            await pendingSyncTask?.value
        }
    }

    func startFocus(taskID: String, title: String) async {
        _ = await focusService.startSession(
            taskId: taskID,
            taskTitle: title,
            startTime: currentDate
        )
    }

    func generateAIText() async throws -> String {
        try await ai.generateText()
    }

    func waitUntilAIRequestIsSuspended(id: String) async {
        await ai.waitUntilSuspended(id: id)
    }

    @discardableResult
    func resolveAIRequest(
        id: String,
        with result: Result<String, ScenarioAIError>
    ) async -> Bool {
        await ai.resolve(id: id, with: result)
    }

    func sendDayPack(
        _ dayPack: DayPack,
        messageID: UInt16,
        maxChunkSize: Int
    ) throws {
        guard connectionState == .connected else {
            throw AppDeviceScenarioError.disconnected
        }

        let payload = BLEDataEncoder.encodeDayPack(dayPack, screenSize: .fourInch)
        let packets = try BLEPacketizer.packetize(
            type: BLEDataType.dayPack.rawValue,
            messageId: messageID,
            payload: payload,
            maxChunkSize: maxChunkSize
        )
        _ = try transmit(
            type: BLEDataType.dayPack.rawValue,
            messageID: messageID,
            packets: packets
        )
    }

    func snapshot() async -> AppDeviceScenarioSnapshot {
        let operationEntries = await operationPersistence.entries()
        let focusHistory = await focusPersistence.sessions()
        return AppDeviceScenarioSnapshot(
            now: currentDate,
            connectionState: connectionState,
            appTasks: appState.tasks,
            executedSyncTriggers: executedSyncTriggers,
            outboundTransactions: outboundTransactions,
            committedVersion: taskSnapshotFirmware.version,
            pendingVersion: taskSnapshotFirmware.pendingVersion,
            taskQueue: taskSnapshotFirmware.tasks.map(\.id),
            focus: focusService.activeSession == nil
                ? nil
                : focusService.progressSnapshot(now: currentDate),
            currentPage: currentPage,
            deviceFocus: deviceFocus,
            offlineActions: offlineEventRecords.compactMap {
                BLEEventHandler.parseEventLogRecord(from: $0)
            },
            appOperationLedger: operationEntries,
            focusHistory: focusHistory
        )
    }

    private func installAppBoundaries() {
        let clock = self.clock
        appState.bleSyncSleeper = { duration in
            try await clock.sleep(for: duration)
        }
        appState.bleSyncExecutor = { [weak self] trigger in
            self?.executedSyncTriggers.append(trigger)
        }
    }

    private func transmit(
        type: UInt8,
        messageID: UInt16,
        packets: [Data],
        onPacketWritten: ((Int) throws -> Void)? = nil
    ) throws -> SimulatedAppPacket? {
        guard connectionState == .connected else {
            throw AppDeviceScenarioError.disconnected
        }

        let failedChunkIndex = failedChunkIndexes.first
        if failedChunkIndex != nil {
            failedChunkIndexes.removeFirst()
        }
        if let failedChunkIndex,
           failedChunkIndex < 0 || failedChunkIndex >= packets.count {
            throw AppDeviceScenarioError.chunkIndexOutOfRange(
                index: failedChunkIndex,
                packetCount: packets.count
            )
        }
        var receivedPacket: SimulatedAppPacket?
        var writtenPacketCount = 0

        for (index, packet) in packets.enumerated() {
            if index == failedChunkIndex {
                outboundTransactions.append(ScenarioOutboundTransaction(
                    type: type,
                    messageID: messageID,
                    packetCount: packets.count,
                    writtenPacketCount: writtenPacketCount,
                    result: .failed(chunkIndex: index),
                    receivedPacket: nil
                ))
                hardware = SimulatedHardware()
                throw AppDeviceScenarioError.chunkWriteFailed(index: index)
            }
            if let parsed = try hardware.receiveAppPacket(packet) {
                receivedPacket = parsed
            }
            writtenPacketCount += 1
            try onPacketWritten?(index)
        }

        outboundTransactions.append(ScenarioOutboundTransaction(
            type: type,
            messageID: messageID,
            packetCount: packets.count,
            writtenPacketCount: writtenPacketCount,
            result: .delivered,
            receivedPacket: receivedPacket
        ))
        return receivedPacket
    }

    private func allocateTaskSnapshotMessageID() -> UInt16 {
        let messageID = nextTaskSnapshotMessageID
        nextTaskSnapshotMessageID = messageID == .max ? 1 : messageID + 1
        return messageID
    }

    private func allocateDeviceMessageID() -> UInt16 {
        let messageID = nextDeviceMessageID
        nextDeviceMessageID = messageID == .max ? 1 : messageID + 1
        return messageID
    }
}

extension AppDeviceScenario: TaskListSnapshotSending {
    var hardwareScreenSize: ScreenSize { .fourInch }
    var taskListSnapshotDestinationID: String { "scenario-device" }

    func withTaskStateMessageGate(
        _ operation: @MainActor () async throws -> Void
    ) async throws {
        try await operation()
    }

    func writeTaskListSnapshotAckPayload(
        _ payload: Data,
        expectedTaskStateVersion: UInt64?
    ) async throws {
        _ = expectedTaskStateVersion
        let acknowledgement = try SimulatedAppPacket(
            type: BLEDataType.taskListSnapshotAck.rawValue,
            payload: payload,
            transport: .simple
        ).parseTaskListSnapshotAck()
        let usesChunkedTransport = payload.count + 3 > taskSnapshotMaxWriteLength
        let messageID: UInt16
        let packets: [Data]
        if usesChunkedTransport {
            messageID = allocateTaskSnapshotMessageID()
            packets = try BLEPacketizer.packetize(
                type: BLEDataType.taskListSnapshotAck.rawValue,
                messageId: messageID,
                payload: payload,
                maxChunkSize: taskSnapshotMaxWriteLength - BLEPacketizer.headerSize
            )
        } else {
            messageID = 0
            packets = [BLESimpleEncoder.encode(
                type: BLEDataType.taskListSnapshotAck.rawValue,
                payload: payload
            )]
        }

        var stagedPayloadByteCount = 0
        let stageAfterPacketIndex = usesChunkedTransport
            ? packets.firstIndex { packet in
                stagedPayloadByteCount += Int(packet.bigEndianUInt16(at: 7))
                return stagedPayloadByteCount >= 15
            }
            : nil
        let received = try transmit(
            type: BLEDataType.taskListSnapshotAck.rawValue,
            messageID: messageID,
            packets: packets,
            onPacketWritten: { [weak self] index in
                guard index == stageAfterPacketIndex else { return }
                try self?.taskSnapshotFirmware.stage(
                    acknowledgement,
                    screenSize: self?.hardwareScreenSize ?? .fourInch
                )
            }
        )
        guard let received else {
            throw SimulationError.incompleteChunkedMessage
        }
        let receivedAcknowledgement = try received.parseTaskListSnapshotAck()
        if !usesChunkedTransport {
            try taskSnapshotFirmware.stage(
                receivedAcknowledgement,
                screenSize: hardwareScreenSize
            )
        }
        try taskSnapshotFirmware.apply(
            receivedAcknowledgement,
            screenSize: hardwareScreenSize
        )
    }
}

@MainActor
private final class ScenarioFocusGuard: FocusGuardService {
    var authorizationStatus: FocusAuthorizationStatus = .notDetermined
    var isDeepFocusFeatureEnabled = false
    var isDeepFocusCapable = false
    var canShowDeepFocusEntry = false
    var selectedApplicationCount = 0
    var isPickerPresented = false

    func refreshAuthorizationStatus() async {}
    func requestAuthorization() async -> FocusAuthorizationStatus { .notDetermined }
    func presentAppPicker() {}
    func applyShield(selection: FocusAppSelection) throws {}
    func clearShield() {}
    func currentSelection() -> FocusAppSelection? { nil }
}
