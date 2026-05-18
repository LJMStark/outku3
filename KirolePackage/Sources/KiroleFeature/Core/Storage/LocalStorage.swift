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

    private enum Files {
        static let pet = "pet.json"
        static let tasks = "tasks.json"
        static let events = "events.json"
        static let syncState = "sync_state.json"
        static let haikuCache = "haiku_cache.json"
        static let userProfile = "user_profile.json"
        static let focusSessions = "focus_sessions.json"
        static let eventLogs = "event_logs.json"
        static let aiInteractions = "ai_interactions.json"
        static let behaviorSummary = "behavior_summary.json"
        static let onboardingProfile = "onboarding_profile.json"
        static let deepFocusSelection = "deep_focus_selection.json"
        static let activeFocusSession = "focus_session_active.json"
        static let outbox = "outbox.json"
        static let googleSyncMetadata = "google_sync_metadata.json"
        static let companionUsageState = "companion_usage_state.json"
        static let avatarData = "avatar.dat"
        static let avatarPixels = "avatar_pixels.dat"
        static let sharedCompanionDialogue = "shared_companion_dialogue.json"

        static let persisted = [
            pet, tasks, events,
            syncState, haikuCache, userProfile,
            focusSessions, eventLogs, aiInteractions,
            behaviorSummary, onboardingProfile,
            deepFocusSelection, activeFocusSession,
            outbox, googleSyncMetadata, companionUsageState,
            avatarData, avatarPixels, sharedCompanionDialogue,
        ]
    }

    enum DevelopmentStorageSchema {
        static let currentVersion = 5
    }

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
        for file in Files.persisted {
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
        try save(pet, to: Files.pet)
    }

    public func loadPet() throws -> Pet? {
        try load(Pet.self, from: Files.pet)
    }

    // MARK: - Tasks

    public func saveTasks(_ tasks: [TaskItem]) throws {
        try save(tasks, to: Files.tasks)
    }

    public func loadTasks() throws -> [TaskItem]? {
        try load([TaskItem].self, from: Files.tasks)
    }

    // MARK: - Events

    public func saveEvents(_ events: [CalendarEvent]) throws {
        try save(events, to: Files.events)
    }

    public func loadEvents() throws -> [CalendarEvent]? {
        try load([CalendarEvent].self, from: Files.events)
    }

    // MARK: - User Profile

    public func saveUserProfile(_ profile: UserProfile) throws {
        try save(profile, to: Files.userProfile)
    }

    public func loadUserProfile() throws -> UserProfile? {
        try load(UserProfile.self, from: Files.userProfile)
    }

    // MARK: - Companion Usage

    public func saveCompanionUsageState(_ state: CompanionUsageState) throws {
        try save(state, to: Files.companionUsageState)
    }

    public func loadCompanionUsageState() throws -> CompanionUsageState? {
        try load(CompanionUsageState.self, from: Files.companionUsageState)
    }

    // MARK: - Onboarding Profile

    public func saveOnboardingProfile(_ profile: OnboardingProfile) throws {
        try save(profile, to: Files.onboardingProfile)
    }

    public func loadOnboardingProfile() throws -> OnboardingProfile? {
        try load(OnboardingProfile.self, from: Files.onboardingProfile)
    }

    // MARK: - Sync State

    public func saveSyncState(_ state: SyncState) throws {
        try save(state, to: Files.syncState)
    }

    public func loadSyncState() throws -> SyncState? {
        try load(SyncState.self, from: Files.syncState)
    }

    // MARK: - Haiku Cache

    /// Cache today's haiku
    public func cacheHaiku(_ haiku: Haiku, for date: Date) throws {
        let dateString = ISO8601DateFormatter().string(from: date)
        let cacheEntry = HaikuCache(haiku: haiku, date: dateString)
        try save(cacheEntry, to: Files.haikuCache)
    }

    /// Retrieve the cached haiku if it was generated today
    public func getCachedHaiku(for date: Date) throws -> Haiku? {
        guard let cache = try load(HaikuCache.self, from: Files.haikuCache) else {
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
        try save(cache, to: Files.sharedCompanionDialogue)
    }

    public func loadSharedCompanionDialogue() throws -> SharedCompanionDialogueCache? {
        try load(SharedCompanionDialogueCache.self, from: Files.sharedCompanionDialogue)
    }

    // MARK: - AI Interactions

    /// Save AI interaction history (capped at 100 most recent)
    public func saveAIInteractions(_ interactions: [AIInteraction]) throws {
        let capped = Array(interactions.suffix(100))
        try save(capped, to: Files.aiInteractions)
    }

    /// Load AI interaction history
    public func loadAIInteractions() throws -> [AIInteraction]? {
        try load([AIInteraction].self, from: Files.aiInteractions)
    }

    // MARK: - Behavior Summary

    // TODO: saveBehaviorSummary has 0 callers — behavior summary pipeline is inactive.
    // Connect after hardware integration: call saveBehaviorSummary after daily settlement
    // to give companions genuine memory. Until then, loadBehaviorSummary always returns nil.

    /// Save user behavior summary
    public func saveBehaviorSummary(_ summary: UserBehaviorSummary) throws {
        try save(summary, to: Files.behaviorSummary)
    }

    /// Load user behavior summary
    public func loadBehaviorSummary() throws -> UserBehaviorSummary? {
        try load(UserBehaviorSummary.self, from: Files.behaviorSummary)
    }

    // MARK: - Focus Sessions

    public func saveFocusSessions(_ sessions: [FocusSession]) throws {
        try save(sessions, to: Files.focusSessions)
    }

    public func loadFocusSessions() throws -> [FocusSession]? {
        try load([FocusSession].self, from: Files.focusSessions)
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

    /// Loads sessions for the past `count` days (day -1 through day -count) in one actor call.
    public func loadFocusSessionsForPastDays(_ count: Int) throws -> [FocusSession] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var result: [FocusSession] = []
        for offset in 1...count {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let sessions = (try? loadFocusSessionsForDate(date)) ?? []
            result.append(contentsOf: sessions)
        }
        return result
    }

    public func saveActiveFocusSession(_ session: FocusSession) throws {
        try save(session, to: Files.activeFocusSession)
    }

    public func loadActiveFocusSession() throws -> FocusSession? {
        try load(FocusSession.self, from: Files.activeFocusSession)
    }

    public func clearActiveFocusSession() throws {
        try deleteFile(named: Files.activeFocusSession)
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
        try save(cappedLogs, to: Files.eventLogs)
    }

    public func loadEventLogs() throws -> [EventLog]? {
        try load([EventLog].self, from: Files.eventLogs)
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
        try save(selection, to: Files.deepFocusSelection)
        userDefaults.set(selection.selectedApplicationCount, forKey: Keys.deepFocusSelectionCount)
    }

    public func loadDeepFocusSelection() throws -> FocusAppSelection? {
        try load(FocusAppSelection.self, from: Files.deepFocusSelection)
    }

    public func clearDeepFocusSelection() throws {
        try deleteFile(named: Files.deepFocusSelection)
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
        try save(entries, to: Files.outbox)
    }

    public func loadOutbox() throws -> [OutboxEntry] {
        try load([OutboxEntry].self, from: Files.outbox) ?? []
    }

    // MARK: - Google Sync Metadata

    public func saveGoogleSyncMetadata(_ metadata: GoogleSyncMetadata) throws {
        try save(metadata, to: Files.googleSyncMetadata)
    }

    public func loadGoogleSyncMetadata() throws -> GoogleSyncMetadata? {
        try load(GoogleSyncMetadata.self, from: Files.googleSyncMetadata)
    }

    // MARK: - Avatar Data

    /// Save original avatar image data
    public func saveAvatarData(_ data: Data) throws {
        let url = documentsDirectory.appendingPathComponent(Files.avatarData)
        try data.write(to: url, options: [.atomic])
    }

    /// Load original avatar image data
    public func loadAvatarData() -> Data? {
        let url = documentsDirectory.appendingPathComponent(Files.avatarData)
        return try? Data(contentsOf: url)
    }

    /// Save 4bpp encoded pixel data for BLE transmission
    public func saveAvatarPixels(_ data: Data) throws {
        let url = documentsDirectory.appendingPathComponent(Files.avatarPixels)
        try data.write(to: url, options: [.atomic])
    }

    /// Load 4bpp encoded pixel data
    public func loadAvatarPixels() -> Data? {
        let url = documentsDirectory.appendingPathComponent(Files.avatarPixels)
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
