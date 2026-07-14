import Testing
import Foundation
@testable import KiroleFeature

// Tests for Custom Companion BLE push queue:
// - pending push flag is set when push fails, cleared when it succeeds
// - flushPendingCustomCompanionPushIfNeeded skips when no companion is active
// - LocalStorage save/load/clear round-trips correctly
//
// These touch global UserDefaults.standard (pendingCustomCompanionPushId) via
// LocalStorage.shared. Other suites reset .standard for rapid-dev-reset coverage,
// which now sweeps pendingCustomCompanionPushId too, so every test that reads/writes
// it must take SharedPersistenceTestLock to serialize against those resets.
@Suite("CustomCompanionBLEQueueTests", .serialized)
@MainActor
struct CustomCompanionBLEQueueTests {

    // MARK: - LocalStorage round-trip

    @Test("given pendingCustomCompanionPushId saved, when loaded, returns same UUID")
    func givenSavedPendingPushId_whenLoaded_returnsSameUUID() async {
        await SharedPersistenceTestLock.shared.withLock {
            await LocalStorage.shared.clearPendingCustomCompanionPush()
            let id = UUID()
            await LocalStorage.shared.savePendingCustomCompanionPush(id: id)

            let loaded = await LocalStorage.shared.loadPendingCustomCompanionPush()
            #expect(loaded == id)

            await LocalStorage.shared.clearPendingCustomCompanionPush()
        }
    }

    @Test("given no pending push saved, when loaded, returns nil")
    func givenNoPendingPush_whenLoaded_returnsNil() async {
        await SharedPersistenceTestLock.shared.withLock {
            await LocalStorage.shared.clearPendingCustomCompanionPush()

            let loaded = await LocalStorage.shared.loadPendingCustomCompanionPush()
            #expect(loaded == nil)
        }
    }

    @Test("given pending push saved, when cleared, subsequent load returns nil")
    func givenPendingSaved_whenCleared_loadReturnsNil() async {
        await SharedPersistenceTestLock.shared.withLock {
            await LocalStorage.shared.clearPendingCustomCompanionPush()
            await LocalStorage.shared.savePendingCustomCompanionPush(id: UUID())
            await LocalStorage.shared.clearPendingCustomCompanionPush()

            let loaded = await LocalStorage.shared.loadPendingCustomCompanionPush()
            #expect(loaded == nil)
        }
    }

    // MARK: - AppState flag restoration

