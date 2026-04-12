import Foundation

@MainActor
public final class SceneUnlockService {
    public static let shared = SceneUnlockService()
    
    private init() {}
    
    public func fetchAvailableScenes(energyBottles: Int, now: Date = Date()) -> [SceneUnlock] {
        DisplayScene.unlockedScenes(for: energyBottles, now: now)
    }

    public func currentSceneId(energyBottles: Int) -> String {
        DisplayScene.currentScene(for: energyBottles).rawValue
    }
}
