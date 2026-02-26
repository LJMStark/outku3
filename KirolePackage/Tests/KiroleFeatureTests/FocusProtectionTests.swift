import Foundation
import Testing
@testable import KiroleFeature

@MainActor
private final class MockFocusGuardService: FocusGuardService {
    var authorizationStatus: FocusAuthorizationStatus
    var isDeepFocusFeatureEnabled: Bool
    var isDeepFocusCapable: Bool
    var canShowDeepFocusEntry: Bool {
        isDeepFocusFeatureEnabled && isDeepFocusCapable && authorizationStatus != .unavailable
    }
    var selectedApplicationCount: Int
    var isPickerPresented: Bool = false

    var applyShieldCalls = 0
    var clearShieldCalls = 0
    var requestAuthorizationCalls = 0
    var requestAuthorizationResult: FocusAuthorizationStatus?
    var applyShieldError: FocusGuardError?
    var selection: FocusAppSelection?

    init(
        authorizationStatus: FocusAuthorizationStatus,
        isDeepFocusFeatureEnabled: Bool = true,
        isDeepFocusCapable: Bool = true,
        selectedApplicationCount: Int = 1,
        selection: FocusAppSelection? = FocusAppSelection(tokenData: Data([0x01]), selectedApplicationCount: 1)
    ) {
        self.authorizationStatus = authorizationStatus
        self.isDeepFocusFeatureEnabled = isDeepFocusFeatureEnabled
        self.isDeepFocusCapable = isDeepFocusCapable
        self.selectedApplicationCount = selectedApplicationCount
        self.selection = selection
    }

    func refreshAuthorizationStatus() async {}

    func requestAuthorization() async -> FocusAuthorizationStatus {
        requestAuthorizationCalls += 1
        if let result = requestAuthorizationResult {
            authorizationStatus = result
        }
        return authorizationStatus
    }

    func presentAppPicker() {
        isPickerPresented = true
    }

    func applyShield(selection: FocusAppSelection) throws {
        if let applyShieldError {
            throw applyShieldError
        }
        applyShieldCalls += 1
    }

    func clearShield() {
        clearShieldCalls += 1
    }

    func currentSelection() -> FocusAppSelection? {
        selection
    }
}

@Suite("Focus Protection Tests")
struct FocusProtectionTests {
    @Test("Deep focus applies shield on start and clears once on end")
    @MainActor
    func deepFocusApplyAndClearFlow() async throws {
        let guardService = MockFocusGuardService(authorizationStatus: .approved)
        let service = FocusSessionService.makeForTesting(focusGuardService: guardService, persistenceEnabled: false)

        await service.startSession(taskId: "deep-focus-task-1", taskTitle: "Deep Focus Task", mode: .deepFocus)

        #expect(guardService.applyShieldCalls == 1)
        #expect(service.activeSession?.mode == .deepFocus)
        #expect(service.activeSession?.protectionState == .protected)

        service.endSession(reason: .completed)

        #expect(guardService.clearShieldCalls == 1)
    }

    @Test("Denied authorization falls back to standard mode")
    @MainActor
    func deniedAuthorizationFallsBack() async throws {
        let guardService = MockFocusGuardService(authorizationStatus: .notDetermined)
        guardService.requestAuthorizationResult = .denied
        let service = FocusSessionService.makeForTesting(focusGuardService: guardService, persistenceEnabled: false)

        await service.startSession(taskId: "deep-focus-task-2", taskTitle: "Denied Case", mode: .deepFocus)
        let session = try #require(service.activeSession)

        #expect(session.mode == .standard)
        #expect(session.protectionState == .fallback)
        #expect(session.interruptionSource == .permissionDenied)
        #expect(guardService.applyShieldCalls == 0)
    }

    @Test("Revoked authorization during session downgrades to fallback and records source")
    @MainActor
    func revokedAuthorizationDowngradesSession() async throws {
        let guardService = MockFocusGuardService(authorizationStatus: .approved)
        let service = FocusSessionService.makeForTesting(focusGuardService: guardService, persistenceEnabled: false)

        await service.startSession(taskId: "deep-focus-task-3", taskTitle: "Revoke Case", mode: .deepFocus)
        #expect(service.activeSession?.protectionState == .protected)

        guardService.authorizationStatus = .denied
        await service.refreshProtectionStatus()

        let session = try #require(service.activeSession)
        #expect(session.mode == .standard)
        #expect(session.protectionState == .fallback)
        #expect(session.interruptionSource == .authorizationRevoked)
        #expect(guardService.clearShieldCalls == 1)
    }

    @Test("Launch recovery clears stale shield and finalizes active session")
    @MainActor
    func launchRecoveryFinalizesActiveSession() async throws {
        let taskId = "recovery-task-\(UUID().uuidString)"
        let active = FocusSession(
            taskId: taskId,
            taskTitle: "Recovered Session",
            startTime: Date().addingTimeInterval(-600),
            mode: .deepFocus,
            protectionState: .protected
        )

        let guardService = MockFocusGuardService(authorizationStatus: .approved)
        let service = FocusSessionService.makeForTesting(focusGuardService: guardService, persistenceEnabled: false)
        service.recoverPersistedSessionForTesting(active, wasShieldActive: true, endTime: Date())

        #expect(service.activeSession == nil)

        let recovered = service.todaySessions.last { $0.taskId == taskId }
        #expect(recovered?.endReason == .recoveredOnLaunch)
        #expect(recovered?.protectionState == .fallback)
        #expect(recovered?.interruptionSource == .recoveredOnLaunch)
        #expect(guardService.clearShieldCalls == 1)
    }
}