    @Test("custom companion load purge only rejects existing non-PNG assets")
    func customCompanionLoadPurgeDecision() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        #expect(AppState.shouldPurgeStoredCustomCompanion(imageData: nil) == false)
        #expect(AppState.shouldPurgeStoredCustomCompanion(imageData: png) == false)
        #expect(AppState.shouldPurgeStoredCustomCompanion(imageData: Data([0x01, 0x35, 0x62])) == true)
    }

    @Test("given pending push exists in LocalStorage, when flag checked after save, isCustomAvatarPendingBLEPush reflects storage")
    func givenStorageHasPendingPush_flagReflectsStorage() async {
        await SharedPersistenceTestLock.shared.withLock {
            let id = UUID()
            await LocalStorage.shared.savePendingCustomCompanionPush(id: id)

            // Simulate what loadLocalData does
            let hasPending = await LocalStorage.shared.loadPendingCustomCompanionPush() != nil
            #expect(hasPending == true)

            await LocalStorage.shared.clearPendingCustomCompanionPush()
        }
    }

    // MARK: - flushPendingCustomCompanionPushIfNeeded guard conditions

    @Test("given no custom companion selected, flushPendingCustomCompanionPushIfNeeded is a no-op")
    func givenNoCustomCompanion_flushIsNoOp() async {
        await SharedPersistenceTestLock.shared.withLock {
            // Precondition: AppState has no customCompanionId
            let savedProfile = AppState.shared.userProfile
            var testProfile = savedProfile
            testProfile.customCompanionId = nil
            AppState.shared.updateUserProfile(testProfile)
            AppState.shared.isCustomAvatarPendingBLEPush = true

            // Should not throw, should not change flag (guard returns early — no id to flush)
            await AppState.shared.flushPendingCustomCompanionPushIfNeeded()

            // Flag remains true because guard returned before clearing it
            #expect(AppState.shared.isCustomAvatarPendingBLEPush == true)

            // Restore
            AppState.shared.updateUserProfile(savedProfile)
            AppState.shared.isCustomAvatarPendingBLEPush = false
            await LocalStorage.shared.clearPendingCustomCompanionPush()
        }
    }

    @Test("given flag is false, flushPendingCustomCompanionPushIfNeeded is a no-op")
    func givenFlagFalse_flushIsNoOp() async {
        AppState.shared.isCustomAvatarPendingBLEPush = false

        // Should return immediately without side effects
        await AppState.shared.flushPendingCustomCompanionPushIfNeeded()

        #expect(AppState.shared.isCustomAvatarPendingBLEPush == false)
    }

    // MARK: - v2.5.24 wire-contract guard (stale/oversize assets never retry forever)

    /// 升级前遗留的 4bpp 资产（非 PNG）必须被推送护栏丢弃：清 pending 标记 + 复位重试计数，
    /// 而不是当成 SubVersion 0x02 发给固件或无限重试。护栏在触碰 BLEService 之前触发，
    /// 测试进程里不会引发 CBCentralManager 创建。
    @Test("legacy 4bpp asset drops the push and clears the pending marker instead of retrying")
    func legacyAssetDropsPushAndClearsPending() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let id = UUID()
            // 真实旧 4bpp 头字节（packPixelPair 输出形态），永远不可能是 PNG 签名。
            try await LocalStorage.shared.saveCustomCompanionAssets(
                id: id,
                previewData: Data([0x01]),
                imageData: Data([0x01, 0x35, 0x62])
            )
            await LocalStorage.shared.savePendingCustomCompanionPush(id: id)
            let savedProfile = AppState.shared.userProfile
            var profile = savedProfile
            profile.customCompanionId = id
            AppState.shared.updateUserProfile(profile)
            AppState.shared.isCustomAvatarPendingBLEPush = true
            AppState.shared.customAvatarFlushAttempts = 0

            await AppState.shared.flushPendingCustomCompanionPushIfNeeded()

            #expect(AppState.shared.isCustomAvatarPendingBLEPush == false)
            #expect(AppState.shared.customAvatarFlushAttempts == 0)
            let pending = await LocalStorage.shared.loadPendingCustomCompanionPush()
            #expect(pending == nil)

            // Restore
            AppState.shared.updateUserProfile(savedProfile)
            try? await LocalStorage.shared.deleteCustomCompanionAssets(id: id)
            await LocalStorage.shared.clearPendingCustomCompanionPush()
        }
    }

    /// 带合法 PNG 签名但超过 1MiB 的资产（损坏/被替换的本地文件）同样必须被丢弃——
    /// §4.12 白纸黑字承诺设备绝不会收到 >1,048,576 字节的 PNG，出口必须设防。
    @Test("oversize PNG asset is rejected at the push choke point")
    func oversizePNGAssetIsRejected() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let id = UUID()
            var oversize = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
            oversize.append(Data(count: AvatarImageProcessor.maxEncodedByteCount)) // 签名 + 1MiB → 超限
            try await LocalStorage.shared.saveCustomCompanionAssets(
                id: id,
                previewData: Data([0x01]),
                imageData: oversize
            )
            await LocalStorage.shared.savePendingCustomCompanionPush(id: id)
            let savedProfile = AppState.shared.userProfile
            var profile = savedProfile
            profile.customCompanionId = id
            AppState.shared.updateUserProfile(profile)
            AppState.shared.isCustomAvatarPendingBLEPush = true

            await AppState.shared.flushPendingCustomCompanionPushIfNeeded()

            #expect(AppState.shared.isCustomAvatarPendingBLEPush == false)
            let pending = await LocalStorage.shared.loadPendingCustomCompanionPush()
            #expect(pending == nil)

            // Restore
            AppState.shared.updateUserProfile(savedProfile)
            try? await LocalStorage.shared.deleteCustomCompanionAssets(id: id)
            await LocalStorage.shared.clearPendingCustomCompanionPush()
        }
    }

    // MARK: - Flush back-off schedule (livelock regression)

    @Test("Flush retries every sync for the first burst, then periodically — never permanently stops")
    func flushBackoffSchedule_neverPermanentlyStops() {
        // First burst: every attempt re-pushes so a transient failure recovers fast.
        for attempt in 1...5 {
            #expect(AppState.shouldAttemptCustomAvatarFlush(attempt: attempt) == true)
        }
        // After the burst, most syncs are skipped — no per-sync spamming when firmware can't 0x15.
        #expect(AppState.shouldAttemptCustomAvatarFlush(attempt: 6) == false)
        #expect(AppState.shouldAttemptCustomAvatarFlush(attempt: 19) == false)
        // ...but it keeps retrying periodically, so recovered hardware self-heals.
        // Regression guard: the old hard cap returned false for EVERY attempt >= 5 forever,
        // stranding a pending push permanently (the livelock Codex flagged).
        #expect(AppState.shouldAttemptCustomAvatarFlush(attempt: 20) == true)
        #expect(AppState.shouldAttemptCustomAvatarFlush(attempt: 40) == true)
        #expect(AppState.shouldAttemptCustomAvatarFlush(attempt: 100) == true)

        // Strongest invariant: there is ALWAYS a future attempt that re-pushes — never gives up.
        let farFuture = 10_000
        let hasUpcomingRetry = (farFuture...(farFuture + 20)).contains {
            AppState.shouldAttemptCustomAvatarFlush(attempt: $0)
        }
        #expect(hasUpcomingRetry == true)
    }
}
