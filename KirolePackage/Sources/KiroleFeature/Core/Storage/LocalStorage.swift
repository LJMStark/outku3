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
        static let lastDayPackSemanticHash = "lastDayPackSemanticHash"
        static let taskListSnapshotEpoch = "taskListSnapshotEpoch"
        static let taskListSnapshotRevision = "taskListSnapshotRevision"
        static let lastBleSyncTime = "lastBleSyncTime"
        static let focusEnforcementMode = "focusEnforcementMode"
        static let deepFocusShieldActive = "deepFocusShieldActive"
        static let deepFocusSelectionCount = "deepFocusSelectionCount"
        static let consecutiveDays = "consecutiveDays"
        static let lastUsageDate = "lastUsageDate"
        static let energyBottles = "energyBottles"
        static let lastCelebratedUnlockCount = "lastCelebratedUnlockCount"
        static let lastHomeHaikuShownDate = "lastHomeHaikuShownDate"
        static let taskLibraryStabilityCheckpoint = "taskLibraryStabilityCheckpoint"
        static let dailyContentStabilityCheckpoint = "dailyContentStabilityCheckpoint"
        static let dailyContentObservedDate = "dailyContentObservedDate"
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
        static let taskOperationLedger = "task_operation_ledger.json"
        static let taskListSnapshotVersion = "task_list_snapshot_version.json"
        static let taskLibraryCommittedStates = "task_library_committed_states.json"
        static let taskLibraryPendingDeliveries = "task_library_pending_deliveries.json"
        static let dailyContentCommittedStates = "daily_content_committed_states.json"
        static let dailyContentPendingDeliveries = "daily_content_pending_deliveries.json"
        static let focusEnergyAwardReceipts = "focus_energy_award_receipts.json"
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
        static let pendingCustomAvatarOperation = "pending_custom_avatar_operation.json"
        static let pendingCustomAvatarPreview = "pending_custom_avatar_preview.png"
        static let pendingCustomAvatarImage = "pending_custom_avatar_image.dat"
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
            focusSessions, eventLogs, taskOperationLedger, taskListSnapshotVersion,
            taskLibraryCommittedStates, taskLibraryPendingDeliveries,
            dailyContentCommittedStates, dailyContentPendingDeliveries,
            focusEnergyAwardReceipts, aiInteractions,
            behaviorSummary, onboardingProfile,
            deepFocusSelection, activeFocusSession,
            outbox, googleSyncMetadata, companionUsageState,
            integrationConnections,
            sharedCompanionDialogue,
            customCompanions,
            integrationSyncTimes,
            pendingCustomAvatarOperation,
            pendingCustomAvatarPreview,
            pendingCustomAvatarImage,
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
        static let currentVersion = 9
    }

    private struct TaskListSnapshotDeliveryState: Codable {
        /// Compatibility cursor for the pre-delivery-store API. It has no device identity and is
        /// deliberately never used to seed a real destination.
        var legacyVersion: TaskListSnapshotVersion?
        var destinations: [TaskListSnapshotDestinationState]

        static let empty = TaskListSnapshotDeliveryState(
            legacyVersion: nil,
            destinations: []
        )
    }

    private struct TaskListSnapshotDestinationState: Codable {
        let destinationID: String
        var lastFrozenVersion: TaskListSnapshotVersion?
        var reservation: TaskListSnapshotDeliveryReservation?
        var frozenResponses: [StoredTaskListSnapshotResponse]
    }

    private struct TaskListSnapshotDeliveryReservation: Codable {
        let key: TaskListSnapshotRequestKey
        let version: TaskListSnapshotVersion
    }

    private struct StoredTaskListSnapshotResponse: Codable {
        var response: FrozenTaskListSnapshotResponse
        var phase: TaskListSnapshotDeliveryPhase
    }

    private enum TaskListSnapshotDeliveryPhase: String, Codable {
        case prepared
        case attempted
        case delivered
    }

    private enum TaskListSnapshotDeliveryStorageError: Error {
        case activeDeliveryConflict
        case reservationMismatch
        case responseMismatch
    }

    private nonisolated static let resettableUserDefaultKeys = [
        Keys.developmentStorageSchemaVersion,
        Keys.lastEventLogTimestamp,
        Keys.lastDayPackHash,
        Keys.lastDayPackSemanticHash,
        Keys.taskListSnapshotEpoch,
        Keys.taskListSnapshotRevision,
        Keys.lastBleSyncTime,
        Keys.focusEnforcementMode,
        Keys.deepFocusShieldActive,
        Keys.deepFocusSelectionCount,
        Keys.consecutiveDays,
        Keys.lastUsageDate,
        Keys.energyBottles,
        Keys.lastCelebratedUnlockCount,
        Keys.lastHomeHaikuShownDate,
        Keys.taskLibraryStabilityCheckpoint,
        Keys.dailyContentStabilityCheckpoint,
        Keys.dailyContentObservedDate,
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

    nonisolated static func saveTaskLibraryStabilityCheckpoint(
        _ checkpoint: TaskLibraryStabilityCheckpoint,
        userDefaults: UserDefaults = .standard
    ) throws {
        userDefaults.set(try JSONEncoder().encode(checkpoint), forKey: Keys.taskLibraryStabilityCheckpoint)
    }

    nonisolated static func loadTaskLibraryStabilityCheckpoint(
        userDefaults: UserDefaults = .standard
    ) throws -> TaskLibraryStabilityCheckpoint? {
        guard let data = userDefaults.data(forKey: Keys.taskLibraryStabilityCheckpoint) else {
            return nil
        }
        return try JSONDecoder().decode(TaskLibraryStabilityCheckpoint.self, from: data)
    }

    nonisolated static func clearTaskLibraryStabilityCheckpoint(
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.removeObject(forKey: Keys.taskLibraryStabilityCheckpoint)
    }

    nonisolated static func saveDailyContentStabilityCheckpoint(
        _ checkpoint: DailyContentStabilityCheckpoint,
        userDefaults: UserDefaults = .standard
    ) throws {
        userDefaults.set(
            try JSONEncoder().encode(checkpoint),
            forKey: Keys.dailyContentStabilityCheckpoint
        )
    }

    nonisolated static func loadDailyContentStabilityCheckpoint(
        userDefaults: UserDefaults = .standard
    ) throws -> DailyContentStabilityCheckpoint? {
        guard let data = userDefaults.data(forKey: Keys.dailyContentStabilityCheckpoint) else {
            return nil
        }
        return try JSONDecoder().decode(DailyContentStabilityCheckpoint.self, from: data)
    }

    nonisolated static func clearDailyContentStabilityCheckpoint(
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.removeObject(forKey: Keys.dailyContentStabilityCheckpoint)
    }

    nonisolated static func saveDailyContentObservedDate(
        _ date: DailyContentDate,
        userDefaults: UserDefaults = .standard
    ) {
        userDefaults.set(
            try? JSONEncoder().encode(date),
            forKey: Keys.dailyContentObservedDate
        )
    }

    nonisolated static func loadDailyContentObservedDate(
        userDefaults: UserDefaults = .standard
    ) -> DailyContentDate? {
        guard let data = userDefaults.data(forKey: Keys.dailyContentObservedDate) else {
            return nil
        }
        return try? JSONDecoder().decode(DailyContentDate.self, from: data)
    }

    // MARK: - Task Library Delivery

    func saveTaskLibraryCommittedState(
        _ state: TaskLibraryCommittedState,
        for destinationID: String
    ) throws {
        guard !destinationID.isEmpty else { return }
        var snapshots = try loadTaskLibraryCommittedSnapshots()
        if snapshots[destinationID]?.state != state {
            snapshots[destinationID] = TaskLibraryCommittedSnapshot(
                state: state,
                records: [],
                phaseSourceFingerprints: [:],
                hasCompleteRecords: false,
                personaFingerprint: ""
            )
        }
        try save(snapshots, to: Files.taskLibraryCommittedStates)
    }

    func loadTaskLibraryCommittedState(
        for destinationID: String
    ) throws -> TaskLibraryCommittedState? {
        guard !destinationID.isEmpty else { return nil }
        return try loadTaskLibraryCommittedSnapshots()[destinationID]?.state
    }

    func saveTaskLibraryCommittedSnapshot(
        _ snapshot: TaskLibraryCommittedSnapshot,
        for destinationID: String
    ) throws {
        guard !destinationID.isEmpty else { return }
        var snapshots = try loadTaskLibraryCommittedSnapshots()
        snapshots[destinationID] = snapshot
        try save(snapshots, to: Files.taskLibraryCommittedStates)
    }

    func loadTaskLibraryCommittedSnapshot(
        for destinationID: String
    ) throws -> TaskLibraryCommittedSnapshot? {
        guard !destinationID.isEmpty else { return nil }
        return try loadTaskLibraryCommittedSnapshots()[destinationID]
    }

    func removeTaskLibraryCommittedState(for destinationID: String) throws {
        guard !destinationID.isEmpty else { return }
        var snapshots = try loadTaskLibraryCommittedSnapshots()
        guard snapshots.removeValue(forKey: destinationID) != nil else { return }
        try save(snapshots, to: Files.taskLibraryCommittedStates)
    }

    func clearTaskLibraryCommittedStates() throws {
        try deleteFile(named: Files.taskLibraryCommittedStates)
    }

    func saveTaskLibraryPendingDelivery(
        _ delivery: TaskLibraryPendingDelivery,
        for destinationID: String
    ) throws {
        guard !destinationID.isEmpty else { return }
        var deliveries = try loadTaskLibraryPendingDeliveries()
        deliveries[destinationID] = delivery
        try save(deliveries, to: Files.taskLibraryPendingDeliveries)
    }

    func loadTaskLibraryPendingDelivery(
        for destinationID: String
    ) throws -> TaskLibraryPendingDelivery? {
        guard !destinationID.isEmpty else { return nil }
        return try loadTaskLibraryPendingDeliveries()[destinationID]
    }

    func removeTaskLibraryPendingDelivery(for destinationID: String) throws {
        guard !destinationID.isEmpty else { return }
        var deliveries = try loadTaskLibraryPendingDeliveries()
        guard deliveries.removeValue(forKey: destinationID) != nil else { return }
        try save(deliveries, to: Files.taskLibraryPendingDeliveries)
    }

    func clearTaskLibraryPendingDeliveries() throws {
        try deleteFile(named: Files.taskLibraryPendingDeliveries)
    }

    private func loadTaskLibraryCommittedSnapshots() throws
        -> [String: TaskLibraryCommittedSnapshot] {
        try load(
            [String: TaskLibraryCommittedSnapshot].self,
            from: Files.taskLibraryCommittedStates
        ) ?? [:]
    }

    private func loadTaskLibraryPendingDeliveries() throws -> [String: TaskLibraryPendingDelivery] {
        try load(
            [String: TaskLibraryPendingDelivery].self,
            from: Files.taskLibraryPendingDeliveries
        ) ?? [:]
    }

    // MARK: - Daily Content Delivery

    func saveDailyContentCommittedSnapshot(
        _ snapshot: DailyContentCommittedSnapshot,
        for destinationID: String
    ) throws {
        guard !destinationID.isEmpty else { return }
        var snapshots = try loadDailyContentCommittedSnapshots()
        snapshots[destinationID] = snapshot
        try save(snapshots, to: Files.dailyContentCommittedStates)
    }

    func loadDailyContentCommittedSnapshot(
        for destinationID: String
    ) throws -> DailyContentCommittedSnapshot? {
        guard !destinationID.isEmpty else { return nil }
        return try loadDailyContentCommittedSnapshots()[destinationID]
    }

    func removeDailyContentCommittedSnapshot(for destinationID: String) throws {
        guard !destinationID.isEmpty else { return }
        var snapshots = try loadDailyContentCommittedSnapshots()
        guard snapshots.removeValue(forKey: destinationID) != nil else { return }
        try save(snapshots, to: Files.dailyContentCommittedStates)
    }

    func saveDailyContentPendingDelivery(
        _ delivery: DailyContentPendingDelivery,
        for destinationID: String
    ) throws {
        guard !destinationID.isEmpty else { return }
        var deliveries = try loadDailyContentPendingDeliveries()
        deliveries[destinationID] = delivery
        try save(deliveries, to: Files.dailyContentPendingDeliveries)
    }

    func loadDailyContentPendingDelivery(
        for destinationID: String
    ) throws -> DailyContentPendingDelivery? {
        guard !destinationID.isEmpty else { return nil }
        return try loadDailyContentPendingDeliveries()[destinationID]
    }

    func removeDailyContentPendingDelivery(for destinationID: String) throws {
        guard !destinationID.isEmpty else { return }
        var deliveries = try loadDailyContentPendingDeliveries()
        guard deliveries.removeValue(forKey: destinationID) != nil else { return }
        try save(deliveries, to: Files.dailyContentPendingDeliveries)
    }

    func clearDailyContentCommittedSnapshots() throws {
        try save([String: DailyContentCommittedSnapshot](), to: Files.dailyContentCommittedStates)
    }

    func clearDailyContentPendingDeliveries() throws {
        try save([String: DailyContentPendingDelivery](), to: Files.dailyContentPendingDeliveries)
    }

    private func loadDailyContentCommittedSnapshots()
        throws -> [String: DailyContentCommittedSnapshot] {
        try load(
            [String: DailyContentCommittedSnapshot].self,
            from: Files.dailyContentCommittedStates
        ) ?? [:]
    }

    private func loadDailyContentPendingDeliveries()
        throws -> [String: DailyContentPendingDelivery] {
        try load(
            [String: DailyContentPendingDelivery].self,
            from: Files.dailyContentPendingDeliveries
        ) ?? [:]
    }

    func saveTaskOperationLedger(_ entries: [TaskOperationLedgerEntry]) throws {
        try save(entries, to: Files.taskOperationLedger)
    }

    func loadTaskOperationLedger() throws -> [TaskOperationLedgerEntry]? {
        try load([TaskOperationLedgerEntry].self, from: Files.taskOperationLedger)
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

    /// Atomically records the cumulative target before updating UserDefaults. If the process dies
    /// between those writes, the same receipt restores the target; if it dies afterwards, replay
    /// observes the receipt and never increments twice.
    func applyFocusEnergyReward(receiptID: UUID, bottles: Int) throws -> Int {
        var targets = try load([String: Int].self, from: Files.focusEnergyAwardReceipts) ?? [:]
        let durableMaximum = targets.values.max() ?? 0
        let currentTotal = max(userDefaults.integer(forKey: Keys.energyBottles), durableMaximum)
        let key = receiptID.uuidString

        if let existingTarget = targets[key] {
            let repairedTotal = max(currentTotal, existingTarget)
            userDefaults.set(repairedTotal, forKey: Keys.energyBottles)
            return repairedTotal
        }

        let increment = max(0, bottles)
        let (sum, overflow) = currentTotal.addingReportingOverflow(increment)
        let target = overflow ? Int.max : sum
        targets[key] = target
        try save(targets, to: Files.focusEnergyAwardReceipts)
        userDefaults.set(target, forKey: Keys.energyBottles)
        return target
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

    public func saveLastDayPackSemanticHash(_ hash: String) {
        userDefaults.set(hash, forKey: Keys.lastDayPackSemanticHash)
    }

    public func loadLastDayPackSemanticHash() -> String? {
        userDefaults.string(forKey: Keys.lastDayPackSemanticHash)
    }

    /// Atomically advances the durable version used by `0x1B TaskListSnapshotAck`.
    /// This legacy entry point shares the same atomically-replaced delivery-state document used
    /// by the responder, so tests and older call sites cannot expose a mixed epoch/revision pair.
    public func nextTaskListSnapshotVersion() throws -> TaskListSnapshotVersion {
        var state: TaskListSnapshotDeliveryState
        do {
            state = try loadTaskListSnapshotDeliveryState()
        } catch {
            try quarantineCorruptFile(named: Files.taskListSnapshotVersion)
            state = .empty
        }
        let next = nextTaskListSnapshotVersion(
            after: state.legacyVersion,
            avoiding: taskListSnapshotEpochs(in: state)
        )
        state.legacyVersion = next
        try save(state, to: Files.taskListSnapshotVersion)
        return next
    }

    func saveTaskListSnapshotVersion(_ version: TaskListSnapshotVersion) throws {
        var state = try loadTaskListSnapshotDeliveryState()
        state.legacyVersion = version
        try save(state, to: Files.taskListSnapshotVersion)
    }

    func loadTaskListSnapshotVersion() throws -> TaskListSnapshotVersion? {
        try loadTaskListSnapshotDeliveryState().legacyVersion
    }

    // MARK: - Per-destination snapshot version management (v2.12.0 inventory reconciliation)

    /// Load the last frozen version for a specific destination.
    /// Returns nil if the destination has no record — caller should treat this as the device
    /// being in a clean state (no baseline to compare against).
    func loadTaskListSnapshotVersion(for destinationID: String) async throws -> TaskListSnapshotVersion? {
        let state = try loadTaskListSnapshotDeliveryState()
        return state.destinations.first(where: { $0.destinationID == destinationID })?.lastFrozenVersion
    }

    /// Update the last frozen version baseline for a specific destination.
    /// Called when the device reports a committed version via 0x30 inventory that differs from
    /// App's record — App adopts device's version as the new baseline.
    func saveTaskListSnapshotVersion(
        _ version: TaskListSnapshotVersion,
        for destinationID: String
    ) async throws {
        var state: TaskListSnapshotDeliveryState
        do {
            state = try loadTaskListSnapshotDeliveryState()
        } catch {
            try quarantineCorruptFile(named: Files.taskListSnapshotVersion)
            state = .empty
        }
        if let idx = state.destinations.firstIndex(where: { $0.destinationID == destinationID }) {
            state.destinations[idx].lastFrozenVersion = version
        } else {
            state.destinations.append(TaskListSnapshotDestinationState(
                destinationID: destinationID,
                lastFrozenVersion: version,
                reservation: nil,
                frozenResponses: []
            ))
        }
        try save(state, to: Files.taskListSnapshotVersion)
    }

    /// Remove the delivery state for a destination so the next 0x1B starts with a fresh epoch.
    /// Called when device reports `.missing` via 0x30 inventory (power cycle / restart wiped RAM).
    func clearTaskListSnapshotDeliveryState(for destinationID: String) async throws {
        var state: TaskListSnapshotDeliveryState
        do {
            state = try loadTaskListSnapshotDeliveryState()
        } catch {
            // Already corrupt; quarantine and start fresh — desired end state is empty anyway.
            try quarantineCorruptFile(named: Files.taskListSnapshotVersion)
            return
        }
        state.destinations.removeAll { $0.destinationID == destinationID }
        try save(state, to: Files.taskListSnapshotVersion)
    }

    func hasAttemptedTaskListSnapshotDelivery(
        for destinationID: String
    ) async throws -> Bool {
        let state = try loadTaskListSnapshotDeliveryState()
        guard let destination = state.destinations.first(where: {
            $0.destinationID == destinationID
        }) else { return false }
        return destination.frozenResponses.contains { $0.phase == .attempted }
    }

    func prepareTaskListSnapshotDelivery(
        for key: TaskListSnapshotRequestKey
    ) throws -> TaskListSnapshotDeliveryPreparation {
        var state: TaskListSnapshotDeliveryState
        do {
            state = try loadTaskListSnapshotDeliveryState()
        } catch {
            try quarantineCorruptFile(named: Files.taskListSnapshotVersion)
            state = .empty
        }

        guard let destinationIndex = state.destinations.firstIndex(where: {
            $0.destinationID == key.destinationID
        }) else {
            let version = nextTaskListSnapshotVersion(
                after: nil,
                avoiding: taskListSnapshotEpochs(in: state)
            )
            state.destinations.append(TaskListSnapshotDestinationState(
                destinationID: key.destinationID,
                lastFrozenVersion: nil,
                reservation: TaskListSnapshotDeliveryReservation(
                    key: key,
                    version: version
                ),
                frozenResponses: []
            ))
            try save(state, to: Files.taskListSnapshotVersion)
            return .reserved(version)
        }

        var destination = state.destinations[destinationIndex]
        if let immutable = destination.frozenResponses.first(where: {
            $0.response.key == key && $0.phase != .prepared
        }) {
            return .frozen(immutable.response)
        }
        // OperationID is not a globally monotonic firmware sequence. Even a numerically larger
        // different key cannot prove that an uncertain write was applied; offline batches may
        // legitimately contain several pending operations.
        guard !destination.frozenResponses.contains(where: {
            $0.phase == .attempted
        }) else {
            throw TaskListSnapshotDeliveryStorageError.activeDeliveryConflict
        }
        let removedDeliveredResponse = destination.frozenResponses.contains {
            $0.phase == .delivered
        }
        destination.frozenResponses.removeAll { $0.phase == .delivered }
        if let preparedIndex = destination.frozenResponses.firstIndex(where: {
            $0.phase == .prepared
        }) {
            let prepared = destination.frozenResponses.remove(at: preparedIndex)
            destination.reservation = TaskListSnapshotDeliveryReservation(
                key: key,
                version: prepared.response.version
            )
            state.destinations[destinationIndex] = destination
            try save(state, to: Files.taskListSnapshotVersion)
            return .reserved(prepared.response.version)
        }
        if let reservation = destination.reservation {
            if reservation.key != key {
                destination.reservation = TaskListSnapshotDeliveryReservation(
                    key: key,
                    version: reservation.version
                )
            }
            if reservation.key != key || removedDeliveredResponse {
                state.destinations[destinationIndex] = destination
                try save(state, to: Files.taskListSnapshotVersion)
            }
            return .reserved(reservation.version)
        }
        let version = nextTaskListSnapshotVersion(
            after: destination.lastFrozenVersion,
            avoiding: taskListSnapshotEpochs(in: state)
        )
        destination.reservation = TaskListSnapshotDeliveryReservation(
            key: key,
            version: version
        )
        state.destinations[destinationIndex] = destination
        try save(state, to: Files.taskListSnapshotVersion)
        return .reserved(version)
    }

    func freezeTaskListSnapshotDelivery(
        _ response: FrozenTaskListSnapshotResponse
    ) throws {
        var state = try loadTaskListSnapshotDeliveryState()
        guard let destinationIndex = state.destinations.firstIndex(where: {
            $0.destinationID == response.key.destinationID
        }) else {
            throw TaskListSnapshotDeliveryStorageError.reservationMismatch
        }
        var destination = state.destinations[destinationIndex]
        guard destination.reservation?.key == response.key,
              destination.reservation?.version == response.version else {
            throw TaskListSnapshotDeliveryStorageError.reservationMismatch
        }
        destination.frozenResponses.removeAll { $0.response.key == response.key }
        destination.frozenResponses.append(StoredTaskListSnapshotResponse(
            response: response,
            phase: .prepared
        ))
        destination.lastFrozenVersion = response.version
        destination.reservation = nil
        state.destinations[destinationIndex] = destination
        try save(state, to: Files.taskListSnapshotVersion)
    }

    func markTaskListSnapshotDeliveryAttempted(
        _ response: FrozenTaskListSnapshotResponse
    ) throws {
        var state = try loadTaskListSnapshotDeliveryState()
        guard let destinationIndex = state.destinations.firstIndex(where: {
            $0.destinationID == response.key.destinationID
        }) else {
            throw TaskListSnapshotDeliveryStorageError.responseMismatch
        }
        var destination = state.destinations[destinationIndex]
        guard let responseIndex = destination.frozenResponses.firstIndex(where: {
            $0.response == response
        }) else {
            throw TaskListSnapshotDeliveryStorageError.responseMismatch
        }
        switch destination.frozenResponses[responseIndex].phase {
        case .prepared:
            destination.frozenResponses[responseIndex].phase = .attempted
            state.destinations[destinationIndex] = destination
            try save(state, to: Files.taskListSnapshotVersion)
        case .attempted:
            return
        case .delivered:
            throw TaskListSnapshotDeliveryStorageError.responseMismatch
        }
    }

    func rewindUnwrittenTaskListSnapshotDelivery(
        _ response: FrozenTaskListSnapshotResponse
    ) throws {
        var state = try loadTaskListSnapshotDeliveryState()
        guard let destinationIndex = state.destinations.firstIndex(where: {
            $0.destinationID == response.key.destinationID
        }) else {
            throw TaskListSnapshotDeliveryStorageError.responseMismatch
        }
        var destination = state.destinations[destinationIndex]
        if destination.reservation?.key == response.key,
           destination.reservation?.version == response.version {
            return
        }
        guard destination.frozenResponses.contains(where: {
            $0.response == response && $0.phase != .delivered
        }) else {
            throw TaskListSnapshotDeliveryStorageError.responseMismatch
        }
        destination.frozenResponses.removeAll { $0.response == response }
        destination.reservation = TaskListSnapshotDeliveryReservation(
            key: response.key,
            version: response.version
        )
        state.destinations[destinationIndex] = destination
        try save(state, to: Files.taskListSnapshotVersion)
    }

    func markTaskListSnapshotDeliveryDelivered(
        _ response: FrozenTaskListSnapshotResponse
    ) async throws {
        var state = try loadTaskListSnapshotDeliveryState()
        guard let destinationIndex = state.destinations.firstIndex(where: {
            $0.destinationID == response.key.destinationID
        }) else {
            throw TaskListSnapshotDeliveryStorageError.responseMismatch
        }
        var destination = state.destinations[destinationIndex]
        guard let responseIndex = destination.frozenResponses.firstIndex(where: {
            $0.response == response
        }) else {
            throw TaskListSnapshotDeliveryStorageError.responseMismatch
        }
        switch destination.frozenResponses[responseIndex].phase {
        case .attempted:
            destination.frozenResponses[responseIndex].phase = .delivered
            state.destinations[destinationIndex] = destination
            try save(state, to: Files.taskListSnapshotVersion)
        case .delivered:
            return
        case .prepared:
            throw TaskListSnapshotDeliveryStorageError.responseMismatch
        }
    }

    func completeTaskListSnapshotDelivery(
        _ response: FrozenTaskListSnapshotResponse
    ) throws {
        var state = try loadTaskListSnapshotDeliveryState()
        guard let destinationIndex = state.destinations.firstIndex(where: {
            $0.destinationID == response.key.destinationID
        }) else { return }
        var destination = state.destinations[destinationIndex]
        guard let responseIndex = destination.frozenResponses.firstIndex(where: {
            $0.response == response
        }) else { return }
        guard destination.frozenResponses[responseIndex].phase == .delivered else {
            throw TaskListSnapshotDeliveryStorageError.responseMismatch
        }
        destination.frozenResponses.remove(at: responseIndex)
        state.destinations[destinationIndex] = destination
        try save(state, to: Files.taskListSnapshotVersion)
    }

    private func loadTaskListSnapshotDeliveryState() throws -> TaskListSnapshotDeliveryState {
        do {
            return try load(
                TaskListSnapshotDeliveryState.self,
                from: Files.taskListSnapshotVersion
            ) ?? .empty
        } catch {
            if let legacy = try? load(
                TaskListSnapshotVersion.self,
                from: Files.taskListSnapshotVersion
            ) {
                return TaskListSnapshotDeliveryState(
                    legacyVersion: legacy,
                    destinations: []
                )
            }
            throw error
        }
    }

    private func nextTaskListSnapshotVersion(
        after current: TaskListSnapshotVersion?,
        avoiding usedEpochs: Set<UInt32>
    ) -> TaskListSnapshotVersion {
        if let current, current.revision < UInt32.max {
            return TaskListSnapshotVersion(
                epoch: current.epoch,
                revision: current.revision + 1
            )
        }
        var newEpoch = UInt32.random(in: 1...UInt32.max)
        while usedEpochs.contains(newEpoch) {
            newEpoch = newEpoch == UInt32.max ? 1 : newEpoch + 1
        }
        return TaskListSnapshotVersion(epoch: newEpoch, revision: 1)
    }

    private func taskListSnapshotEpochs(
        in state: TaskListSnapshotDeliveryState
    ) -> Set<UInt32> {
        var epochs = Set(state.legacyVersion.map { [$0.epoch] } ?? [])
        for destination in state.destinations {
            if let version = destination.lastFrozenVersion {
                epochs.insert(version.epoch)
            }
            if let reservation = destination.reservation {
                epochs.insert(reservation.version.epoch)
            }
            for stored in destination.frozenResponses {
                epochs.insert(stored.response.version.epoch)
            }
        }
        return epochs
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

    /// Account cleanup must remove both the live index and a quarantined decode failure because
    /// either can contain names, prompts, backstory, and sensitive-boundary text.
    public func deleteCustomCompanionIndex() throws {
        try deleteFile(named: Files.customCompanions)
        try deleteFile(named: Files.customCompanions + ".corrupt")
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

    /// Sign-out cleanup cannot trust `custom_companions.json` to enumerate every private image:
    /// a missing or quarantined index may leave orphan files. Sweep only direct Documents
    /// children with the fixed companion prefix; pending candidate files use another prefix.
    public func deleteAllCustomCompanionAssets() throws {
        try Self.deleteAllCustomCompanionAssets(
            fileManager: fileManager,
            documentsDirectory: documentsDirectory
        )
    }

    nonisolated static func deleteAllCustomCompanionAssets(
        fileManager: FileManager,
        documentsDirectory: URL
    ) throws {
        let names = try fileManager.contentsOfDirectory(atPath: documentsDirectory.path)
        for name in names where name.hasPrefix(Files.customCompanionAssetPrefix) {
            try fileManager.removeItem(at: documentsDirectory.appendingPathComponent(name))
        }
    }

    // MARK: - Pending Custom Avatar Operation

    public nonisolated static var pendingCustomAvatarPreviewFileName: String {
        Files.pendingCustomAvatarPreview
    }

    public nonisolated static var pendingCustomAvatarImageFileName: String {
        Files.pendingCustomAvatarImage
    }

    public func savePendingCustomAvatarOperation(
        _ operation: PendingCustomAvatarOperation
    ) throws {
        try save(operation, to: Files.pendingCustomAvatarOperation)
    }

    public func loadPendingCustomAvatarOperation() throws -> PendingCustomAvatarOperation? {
        try load(PendingCustomAvatarOperation.self, from: Files.pendingCustomAvatarOperation)
    }

    public func savePendingCustomAvatarAssets(
        previewData: Data,
        imageData: Data
    ) throws {
        let previewURL = documentsDirectory.appendingPathComponent(Files.pendingCustomAvatarPreview)
        let imageURL = documentsDirectory.appendingPathComponent(Files.pendingCustomAvatarImage)
        try previewData.write(to: previewURL, options: [.atomic])
        try imageData.write(to: imageURL, options: [.atomic])
    }

    public func loadPendingCustomAvatarPreviewData() -> Data? {
        try? Data(contentsOf: documentsDirectory.appendingPathComponent(Files.pendingCustomAvatarPreview))
    }

    public func loadPendingCustomAvatarImageData() -> Data? {
        try? Data(contentsOf: documentsDirectory.appendingPathComponent(Files.pendingCustomAvatarImage))
    }

    /// Promotes the staged source PNG files only after firmware confirms `committed`.
    public func commitPendingCustomAvatarAssets(to id: UUID) throws {
        guard let previewData = loadPendingCustomAvatarPreviewData(),
              let imageData = loadPendingCustomAvatarImageData() else {
            throw CustomAvatarOperationError.missingAvatarData
        }
        try saveCustomCompanionAssets(id: id, previewData: previewData, imageData: imageData)
    }

    /// Removes the JSON transaction and its candidate files. Offline erase operations contain
    /// only the JSON marker, so calling this is idempotent for every operation kind.
    public func clearPendingCustomAvatarOperation() throws {
        // Delete sensitive candidate bytes first and the durable operation marker last. If a
        // filesystem error interrupts cleanup, launch recovery still has a record to inspect;
        // deleting JSON first could leave untracked personal photos behind permanently.
        try deleteFile(named: Files.pendingCustomAvatarPreview)
        try deleteFile(named: Files.pendingCustomAvatarImage)
        try deleteFile(named: Files.pendingCustomAvatarOperation)
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

extension LocalStorage:
    TaskListSnapshotDeliveryStoring,
    TaskListSnapshotVersionProviding {}

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
