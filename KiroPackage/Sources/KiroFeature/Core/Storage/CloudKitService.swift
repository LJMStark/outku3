import CloudKit
import Foundation

// MARK: - CloudKit Service

/// iCloud 数据同步服务，用于跨设备同步宠物和连续打卡数据
public actor CloudKitService {
    public static let shared = CloudKitService()

    // 懒加载 CloudKit 容器，避免在未配置时崩溃
    private var _container: CKContainer?
    private var container: CKContainer? {
        if _container == nil {
            // 使用默认容器而非指定标识符，更安全
            _container = CKContainer.default()
        }
        return _container
    }

    private var database: CKDatabase? {
        container?.privateCloudDatabase
    }

    private enum RecordType {
        static let pet = "Pet"
        static let streak = "Streak"
    }

    private enum RecordID {
        static let pet = CKRecord.ID(recordName: "pet_main")
        static let streak = CKRecord.ID(recordName: "streak_main")
    }

    private init() {
        // 延迟初始化，不在 init 中创建容器
    }

    // MARK: - Account Status

    /// 检查 iCloud 账户状态
    public func checkAccountStatus() async -> CKAccountStatus {
        guard let container = container else { return .couldNotDetermine }
        return (try? await container.accountStatus()) ?? .couldNotDetermine
    }

    /// iCloud 是否可用
    public var isAvailable: Bool {
        get async {
            guard container != nil else { return false }
            return await checkAccountStatus() == .available
        }
    }

    // MARK: - Pet Data

    /// 保存宠物数据到 iCloud
    public func savePet(_ pet: Pet) async throws {
        guard let database = database else { return }
        let record = CKRecord(recordType: RecordType.pet, recordID: RecordID.pet)
        record["name"] = pet.name
        record["pronouns"] = pet.pronouns.rawValue
        record["adventuresCount"] = pet.adventuresCount
        record["age"] = pet.age
        record["status"] = pet.status.rawValue
        record["mood"] = pet.mood.rawValue
        record["scene"] = pet.scene.rawValue
        record["stage"] = pet.stage.rawValue
        record["progress"] = pet.progress
        record["weight"] = pet.weight
        record["height"] = pet.height
        record["tailLength"] = pet.tailLength
        record["currentForm"] = pet.currentForm.rawValue
        record["lastInteraction"] = pet.lastInteraction
        _ = try await database.save(record)
    }

    /// 从 iCloud 获取宠物数据
    public func fetchPet() async throws -> Pet? {
        guard database != nil else { return nil }
        guard let record = try await fetchLatestRecord(type: RecordType.pet) else {
            return nil
        }
        return Pet(
            name: record["name"] as? String ?? "Baby Waffle",
            pronouns: (record["pronouns"] as? String).flatMap(PetPronouns.init) ?? .theyThem,
            adventuresCount: record["adventuresCount"] as? Int ?? 0,
            age: record["age"] as? Int ?? 0,
            status: (record["status"] as? String).flatMap(PetStatus.init) ?? .happy,
            mood: (record["mood"] as? String).flatMap(PetMood.init) ?? .happy,
            scene: (record["scene"] as? String).flatMap(PetScene.init) ?? .indoor,
            stage: (record["stage"] as? String).flatMap(PetStage.init) ?? .baby,
            progress: record["progress"] as? Double ?? 0,
            weight: record["weight"] as? Double ?? 50,
            height: record["height"] as? Double ?? 5,
            tailLength: record["tailLength"] as? Double ?? 2,
            currentForm: (record["currentForm"] as? String).flatMap(PetForm.init) ?? .cat,
            lastInteraction: record["lastInteraction"] as? Date ?? Date()
        )
    }

    // MARK: - Streak Data

    /// 保存连续打卡数据到 iCloud
    public func saveStreak(_ streak: Streak) async throws {
        guard let database = database else { return }
        let record = CKRecord(recordType: RecordType.streak, recordID: RecordID.streak)
        record["currentStreak"] = streak.currentStreak
        record["longestStreak"] = streak.longestStreak
        record["lastActiveDate"] = streak.lastActiveDate
        _ = try await database.save(record)
    }

    /// 从 iCloud 获取连续打卡数据
    public func fetchStreak() async throws -> Streak? {
        guard database != nil else { return nil }
        guard let record = try await fetchLatestRecord(type: RecordType.streak) else {
            return nil
        }
        return Streak(
            currentStreak: record["currentStreak"] as? Int ?? 0,
            longestStreak: record["longestStreak"] as? Int ?? 0,
            lastActiveDate: record["lastActiveDate"] as? Date
        )
    }

    // MARK: - Sync

    /// 同步宠物数据（冲突解决：使用最近修改的版本）
    public func syncPet(local: Pet) async throws -> Pet {
        guard await isAvailable else { return local }

        if let remote = try await fetchPet(), remote.lastInteraction > local.lastInteraction {
            return remote
        }
        try await savePet(local)
        return local
    }

    /// 同步连续打卡数据（合并策略：取较大值）
    public func syncStreak(local: Streak) async throws -> Streak {
        guard await isAvailable else { return local }

        guard let remote = try await fetchStreak() else {
            try await saveStreak(local)
            return local
        }

        let merged = Streak(
            currentStreak: max(local.currentStreak, remote.currentStreak),
            longestStreak: max(local.longestStreak, remote.longestStreak),
            lastActiveDate: [local.lastActiveDate, remote.lastActiveDate].compactMap { $0 }.max()
        )
        try await saveStreak(merged)
        return merged
    }

    // MARK: - Subscriptions

    /// 设置 CloudKit 订阅以接收远程变更通知
    public func setupSubscriptions() async throws {
        guard let database = database else { return }
        let subscription = CKQuerySubscription(
            recordType: RecordType.pet,
            predicate: NSPredicate(value: true),
            subscriptionID: "pet-changes",
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        let notification = CKSubscription.NotificationInfo()
        notification.shouldSendContentAvailable = true
        subscription.notificationInfo = notification
        _ = try await database.save(subscription)
    }

    // MARK: - Private Helpers

    /// 获取指定类型的最新记录
    private func fetchLatestRecord(type: String) async throws -> CKRecord? {
        guard let database = database else { return nil }
        let query = CKQuery(recordType: type, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "modificationDate", ascending: false)]
        let (results, _) = try await database.records(matching: query, resultsLimit: 1)
        guard let (_, result) = results.first else { return nil }
        return try result.get()
    }
}
