import Foundation
import os

enum SimulatorBridgeTaskCommand: Equatable, Sendable {
    case start(taskID: String)
    case complete(taskID: String, operationID: UInt32? = nil, timestamp: Date? = nil)
    case skip(taskID: String, operationID: UInt32? = nil, timestamp: Date? = nil)
    case replayEnd

    var carriesDeviceOperationMetadata: Bool {
        switch self {
        case .complete(_, let operationID, let timestamp),
             .skip(_, let operationID, let timestamp):
            return operationID != nil || timestamp != nil
        case .start, .replayEnd:
            return false
        }
    }
}

@MainActor
final class SimulatorBridgeTaskCommandQueue {
    typealias Handler = @MainActor (SimulatorBridgeTaskCommand, UInt64) async -> Void

    private let handler: Handler
    private var tail: Task<Void, Never>?

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func enqueue(_ command: SimulatorBridgeTaskCommand, connectionGeneration: UInt64 = 0) {
        let predecessor = tail
        tail = Task { @MainActor [handler] in
            await predecessor?.value
            await handler(command, connectionGeneration)
        }
    }

    func waitUntilIdle() async {
        await tail?.value
    }
}

@MainActor
final class SimulatorBridgeTaskDeliveryCoordinator {
    typealias Sender = @MainActor (_ payload: [String: Any]) async -> Bool

    private var offlineReplayFailed = false
    private var activeConnectionGeneration: UInt64 = 0

    func beginConnection(generation: UInt64) {
        activeConnectionGeneration = generation
        offlineReplayFailed = false
    }

    func deliver(
        receipt: TaskOperationReceipt,
        isOfflineReplay: Bool,
        connectionGeneration: UInt64 = 0,
        acknowledgementPayload: [String: Any],
        taskLibraryPayload: @escaping @MainActor () -> [String: Any],
        send: Sender
    ) async {
        guard connectionGeneration == activeConnectionGeneration else { return }
        let acknowledgementSucceeded = await send(acknowledgementPayload)
        guard connectionGeneration == activeConnectionGeneration else { return }
        if isOfflineReplay {
            if !acknowledgementSucceeded || receipt.result == .internalError {
                offlineReplayFailed = true
            }
            return
        }
        guard acknowledgementSucceeded, receipt.result != .internalError else { return }
        _ = await send(taskLibraryPayload())
    }

    func finishOfflineReplay(
        connectionGeneration: UInt64 = 0,
        taskLibraryPayload: @escaping @MainActor () -> [String: Any],
        send: Sender
    ) async {
        guard connectionGeneration == activeConnectionGeneration else { return }
        let maySendLibrary = !offlineReplayFailed
        offlineReplayFailed = false
        guard maySendLibrary else { return }
        _ = await send(taskLibraryPayload())
    }

    func endConnection(generation: UInt64) {
        guard generation == activeConnectionGeneration else { return }
        activeConnectionGeneration = generation == .max ? 0 : generation + 1
        offlineReplayFailed = false
    }
}

@MainActor
public final class SimulatorBridge {
    public static let shared = SimulatorBridge()
    private let logger = Logger(subsystem: "com.kirole.app", category: "SimulatorBridge")
    
    private var webSocketTask: URLSessionWebSocketTask?
    public private(set) var isConnected = false
    private var connectionGeneration: UInt64 = 0
    private var nextTaskOperationID = UInt32.random(in: 1...UInt32.max)
    private let taskDeliveryCoordinator = SimulatorBridgeTaskDeliveryCoordinator()
    private lazy var taskCommandQueue = SimulatorBridgeTaskCommandQueue { [weak self] command, generation in
        guard let self else { return }
        guard generation == self.connectionGeneration else { return }
        if command == .replayEnd {
            await self.taskDeliveryCoordinator.finishOfflineReplay(
                connectionGeneration: generation,
                taskLibraryPayload: {
                    Self.taskLibraryPayload(
                        records: AppState.shared.simulatorTaskLibraryRecords()
                    )
                },
                send: { payload in await self.sendJSONAndWait(payload) }
            )
            return
        }
        guard let receipt = await Self.processTaskCommand(
            command,
            operationID: self.takeTaskOperationID()
        ), let acknowledgementPayload = Self.taskActionAcknowledgementPayload(receipt) else {
            return
        }
        await self.taskDeliveryCoordinator.deliver(
            receipt: receipt,
            isOfflineReplay: command.carriesDeviceOperationMetadata,
            connectionGeneration: generation,
            acknowledgementPayload: acknowledgementPayload,
            taskLibraryPayload: {
                Self.taskLibraryPayload(
                    records: AppState.shared.simulatorTaskLibraryRecords()
                )
            },
            send: { payload in await self.sendJSONAndWait(payload) }
        )
    }
    
