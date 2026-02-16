import Foundation

// MARK: - Local Storage

/// Local data persistence using UserDefaults and the file system
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

    // MARK: - Generic File Helpers

    /// Save an encodable value to a JSON file in the documents directory
    private func save<T: Encodable>(_ value: T, to filename: String) throws {
        let data = try encoder.encode(value)
        let url = documentsDirectory.appendingPathComponent(filename)
        try data.write(to: url)
    }

    /// Delete a specific file from the documents directory
    public func deleteFile(named filename: String) throws {
        let url = documentsDirectory.appendingPathComponent(filename)
        let resolvedPath = url.standardizedFileURL.path
        let documentsPath = documentsDirectory.standardizedFileURL.path
        guard resolvedPath.hasPrefix(documentsPath) else {
            return
        }
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    /// Load a decodable value from a JSON file in the documents directory
    private func load<T: Decodable>(_ type: T.Type, from filename: String) throws -> T? {
        let url = documentsDirectory.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(T.self, from: data)
    }

    // MARK: - Pet Data

    public func savePet(_ pet: Pet) throws {
        try save(pet, to: "pet.json")
    }

    public func loadPet() throws -> Pet? {
        try load(Pet.self, from: "pet.json")
    }

    // MARK: - Streak Data

    public func saveStreak(_ streak: Streak) throws {
        try save(streak, to: "streak.json")
    }

    public func loadStreak() throws -> Streak? {
        try load(Streak.self, from: "streak.json")
    }

    // MARK: - Tasks

    public func saveTasks(_ tasks: [TaskItem]) throws {
        try save(tasks, to: "tasks.json")
    }

    public func loadTasks() throws -> [TaskItem]? {
        try load([TaskItem].self, from: "tasks.json")
    }

    // MARK: - Events

    public func saveEvents(_ events: [CalendarEvent]) throws {
        try save(events, to: "events.json")
    }

    public func loadEvents() throws -> [CalendarEvent]? {
        try load([CalendarEvent].self, from: "events.json")
    }

    // MARK: - User Profile

    public func saveUserProfile(_ profile: UserProfile) throws {
        try save(profile, to: "user_profile.json")
    }

    public func loadUserProfile() throws -> UserProfile? {
        try load(UserProfile.self, from: "user_profile.json")
    }

    // MARK: - Onboarding Profile

    public func saveOnboardingProfile(_ profile: OnboardingProfile) throws {
        try save(profile, to: "onboarding_profile.json")
    }

    public func loadOnboardingProfile() throws -> OnboardingProfile? {
        try load(OnboardingProfile.self, from: "onboarding_profile.json")
    }

    // MARK: - Sync State

    public func saveSyncState(_ state: SyncState) throws {
        try save(state, to: "sync_state.json")
    }

    public func loadSyncState() throws -> SyncState? {
        try load(SyncState.self, from: "sync_state.json")
    }

    // MARK: - Haiku Cache

    /// Cache today's haiku
    public func cacheHaiku(_ haiku: Haiku, for date: Date) throws {
        let dateString = ISO8601DateFormatter().string(from: date)
        let cacheEntry = HaikuCache(haiku: haiku, date: dateString)
        try save(cacheEntry, to: "haiku_cache.json")
    }

    /// Retrieve the cached haiku if it was generated today
    public func getCachedHaiku(for date: Date) throws -> Haiku? {
        guard let cache = try load(HaikuCache.self, from: "haiku_cache.json") else {
            return nil
        }

        // Compare date prefixes (YYYY-MM-DD) to check same day
        let dateString = ISO8601DateFormatter().string(from: date)
        let cachedDatePrefix = String(cache.date.prefix(10))
        let currentDatePrefix = String(dateString.prefix(10))

        guard cachedDatePrefix == currentDatePrefix else {
            return nil
        }

        return cache.haiku
    }

    // MARK: - AI Interactions

    /// Save AI interaction history (capped at 100 most recent)
    public func saveAIInteractions(_ interactions: [AIInteraction]) throws {
        let capped = Array(interactions.suffix(100))
        try save(capped, to: "ai_interactions.json")
    }

    /// Load AI interaction history
    public func loadAIInteractions() throws -> [AIInteraction]? {
        try load([AIInteraction].self, from: "ai_interactions.json")
    }

    // MARK: - Behavior Summary

    /// Save user behavior summary
    public func saveBehaviorSummary(_ summary: UserBehaviorSummary) throws {
        try save(summary, to: "behavior_summary.json")
    }

    /// Load user behavior summary
    public func loadBehaviorSummary() throws -> UserBehaviorSummary? {
        try load(UserBehaviorSummary.self, from: "behavior_summary.json")
    }

    // MARK: - Focus Sessions

    public func saveFocusSessions(_ sessions: [FocusSession]) throws {
        try save(sessions, to: "focus_sessions.json")
    }

    public func loadFocusSessions() throws -> [FocusSession]? {
        try load([FocusSession].self, from: "focus_sessions.json")
    }

    /// Save focus sessions for a specific date (YYYY-MM-DD key)
    public func saveFocusSessionsForDate(_ sessions: [FocusSession], date: Date) throws {
        let dateKey = Self.dateKey(from: date)
        try save(sessions, to: "focus_sessions_\(dateKey).json")
    }

    /// Load focus sessions for a specific date
    public func loadFocusSessionsForDate(_ date: Date) throws -> [FocusSession]? {
        let dateKey = Self.dateKey(from: date)
        return try load([FocusSession].self, from: "focus_sessions_\(dateKey).json")
    }

    private static func dateKey(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    // MARK: - Event Logs

    public func saveEventLogs(_ logs: [EventLog]) throws {
        let cappedLogs = Array(logs.suffix(1000))
        try save(cappedLogs, to: "event_logs.json")
    }

    public func loadEventLogs() throws -> [EventLog]? {
        try load([EventLog].self, from: "event_logs.json")
    }

    // MARK: - UserDefaults Accessors

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

    // MARK: - Dehydration Cache

    public func saveDehydrationCache(_ cache: DehydrationCache, taskId: String) throws {
        let safeId = taskId.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        try save(cache, to: "dehydration_\(safeId).json")
    }

    public func loadDehydrationCache(taskId: String) throws -> DehydrationCache? {
        let safeId = taskId.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return try load(DehydrationCache.self, from: "dehydration_\(safeId).json")
    }

    // MARK: - Clear All

    /// Remove all persisted local data
    public func clearAll() throws {
        let files = [
            "pet.json", "streak.json", "tasks.json", "events.json",
            "sync_state.json", "haiku_cache.json", "user_profile.json",
            "focus_sessions.json", "event_logs.json", "ai_interactions.json",
            "behavior_summary.json", "onboarding_profile.json"
        ]
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
}

// MARK: - Haiku Cache

private struct HaikuCache: Codable {
    let haiku: Haiku
    let date: String
}
