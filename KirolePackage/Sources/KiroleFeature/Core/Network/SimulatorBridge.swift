import Foundation
import os

@MainActor
public final class SimulatorBridge {
    public static let shared = SimulatorBridge()
    private let logger = Logger(subsystem: "com.kirole.app", category: "SimulatorBridge")
    
    private var webSocketTask: URLSessionWebSocketTask?
    public private(set) var isConnected = false
    
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
        taskTitle: String? = nil
    ) {
        var payload: [String: Any] = [
            "type": "app_focus_state",
            "energyBottles": energyBottles,
            "elapsedMinutes": elapsedMinutes
        ]
        
        if let session = session {
            payload["activeFocusTaskId"] = session.taskId
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
        
        // Pass events to app state
        Task { @MainActor in
            switch type {
            case "hw_complete_task":
                if let taskId = json["taskId"] as? String {
                    FocusSessionService.shared.completeTask(taskId: taskId)
                }
            case "hw_skip_task":
                if let taskId = json["taskId"] as? String {
                    FocusSessionService.shared.skipTask(taskId: taskId)
                }
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
}
