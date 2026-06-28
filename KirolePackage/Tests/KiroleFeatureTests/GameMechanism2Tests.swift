import Foundation
import Testing
@testable import KiroleFeature

@MainActor
private final class GameMechanismMockFocusGuardService: FocusGuardService {
    var authorizationStatus: FocusAuthorizationStatus = .approved
    var isDeepFocusFeatureEnabled: Bool = true
    var isDeepFocusCapable: Bool = true
    var canShowDeepFocusEntry: Bool { true }
    var selectedApplicationCount: Int = 1
    var isPickerPresented: Bool = false

    func refreshAuthorizationStatus() async {}
    func requestAuthorization() async -> FocusAuthorizationStatus { authorizationStatus }
    func presentAppPicker() {}
    func applyShield(selection: FocusAppSelection) throws {}
    func clearShield() {}
    func currentSelection() -> FocusAppSelection? {
        FocusAppSelection(tokenData: Data([0x01]), selectedApplicationCount: 1)
    }
}

@Suite("Game Mechanism 2 Tests", .serialized)
struct GameMechanism2Tests {
    @Test("UserProfile decode defaults to joy when no companion fields present")
    func userProfileDecodeMissingCharacterDefaultsToJoy() throws {
        let json = """
        {
          "workType": "Other",
          "primaryGoals": []
        }
        """
        let data = Data(json.utf8)
        let profile = try JSONDecoder().decode(UserProfile.self, from: data)

        #expect(profile.companionCharacter == .joy)
        #expect(profile.companionStyle == .joy)
        #expect(profile.intimacyStage == .acquaintance)
    }