    private init() {}
    
    public func connect() {
        guard let url = URL(string: "ws://localhost:3456") else { return }
        
        // Don't reconnect if already connected/connecting
        guard webSocketTask == nil else { return }

        connectionGeneration = connectionGeneration == .max ? 1 : connectionGeneration + 1
        taskDeliveryCoordinator.beginConnection(generation: connectionGeneration)
        
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        isConnected = true
        
        logger.info("Connecting to E-ink Simulator at \(url.absoluteString)")
        
        receiveMessage()
    }
    
    public func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        taskDeliveryCoordinator.endConnection(generation: connectionGeneration)
        logger.info("Disconnected from E-ink Simulator")
    }
    
    public func sendJSON(_ payload: [String: Any]) {
        guard isConnected, let task = webSocketTask else {
            logger.warning("Attempted to send JSON to simulator but bridge is not connected.")
            return
        }
        
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            guard let string = String(data: data, encoding: .utf8) else { return }
            
            let message = URLSessionWebSocketTask.Message.string(string)
            task.send(message) { [weak self] error in
                if let error = error {
                    self?.logger.error("Error sending message to simulator: \(error.localizedDescription)")
                    return
                }
            }
        } catch {
            logger.error("JSON Serialization error: \(error.localizedDescription)")
        }
    }

    private func sendJSONAndWait(_ payload: [String: Any]) async -> Bool {
        guard isConnected, let task = webSocketTask else {
            logger.warning("Attempted to send JSON to simulator but bridge is not connected.")
            return false
        }
        let string: String
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            guard let encoded = String(data: data, encoding: .utf8) else { return false }
            string = encoded
        } catch {
            logger.error("JSON Serialization error: \(error.localizedDescription)")
            return false
        }
        return await withCheckedContinuation { continuation in
            task.send(.string(string)) { [weak self] error in
                if let error {
                    self?.logger.error("Error sending message to simulator: \(error.localizedDescription)")
                    continuation.resume(returning: false)
                } else {
                    continuation.resume(returning: true)
                }
            }
        }
    }
    
    // MARK: - Game Mechanism 2 Integrations
    
    public func sendPetStatus(
        petName: String,
        petMood: String,
        sceneId: String,
        characterId: String
    ) {
        sendJSON([
            "type": "app_pet_status",
            "petName": petName,
            "petMood": petMood,
            "sceneId": sceneId,
            "characterId": characterId
        ])
    }
    
    public func sendFocusState(
        session: FocusSession?,
        energyBottles: Int,
        focusPhase: FocusPhase,
        elapsedMinutes: Int,
        taskID: String? = nil,
        taskTitle: String? = nil
    ) {
        var payload: [String: Any] = [
            "type": "app_focus_state",
            "energyBottles": energyBottles,
            "elapsedMinutes": elapsedMinutes
        ]
        
        if let session = session {
            payload["activeFocusTaskId"] = taskID ?? session.taskId
            payload["taskTitle"] = taskTitle
            payload["focusPhase"] = focusPhase.rawValue
        } else {
            payload["activeFocusTaskId"] = NSNull()
            payload["taskTitle"] = NSNull()
            payload["focusPhase"] = FocusPhase.idle.rawValue
        }
        
        sendJSON(payload)
    }
    
    public func sendScreensaver(config: ScreensaverConfig) {
        var configPayload: [String: Any] = [
            "type": config.type == .postcard ? "postcard" : "normal",
            "quote": config.quote,
            "author": config.author,
            "sceneId": config.sceneId
        ]
        if let postcardDay = config.postcardDay {
            configPayload["postcardDay"] = postcardDay
        }
        sendJSON([
            "type": "app_screensaver",
            "config": configPayload
        ])
    }
    
    public func sendSceneUnlocks(unlocks: [SceneUnlock]) {
        let unlocksPayload = unlocks.map { ["sceneId": $0.sceneId] }
        sendJSON([
            "type": "app_scene_unlock",
            "unlocks": unlocksPayload
        ])
    }

    public func sendTaskLibrary(records: [TaskLibraryRecord]) {
        sendJSON(Self.taskLibraryPayload(records: records))
    }

    static func taskLibraryPayload(records: [TaskLibraryRecord]) -> [String: Any] {
        let payloadRecords: [[String: Any]] = records.map { record in
            [
                "id": record.taskID,
                "order": record.order,
                "title": record.title,
                "detail": record.detail,
                "dueTimestamp": record.dueTimestamp.map { $0 as Any } ?? NSNull(),
                "priority": record.priority.rawValue,
                "phaseTexts": [
                    "starting": record.phaseTexts.starting,
                    "building": record.phaseTexts.building,
                    "deep": record.phaseTexts.deep
                ]
            ]
        }
        return [
            "type": "app_task_library",
            "payload": ["records": payloadRecords]
        ]
    }
    
    private func receiveMessage() {
        guard let task = webSocketTask else { return }
        
        task.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .failure(let error):
                Task { @MainActor in
                    self.logger.error("Simulator Bridge connection closed or error: \(error.localizedDescription)")
                    self.isConnected = false
                    self.webSocketTask = nil
                    self.taskDeliveryCoordinator.endConnection(
                        generation: self.connectionGeneration
                    )
                    
                    // Auto reconnect after delay in debug mode
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        if !self.isConnected {
                            self.connect()
                        }
                    }
                }
                
            case .success(let message):
                Task { @MainActor in
                    switch message {
                    case .string(let text):
                        self.handleIncomingJSON(text)
                    case .data(_):
                        // Not expecting binary data from simulator
                        break
                    @unknown default:
                        break
                    }
                    // Continue listening
                    self.receiveMessage()
                }
            }
        }
    }
    
    private func handleIncomingJSON(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }
        
        logger.info("Received from Simulator: \(type)")

        if let command = Self.taskCommand(from: text) {
            taskCommandQueue.enqueue(
                command,
                connectionGeneration: connectionGeneration
            )
            return
        }

        // Pass non-task events to app state.
        Task { @MainActor in
            switch type {
            case "hw_bottle_earned":
                if let newTotal = json["totalEnergyBottles"] as? Int {
                    Task {
                        await LocalStorage.shared.saveEnergyBottles(newTotal)
                    }
                }
            default:
                break
            }
        }
    }

    private func takeTaskOperationID() -> UInt32 {
        let current = nextTaskOperationID
        nextTaskOperationID = current == .max ? 1 : current + 1
        return current
    }

    static func taskLibraryRecords(
        tasks: [TaskItem],
        phaseTexts: [String: TaskLibraryPhaseTexts],
        now: Date,
        calendar: Calendar
    ) -> [TaskLibraryRecord] {
        // 与真机 0x23 同一口径：只投影今天的任务且同样截到 20 条，模拟器与硬件显示不得分叉。
        TaskLibraryMembership.members(of: tasks, on: now, calendar: calendar)
            .enumerated()
            .compactMap { index, task in
                guard let order = UInt32(exactly: index) else { return nil }
                return TaskLibraryRecord(
                    task: task,
                    order: order,
                    phaseTexts: phaseTexts[task.hardwareIdentifier] ?? .localFallback
                )
            }
    }

    static func processTaskCommand(
        _ command: SimulatorBridgeTaskCommand,
        operationID: UInt32,
        appState: AppState = .shared,
        focusService: FocusSessionService = .shared,
        operationLedger: TaskOperationLedger = .shared,
        hardwareTaskPersistence: (any HardwareTaskStatePersisting)? = nil,
        now: Date = Date()
    ) async -> TaskOperationReceipt? {
        if command == .replayEnd { return nil }
        let eventType: EventLogType
        let taskID: String
        let eventOperationID: UInt32?
        let eventTimestamp: Date
        let hasDeviceTimestamp: Bool
        switch command {
        case .start(let wireTaskID):
            eventType = .enterTaskIn
            taskID = wireTaskID
            eventOperationID = nil
            eventTimestamp = now
            hasDeviceTimestamp = false
        case .complete(let wireTaskID, let providedOperationID, let providedTimestamp):
            eventType = .completeTask
            taskID = wireTaskID
            eventOperationID = providedOperationID ?? operationID
            eventTimestamp = providedTimestamp ?? now
            hasDeviceTimestamp = providedTimestamp != nil
        case .skip(let wireTaskID, let providedOperationID, let providedTimestamp):
            eventType = .skipTask
            taskID = wireTaskID
            eventOperationID = providedOperationID ?? operationID
            eventTimestamp = providedTimestamp ?? now
            hasDeviceTimestamp = providedTimestamp != nil
        case .replayEnd:
            return nil
        }

        let event = EventLog(
            eventType: eventType,
            taskId: taskID,
            operationID: eventOperationID,
            timestamp: eventTimestamp,
            hasDeviceTimestamp: hasDeviceTimestamp
        )
        let processing = await BLEEventHandler.processEventLogs(
            [event],
            service: nil,
            focusService: focusService,
            isReplay: hasDeviceTimestamp,
            tasksOverride: appState.tasks,
            persistLogs: false,
            operationLedger: operationLedger,
            deviceIDOverride: "eink-simulator",
            appState: appState,
            hardwareTaskPersistence: hardwareTaskPersistence,
            nowProvider: { now }
        )
        return processing.taskOperationReceipts.first
    }

    static func taskActionAcknowledgementPayload(
        _ receipt: TaskOperationReceipt
    ) -> [String: Any]? {
        let action: String
        switch receipt.action {
        case .completeTask:
            action = "complete"
        case .skipTask:
            action = "skip"
        case .requestRefresh:
            return nil
        }
        return [
            "type": "app_task_action_ack",
            "action": action,
            "operationId": Int(receipt.operationID),
            "result": taskActionResultName(receipt.result)
        ]
    }

    private static func taskActionResultName(_ result: TaskListSnapshotResultCode) -> String {
        switch result {
        case .applied: "applied"
        case .alreadyApplied: "alreadyApplied"
        case .taskNotFound: "taskNotFound"
        case .invalidRequest: "invalidRequest"
        case .supersededByApp: "supersededByApp"
        case .internalError: "internalError"
        }
    }

    nonisolated static func taskCommand(from text: String) -> SimulatorBridgeTaskCommand? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return nil
        }

        if type == "hw_task_action_replay_end" {
            return .replayEnd
        }

        guard let taskID = json["taskId"] as? String, !taskID.isEmpty else { return nil }

        switch type {
        case "hw_start_task":
            return .start(taskID: taskID)
        case "hw_complete_task":
            guard let metadata = taskOperationMetadata(from: json) else { return nil }
            return .complete(
                taskID: taskID,
                operationID: metadata.operationID,
                timestamp: metadata.timestamp
            )
        case "hw_skip_task":
            guard let metadata = taskOperationMetadata(from: json) else { return nil }
            return .skip(
                taskID: taskID,
                operationID: metadata.operationID,
                timestamp: metadata.timestamp
            )
        default:
            return nil
        }
    }

    private nonisolated static func taskOperationMetadata(
        from json: [String: Any]
    ) -> (operationID: UInt32?, timestamp: Date?)? {
        let operationID: UInt32?
        if let rawOperationID = json["operationId"] {
            guard !(rawOperationID is Bool),
                  let number = rawOperationID as? NSNumber,
                  number.doubleValue.rounded() == number.doubleValue,
                  (1...Double(UInt32.max)).contains(number.doubleValue) else {
                return nil
            }
            operationID = UInt32(number.doubleValue)
        } else {
            operationID = nil
        }

        let timestamp: Date?
        if let rawTimestamp = json["timestamp"] {
            guard !(rawTimestamp is Bool),
                  let number = rawTimestamp as? NSNumber,
                  number.doubleValue.isFinite,
                  number.doubleValue >= 0 else {
                return nil
            }
            timestamp = Date(timeIntervalSince1970: number.doubleValue)
        } else {
            timestamp = nil
        }
        return (operationID, timestamp)
    }
}
