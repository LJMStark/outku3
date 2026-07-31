import Foundation

// MARK: - Focus Protection

extension FocusSessionService {
    struct ProtectionContext {
        var mode: FocusEnforcementMode
        var protectionState: FocusProtectionState
        var interruptionSource: FocusInterruptionSource?
        var shieldGeneration: UInt64? = nil
    }

    func resolveProtectionContext(
        requestedMode: FocusEnforcementMode
    ) async -> ProtectionContext {
        guard requestedMode == .deepFocus else {
            return ProtectionContext(
                mode: .standard,
                protectionState: .unprotected,
                interruptionSource: nil
            )
        }

        guard focusGuardService.isDeepFocusFeatureEnabled else {
            Task {
                await FocusMetricsService.shared.record(.sessionFallback)
            }
            return ProtectionContext(
                mode: .standard,
                protectionState: .fallback,
                interruptionSource: .featureDisabled
            )
        }
        guard focusGuardService.isDeepFocusCapable else {
            Task {
                await FocusMetricsService.shared.record(.sessionFallback)
            }
            return ProtectionContext(
                mode: .standard,
                protectionState: .fallback,
                interruptionSource: .capabilityUnavailable
            )
        }

        await focusGuardService.refreshAuthorizationStatus()
        var status = focusGuardService.authorizationStatus
        if status == .notDetermined {
            Task {
                await FocusMetricsService.shared.record(.authorizationRequested)
            }
            status = await focusGuardService.requestAuthorization()
        }

        guard status == .approved else {
            Task {
                await FocusMetricsService.shared.record(.authorizationDenied)
                await FocusMetricsService.shared.record(.sessionFallback)
            }
            return ProtectionContext(
                mode: .standard,
                protectionState: .fallback,
                interruptionSource: .permissionDenied
            )
        }

        Task {
            await FocusMetricsService.shared.record(.authorizationApproved)
        }

        guard let selection = focusGuardService.currentSelection(), !selection.isEmpty else {
            Task {
                await FocusMetricsService.shared.record(.sessionFallback)
            }
            return ProtectionContext(
                mode: .standard,
                protectionState: .fallback,
                interruptionSource: .selectionMissing
            )
        }

        do {
            try focusGuardService.applyShield(selection: selection)
            let shieldGeneration = claimNewShieldGeneration()
            if persistenceEnabled {
                await localStorage.saveDeepFocusShieldActive(true)
            }
            Task {
                await FocusMetricsService.shared.record(.protectionApplied)
            }
            return ProtectionContext(
                mode: .deepFocus,
                protectionState: .protected,
                interruptionSource: nil,
                shieldGeneration: shieldGeneration
            )
        } catch {
            ErrorReporter.log(
                .sync(
                    component: "FocusGuard.applyShield",
                    underlying: error.localizedDescription
                ),
                context: "FocusSessionService.resolveProtectionContext"
            )
            Task {
                await FocusMetricsService.shared.record(.protectionApplyFailed)
                await FocusMetricsService.shared.record(.sessionFallback)
            }
            return ProtectionContext(
                mode: .standard,
                protectionState: .fallback,
                interruptionSource: .shieldApplyFailed
            )
        }
    }

    private func claimNewShieldGeneration() -> UInt64 {
        shieldGenerationCounter = shieldGenerationCounter == .max
            ? 1
            : shieldGenerationCounter + 1
        currentShieldGeneration = shieldGenerationCounter
        return shieldGenerationCounter
    }

    /// 计算专注时间：只有超过阈值的无屏幕活动时段才计入
    func calculateFocusTime(
        sessionStart: Date,
        sessionEnd: Date,
        screenUnlockEvents: [ScreenUnlockEvent]
    ) -> TimeInterval {
        FocusTimeCalculator.countableFocusTime(
            sessionStart: sessionStart,
            sessionEnd: sessionEnd,
            screenUnlockEvents: screenUnlockEvents,
            thresholdSeconds: Constants.focusThresholdSeconds
        )
    }

    /// Loads the saved focus enforcement mode from UserDefaults and applies ScreenTime guard.
    func loadFocusEnforcementMode() async {
        let saved = await localStorage.loadFocusEnforcementMode() ?? .standard
        if saved == .deepFocus && !ScreenTimeFocusGuardService.shared.canShowDeepFocusEntry {
            focusEnforcementMode = .standard
            await localStorage.saveFocusEnforcementMode(.standard)
        } else {
            focusEnforcementMode = saved
        }
    }

    /// Sets the focus enforcement mode and persists it.
    public func setFocusEnforcementMode(_ mode: FocusEnforcementMode) {
        focusEnforcementMode = mode
        Task {
            await localStorage.saveFocusEnforcementMode(mode)
        }
    }
}
