import Testing
import Foundation
@testable import KiroleFeature

/// 测试 0x1B 快照版本 inventory 对齐机制（v2.18.0 双保险方案）。
///
/// 每个测试用 UUID 化的 destinationID 隔离 JSON 文件里的 per-destination 条目。
/// 使用 SharedPersistenceTestLock 防止并发测试套件间的 LocalStorage 文件争用。
@Suite("BLE Task List Snapshot Inventory Reconciliation")
@MainActor
struct BLETaskListSnapshotInventoryReconcileTests {

    // MARK: - .missing 场景

    @Test(".missing 应清除本地快照基线并返回 true（触发立即刷新）")
    func missingInventoryClearsLocalBaseline() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
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

            // 应返回 true：触发优先级同步，下次 0x1B 将携带随机新 epoch（由 nextTaskListSnapshotVersion 生成）
            #expect(needsRefresh == true)

            // 本地版本应被清除
            let savedVersion = try await LocalStorage.shared.loadTaskListSnapshotVersion(for: destinationID)
            #expect(savedVersion == nil)
        }
    }

    // MARK: - .committed 场景

    @Test(".committed 应采纳设备版本为新基线（App 本地没有旧版本时）")
    func committedInventoryAdoptsDeviceVersionWhenNoLocalVersion() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            // 全新 destinationID：LocalStorage 里没有这个设备的任何记录
            let destinationID = "test-device-\(UUID().uuidString)"
            let deviceVersion = TaskListSnapshotVersion(epoch: 1, revision: 1)

            let needsRefresh = await BLESyncCoordinator.shared.reconcileTaskListSnapshotInventory(
                .committed(deviceVersion),
                destinationID: destinationID
            )

            // 首次对齐：返回 false（不触发立即刷新，等常规 sync 窗口）
            #expect(needsRefresh == false)

            let savedVersion = try await LocalStorage.shared.loadTaskListSnapshotVersion(for: destinationID)
            #expect(savedVersion == deviceVersion)
        }
    }

    @Test(".committed 应采纳设备版本为新基线（App 本地有不同旧版本时——核心修复场景）")
    func committedInventoryAdoptsDeviceVersionWhenLocalVersionDiffers() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let destinationID = "test-device-\(UUID().uuidString)"

            // App 本地有高版本（设备重启前 App 侧写的 985）
            try await LocalStorage.shared.saveTaskListSnapshotVersion(
                TaskListSnapshotVersion(epoch: 100, revision: 985),
                for: destinationID
            )

            // 设备重启，NVS 保存的版本可能是 epoch=1/revision=1（v2.18.0 双保险修复的核心场景）
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
    }

    @Test(".missing 在空 destinationID 时应返回 false（guard 短路）")
    func missingInventoryWithEmptyDestinationReturnsFalse() async {
        await SharedPersistenceTestLock.shared.withLock {
            let needsRefresh = await BLESyncCoordinator.shared.reconcileTaskListSnapshotInventory(
                .missing,
                destinationID: ""
            )
            #expect(needsRefresh == false)
        }
    }

    @Test(".committed 应保持现有版本不变（App 本地版本与设备相同时）")
    func committedInventoryKeepsVersionWhenMatching() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let destinationID = "test-device-\(UUID().uuidString)"
            let version = TaskListSnapshotVersion(epoch: 10, revision: 20)

            try await LocalStorage.shared.saveTaskListSnapshotVersion(version, for: destinationID)

            let needsRefresh = await BLESyncCoordinator.shared.reconcileTaskListSnapshotInventory(
                .committed(version),
                destinationID: destinationID
            )

            #expect(needsRefresh == false)

            let savedVersion = try await LocalStorage.shared.loadTaskListSnapshotVersion(for: destinationID)
            #expect(savedVersion == version)
        }
    }

    @Test(".committed 在空 destinationID 时应返回 false（guard 短路）")
    func committedInventoryWithEmptyDestinationReturnsFalse() async {
        await SharedPersistenceTestLock.shared.withLock {
            let needsRefresh = await BLESyncCoordinator.shared.reconcileTaskListSnapshotInventory(
                .committed(TaskListSnapshotVersion(epoch: 1, revision: 1)),
                destinationID: ""
            )
            #expect(needsRefresh == false)
        }
    }

    // MARK: - prepare 路径集成（v2.18.0 P1 修复验证）

    /// 验证 `.committed` 采纳不同版本时先 clear 再 save（P1 修复）：
    /// stale `.attempted` frozenResponse 被清除，后续 prepare 不抛出 activeDeliveryConflict。
    @Test(".committed 采纳后 stale .attempted 被清，下一次 prepare 不阻塞")
    func committedAdoptionClearsStaleFrozenResponsesAllowingPrepare() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let destinationID = "test-device-\(UUID().uuidString)"

            // 阶段一：注入 stale .attempted frozenResponse（模拟重启前未完成的事务）
            // prepare → freeze → markAttempted 三步，destination 里留下 .attempted 残留
            let key1 = TaskListSnapshotRequestKey(
                destinationID: destinationID,
                action: .completeTask,
                operationID: 1
            )
            let prep1 = try await LocalStorage.shared.prepareTaskListSnapshotDelivery(for: key1)
            guard case let .reserved(v1) = prep1 else {
                Issue.record("Expected .reserved from prepare, got \(prep1)")
                return
            }
            let frozen1 = FrozenTaskListSnapshotResponse(key: key1, version: v1, payload: Data())
            try await LocalStorage.shared.freezeTaskListSnapshotDelivery(frozen1)
            try await LocalStorage.shared.markTaskListSnapshotDeliveryAttempted(frozen1)

            // 阶段二：设备重启，0x30 上报 .committed(epoch=999, revision=1)
            // P1 修复路径：clearTaskListSnapshotDeliveryState 先删整个 destination 条目（含 stale .attempted），
            // 再 saveTaskListSnapshotVersion 写入干净基线
            let deviceVersion = TaskListSnapshotVersion(epoch: 999, revision: 1)
            let needsRefresh = await BLESyncCoordinator.shared.reconcileTaskListSnapshotInventory(
                .committed(deviceVersion),
                destinationID: destinationID
            )
            #expect(needsRefresh == false)
            let adoptedVersion = try await LocalStorage.shared.loadTaskListSnapshotVersion(
                for: destinationID
            )
            #expect(adoptedVersion == deviceVersion)

            // 阶段三：下一次 Complete 触发 prepare，不应抛出 activeDeliveryConflict
            // nextTaskListSnapshotVersion(after: (999,1)) → (999,2)（同 epoch 内递增 revision）
            let key2 = TaskListSnapshotRequestKey(
                destinationID: destinationID,
                action: .completeTask,
                operationID: 2
            )
            let prep2 = try await LocalStorage.shared.prepareTaskListSnapshotDelivery(for: key2)
            guard case let .reserved(v2) = prep2 else {
                Issue.record("Expected .reserved after reconcile, got \(prep2)")
                return
            }
            #expect(v2.epoch == deviceVersion.epoch)
            #expect(v2.revision == deviceVersion.revision + 1)
        }
    }
}