    @Test("Rapid development storage reset clears persisted local state on schema change")
    func rapidDevelopmentStorageResetClearsPersistedData() throws {
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaultsSuite = "LocalStorageReset-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: defaultsSuite))
        defer {
            try? fileManager.removeItem(at: documentsDirectory)
            userDefaults.removePersistentDomain(forName: defaultsSuite)
        }

        try fileManager.createDirectory(at: documentsDirectory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: documentsDirectory.appendingPathComponent("user_profile.json"))
        userDefaults.set(7, forKey: "energyBottles")
        userDefaults.set(0, forKey: LocalStorage.developmentStorageSchemaVersionKey)

        let didReset = try LocalStorage.resetForRapidDevelopmentIfNeeded(
            currentSchemaVersion: LocalStorage.currentDevelopmentStorageSchemaVersion,
            userDefaults: userDefaults,
            fileManager: fileManager,
            documentsDirectory: documentsDirectory
        )

        #expect(didReset)
        #expect(!fileManager.fileExists(atPath: documentsDirectory.appendingPathComponent("user_profile.json").path))
        #expect(userDefaults.object(forKey: "energyBottles") == nil)
        #expect(
            userDefaults.integer(forKey: LocalStorage.developmentStorageSchemaVersionKey)
                == LocalStorage.currentDevelopmentStorageSchemaVersion
        )
    }

    @Test("Rapid development storage reset keeps data when schema version matches")
    func rapidDevelopmentStorageResetSkipsMatchingSchema() throws {
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaultsSuite = "LocalStorageReset-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: defaultsSuite))
        defer {
            try? fileManager.removeItem(at: documentsDirectory)
            userDefaults.removePersistentDomain(forName: defaultsSuite)
        }

        try fileManager.createDirectory(at: documentsDirectory, withIntermediateDirectories: true)
        let profileURL = documentsDirectory.appendingPathComponent("user_profile.json")
        try Data("{}".utf8).write(to: profileURL)
        userDefaults.set(
            LocalStorage.currentDevelopmentStorageSchemaVersion,
            forKey: LocalStorage.developmentStorageSchemaVersionKey
        )

        let didReset = try LocalStorage.resetForRapidDevelopmentIfNeeded(
            currentSchemaVersion: LocalStorage.currentDevelopmentStorageSchemaVersion,
            userDefaults: userDefaults,
            fileManager: fileManager,
            documentsDirectory: documentsDirectory
        )

        #expect(!didReset)
        #expect(fileManager.fileExists(atPath: profileURL.path))
    }

    @Test("Rapid development storage reset clears core persisted files")
    func rapidDevelopmentStorageResetClearsCoreFiles() throws {
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaultsSuite = "LocalStorageReset-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: defaultsSuite))
        let fileNames = [
            "tasks.json",
            "events.json",
            "ai_interactions.json",
            "focus_session_active.json",
            "shared_companion_dialogue.json",
            "avatar.dat",
            "avatar_pixels.dat",
        ]
        defer {
            try? fileManager.removeItem(at: documentsDirectory)
            userDefaults.removePersistentDomain(forName: defaultsSuite)
        }

        try fileManager.createDirectory(at: documentsDirectory, withIntermediateDirectories: true)
        for fileName in fileNames {
            try Data("fixture".utf8).write(to: documentsDirectory.appendingPathComponent(fileName))
        }

        let didReset = try LocalStorage.resetForRapidDevelopmentIfNeeded(
            currentSchemaVersion: LocalStorage.currentDevelopmentStorageSchemaVersion,
            userDefaults: userDefaults,
            fileManager: fileManager,
            documentsDirectory: documentsDirectory
        )

        #expect(didReset)
        for fileName in fileNames {
            #expect(!fileManager.fileExists(atPath: documentsDirectory.appendingPathComponent(fileName).path))
        }
    }

    @Test("Onboarding profile maps character selection and resets stage on IP switch")
    func onboardingProfileMapsToProductIPs() {
        let existing = UserProfile(
            companionCharacter: .nova,
            intimacyStage: .closeFriend
        )
        let onboarding = OnboardingProfile(companionCharacter: .silas)

        let mapped = UserProfile.from(onboarding: onboarding, merging: existing)

        #expect(mapped.companionCharacter == .silas)
        #expect(mapped.companionStyle == .silas)
        #expect(mapped.intimacyStage == .acquaintance)
    }

    @Test("Binding day thresholds map to intimacy stages")
    func intimacyStageThresholds() {
        #expect(IntimacyStage.from(bindingDays: 4) == .acquaintance)
        #expect(IntimacyStage.from(bindingDays: 5) == .familiar)
        #expect(IntimacyStage.from(bindingDays: 14) == .familiar)
        #expect(IntimacyStage.from(bindingDays: 15) == .closeFriend)
    }

    @Test("Consecutive usage progress increments once per day and resets after gaps")
    func consecutiveUsageProgress() {
        var progress = ConsecutiveUsageProgress()
        let calendar = Calendar(identifier: .gregorian)
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let day2 = calendar.date(byAdding: .day, value: 1, to: day1)!
        let day4 = calendar.date(byAdding: .day, value: 3, to: day1)!

        let firstUse = progress.registerUse(on: day1)
        #expect(firstUse)
        #expect(progress.currentStreak == 1)
        let secondSameDayUse = progress.registerUse(on: day1)
        #expect(!secondSameDayUse)
        #expect(progress.currentStreak == 1)
        let nextDayUse = progress.registerUse(on: day2)
        #expect(nextDayUse)
        #expect(progress.currentStreak == 2)
        let postGapUse = progress.registerUse(on: day4)
        #expect(postGapUse)
        #expect(progress.currentStreak == 1)
    }

    @Test("Companion binding progress counts unique usage days per IP")
    func companionBindingProgress() {
        var progress = CompanionBindingProgress()
        let calendar = Calendar(identifier: .gregorian)
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let day2 = calendar.date(byAdding: .day, value: 1, to: day1)!

        let firstUse = progress.registerUse(on: day1)
        #expect(firstUse)
        #expect(progress.totalUsedDays == 1)
        let secondSameDayUse = progress.registerUse(on: day1)
        #expect(!secondSameDayUse)
        #expect(progress.totalUsedDays == 1)
        let nextDayUse = progress.registerUse(on: day2)
        #expect(nextDayUse)
        #expect(progress.totalUsedDays == 2)
    }

    @Test("Energy bottles unlock harbor, forest, and night city scenes in order")
    @MainActor
    func displayScenesUnlockByEnergyBottles() {
        let service = SceneUnlockService.shared

        #expect(service.fetchAvailableScenes(energyBottles: 0).map(\.sceneId) == ["harbor"])
        #expect(service.fetchAvailableScenes(energyBottles: 79).map(\.sceneId) == ["harbor"])
        #expect(service.fetchAvailableScenes(energyBottles: 80).map(\.sceneId) == ["harbor", "forest"])
        #expect(service.fetchAvailableScenes(energyBottles: 160).map(\.sceneId) == ["harbor", "forest", "nightCity"])
        #expect(service.currentSceneId(energyBottles: 160) == "nightCity")
    }

    @Test("Screensaver postcard days only trigger on 3 7 21 day milestones")
    @MainActor
    func postcardDayRules() {
        #expect(ScreensaverService.isPostcardDay(usageDays: 0) == false)
        #expect(ScreensaverService.isPostcardDay(usageDays: 3) == true)
        #expect(ScreensaverService.isPostcardDay(usageDays: 7) == true)
        #expect(ScreensaverService.isPostcardDay(usageDays: 21) == true)
        #expect(ScreensaverService.isPostcardDay(usageDays: 30) == false)
    }

    @Test("Ending a 60 minute focus session records two earned energy bottles")
    @MainActor
    func focusSessionAccumulatesEnergyBottles() async {
        let focusGuardService = GameMechanismMockFocusGuardService()
        let service = FocusSessionService.makeForTesting(
            focusGuardService: focusGuardService,
            persistenceEnabled: false
        )
        let startTime = Date().addingTimeInterval(-3600)

        await service.startSession(
            taskId: "energy-focus-task",
            taskTitle: "Energy Focus Task",
            startTime: startTime
        )
        service.endSession(reason: .completed, endTime: Date())

        #expect(service.todaySessions.last?.earnedEnergyBottles == 2)
    }

    @Test("Screen unlock breaks countable focus segments below 30 minute threshold")
    func screenUnlockBreaksCountableFocusSegments() {
        let startTime = Date(timeIntervalSince1970: 1_700_000_000)
        let unlockTime = startTime.addingTimeInterval(25 * 60)
        let endTime = startTime.addingTimeInterval(50 * 60)

        let focusTime = FocusTimeCalculator.countableFocusTime(
            sessionStart: startTime,
            sessionEnd: endTime,
            screenUnlockEvents: [ScreenUnlockEvent(timestamp: unlockTime, duration: 0)],
            thresholdSeconds: 30 * 60
        )

        #expect(focusTime == 0)
        #expect(FocusEnergyCalculator.bottlesEarned(minutes: Int(focusTime / 60)) == 0)
    }

    @Test("Recovered focus session also computes earned energy bottles")
    @MainActor
    func recoveredFocusSessionAccumulatesEnergyBottles() {
        let focusGuardService = GameMechanismMockFocusGuardService()
        let service = FocusSessionService.makeForTesting(
            focusGuardService: focusGuardService,
            persistenceEnabled: false
        )
        let endTime = Date()
        let active = FocusSession(
            taskId: "recovered-energy-focus-task",
            taskTitle: "Recovered Energy Focus Task",
            startTime: endTime.addingTimeInterval(-3600)
        )

        service.recoverPersistedSessionForTesting(active, wasShieldActive: false, endTime: endTime)

        #expect(service.todaySessions.last?.earnedEnergyBottles == 2)
    }

    @Test("BLE event replay uses event timestamps for focus session timing")
    @MainActor
    func bleEventReplayUsesEventTimestamps() async {
        let appState = AppState.makeForTesting()
        let focusGuardService = GameMechanismMockFocusGuardService()
        let focusService = FocusSessionService.makeForTesting(
            focusGuardService: focusGuardService,
            persistenceEnabled: false
        )
        let taskId = "ble-replay-task-\(UUID().uuidString)"
        let originalTasks = appState.tasks
        let startTime = Date(timeIntervalSince1970: 1_700_000_000)
        let endTime = startTime.addingTimeInterval(3600)

        appState.tasks = [TaskItem(id: taskId, title: "Replay Task")]

        let startLog = EventLog(eventType: .enterTaskIn, taskId: taskId, timestamp: startTime)
        await BLEEventHandler.handleEventLogs(
            [startLog],
            service: BLEService.shared,
            focusService: focusService,
            lastTimestampOverride: 0
        )
        #expect(focusService.activeSession?.startTime == startTime)

        let completeLog = EventLog(eventType: .completeTask, taskId: taskId, timestamp: endTime)
        await BLEEventHandler.handleEventLogs(
            [completeLog],
            service: BLEService.shared,
            focusService: focusService,
            lastTimestampOverride: 0
        )
        await focusService.waitForPendingPersistenceForTesting()

        let replayedSession = focusService.todaySessions.last { $0.taskId == taskId }
        #expect(replayedSession?.earnedEnergyBottles == 2)

        appState.tasks = originalTasks
    }

    @Test("Batch-replayed reminder ack resets the SmartReminder cooldown (live + replay parity)")
    @MainActor
    func batchReplayedReminderAckResetsCooldown() async {
        let reminder = SmartReminderService.shared
        // Pick an ack time strictly after any existing cooldown so max-merge advances it —
        // makes the assertion robust to the shared singleton's state from other serialized tests.
        let baseline = reminder.lastReminderTime ?? .distantPast
        let ackTime = max(baseline, Date()).addingTimeInterval(3600)

        let ackLog = EventLog(eventType: .reminderAcknowledged, timestamp: ackTime)
        await BLEEventHandler.handleEventLogs(
            [ackLog],
            service: BLEService.shared,
            isReplay: true,
            lastTimestampOverride: 0
        )

        // Regression guard: before the fix the replay path (isReplay: true) only ran
        // applyEventStateMutation (completeTask only) and never reset the reminder cooldown,
        // so an offline-then-replayed hardware ack could let the next sync immediately re-push.
        #expect(reminder.lastReminderTime == ackTime)
    }
}
