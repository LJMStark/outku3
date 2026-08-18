import Foundation

// MARK: - BLE Structural Commit Hash

/// 上次成功 COMMIT 到硬件的结构指纹（任务栏 / 日程 / agenda 身份，见
/// `HardwareContentFingerprint`）。持久化的原因：只存内存时 App 每次重启后
/// 首轮同步都会因 nil 误判"内容变了"，对无变化的数据集多做一次 E-ink 全刷。
///
/// 该键独立于主文件的 resettableUserDefaultKeys：数据重置后 tasks/events 归零，
/// 结构哈希自然改变并触发新一轮 COMMIT，残留旧值无正确性影响。
extension LocalStorage {
    private nonisolated static let lastCommittedStructuralHashKey = "lastCommittedStructuralHash"

    public func saveLastCommittedStructuralHash(_ hash: String) {
        UserDefaults.standard.set(hash, forKey: Self.lastCommittedStructuralHashKey)
    }

    public func loadLastCommittedStructuralHash() -> String? {
        UserDefaults.standard.string(forKey: Self.lastCommittedStructuralHashKey)
    }
}
