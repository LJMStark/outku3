import Foundation
@testable import KiroleFeature

actor FocusPersistenceFailureStub: FocusSessionPersisting {
    private var storedSessions: [FocusSession]
    private var storedActive: FocusSession?
    private var remainingHistoryFailures: Int
    private var remainingClearFailures: Int
    private var remainingEnergyAwardFailures: Int
    private var remainingActiveSaveFailures: Int
    private let historySaveBarrier: FocusLaunchBarrier?
    private let activeSaveBarrier: FocusLaunchBarrier?
    private var historySaveStarted = false
    private var activeSaveStarted = false
    private var energyAwards: [UUID: Int] = [:]
    private var storedEnergyTotal = 0

    init(
        initialSessions: [FocusSession] = [],
        initialActive: FocusSession? = nil,
        failHistorySaves: Int = 0,
        failClears: Int = 0,
        failEnergyAwards: Int = 0,
        failActiveSaves: Int = 0,
        historySaveBarrier: FocusLaunchBarrier? = nil,
        activeSaveBarrier: FocusLaunchBarrier? = nil
    ) {
        storedSessions = initialSessions
        storedActive = initialActive
        remainingHistoryFailures = failHistorySaves
        remainingClearFailures = failClears
        remainingEnergyAwardFailures = failEnergyAwards
        remainingActiveSaveFailures = failActiveSaves
        self.historySaveBarrier = historySaveBarrier
        self.activeSaveBarrier = activeSaveBarrier
    }

    func loadSessions() async throws -> [FocusSession]? { storedSessions }

    func saveSessions(_ sessions: [FocusSession], date: Date) async throws {
        if let historySaveBarrier {
            historySaveStarted = true
            await historySaveBarrier.wait()
        }
        if remainingHistoryFailures > 0 {
            remainingHistoryFailures -= 1
            throw FocusPersistenceTestError.injectedHistoryFailure
        }
        storedSessions = sessions
    }

    func loadActiveSession() async throws -> FocusSession? { storedActive }

    func saveActiveSession(_ session: FocusSession) async throws {
        let shouldFail = remainingActiveSaveFailures > 0
        if shouldFail {
            remainingActiveSaveFailures -= 1
        }
        if let activeSaveBarrier, !activeSaveStarted {
            activeSaveStarted = true
            await activeSaveBarrier.wait()
        }
        if shouldFail {
            throw FocusPersistenceTestError.injectedActiveSaveFailure
        }
        storedActive = session
    }

    func clearActiveSession() async throws {
        if remainingClearFailures > 0 {
            remainingClearFailures -= 1
            throw FocusPersistenceTestError.injectedClearFailure
        }
        storedActive = nil
    }

    func applyEnergyReward(receiptID: UUID, bottles: Int) async throws -> Int {
        if remainingEnergyAwardFailures > 0 {
            remainingEnergyAwardFailures -= 1
            throw FocusPersistenceTestError.injectedEnergyAwardFailure
        }
        if let target = energyAwards[receiptID] {
            storedEnergyTotal = max(storedEnergyTotal, target)
            return storedEnergyTotal
        }
        let target = storedEnergyTotal + max(0, bottles)
        energyAwards[receiptID] = target
        storedEnergyTotal = target
        return target
    }

    func sessions() -> [FocusSession] { storedSessions }
    func activeSession() -> FocusSession? { storedActive }
    func energyTotal() -> Int { storedEnergyTotal }
    func hasStartedHistorySave() -> Bool { historySaveStarted }
    func hasStartedActiveSave() -> Bool { activeSaveStarted }
}

enum FocusPersistenceTestError: Error {
    case injectedHistoryFailure
    case injectedClearFailure
    case injectedEnergyAwardFailure
    case injectedActiveSaveFailure
}

