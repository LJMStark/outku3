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
