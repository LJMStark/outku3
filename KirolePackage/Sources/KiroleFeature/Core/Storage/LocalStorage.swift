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
        static let pendingCustomCompanionPushId = "pendingCustomCompanionPushId"
        static let customAvatarLastPushedDeviceId = "customAvatarLastPushedDeviceId"
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
        static let integrationConnections = "integration_connections.json"
        static let sharedCompanionDialogue = "shared_companion_dialogue.json"
        static let customCompanions = "custom_companions.json"
        static let integrationSyncTimes = "integration_sync_times.json"
        /// Prefix for per-companion avatar image/preview blobs (PNG since v2.5.24).
        /// Actual filenames are built from CustomCompanion.avatarPixelsFileName / avatarPreviewFileName.
        static let customCompanionAssetPrefix = "custom_companion_"
        /// Prefix for date-partitioned focus history files (`focus_sessions_YYYY-MM-DD.json`).
        static let focusSessionHistoryPrefix = "focus_sessions_"

        static let dynamicPersistedPrefixes = [
            customCompanionAssetPrefix,
            focusSessionHistoryPrefix,
        ]

        static let persisted = [
            pet, tasks, events,
            syncState, haikuCache, userProfile,
            focusSessions, eventLogs, aiInteractions,
            behaviorSummary, onboardingProfile,
            deepFocusSelection, activeFocusSession,
            outbox, googleSyncMetadata, companionUsageState,
            integrationConnections,
            sharedCompanionDialogue,
            customCompanions,
            integrationSyncTimes,
        ]

        /// Filenames the app no longer writes but that may still exist on disk from
        /// prior installs. Reset/clearAll continues to sweep these so removed-feature
        /// data doesn't linger forever after a user upgrades. Add an entry here when
        /// retiring a persisted file — never delete from this list.
        static let legacy = [
            "avatar.dat",
            "avatar_pixels.dat",
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
        Keys.pendingCustomCompanionPushId,
        Keys.customAvatarLastPushedDeviceId,
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
        for file in Files.persisted + Files.legacy {
            let url = documentsDirectory.appendingPathComponent(file)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }

        // Date-partitioned focus history and custom companion assets use dynamic filenames.
        let contents = (try? fileManager.contentsOfDirectory(atPath: documentsDirectory.path)) ?? []
        for name in contents where Files.dynamicPersistedPrefixes.contains(where: { name.hasPrefix($0) }) {
            let url = documentsDirectory.appendingPathComponent(name)
            try? fileManager.removeItem(at: url)
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
        guard let url = validatedDocumentFileURL(named: filename) else { return }
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    /// Quarantine a corrupt/unreadable file by renaming it to `<name>.corrupt`.
    /// On a read/decode failure the caller would otherwise let default/partial data silently
    /// overwrite the original; moving it aside preserves the original for recovery/forensics while
    /// letting the app continue. Overwrites any prior `.corrupt`. Documents-directory scoped only.
    public func quarantineCorruptFile(named filename: String) throws {
        guard let url = validatedDocumentFileURL(named: filename) else { return }
        guard fileManager.fileExists(atPath: url.path) else { return }

        let quarantineURL = documentsDirectory.appendingPathComponent(filename + ".corrupt")
        if fileManager.fileExists(atPath: quarantineURL.path) {
            try fileManager.removeItem(at: quarantineURL)
        }
        try fileManager.moveItem(at: url, to: quarantineURL)
    }

    /// Resolves a direct child of Documents while rejecting absolute, nested, and traversal paths.
    private func validatedDocumentFileURL(named filename: String) -> URL? {
        guard !filename.contains(".."), !filename.contains("/") else { return nil }

        let url = documentsDirectory.appendingPathComponent(filename)
        let resolvedPath = url.standardizedFileURL.path
        let documentsPath = documentsDirectory.standardizedFileURL.path + "/"
        guard resolvedPath.hasPrefix(documentsPath) else { return nil }
        return url
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

    // MARK: - Integration Connection State

    /// Persisted per-integration connection toggle (IntegrationType.rawValue → isConnected).
    /// Restored on launch so a user's disconnect survives relaunch instead of reverting to defaults.
    public func saveIntegrationConnections(_ states: [String: Bool]) throws {
        try save(states, to: Files.integrationConnections)
    }

    public func loadIntegrationConnections() throws -> [String: Bool]? {
        try load([String: Bool].self, from: Files.integrationConnections)
    }

    // MARK: - Integration Sync Times

    public func saveIntegrationSyncTimes(_ times: [String: Date]) throws {
        try save(times, to: Files.integrationSyncTimes)
    }

    public func loadIntegrationSyncTimes() throws -> [String: Date] {
        try load([String: Date].self, from: Files.integrationSyncTimes) ?? [:]
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
        // `1...count` traps (uncatchable precondition failure) when count < 1, so a
        // non-positive window must short-circuit before the closed range is formed.
        guard count > 0 else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var result: [FocusSession] = []
        for offset in 1...count {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            do {
                result.append(contentsOf: try loadFocusSessionsForDate(date) ?? [])
            } catch {
                // 单日文件损坏只跳过该天，但必须留痕——静默按 0 计会让周/月统计与趋势悄悄算错。
                ErrorReporter.log(
                    .persistence(operation: "read", target: "focus_sessions(\(date))", underlying: error.localizedDescription),
                    context: "LocalStorage.loadFocusSessionsForPastDays"
                )
            }
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

    /// Builds a local calendar-day key using the timezone in effect at call time.
    /// A cached `DateFormatter` would freeze the timezone for the process lifetime.
    nonisolated static func dateKey(
        from date: Date,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            assertionFailure("Gregorian calendar did not produce a complete date")
            return "0000-00-00"
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    // MARK: - Event Logs

    public func saveEventLogs(_ logs: [EventLog]) throws {
        let cappedLogs = Array(logs.suffix(1000))
        try save(cappedLogs, to: Files.eventLogs)
    }

    public func loadEventLogs() throws -> [EventLog]? {
        try load([EventLog].self, from: Files.eventLogs)
    }

    /// Atomically appends BLE logs and, for replay batches only, advances the replay watermark.
    /// Keeping the read/merge/write/watermark sequence inside this actor prevents concurrent live
    /// and 0x21 persistence tasks from overwriting one another or moving the watermark backwards.
    func appendEventLogs(
        _ logs: [EventLog],
        isReplay: Bool,
        replayWatermarkCandidate: UInt32?
    ) throws {
        let currentWatermark = loadLastEventLogTimestamp() ?? 0
        let logsToPersist = isReplay
            ? logs.filter { UInt32($0.timestamp.timeIntervalSince1970) > currentWatermark }
            : logs

        if !logsToPersist.isEmpty {
            let existing = try loadEventLogs() ?? []
            try saveEventLogs(existing + logsToPersist)
        }

        guard isReplay,
              let replayWatermarkCandidate,
              replayWatermarkCandidate > currentWatermark else {
            return
        }
        saveLastEventLogTimestamp(replayWatermarkCandidate)
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

    // MARK: - Custom Companions

    public func saveCustomCompanions(_ companions: [CustomCompanion]) throws {
        try save(companions, to: Files.customCompanions)
    }

    public func loadCustomCompanions() throws -> [CustomCompanion] {
        try load([CustomCompanion].self, from: Files.customCompanions) ?? []
    }

    /// Filenames are derived from the companion id so they're stable across renames and
    /// safe to share between code that only holds the id (e.g. BLE push) and code that
    /// holds the full struct.
    public nonisolated static func customCompanionPreviewFileName(for id: UUID) -> String {
        "\(Files.customCompanionAssetPrefix)\(id.uuidString)_preview.png"
    }

    /// Legacy on-disk name（`_pixels.dat`）保留不改：文件名经 `CustomCompanion.avatarPixelsFileName`
    /// 持久化在 custom_companions.json 里，改名会 break 既有解码。v2.5.24 起该文件存的是
    /// 硬件 PNG（AvatarImageProcessor 产出），不再是 4bpp 像素数据。
    public nonisolated static func customCompanionPixelsFileName(for id: UUID) -> String {
        "\(Files.customCompanionAssetPrefix)\(id.uuidString)_pixels.dat"
    }

    /// 注：v2.5.24 起 preview 与 image 通常是同一份 PNG 字节（AvatarProcessResult 两槽同源），
    /// 这里刻意保持双文件写入以不动 CustomCompanion 的双文件契约；合并为单文件属未来优化。
    public func saveCustomCompanionAssets(
        id: UUID,
        previewData: Data,
        imageData: Data
    ) throws {
        let previewURL = documentsDirectory.appendingPathComponent(
            Self.customCompanionPreviewFileName(for: id)
        )
        let imageURL = documentsDirectory.appendingPathComponent(
            Self.customCompanionPixelsFileName(for: id)
        )
        try previewData.write(to: previewURL, options: [.atomic])
        try imageData.write(to: imageURL, options: [.atomic])
    }

    public func loadCustomCompanionPreview(id: UUID) -> Data? {
        let url = documentsDirectory.appendingPathComponent(
            Self.customCompanionPreviewFileName(for: id)
        )
        return try? Data(contentsOf: url)
    }

    /// Loads the hardware avatar PNG (v2.5.24+; pre-existing installs may still hold
    /// legacy 4bpp bytes here — callers guard with `AvatarImageProcessor.isPNGData`).
    public func loadCustomCompanionImageData(id: UUID) -> Data? {
        let url = documentsDirectory.appendingPathComponent(
            Self.customCompanionPixelsFileName(for: id)
        )
        return try? Data(contentsOf: url)
    }

    public func deleteCustomCompanionAssets(id: UUID) throws {
        try deleteFile(named: Self.customCompanionPreviewFileName(for: id))
        try deleteFile(named: Self.customCompanionPixelsFileName(for: id))
    }

    // MARK: - Pending Custom Companion BLE Push

    /// Saves the companion ID whose avatar PNG frame failed to reach the hardware.
    /// Cleared automatically when the push succeeds on the next BLE connection.
    /// v2.5.33: 最近一次成功收到 0x15 头像的设备 id——连接到不同设备时触发自动重推。
    public func saveCustomAvatarLastPushedDeviceID(_ id: String) {
        userDefaults.set(id, forKey: Keys.customAvatarLastPushedDeviceId)
    }

    public func loadCustomAvatarLastPushedDeviceID() -> String? {
        userDefaults.string(forKey: Keys.customAvatarLastPushedDeviceId)
    }

    public func savePendingCustomCompanionPush(id: UUID) {
        userDefaults.set(id.uuidString, forKey: Keys.pendingCustomCompanionPushId)
    }

    public func loadPendingCustomCompanionPush() -> UUID? {
        guard let uuidString = userDefaults.string(forKey: Keys.pendingCustomCompanionPushId) else { return nil }
        return UUID(uuidString: uuidString)
    }

    public func clearPendingCustomCompanionPush() {
        userDefaults.removeObject(forKey: Keys.pendingCustomCompanionPushId)
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
