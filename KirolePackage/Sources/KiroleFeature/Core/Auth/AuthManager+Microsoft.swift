@MainActor
extension AuthManager {
    public func ensureMicrosoftAccess(for type: IntegrationType) async throws {
        let capability: MicrosoftIntegrationCapability
        switch type {
        case .outlookCalendar:
            capability = .outlookCalendar
        case .microsoftToDo:
            capability = .todo
        default:
            return
        }
        guard microsoftAvailability(type) else {
            throw MicrosoftAuthError.secureConfigurationRequired
        }

        if await microsoftAuthService.hasAccess(to: capability) {
            isMicrosoftConnected = true
            updateMicrosoftCapabilityState(capability)
            return
        }
        // Block AppState commits and new engine work for the entire interactive MSAL window. The
        // second generation publish after authorize also catches same-account A→B→A ABA changes.
        let commitBoundary = try MicrosoftSyncCommitGate.beginTransition()
        let transition: MicrosoftSyncAccountTransition
        do {
            transition = try await MicrosoftSyncEngine.shared.beginAccountTransition(
                clearingProviderState: false
            )
        } catch {
            MicrosoftSyncCommitGate.finishTransition(commitBoundary)
            throw error
        }
        do {
            _ = try await microsoftAuthService.authorize(capabilities: [capability])
        } catch {
            await MicrosoftSyncEngine.shared.finishAccountTransition(transition)
            MicrosoftSyncCommitGate.finishTransition(commitBoundary)
            throw error
        }
        await MicrosoftSyncEngine.shared.finishAccountTransition(transition)
        MicrosoftSyncCommitGate.finishTransition(commitBoundary)

        // Consent is per-scope: the user (or a tenant policy) can complete sign-in while declining
        // Calendars.Read, and `authorize` still returns an account. Without this check Settings
        // would show Outlook as connected while every sync failed on a missing scope, leaving the
        // user to guess that the cure is to disconnect and reconnect. Google's connect path makes
        // the same check via `hasRequiredAccess`.
        guard await microsoftAuthService.hasAccess(to: capability) else {
            throw MicrosoftAuthError.missingRequiredScope
        }
        isMicrosoftConnected = true
        updateMicrosoftCapabilityState(capability)
    }

    public func disconnectMicrosoft() async throws {
        // Keep both commit paths blocked from the first local reset through verified MSAL cache
        // deletion. Otherwise a new-generation A request could recreate state in that gap.
        let commitBoundary = try MicrosoftSyncCommitGate.beginTransition()
        let transition: MicrosoftSyncAccountTransition
        do {
            transition = try await MicrosoftSyncEngine.shared.beginAccountTransition(
                clearingProviderState: true
            )
        } catch {
            MicrosoftSyncCommitGate.finishTransition(commitBoundary)
            throw error
        }
        do {
            try await microsoftAuthService.disconnect()
        } catch {
            await MicrosoftSyncEngine.shared.finishAccountTransition(transition)
            MicrosoftSyncCommitGate.finishTransition(commitBoundary)
            throw error
        }
        await MicrosoftSyncEngine.shared.finishAccountTransition(transition)
        MicrosoftSyncCommitGate.finishTransition(commitBoundary)
        isMicrosoftConnected = false
        hasMicrosoftCalendarAccess = false
        hasMicrosoftTodoAccess = false
    }

    private func updateMicrosoftCapabilityState(_ capability: MicrosoftIntegrationCapability) {
        switch capability {
        case .outlookCalendar:
            hasMicrosoftCalendarAccess = true
        case .todo:
            hasMicrosoftTodoAccess = true
        }
    }
}
