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
    @Test("Legacy streak data keeps the saved streak on first use after migration")
    @MainActor
    func legacyStreakMigrationPreservesSavedStreak() async throws {
        let storage = LocalStorage.shared
        let state = AppState.makeForTesting()
        let now = Date(timeIntervalSince1970: 1_710_000_000)

        let originalDays = await storage.loadConsecutiveDays()
        let originalLastUsageDate = await storage.loadLastUsageDate()
        let originalUsageState = try await storage.loadCompanionUsageState()

        await storage.saveConsecutiveDays(5)
        await storage.saveLastUsageDate(nil)

        await state.registerUsageActivity(now: now)

        #expect(await storage.loadConsecutiveDays() == 5)
        #expect(await storage.loadLastUsageDate() == now)

        await storage.saveConsecutiveDays(originalDays)
        await storage.saveLastUsageDate(originalLastUsageDate)
        if let originalUsageState {
            try await storage.saveCompanionUsageState(originalUsageState)
        } else {
            try await storage.deleteFile(named: "companion_usage_state.json")
        }
    }

    @Test("Backward-compatible UserProfile decode derives missing companion fields")
    func userProfileBackwardCompatibleDecode() throws {
        let json = """
        {
          "workType": "Other",
          "primaryGoals": [],
          "companionStyle": "Slacker"
        }
        """
        let data = Data(json.utf8)
        let profile = try JSONDecoder().decode(UserProfile.self, from: data)

        #expect(profile.companionStyle == .slacker)
        #expect(profile.companionCharacter == .silas)
        #expect(profile.intimacyStage == .acquaintance)
    }

    @Test("Onboarding profile maps product styles to IPs and resets stage on IP switch")
    func onboardingProfileMapsToProductIPs() {
        let existing = UserProfile(
            companionStyle: .challenger,
            companionCharacter: .nova,
            intimacyStage: .closeFriend
        )
        let onboarding = OnboardingProfile(companionStyle: .slacker)

        let mapped = UserProfile.from(onboarding: onboarding, merging: existing)

        #expect(mapped.companionStyle == .slacker)
        #expect(mapped.companionCharacter == .silas)
        #expect(mapped.intimacyStage == .acquaintance)
    }

    @Test("Binding day thresholds map to intimacy stages")
    func intimacyStageThresholds() {
        #expect(IntimacyStage.from(bindingDays: 1) == .acquaintance)
        #expect(IntimacyStage.from(bindingDays: 6) == .familiar)
        #expect(IntimacyStage.from(bindingDays: 16) == .closeFriend)
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
        let appState = AppState.shared
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
            focusService: focusService
        )
        #expect(focusService.activeSession?.startTime == startTime)

        let completeLog = EventLog(eventType: .completeTask, taskId: taskId, timestamp: endTime)
        await BLEEventHandler.handleEventLogs(
            [completeLog],
            service: BLEService.shared,
            focusService: focusService
        )
        await focusService.waitForPendingPersistenceForTesting()

        let replayedSession = focusService.todaySessions.last { $0.taskId == taskId }
        #expect(replayedSession?.earnedEnergyBottles == 2)

        appState.tasks = originalTasks
    }
}
