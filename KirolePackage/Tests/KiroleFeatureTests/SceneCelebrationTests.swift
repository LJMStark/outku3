import Testing
import Foundation
@testable import KiroleFeature

// MARK: - Scene Celebration Tests
// 覆盖跨阈值即时反馈链路：DisplayScene 纯函数边界 + LocalStorage 持久化字段
// + 端到端"第二次同样跨阈值不再重复触发"。

@Suite("Scene Celebration: DisplayScene Diff")
struct DisplaySceneDiffTests {

    @Test("不跨阈值返回空数组")
    func noUnlockBelowThreshold() {
        #expect(DisplayScene.newlyUnlockedSceneIds(from: 0, to: 79) == [])
        #expect(DisplayScene.newlyUnlockedSceneIds(from: 81, to: 159) == [])
    }

    @Test("跨过 80 解锁 forest")
    func unlockForest() {
        #expect(DisplayScene.newlyUnlockedSceneIds(from: 78, to: 82) == ["forest"])
    }

    @Test("跨过 160 解锁 nightCity")
    func unlockNightCity() {
        #expect(DisplayScene.newlyUnlockedSceneIds(from: 159, to: 161) == ["nightCity"])
    }

    @Test("一次跨过两条线返回两个场景")
    func unlockBothInOneJump() {
        #expect(DisplayScene.newlyUnlockedSceneIds(from: 50, to: 200) == ["forest", "nightCity"])
    }

    @Test("跨过最高档后封顶不再 emit")
    func saturateAtTopTier() {
        #expect(DisplayScene.newlyUnlockedSceneIds(from: 200, to: 400) == [])
    }
}

@Suite("Scene Celebration: LocalStorage", .serialized)
struct CelebrationStorageTests {

    @Test("默认值是 1（harbor 不需要庆祝）")
    @MainActor
    func defaultIsOne() async {
        await SharedPersistenceTestLock.shared.withLock {
            let storage = LocalStorage.shared
            // 清掉再读：UserDefaults 中没有时应回落到默认 1
            UserDefaults.standard.removeObject(forKey: "lastCelebratedUnlockCount")
            let value = await storage.loadLastCelebratedUnlockCount()
            #expect(value == 1)
        }
    }

    @Test("save/load 往返")
    @MainActor
    func saveLoadRoundTrip() async {
        await SharedPersistenceTestLock.shared.withLock {
            let storage = LocalStorage.shared
            await storage.saveLastCelebratedUnlockCount(2)
            let value = await storage.loadLastCelebratedUnlockCount()
            #expect(value == 2)

            await storage.saveLastCelebratedUnlockCount(3)
            let value2 = await storage.loadLastCelebratedUnlockCount()
            #expect(value2 == 3)

            // 还原
            UserDefaults.standard.removeObject(forKey: "lastCelebratedUnlockCount")
        }
    }

    @Test("开发期重置会清掉庆祝计数")
    @MainActor
    func resetClearsCelebrationCounter() async throws {
        let defaults = UserDefaults.standard
        let schemaKey = LocalStorage.developmentStorageSchemaVersionKey
        let celebrationKey = "lastCelebratedUnlockCount"

        // Hold the lock across the reset itself, not just setup: resetForRapidDevelopment
        // wipes every resettable key on global .standard (now including
        // avatar-operation files), so it must be serialized against other suites
        // that read/write those keys (e.g. CustomCompanionBLEQueueTests).
        try await SharedPersistenceTestLock.shared.withLock {
            defaults.set(1, forKey: schemaKey)
            defaults.set(3, forKey: celebrationKey)
            defer {
                defaults.removeObject(forKey: schemaKey)
                defaults.removeObject(forKey: celebrationKey)
            }

            let didReset = try LocalStorage.resetForRapidDevelopmentIfNeeded(
                currentSchemaVersion: LocalStorage.currentDevelopmentStorageSchemaVersion + 1,
                userDefaults: defaults,
                fileManager: FileManager.default,
                documentsDirectory: nil
            )

            #expect(didReset)
            #expect(defaults.object(forKey: celebrationKey) == nil)
        }
    }
}
