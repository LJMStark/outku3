import Foundation

// MARK: - Local Storage

/// 本地数据持久化，使用 UserDefaults 和文件系统
public actor LocalStorage {
    public static let shared = LocalStorage()

    private let userDefaults = UserDefaults.standard
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private enum Keys {
        static let lastEventLogTimestamp = "lastEventLogTimestamp"
        static let lastDayPackHash = "lastDayPackHash"
        static let lastBleSyncTime = "lastBleSyncTime"
    }

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Pet Data

    /// 保存宠物数据到本地
    public func savePet(_ pet: Pet) throws {
        let data = try encoder.encode(pet)
        let url = documentsDirectory.appendingPathComponent("pet.json")
        try data.write(to: url)
    }

    /// 从本地加载宠物数据
    public func loadPet() throws -> Pet? {
        let url = documentsDirectory.appendingPathComponent("pet.json")
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(Pet.self, from: data)
    }

    // MARK: - Streak Data

    /// 保存连续打卡数据
    public func saveStreak(_ streak: Streak) throws {
        let data = try encoder.encode(streak)
        let url = documentsDirectory.appendingPathComponent("streak.json")
        try data.write(to: url)
    }

    /// 加载连续打卡数据
    public func loadStreak() throws -> Streak? {
        let url = documentsDirectory.appendingPathComponent("streak.json")
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(Streak.self, from: data)
    }

    // MARK: - Tasks

    /// 保存任务列表
    public func saveTasks(_ tasks: [TaskItem]) throws {
        let data = try encoder.encode(tasks)
        let url = documentsDirectory.appendingPathComponent("tasks.json")
        try data.write(to: url)
    }

    /// 加载任务列表
    public func loadTasks() throws -> [TaskItem]? {
        let url = documentsDirectory.appendingPathComponent("tasks.json")
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode([TaskItem].self, from: data)
    }

    // MARK: - Events

    /// 保存日历事件
    public func saveEvents(_ events: [CalendarEvent]) throws {
        let data = try encoder.encode(events)
        let url = documentsDirectory.appendingPathComponent("events.json")
        try data.write(to: url)
    }

    /// 加载日历事件
    public func loadEvents() throws -> [CalendarEvent]? {
        let url = documentsDirectory.appendingPathComponent("events.json")
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode([CalendarEvent].self, from: data)
    }

    // MARK: - User Profile

    /// 保存用户偏好
    public func saveUserProfile(_ profile: UserProfile) throws {
        let data = try encoder.encode(profile)
        let url = documentsDirectory.appendingPathComponent("user_profile.json")
        try data.write(to: url)
    }

    /// 加载用户偏好
    public func loadUserProfile() throws -> UserProfile? {
        let url = documentsDirectory.appendingPathComponent("user_profile.json")
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(UserProfile.self, from: data)
    }

    // MARK: - Sync State

    /// 保存同步状态
    public func saveSyncState(_ state: SyncState) throws {
        let data = try encoder.encode(state)
        let url = documentsDirectory.appendingPathComponent("sync_state.json")
        try data.write(to: url)
    }

    /// 加载同步状态
    public func loadSyncState() throws -> SyncState? {
        let url = documentsDirectory.appendingPathComponent("sync_state.json")
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(SyncState.self, from: data)
    }

    // MARK: - Haiku Cache

    /// 缓存今日 Haiku
    public func cacheHaiku(_ haiku: Haiku, for date: Date) throws {
        let dateString = ISO8601DateFormatter().string(from: date)
        let cacheEntry = HaikuCache(haiku: haiku, date: dateString)
        let data = try encoder.encode(cacheEntry)
        let url = documentsDirectory.appendingPathComponent("haiku_cache.json")
        try data.write(to: url)
    }

    /// 获取缓存的 Haiku（如果是今天的）
    public func getCachedHaiku(for date: Date) throws -> Haiku? {
        let url = documentsDirectory.appendingPathComponent("haiku_cache.json")
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        let cache = try decoder.decode(HaikuCache.self, from: data)

        // 检查是否是同一天
        let dateString = ISO8601DateFormatter().string(from: date)
        let cachedDatePrefix = String(cache.date.prefix(10))
        let currentDatePrefix = String(dateString.prefix(10))

        if cachedDatePrefix == currentDatePrefix {
            return cache.haiku
        }

        return nil
    }

    // MARK: - Clear All

    /// 清除所有本地数据
    public func clearAll() throws {
        let files = ["pet.json", "streak.json", "tasks.json", "events.json", "sync_state.json", "haiku_cache.json", "user_profile.json", "focus_sessions.json", "event_logs.json"]
        for file in files {
            let url = documentsDirectory.appendingPathComponent(file)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }

        userDefaults.removeObject(forKey: Keys.lastEventLogTimestamp)
        userDefaults.removeObject(forKey: Keys.lastDayPackHash)
        userDefaults.removeObject(forKey: Keys.lastBleSyncTime)
    }

    // MARK: - Focus Sessions

    /// 保存专注会话
    public func saveFocusSessions(_ sessions: [FocusSession]) throws {
        let data = try encoder.encode(sessions)
        let url = documentsDirectory.appendingPathComponent("focus_sessions.json")
        try data.write(to: url)
    }

    /// 加载专注会话
    public func loadFocusSessions() throws -> [FocusSession]? {
        let url = documentsDirectory.appendingPathComponent("focus_sessions.json")
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode([FocusSession].self, from: data)
    }

    // MARK: - Event Logs

    public func saveEventLogs(_ logs: [EventLog]) throws {
        let cappedLogs = Array(logs.suffix(1000))
        let data = try encoder.encode(cappedLogs)
        let url = documentsDirectory.appendingPathComponent("event_logs.json")
        try data.write(to: url)
    }

    public func loadEventLogs() throws -> [EventLog]? {
        let url = documentsDirectory.appendingPathComponent("event_logs.json")
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode([EventLog].self, from: data)
    }

    public func saveLastEventLogTimestamp(_ timestamp: UInt32) {
        userDefaults.set(Int(timestamp), forKey: Keys.lastEventLogTimestamp)
    }

    public func loadLastEventLogTimestamp() -> UInt32? {
        let value = userDefaults.object(forKey: Keys.lastEventLogTimestamp) as? Int
        return value.map { UInt32($0) }
    }

    public func saveLastDayPackHash(_ hash: String) {
        userDefaults.set(hash, forKey: Keys.lastDayPackHash)
    }

    public func loadLastDayPackHash() -> String? {
        userDefaults.string(forKey: Keys.lastDayPackHash)
    }

    public func saveLastBleSyncTime(_ date: Date) {
        userDefaults.set(date, forKey: Keys.lastBleSyncTime)
    }

    public func loadLastBleSyncTime() -> Date? {
        userDefaults.object(forKey: Keys.lastBleSyncTime) as? Date
    }
}

// MARK: - Haiku Cache

private struct HaikuCache: Codable {
    let haiku: Haiku
    let date: String
}