actor FocusLaunchBarrier {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isReleased = false

    func wait() async {
        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func release() {
        isReleased = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
final class FocusPersistenceGuardStub: FocusGuardService {
    var authorizationStatus: FocusAuthorizationStatus = .notDetermined
    var isDeepFocusFeatureEnabled = false
    var isDeepFocusCapable = false
    var canShowDeepFocusEntry: Bool { false }
    var selectedApplicationCount = 0
    var isPickerPresented = false

    func refreshAuthorizationStatus() async {}
    func requestAuthorization() async -> FocusAuthorizationStatus { .notDetermined }
    func presentAppPicker() {}
    func applyShield(selection: FocusAppSelection) throws {}
    func clearShield() {}
    func currentSelection() -> FocusAppSelection? { nil }
}

@MainActor
final class FocusProtectionTrackingGuardStub: FocusGuardService {
    var authorizationStatus: FocusAuthorizationStatus = .approved
    var isDeepFocusFeatureEnabled = true
    var isDeepFocusCapable = true
    var canShowDeepFocusEntry: Bool { true }
    var selectedApplicationCount = 1
    var isPickerPresented = false
    private(set) var applyShieldCalls = 0
    private(set) var clearShieldCalls = 0
    private(set) var isShieldApplied = false

    func refreshAuthorizationStatus() async {}
    func requestAuthorization() async -> FocusAuthorizationStatus { .approved }
    func presentAppPicker() {}

    func applyShield(selection: FocusAppSelection) throws {
        applyShieldCalls += 1
        isShieldApplied = true
    }

    func clearShield() {
        clearShieldCalls += 1
        isShieldApplied = false
    }

    func currentSelection() -> FocusAppSelection? {
        FocusAppSelection(tokenData: Data([0x01]), selectedApplicationCount: 1)
    }
}

@MainActor
final class BlockingFocusPersistenceGuardStub: FocusGuardService {
    var authorizationStatus: FocusAuthorizationStatus = .approved
    var isDeepFocusFeatureEnabled = true
    var isDeepFocusCapable = true
    var canShowDeepFocusEntry: Bool { true }
    var selectedApplicationCount = 1
    var isPickerPresented = false
    private(set) var refreshStarted = false
    private(set) var applyShieldCalls = 0
    private(set) var clearShieldCalls = 0
    private var refreshContinuation: CheckedContinuation<Void, Never>?

    func refreshAuthorizationStatus() async {
        refreshStarted = true
        await withCheckedContinuation { continuation in
            refreshContinuation = continuation
        }
    }

    func releaseRefresh() {
        refreshContinuation?.resume()
        refreshContinuation = nil
    }

    func requestAuthorization() async -> FocusAuthorizationStatus { .approved }
    func presentAppPicker() {}
    func applyShield(selection: FocusAppSelection) throws { applyShieldCalls += 1 }
    func clearShield() { clearShieldCalls += 1 }

    func currentSelection() -> FocusAppSelection? {
        FocusAppSelection(tokenData: Data([0x01]), selectedApplicationCount: 1)
    }
}

@MainActor
final class InterleavingFocusGuardStub: FocusGuardService {
    var authorizationStatus: FocusAuthorizationStatus = .approved
    var isDeepFocusFeatureEnabled = true
    var isDeepFocusCapable = true
    var canShowDeepFocusEntry: Bool { true }
    var selectedApplicationCount = 1
    var isPickerPresented = false
    private(set) var refreshCallCount = 0
    private(set) var clearShieldCalls = 0
    private(set) var isShieldApplied = false
    private var waitingRefreshes: [CheckedContinuation<Void, Never>] = []
    private var applyShieldCalls = 0

    func refreshAuthorizationStatus() async {
        refreshCallCount += 1
        await withCheckedContinuation { continuation in
            waitingRefreshes.append(continuation)
        }
    }

    func releaseFirstRefresh() {
        guard !waitingRefreshes.isEmpty else { return }
        waitingRefreshes.removeFirst().resume()
    }

    func requestAuthorization() async -> FocusAuthorizationStatus { .approved }
    func presentAppPicker() {}

    func applyShield(selection: FocusAppSelection) throws {
        applyShieldCalls += 1
        isShieldApplied = true
        if applyShieldCalls == 1, !waitingRefreshes.isEmpty {
            waitingRefreshes.removeFirst().resume()
        }
    }

    func clearShield() {
        clearShieldCalls += 1
        isShieldApplied = false
    }

    func currentSelection() -> FocusAppSelection? {
        FocusAppSelection(tokenData: Data([0x01]), selectedApplicationCount: 1)
    }
}

@MainActor
final class ControlledFocusGuardStub: FocusGuardService {
    var authorizationStatus: FocusAuthorizationStatus = .approved
    var isDeepFocusFeatureEnabled = true
    var isDeepFocusCapable = true
    var canShowDeepFocusEntry: Bool { true }
    var selectedApplicationCount = 1
    var isPickerPresented = false
    private(set) var refreshCallCount = 0
    private(set) var applyShieldCalls = 0
    private(set) var clearShieldCalls = 0
    private(set) var isShieldApplied = false
    private var waitingRefreshes: [CheckedContinuation<Void, Never>] = []

    func refreshAuthorizationStatus() async {
        refreshCallCount += 1
        await withCheckedContinuation { continuation in
            waitingRefreshes.append(continuation)
        }
    }

    func releaseFirstRefresh() {
        guard !waitingRefreshes.isEmpty else { return }
        waitingRefreshes.removeFirst().resume()
    }

    func releaseLastRefresh() {
        guard !waitingRefreshes.isEmpty else { return }
        waitingRefreshes.removeLast().resume()
    }

    func requestAuthorization() async -> FocusAuthorizationStatus { .approved }
    func presentAppPicker() {}

    func applyShield(selection: FocusAppSelection) throws {
        applyShieldCalls += 1
        isShieldApplied = true
    }

    func clearShield() {
        clearShieldCalls += 1
        isShieldApplied = false
    }

    func currentSelection() -> FocusAppSelection? {
        FocusAppSelection(tokenData: Data([0x01]), selectedApplicationCount: 1)
    }
}

@MainActor
final class FocusHardwareExitRecorder {
    private(set) var displaySyncCount = 0
    private(set) var settlementCount = 0

    func recordDisplaySync(_ session: FocusSession?) {
        if session != nil { displaySyncCount += 1 }
    }

    func recordSettlement(
        total: Int,
        newlyUnlocked: [String],
        now: Date,
        defersPresentation: Bool
    ) {
        _ = (total, newlyUnlocked, now, defersPresentation)
        settlementCount += 1
    }
}
