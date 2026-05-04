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

    /// 跨阈值时新解锁的场景 ID 列表（按解锁顺序排列，不含已解锁的）。
    /// 纯函数，仅依据数学差。是否真的"庆祝"还需结合 lastCelebratedUnlockCount 判断（防御重复触发）。
    public static func newlyUnlockedSceneIds(from before: Int, to after: Int) -> [String] {
        let beforeCount = unlockedScenes(for: before).count
        let afterCount = unlockedScenes(for: after).count
        guard afterCount > beforeCount else { return [] }
        return Array(allCases.dropFirst(beforeCount).prefix(afterCount - beforeCount)).map(\.rawValue)
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

    public var displayName: String {
        switch self {
        case .harbor: return "港湾"
        case .forest: return "森林"
        case .nightCity: return "夜城"
        }
    }
}
