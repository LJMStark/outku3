import Foundation

public struct SceneUnlock: Sendable, Codable, Equatable {
    public var sceneId: String
    public var unlockedAt: Date
    
    public init(sceneId: String, unlockedAt: Date = Date()) {
        self.sceneId = sceneId
        self.unlockedAt = unlockedAt
    }
}
