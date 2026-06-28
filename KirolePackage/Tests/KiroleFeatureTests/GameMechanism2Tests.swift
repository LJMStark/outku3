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

    @Test("Energy bottles credit per uninterrupted segment; remainders never combine across an interruption")
    func interruptionResetsInProgressBottleFill() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        func unlock(at minutes: Double) -> ScreenUnlockEvent {
            ScreenUnlockEvent(timestamp: start.addingTimeInterval(minutes * 60), duration: 0)
        }

        // No interruption: floor(75 / 30) = 2.
        #expect(FocusTimeCalculator.countableBottles(
            sessionStart: start,
            sessionEnd: start.addingTimeInterval(75 * 60),
            screenUnlockEvents: []
        ) == 2)

        // 45 | interrupt | 45: each segment floors to 1 bottle; the two 15-min remainders are
        // discarded and must NOT combine into a third bottle. (Pooled-then-floor gave 3 = the bug.)
        #expect(FocusTimeCalculator.countableBottles(
            sessionStart: start,
            sessionEnd: start.addingTimeInterval(90 * 60),
            screenUnlockEvents: [unlock(at: 45)]
        ) == 2)

        // 50 | interrupt | 50: 1 + 1 = 2 (pooled floor(100 / 30) would be 3).
        #expect(FocusTimeCalculator.countableBottles(
            sessionStart: start,
            sessionEnd: start.addingTimeInterval(100 * 60),
            screenUnlockEvents: [unlock(at: 50)]
        ) == 2)

        // Each segment below the 30-min threshold yields nothing.
        #expect(FocusTimeCalculator.countableBottles(
            sessionStart: start,
            sessionEnd: start.addingTimeInterval(50 * 60),
            screenUnlockEvents: [unlock(at: 25)]
        ) == 0)
    }

    @Test("An open (nil-duration) interruption credits no bottles for the foregrounded tail")
    func openInterruptionDoesNotCreditForegroundedTail() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        // Focus 25 min, pick up the phone at 25 min and stay foregrounded until the session ends
        // at 61 min. duration == nil means the interruption never closed, so 26-61 is the user on
        // their phone, not focus — it must credit 0 bottles, not the 1 the old `?? 60` default gave.
        let openUnlock = ScreenUnlockEvent(timestamp: start.addingTimeInterval(25 * 60), duration: nil)
        let end = start.addingTimeInterval(61 * 60)
        #expect(FocusTimeCalculator.countableBottles(
            sessionStart: start,
            sessionEnd: end,
            screenUnlockEvents: [openUnlock]
        ) == 0)

        // Live: while still foregrounded, the current segment is empty (the fill sits at 0).
        let segmentStart = FocusTimeCalculator.currentSegmentStart(
            sessionStart: start,
            now: end,
            screenUnlockEvents: [openUnlock]
        )
        #expect(Int(end.timeIntervalSince(segmentStart) / 60) == 0)
    }

    @Test("Overlapping interruptions never rewind the segment boundary")
    func overlappingInterruptionsDoNotRewindSegmentBoundary() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        // a interrupts 20→50 (30 min); b 25→26 (1 min) nests inside a. b must not rewind the
        // boundary from 50 back to 26 and re-count the 26-50 interrupted span as focus.
        let a = ScreenUnlockEvent(timestamp: start.addingTimeInterval(20 * 60), duration: 30 * 60)
        let b = ScreenUnlockEvent(timestamp: start.addingTimeInterval(25 * 60), duration: 1 * 60)
        // Session ends at 90 min → real focus is only the 50→90 stretch = 40 min = 1 bottle, not 2.
        #expect(FocusTimeCalculator.countableBottles(
            sessionStart: start,
            sessionEnd: start.addingTimeInterval(90 * 60),
            screenUnlockEvents: [a, b]
        ) == 1)
    }

    @Test("Live focus display is segment-aware: fill resets after an interruption and never over-reports vs settlement")
    func liveFocusDisplayIsSegmentAware() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        // 25 min focus, interrupt, then 25 more. Wall-clock elapsed = 50 min.
        let unlock = ScreenUnlockEvent(timestamp: start.addingTimeInterval(25 * 60), duration: 0)
        let now = start.addingTimeInterval(50 * 60)

        // The live fill is measured from the current uninterrupted segment (25 min in), not the
        // 50-minute wall-clock total — so it resets after the interruption.
        let segmentStart = FocusTimeCalculator.currentSegmentStart(
            sessionStart: start,
            now: now,
            screenUnlockEvents: [unlock]
        )
        #expect(Int(now.timeIntervalSince(segmentStart) / 60) == 25)

        // Banked bottles == 0 (both 25-min segments are below 30), matching what endSession would
        // settle. The old wall-clock display reported floor(50/30)=1, contradicting that 0.
        #expect(FocusTimeCalculator.countableBottles(
            sessionStart: start,
            sessionEnd: now,
            screenUnlockEvents: [unlock]
        ) == 0)
    }

    @Test("Next-bottle countdown wakes the live display on the 30-minute boundary")
    func secondsUntilNextBottleCountsDownWithinSegment() {
        let segmentStart = Date(timeIntervalSince1970: 1_700_000_000)
        let block: TimeInterval = 30 * 60

        // 10 min into the segment → next bottle completes in 20 min.
        #expect(FocusTimeCalculator.secondsUntilNextBottle(
            segmentStart: segmentStart,
            now: segmentStart.addingTimeInterval(10 * 60),
            blockSeconds: block
        ) == 20 * 60)

        // Exactly on a boundary (30 min) → a full block until the next bottle.
        #expect(FocusTimeCalculator.secondsUntilNextBottle(
            segmentStart: segmentStart,
            now: segmentStart.addingTimeInterval(30 * 60),
            blockSeconds: block
        ) == 30 * 60)

        // 50 min in (1 bottle banked, 20 min into the second) → next bottle in 10 min.
        #expect(FocusTimeCalculator.secondsUntilNextBottle(
            segmentStart: segmentStart,
            now: segmentStart.addingTimeInterval(50 * 60),
            blockSeconds: block
        ) == 10 * 60)
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
