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
        static let developmentStorageSchemaVersion = "developmentStorageSchemaVersion"
        static let lastEventLogTimestamp = "lastEventLogTimestamp"
        static let lastDayPackHash = "lastDayPackHash"
        static let lastBleSyncTime = "lastBleSyncTime"
        static let focusEnforcementMode = "focusEnforcementMode"
        static let deepFocusShieldActive = "deepFocusShieldActive"
        static let deepFocusSelectionCount = "deepFocusSelectionCount"
        static let consecutiveDays = "consecutiveDays"
        static let lastUsageDate = "lastUsageDate"
        static let energyBottles = "energyBottles"
        static let lastCelebratedUnlockCount = "lastCelebratedUnlockCount"
        static let lastHomeHaikuShownDate = "lastHomeHaikuShownDate"
    }

    enum DevelopmentStorageSchema {
        static let currentVersion = 3
    }

    private nonisolated static let persistedFiles = [
        "pet.json", "streak.json", "tasks.json", "events.json",
        "sync_state.json", "haiku_cache.json", "user_profile.json",
        "focus_sessions.json", "event_logs.json", "ai_interactions.json",
        "behavior_summary.json", "onboarding_profile.json",
        "deep_focus_selection.json", "focus_session_active.json",
        "outbox.json", "google_sync_metadata.json", "companion_usage_state.json",
        "avatar.dat", "avatar_pixels.dat", "shared_companion_dialogue.json",
    ]

    private nonisolated static let resettableUserDefaultKeys = [
        Keys.developmentStorageSchemaVersion,
        Keys.lastEventLogTimestamp,
        Keys.lastDayPackHash,
        Keys.lastBleSyncTime,
        Keys.focusEnforcementMode,
        Keys.deepFocusShieldActive,
        Keys.deepFocusSelectionCount,
        Keys.consecutiveDays,
        Keys.lastUsageDate,
        Keys.energyBottles,
        Keys.lastCelebratedUnlockCount,
        Keys.lastHomeHaikuShownDate,
        "isOnboardingCompleted",
    ]

    nonisolated static var developmentStorageSchemaVersionKey: String {
        Keys.developmentStorageSchemaVersion
    }

    public nonisolated static var currentDevelopmentStorageSchemaVersion: Int {
        DevelopmentStorageSchema.currentVersion
    }

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Rapid Development Reset

    /// During the rapid development phase, local persisted data is disposable.
    /// Any schema bump clears old on-device state instead of carrying migration code.
    @discardableResult
    public nonisolated static func resetForRapidDevelopmentIfNeeded(
        currentSchemaVersion: Int,
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        documentsDirectory: URL? = nil
    ) throws -> Bool {
        let storedVersion = userDefaults.object(forKey: Keys.developmentStorageSchemaVersion) as? Int
        guard storedVersion == currentSchemaVersion else {
            let resolvedDocumentsDirectory = documentsDirectory
                ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try clearPersistedDevelopmentData(
                fileManager: fileManager,
                documentsDirectory: resolvedDocumentsDirectory,
                userDefaults: userDefaults
            )
            userDefaults.set(currentSchemaVersion, forKey: Keys.developmentStorageSchemaVersion)
            return true
        }
        return false
    }

    @discardableResult
    public nonisolated static func resetForRapidDevelopmentIfNeeded() throws -> Bool {
        try resetForRapidDevelopmentIfNeeded(
            currentSchemaVersion: currentDevelopmentStorageSchemaVersion,
            userDefaults: .standard,
            fileManager: .default,
            documentsDirectory: nil
        )
    }

    private nonisolated static func clearPersistedDevelopmentData(
        fileManager: FileManager,
        documentsDirectory: URL,
        userDefaults: UserDefaults
    ) throws {
        for file in persistedFiles {
            let url = documentsDirectory.appendingPathComponent(file)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }

        for key in resettableUserDefaultKeys {
            userDefaults.removeObject(forKey: key)
        }
    }

    // MARK: - Generic File Helpers

    /// Save an encodable value to a JSON file in the documents directory
    private func save<T: Encodable>(_ value: T, to filename: String) throws {
        let data = try encoder.encode(value)
        let url = documentsDirectory.appendingPathComponent(filename)
        // .atomic uses temp-file + rename to prevent partial writes on crash.
        // Sensitive credentials live in Keychain; these JSON files are app data that
        // BLE BGAppRefreshTask needs to read/write while the device is locked.
        try data.write(to: url, options: [.atomic])
    }

    /// Delete a specific file from the documents directory
    public func deleteFile(named filename: String) throws {
        guard !filename.contains(".."), !filename.contains("/") else {
            return
        }
        let url = documentsDirectory.appendingPathComponent(filename)
        let resolvedPath = url.standardizedFileURL.path
        let documentsPath = documentsDirectory.standardizedFileURL.path + "/"
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

    // MARK: - Companion Usage

    public func saveCompanionUsageState(_ state: CompanionUsageState) throws {
        try save(state, to: "companion_usage_state.json")
    }

    public func loadCompanionUsageState() throws -> CompanionUsageState? {
        try load(CompanionUsageState.self, from: "companion_usage_state.json")
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

    // MARK: - Companion Dialogue Cache

    public func saveSharedCompanionDialogue(_ cache: SharedCompanionDialogueCache) throws {
        try save(cache, to: "shared_companion_dialogue.json")
    }

    public func loadSharedCompanionDialogue() throws -> SharedCompanionDialogueCache? {
        try load(SharedCompanionDialogueCache.self, from: "shared_companion_dialogue.json")
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

    public func saveActiveFocusSession(_ session: FocusSession) throws {
        try save(session, to: "focus_session_active.json")
    }

    public func loadActiveFocusSession() throws -> FocusSession? {
        try load(FocusSession.self, from: "focus_session_active.json")
    }

    public func clearActiveFocusSession() throws {
        try deleteFile(named: "focus_session_active.json")
    }

    private nonisolated static let dateKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    private static func dateKey(from date: Date) -> String {
        dateKeyFormatter.string(from: date)
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
    
    // MARK: Gamify Accessors
    
    public func saveConsecutiveDays(_ days: Int) {
        userDefaults.set(days, forKey: Keys.consecutiveDays)
    }
    
    public func loadConsecutiveDays() -> Int {
        userDefaults.integer(forKey: Keys.consecutiveDays)
    }

    public func saveLastUsageDate(_ date: Date?) {
        userDefaults.set(date, forKey: Keys.lastUsageDate)
    }

    public func loadLastUsageDate() -> Date? {
        userDefaults.object(forKey: Keys.lastUsageDate) as? Date
    }
    
    public func saveEnergyBottles(_ blocks: Int) {
        userDefaults.set(blocks, forKey: Keys.energyBottles)
    }

    public func loadEnergyBottles() -> Int {
        userDefaults.integer(forKey: Keys.energyBottles)
    }

    public func saveLastCelebratedUnlockCount(_ count: Int) {
        userDefaults.set(count, forKey: Keys.lastCelebratedUnlockCount)
    }

    /// 已庆祝过的累计解锁场景数。默认 1：harbor 是初始解锁，永远不需要"庆祝"。
    public func loadLastCelebratedUnlockCount() -> Int {
        if userDefaults.object(forKey: Keys.lastCelebratedUnlockCount) == nil {
            return 1
        }
        return userDefaults.integer(forKey: Keys.lastCelebratedUnlockCount)
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

    // MARK: Home Companion

    public func saveLastHomeHaikuShownDate(_ dateString: String) {
        userDefaults.set(dateString, forKey: Keys.lastHomeHaikuShownDate)
    }

    public func loadLastHomeHaikuShownDate() -> String? {
        userDefaults.string(forKey: Keys.lastHomeHaikuShownDate)
    }

    // MARK: - Focus Enforcement Settings

    public func saveFocusEnforcementMode(_ mode: FocusEnforcementMode) {
        userDefaults.set(mode.rawValue, forKey: Keys.focusEnforcementMode)
    }

    public func loadFocusEnforcementMode() -> FocusEnforcementMode? {
        guard let raw = userDefaults.string(forKey: Keys.focusEnforcementMode) else {
            return nil
        }
        return FocusEnforcementMode(rawValue: raw)
    }

    public func saveDeepFocusSelection(_ selection: FocusAppSelection) throws {
        try save(selection, to: "deep_focus_selection.json")
        userDefaults.set(selection.selectedApplicationCount, forKey: Keys.deepFocusSelectionCount)
    }

    public func loadDeepFocusSelection() throws -> FocusAppSelection? {
        try load(FocusAppSelection.self, from: "deep_focus_selection.json")
    }

    public func clearDeepFocusSelection() throws {
        try deleteFile(named: "deep_focus_selection.json")
        userDefaults.removeObject(forKey: Keys.deepFocusSelectionCount)
    }

    public func saveDeepFocusShieldActive(_ active: Bool) {
        userDefaults.set(active, forKey: Keys.deepFocusShieldActive)
    }

    public func loadDeepFocusShieldActive() -> Bool {
        userDefaults.bool(forKey: Keys.deepFocusShieldActive)
    }

    // MARK: - Google Sync Outbox

    public func saveOutbox(_ entries: [OutboxEntry]) throws {
        try save(entries, to: "outbox.json")
    }

    public func loadOutbox() throws -> [OutboxEntry] {
        try load([OutboxEntry].self, from: "outbox.json") ?? []
    }

    // MARK: - Google Sync Metadata

    public func saveGoogleSyncMetadata(_ metadata: GoogleSyncMetadata) throws {
        try save(metadata, to: "google_sync_metadata.json")
    }

    public func loadGoogleSyncMetadata() throws -> GoogleSyncMetadata? {
        try load(GoogleSyncMetadata.self, from: "google_sync_metadata.json")
    }

    // MARK: - Avatar Data

    /// Save original avatar image data
    public func saveAvatarData(_ data: Data) throws {
        let url = documentsDirectory.appendingPathComponent("avatar.dat")
        try data.write(to: url, options: [.atomic])
    }

    /// Load original avatar image data
    public func loadAvatarData() -> Data? {
        let url = documentsDirectory.appendingPathComponent("avatar.dat")
        return try? Data(contentsOf: url)
    }

    /// Save 4bpp encoded pixel data for BLE transmission
    public func saveAvatarPixels(_ data: Data) throws {
        let url = documentsDirectory.appendingPathComponent("avatar_pixels.dat")
        try data.write(to: url, options: [.atomic])
    }

    /// Load 4bpp encoded pixel data
    public func loadAvatarPixels() -> Data? {
        let url = documentsDirectory.appendingPathComponent("avatar_pixels.dat")
        return try? Data(contentsOf: url)
    }

    // MARK: - Clear All

    /// Remove all persisted local data
    public func clearAll() throws {
        try Self.clearPersistedDevelopmentData(
            fileManager: fileManager,
            documentsDirectory: documentsDirectory,
            userDefaults: userDefaults
        )
    }
}

// MARK: - Haiku Cache

private struct HaikuCache: Codable {
    let haiku: Haiku
    let date: String
}

// MARK: - Shared Companion Dialogue Cache

public struct SharedCompanionDialogueCache: Codable, Sendable {
    public let date: String
    public let fingerprint: String
    public let text: String

    public init(date: String, fingerprint: String, text: String) {
        self.date = date
        self.fingerprint = fingerprint
        self.text = text
    }
}
