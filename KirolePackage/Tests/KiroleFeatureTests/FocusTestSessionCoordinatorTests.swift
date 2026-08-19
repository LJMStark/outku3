import Foundation
import Testing
@testable import KiroleFeature

@MainActor
private final class CoordinatorFocusGuard: FocusGuardService {
    var authorizationStatus: FocusAuthorizationStatus
    var isDeepFocusFeatureEnabled: Bool
    var isDeepFocusCapable: Bool
    var canShowDeepFocusEntry: Bool {
        isDeepFocusFeatureEnabled && isDeepFocusCapable && authorizationStatus != .unavailable
    }
    var selectedApplicationCount: Int
    var isPickerPresented = false

    var requestAuthorizationResult: FocusAuthorizationStatus?
    var requestAuthorizationCalls = 0
    var selection: FocusAppSelection?

    init(
        authorizationStatus: FocusAuthorizationStatus = .approved,
        isDeepFocusFeatureEnabled: Bool = true,
        isDeepFocusCapable: Bool = true,
        selection: FocusAppSelection? = FocusAppSelection(
            tokenData: Data([0x01]),
            selectedApplicationCount: 1
        )
    ) {
        self.authorizationStatus = authorizationStatus
        self.isDeepFocusFeatureEnabled = isDeepFocusFeatureEnabled
        self.isDeepFocusCapable = isDeepFocusCapable
        self.selection = selection
        self.selectedApplicationCount = selection?.selectedApplicationCount ?? 0
    }

    func refreshAuthorizationStatus() async {}

    func requestAuthorization() async -> FocusAuthorizationStatus {
        requestAuthorizationCalls += 1
        if let requestAuthorizationResult {
            authorizationStatus = requestAuthorizationResult
        }
        return authorizationStatus
    }

    func presentAppPicker() {
        isPickerPresented = true
    }

    func applyShield(selection: FocusAppSelection) throws {}
    func clearShield() {}

    func currentSelection() -> FocusAppSelection? {
        selection
    }
}

@MainActor
private final class CoordinatorFocusSessionService: FocusTestSessionServing {
    var activeSession: FocusSession?
    var focusEnforcementMode: FocusEnforcementMode
    var startedModes: [FocusEnforcementMode] = []
    var endReasons: [FocusEndReason] = []
    var protectionResult: FocusProtectionState = .protected
    var interruptionSource: FocusInterruptionSource?

    init(mode: FocusEnforcementMode) {
        focusEnforcementMode = mode
    }

    func startSession(
        taskId: String,
        taskTitle: String,
        mode: FocusEnforcementMode,
        startTime: Date,
        fallbackPolicy: FocusSessionFallbackPolicy,
        focusSessionId: FocusSessionId? = nil
    ) async -> FocusSessionStartResult {
        startedModes.append(mode)
        if fallbackPolicy == .reject, protectionResult == .fallback {
            return .rejected(interruptionSource ?? .shieldApplyFailed)
        }
        let session = FocusSession(
            taskId: taskId,
            taskTitle: taskTitle,
            startTime: startTime,
            mode: protectionResult == .protected ? mode : .standard,
            protectionState: protectionResult,
            interruptionSource: interruptionSource
        )
        activeSession = session
        return .started(session)
    }

    func endSession(reason: FocusEndReason, endTime: Date) {
        endReasons.append(reason)
        activeSession = nil
    }
}

@Suite("Focus Test Session Coordinator")
struct FocusTestSessionCoordinatorTests {
    @Test("Ready Deep Focus starts the selected mode")
    @MainActor
    func readyDeepFocusStartsSelectedMode() async {
        let guardService = CoordinatorFocusGuard()
        let focusService = CoordinatorFocusSessionService(mode: .deepFocus)
        let coordinator = FocusTestSessionCoordinator(
            focusGuard: guardService,
            focusService: focusService
        )

        await coordinator.toggleTestSession()

        #expect(focusService.startedModes == [.deepFocus])
        #expect(focusService.activeSession?.protectionState == .protected)
        #expect(coordinator.failureMessage == nil)
    }

    @Test("First Deep Focus launch requests authorization then opens the picker")
    @MainActor
    func firstLaunchRequestsAuthorizationAndOpensPicker() async {
        let guardService = CoordinatorFocusGuard(
            authorizationStatus: .notDetermined,
            selection: nil
        )
        guardService.requestAuthorizationResult = .approved
        let focusService = CoordinatorFocusSessionService(mode: .deepFocus)
        let coordinator = FocusTestSessionCoordinator(
            focusGuard: guardService,
            focusService: focusService
        )

        await coordinator.toggleTestSession()

        #expect(guardService.requestAuthorizationCalls == 1)
        #expect(guardService.isPickerPresented)
        #expect(coordinator.isWaitingForSelection)
        #expect(focusService.startedModes.isEmpty)
    }

