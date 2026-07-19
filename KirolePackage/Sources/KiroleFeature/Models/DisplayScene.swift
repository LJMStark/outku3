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

    /// Energy bottles required to unlock this scene. Derived from order in `allCases`
    /// so it stays in sync with `unlockedScenes(for:)` — adding a 4th scene only requires
    /// adding the case, no formula updates.
    public var unlockThreshold: Int {
        (Self.allCases.firstIndex(of: self) ?? 0) * Self.bottlesPerUnlock
    }

    /// English-only product UI: this name is shown to users (scene-unlock banner in
    /// ContentView, Settings scene tiles). Keep it English — see CLAUDE.md Interaction Rule 4.
    public var displayName: String {
        switch self {
        case .harbor: return "Harbor"
        case .forest: return "Forest"
        case .nightCity: return "Night City"
        }
    }

    /// App-only preview shown in Settings. This is not companion Pet page artwork
    /// and is never sent to the hardware as image bytes.
    public var previewAssetName: String {
        switch self {
        case .harbor: return "display-scene-preview-harbor"
        case .forest: return "display-scene-preview-forest"
        case .nightCity: return "display-scene-preview-night-city"
        }
    }
}
