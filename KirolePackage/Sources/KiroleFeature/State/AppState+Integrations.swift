import Foundation

extension AppState {
    func isIntegrationConnected(_ type: IntegrationType) -> Bool {
        integrationCoordinator.hasIntegration(type, integrations: integrations)
    }

    public func syncGoogleIntegrationStatusFromAuth() {
        guard AuthManager.shared.isGoogleConnected else { return }

        let mappings: [(isGranted: Bool, type: IntegrationType)] = [
            (AuthManager.shared.hasCalendarAccess, .googleCalendar),
            (AuthManager.shared.hasTasksAccess, .googleTasks)
        ]

        for mapping in mappings where mapping.isGranted {
            setIntegrationStatus(mapping.type, isConnected: true)
        }
    }

    public func updateIntegrationStatus(_ type: IntegrationType, isConnected: Bool) {
        let hadGoogleIntegration = hasAnyGoogleIntegrationConnected

        if isConnected {
            disconnectConflictingIntegration(for: type)
        }

        setIntegrationStatus(type, isConnected: isConnected)

        if !isConnected {
            cleanupDisconnectedIntegrationData(for: type)
        }

        reconcileAppleChangeObserver()
        let hasGoogleIntegration = hasAnyGoogleIntegrationConnected

        if hadGoogleIntegration && !hasGoogleIntegration {
            Task { @MainActor in
                await AuthManager.shared.disconnectGoogle()
            }
        }
    }

    var hasAnyGoogleIntegrationConnected: Bool {
        integrationCoordinator.hasAnyGoogleIntegrationConnected(integrations: integrations)
    }

    func setIntegrationStatus(_ type: IntegrationType, isConnected: Bool) {
        integrations = integrationCoordinator.setIntegrationStatus(
            integrations: integrations,
            type: type,
            isConnected: isConnected
        )
    }

    func disconnectConflictingIntegration(for type: IntegrationType) {
        guard let conflictingType = integrationCoordinator.conflictingIntegration(for: type),
              isIntegrationConnected(conflictingType) else {
            return
        }

        setIntegrationStatus(conflictingType, isConnected: false)
        cleanupDisconnectedIntegrationData(for: conflictingType)
    }

    func cleanupDisconnectedIntegrationData(for type: IntegrationType) {
        let cleaned = integrationCoordinator.cleanupDisconnectedData(
            for: type,
            events: events,
            tasks: tasks
        )

        events = cleaned.events
        tasks = cleaned.tasks

        Task { @MainActor in
            await persistEvents(events, context: "AppState.cleanupDisconnectedIntegrationData")
            await persistTasks(tasks, context: "AppState.cleanupDisconnectedIntegrationData")
            updateStatistics()
        }
    }

    func reconcileAppleChangeObserver() {
        if isAnyAppleIntegrationConnected {
            Task { @MainActor in
                await setupAppleChangeObserver()
            }
        } else {
            Task {
                await appleSyncEngine.stopObservingChanges()
            }
        }
    }
}
