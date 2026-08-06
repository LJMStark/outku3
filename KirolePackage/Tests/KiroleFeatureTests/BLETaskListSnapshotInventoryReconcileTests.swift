import Testing
import Foundation
@testable import KiroleFeature

/// 测试 0x1B 快照版本 inventory 对齐机制（v2.18.0 双保险方案）。
///
/// LocalStorage 是私有初始化器的 actor 单例，测试通过 `LocalStorage.shared` 读取验证。
/// 每个测试用 UUID 化的 destinationID 隔离 JSON 文件里的 per-destination 条目，无需加锁。
@Suite("BLE Task List Snapshot Inventory Reconciliation")
@MainActor
struct BLETaskListSnapshotInventoryReconcileTests {

    // MARK: - .missing 场景

    @Test(".missing 应清除本地快照基线并返回 true（触发立即刷新）")
    func missingInventoryClearsLocalBaseline() async throws {
        let destinationID = "test-device-\(UUID().uuidString)"
        let coordinator = BLESyncCoordinator.shared

        // 预置一个旧版本（模拟设备重启前 App 侧留存的高 revision）
        try await LocalStorage.shared.saveTaskListSnapshotVersion(
            TaskListSnapshotVersion(epoch: 100, revision: 500),
            for: destinationID
        )

        // 设备上报 .missing（NVS 丢失或首次绑定）
        let needsRefresh = await coordinator.reconcileTaskListSnapshotInventory(
            .missing,
            destinationID: destinationID
        )

        // 应返回 true：触发立即刷新，下次操作从 epoch=1/revision=1 重新开始
        #expect(needsRefresh == true)

        // 本地版本应被清除
        let savedVersion = try await LocalStorage.shared.loadTaskListSnapshotVersion(for: destinationID)
        #expect(savedVersion == nil)
    }

    @Test(".missing 在空 destinationID 时应返回 false（guard 短路）")
    func missingInventoryWithEmptyDestinationReturnsFalse() async {
        let needsRefresh = await BLESyncCoordinator.shared.reconcileTaskListSnapshotInventory(
            .missing,
            destinationID: ""
        )
        #expect(needsRefresh == false)
    }

    // MARK: - .committed 场景

    @Test(".committed 应采纳设备版本为新基线（App 本地没有旧版本时）")
    func committedInventoryAdoptsDeviceVersionWhenNoLocalVersion() async throws {
        // 全新 destinationID：LocalStorage 里没有这个设备的任何记录
        let destinationID = "test-device-\(UUID().uuidString)"
        let deviceVersion = TaskListSnapshotVersion(epoch: 1, revision: 1)

        // 设备重启后首次 DeviceWake，上报 NVS 里保存的最后应用版本
        let needsRefresh = await BLESyncCoordinator.shared.reconcileTaskListSnapshotInventory(
            .committed(deviceVersion),
            destinationID: destinationID
        )

        // 首次对齐：返回 false（不触发立即刷新，等常规 sync 窗口）
        #expect(needsRefresh == false)

        // 本地应保存设备上报的版本作为新基线
        let savedVersion = try await LocalStorage.shared.loadTaskListSnapshotVersion(for: destinationID)
        #expect(savedVersion == deviceVersion)
    }

    @Test(".committed 应采纳设备版本为新基线（App 本地有不同旧版本时——核心修复场景）")
    func committedInventoryAdoptsDeviceVersionWhenLocalVersionDiffers() async throws {
        let destinationID = "test-device-\(UUID().uuidString)"

        // App 本地有高版本（设备重启前 App 侧写的 985）
        try await LocalStorage.shared.saveTaskListSnapshotVersion(
            TaskListSnapshotVersion(epoch: 100, revision: 985),
            for: destinationID
        )

        // 设备重启，NVS 保存的版本可能是 epoch=1/revision=1（或更低的值）
        // 这是 v2.18.0 双保险修复的核心场景
        let deviceVersion = TaskListSnapshotVersion(epoch: 1, revision: 1)
        let needsRefresh = await BLESyncCoordinator.shared.reconcileTaskListSnapshotInventory(
            .committed(deviceVersion),
            destinationID: destinationID
        )

        // 不触发立即刷新——设备侧 NVS 有有效基线，常规 sync 即可
        #expect(needsRefresh == false)

        // 本地应以设备 NVS 版本为准（设备是权威来源）
        let savedVersion = try await LocalStorage.shared.loadTaskListSnapshotVersion(for: destinationID)
        #expect(savedVersion == deviceVersion)
    }

    @Test(".committed 应保持现有版本不变（App 本地版本与设备相同时）")
    func committedInventoryKeepsVersionWhenMatching() async throws {
        let destinationID = "test-device-\(UUID().uuidString)"
        let version = TaskListSnapshotVersion(epoch: 10, revision: 20)

        // 预置与设备相同的版本
        try await LocalStorage.shared.saveTaskListSnapshotVersion(version, for: destinationID)

        // 设备上报相同版本（正常稳态，未发生重启）
        let needsRefresh = await BLESyncCoordinator.shared.reconcileTaskListSnapshotInventory(
            .committed(version),
            destinationID: destinationID
        )

        // 版本一致，不触发刷新
        #expect(needsRefresh == false)

        // 版本应保持不变
        let savedVersion = try await LocalStorage.shared.loadTaskListSnapshotVersion(for: destinationID)
        #expect(savedVersion == version)
    }

    @Test(".committed 在空 destinationID 时应返回 false（guard 短路）")
    func committedInventoryWithEmptyDestinationReturnsFalse() async {
        let needsRefresh = await BLESyncCoordinator.shared.reconcileTaskListSnapshotInventory(
            .committed(TaskListSnapshotVersion(epoch: 1, revision: 1)),
            destinationID: ""
        )
        #expect(needsRefresh == false)
    }
}
