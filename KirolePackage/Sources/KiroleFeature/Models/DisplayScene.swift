import Foundation

public enum DisplayScene: String, CaseIterable, Sendable, Codable {
    case harbor = "harbor"
    case forest = "forest"
    case nightCity = "nightCity"

    public static let bottlesPerUnlock = 80

    public static func unlockedScenes(for energyBottles: Int, now: Date = Date()) -> [SceneUnlock] {
        let unlockCount = min(
            allCases.count,
            1 + max(0, energyBottles) / bottlesPerUnlock
        )

        return Array(allCases.prefix(unlockCount)).map { scene in
            SceneUnlock(sceneId: scene.rawValue, unlockedAt: now)
        }
    }

    public static func currentScene(for energyBottles: Int) -> DisplayScene {
        let unlockedScenes = unlockedScenes(for: energyBottles)
        guard let lastSceneId = unlockedScenes.last?.sceneId,
              let scene = DisplayScene(rawValue: lastSceneId) else {
            return .harbor
        }
        return scene
    }

    public var commandByte: UInt8 {
        switch self {
        case .harbor:
            return 0x00
        case .forest:
            return 0x01
        case .nightCity:
            return 0x02
        }
    }
}
