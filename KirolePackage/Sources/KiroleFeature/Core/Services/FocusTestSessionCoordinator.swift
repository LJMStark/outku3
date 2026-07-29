import Foundation

@MainActor
protocol FocusTestSessionServing: AnyObject {
    var activeSession: FocusSession? { get }
    var focusEnforcementMode: FocusEnforcementMode { get }

    func startSession(
        taskId: String,
        taskTitle: String,
        mode: FocusEnforcementMode,
        startTime: Date,
        fallbackPolicy: FocusSessionFallbackPolicy
    ) async -> FocusSessionStartResult

    func endSession(reason: FocusEndReason, endTime: Date)
}

extension FocusSessionService: FocusTestSessionServing {}

enum FocusTestSessionLaunchState: Equatable {
    case idle
    case requestingAuthorization
    case awaitingSelection
    case starting
    case failed(String)
}

/// Coordinates the explicit Settings test flow without mixing permission state into the View.
@Observable
@MainActor
final class FocusTestSessionCoordinator {
    private static let testTaskID = "debug-focus-session"
    private static let testTaskTitle = "Debug Focus Session"

    @ObservationIgnored private let focusGuard: any FocusGuardService
    @ObservationIgnored private let focusService: any FocusTestSessionServing

    private(set) var state: FocusTestSessionLaunchState = .idle
    private var shouldResumeAfterPickerDismissal = false

    init(
        focusGuard: any FocusGuardService = ScreenTimeFocusGuardService.shared,
        focusService: any FocusTestSessionServing = FocusSessionService.shared
    ) {
        self.focusGuard = focusGuard
        self.focusService = focusService
    }

    var failureMessage: String? {
        guard case .failed(let message) = state else { return nil }
        return message
    }

    var isWaitingForSelection: Bool {
        state == .awaitingSelection
    }

    var isBusy: Bool {
        switch state {
        case .requestingAuthorization, .starting:
            return true
        case .idle, .awaitingSelection, .failed:
            return false
        }
    }

    func toggleTestSession() async {
        guard !isBusy else { return }
        state = .idle

        if focusService.activeSession != nil {
            focusService.endSession(reason: .manual, endTime: Date())
            return
        }

        let mode = focusService.focusEnforcementMode
        if mode == .standard {
            await startSession(mode: .standard, fallbackPolicy: .allowStandard)
            return
        }

        await prepareDeepFocus()
    }

    func resumeAfterPickerDismissal() async {
        guard shouldResumeAfterPickerDismissal else { return }
        shouldResumeAfterPickerDismissal = false

        guard hasSelection else {
            state = .failed("Select at least one app, category, or website to start Deep Focus.")
            return
        }

        await startSession(mode: .deepFocus, fallbackPolicy: .reject)
    }

    func dismissFailure() {
        if case .failed = state {
            state = .idle
        }
    }

    private func prepareDeepFocus() async {
        guard focusGuard.isDeepFocusFeatureEnabled else {
            state = .failed("Deep Focus is disabled in this build.")
            return
        }
        guard focusGuard.isDeepFocusCapable else {
            state = .failed("Deep Focus is not supported on this device.")
            return
        }

        await focusGuard.refreshAuthorizationStatus()
        var authorizationStatus = focusGuard.authorizationStatus
        if authorizationStatus == .notDetermined {
            state = .requestingAuthorization
            authorizationStatus = await focusGuard.requestAuthorization()
        }

        guard authorizationStatus == .approved else {
            state = .failed(authorizationFailureMessage(for: authorizationStatus))
            return
        }

        guard hasSelection else {
            shouldResumeAfterPickerDismissal = true
            state = .awaitingSelection
            focusGuard.presentAppPicker()
            return
        }

        await startSession(mode: .deepFocus, fallbackPolicy: .reject)
    }

    private var hasSelection: Bool {
        guard let selection = focusGuard.currentSelection() else { return false }
        return !selection.isEmpty
    }

    private func startSession(
        mode: FocusEnforcementMode,
        fallbackPolicy: FocusSessionFallbackPolicy
    ) async {
        guard focusService.activeSession == nil else {
            state = .failed("Another focus session started while Deep Focus was being prepared. End it before starting a test session.")
            return
        }
        state = .starting
        let result = await focusService.startSession(
            taskId: Self.testTaskID,
            taskTitle: Self.testTaskTitle,
            mode: mode,
            startTime: Date(),
            fallbackPolicy: fallbackPolicy
        )

        switch result {
        case .started, .alreadyActive:
            state = .idle
        case .blockedByActiveSession:
            state = .failed("Another focus session started while Deep Focus was being prepared. End it before starting a test session.")
        case .rejected(let source):
            state = .failed(protectionFailureMessage(for: source))
        case .persistenceUnavailable:
            state = .failed("The focus session couldn't start because local session data is still being recovered.")
        }
    }

    private func authorizationFailureMessage(
        for status: FocusAuthorizationStatus
    ) -> String {
        switch status {
        case .denied:
            return "Screen Time access was denied. Allow access in Settings, then try again."
        case .unavailable:
            return "Screen Time access is unavailable in this build."
        case .unsupported:
            return "Deep Focus is not supported on this device."
        case .notDetermined:
            return "Screen Time access wasn't completed. Try again to enable Deep Focus."
        case .approved:
            return "Deep Focus couldn't verify Screen Time access."
        }
    }

    private func protectionFailureMessage(
        for source: FocusInterruptionSource
    ) -> String {
        switch source {
        case .permissionDenied, .authorizationRevoked:
            return "Screen Time access is no longer available. Allow access in Settings, then try again."
        case .selectionMissing:
            return "Select at least one app, category, or website to start Deep Focus."
        case .shieldApplyFailed:
            return "Deep Focus couldn't lock the selected distractions. Try selecting them again."
        case .featureDisabled:
            return "Deep Focus is disabled in this build."
        case .capabilityUnavailable:
            return "Deep Focus is not supported on this device."
        case .recoveredOnLaunch:
            return "The previous focus session is still being recovered. Try again in a moment."
        }
    }
}
