import Foundation
import os

enum SimulatorBridgeTaskCommand: Equatable, Sendable {
    case start(taskID: String)
    case complete(taskID: String)
    case skip(taskID: String)
}

@MainActor
final class SimulatorBridgeTaskCommandQueue {
    typealias Handler = @MainActor (SimulatorBridgeTaskCommand) async -> Void

    private let handler: Handler
    private var tail: Task<Void, Never>?

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func enqueue(_ command: SimulatorBridgeTaskCommand) {
        let predecessor = tail
        tail = Task { @MainActor [handler] in
            await predecessor?.value
            await handler(command)
        }
    }

    func waitUntilIdle() async {
        await tail?.value
    }
}

@MainActor
public final class SimulatorBridge {
    public static let shared = SimulatorBridge()
    private let logger = Logger(subsystem: "com.kirole.app", category: "SimulatorBridge")
    
    private var webSocketTask: URLSessionWebSocketTask?
    public private(set) var isConnected = false
    private var nextTaskOperationID = UInt32.random(in: 1...UInt32.max)
    private lazy var taskCommandQueue = SimulatorBridgeTaskCommandQueue { [weak self] command in
        guard let self else { return }
        await Self.processTaskCommand(
            command,
            operationID: self.takeTaskOperationID()
        )
    }
    
    private init() {}
    
    public func connect() {
        guard let url = URL(string: "ws://localhost:3456") else { return }
        
        // Don't reconnect if already connected/connecting
        guard webSocketTask == nil else { return }
        
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
                }
            }
        } catch {
            logger.error("JSON Serialization error: \(error.localizedDescription)")
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
        sendJSON([
            "type": "app_task_library",
            "payload": ["records": payloadRecords]
        ])
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
            taskCommandQueue.enqueue(command)
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
        phaseTexts: [String: TaskLibraryPhaseTexts]
    ) -> [TaskLibraryRecord] {
        tasks
            .filter { !$0.isCompleted && !$0.pendingDeletion }
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
    ) async {
        let eventType: EventLogType
        let taskID: String
        let eventOperationID: UInt32?
        switch command {
        case .start(let wireTaskID):
            eventType = .enterTaskIn
            taskID = wireTaskID
            eventOperationID = nil
        case .complete(let wireTaskID):
            eventType = .completeTask
            taskID = wireTaskID
            eventOperationID = operationID
        case .skip(let wireTaskID):
            eventType = .skipTask
            taskID = wireTaskID
            eventOperationID = operationID
        }

        let event = EventLog(
            eventType: eventType,
            taskId: taskID,
            operationID: eventOperationID,
            timestamp: now,
            hasDeviceTimestamp: false
        )
        _ = await BLEEventHandler.processEventLogs(
            [event],
            service: nil,
            focusService: focusService,
            tasksOverride: appState.tasks,
            persistLogs: false,
            operationLedger: operationLedger,
            deviceIDOverride: "eink-simulator",
            appState: appState,
            hardwareTaskPersistence: hardwareTaskPersistence,
            nowProvider: { now },
            suppressInitialEnterTaskInFocusStatus: true
        )
    }

    nonisolated static func taskCommand(from text: String) -> SimulatorBridgeTaskCommand? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String,
              let taskID = json["taskId"] as? String,
              !taskID.isEmpty else {
            return nil
        }

        switch type {
        case "hw_start_task":
            return .start(taskID: taskID)
        case "hw_complete_task":
            return .complete(taskID: taskID)
        case "hw_skip_task":
            return .skip(taskID: taskID)
        default:
            return nil
        }
    }
}