    @Test("Closing the requested picker with a selection resumes Deep Focus automatically")
    @MainActor
    func pickerSelectionResumesLaunch() async {
        let guardService = CoordinatorFocusGuard(selection: nil)
        let focusService = CoordinatorFocusSessionService(mode: .deepFocus)
        let coordinator = FocusTestSessionCoordinator(
            focusGuard: guardService,
            focusService: focusService
        )
        await coordinator.toggleTestSession()

        guardService.selection = FocusAppSelection(
            tokenData: Data([0x02]),
            selectedApplicationCount: 1
        )
        guardService.selectedApplicationCount = 1
        guardService.isPickerPresented = false
        await coordinator.resumeAfterPickerDismissal()

        #expect(focusService.startedModes == [.deepFocus])
        #expect(!coordinator.isWaitingForSelection)
        #expect(coordinator.failureMessage == nil)
    }

    @Test("A hardware session that appears while the picker is open is preserved")
    @MainActor
    func hardwareSessionDuringPickerIsPreserved() async {
        let guardService = CoordinatorFocusGuard(selection: nil)
        let focusService = CoordinatorFocusSessionService(mode: .deepFocus)
        let coordinator = FocusTestSessionCoordinator(
            focusGuard: guardService,
            focusService: focusService
        )
        await coordinator.toggleTestSession()

        let hardwareSession = FocusSession(
            taskId: "hardware-task",
            taskTitle: "Hardware Task",
            mode: .standard,
            protectionState: .unprotected
        )
        focusService.activeSession = hardwareSession
        guardService.selection = FocusAppSelection(
            tokenData: Data([0x02]),
            selectedApplicationCount: 1
        )
        guardService.selectedApplicationCount = 1
        guardService.isPickerPresented = false
        await coordinator.resumeAfterPickerDismissal()

        #expect(focusService.activeSession?.id == hardwareSession.id)
        #expect(focusService.startedModes.isEmpty)
        #expect(coordinator.failureMessage?.contains("Another focus session") == true)
    }

    @Test("Closing the requested picker empty reports the missing selection")
    @MainActor
    func emptyPickerSelectionReportsFailure() async {
        let guardService = CoordinatorFocusGuard(selection: nil)
        let focusService = CoordinatorFocusSessionService(mode: .deepFocus)
        let coordinator = FocusTestSessionCoordinator(
            focusGuard: guardService,
            focusService: focusService
        )
        await coordinator.toggleTestSession()

        guardService.isPickerPresented = false
        await coordinator.resumeAfterPickerDismissal()

        #expect(focusService.startedModes.isEmpty)
        #expect(coordinator.failureMessage?.contains("Select at least one") == true)
    }

    @Test("Denied Screen Time access reports a failure without starting Standard")
    @MainActor
    func deniedAuthorizationDoesNotSilentlyFallBack() async {
        let guardService = CoordinatorFocusGuard(
            authorizationStatus: .notDetermined,
            selection: nil
        )
        guardService.requestAuthorizationResult = .denied
        let focusService = CoordinatorFocusSessionService(mode: .deepFocus)
        let coordinator = FocusTestSessionCoordinator(
            focusGuard: guardService,
            focusService: focusService
        )

        await coordinator.toggleTestSession()

        #expect(focusService.startedModes.isEmpty)
        #expect(coordinator.failureMessage?.contains("Screen Time") == true)
    }

    @Test("A failed shield application is ended and reported instead of leaving Standard active")
    @MainActor
    func shieldFallbackIsEndedAndReported() async {
        let guardService = CoordinatorFocusGuard()
        let focusService = CoordinatorFocusSessionService(mode: .deepFocus)
        focusService.protectionResult = .fallback
        focusService.interruptionSource = .shieldApplyFailed
        let coordinator = FocusTestSessionCoordinator(
            focusGuard: guardService,
            focusService: focusService
        )

        await coordinator.toggleTestSession()

        #expect(focusService.startedModes == [.deepFocus])
        #expect(focusService.activeSession == nil)
        #expect(focusService.endReasons.isEmpty)
        #expect(coordinator.failureMessage?.contains("couldn't lock") == true)
    }

    @Test("Standard remains a one-tap test session")
    @MainActor
    func standardStartsDirectly() async {
        let guardService = CoordinatorFocusGuard(
            authorizationStatus: .denied,
            selection: nil
        )
        let focusService = CoordinatorFocusSessionService(mode: .standard)
        let coordinator = FocusTestSessionCoordinator(
            focusGuard: guardService,
            focusService: focusService
        )

        await coordinator.toggleTestSession()

        #expect(focusService.startedModes == [.standard])
        #expect(guardService.requestAuthorizationCalls == 0)
    }

    @Test("Selection count includes apps, categories, and websites")
    func selectionCountIncludesEveryPickerTarget() {
        let selection = FocusAppSelection.normalized(
            tokenData: Data([0x01]),
            applications: 2,
            categories: 1,
            webDomains: 3
        )

        #expect(selection.selectedApplicationCount == 6)
    }

    @Test("Legacy category-only selection is normalized from decoded token counts")
    func legacyCategorySelectionIsNormalized() {
        let normalized = FocusAppSelection.normalized(
            tokenData: Data([0x03]),
            applications: 0,
            categories: 1,
            webDomains: 0
        )

        #expect(!normalized.isEmpty)
        #expect(normalized.selectedApplicationCount == 1)
    }
}
