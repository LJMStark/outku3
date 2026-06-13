import Foundation

extension AppState {
    func isIntegrationConnected(_ type: IntegrationType) -> Bool {
        integrationCoordinator.hasIntegration(type, integrations: integrations)
    }

    public func syncIntegrationStatusFromAuth() {
        let mappings: [(isConnected: Bool, type: IntegrationType)] = [
            (AuthManager.shared.isGoogleConnected && AuthManager.shared.hasCalendarAccess, .googleCalendar),
            (AuthManager.shared.isGoogleConnected && AuthManager.shared.hasTasksAccess, .googleTasks),
            (AuthManager.shared.isNotionConnected, .notion),
            (AuthManager.shared.isTaskadeConnected, .taskade)
        ]

        for mapping in mappings where mapping.isConnected {
            setIntegrationStatus(mapping.type, isConnected: true)
        }
    }

    public func syncGoogleIntegrationStatusFromAuth() {
        syncIntegrationStatusFromAuth()
    }

    public func updateIntegrationStatus(_ type: IntegrationType, isConnected: Bool) {
        if isConnected {
            disconnectConflictingIntegration(for: type)
        }

        setIntegrationStatus(type, isConnected: isConnected)

        if !isConnected {
            cleanupDisconnectedIntegrationData(for: type)
        }

        reconcileAppleChangeObserver()
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
        persistIntegrationConnections()
    }

    /// 持久化各集成的连接开关，使用户的断开/连接意图跨重启保留（否则启动时回落 defaultIntegrations，
    /// Apple Calendar/Reminders 默认 isConnected:true 会让断开的集成自动复活并重新导入数据）。
    private func persistIntegrationConnections() {
        let states = Dictionary(
            uniqueKeysWithValues: integrations.map { ($0.type.rawValue, $0.isConnected) }
        )
        Task { @MainActor in
            do {
                try await localStorage.saveIntegrationConnections(states)
            } catch {
                reportPersistenceError(error, operation: "save", target: "integration_connections.json")
            }
        }
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
