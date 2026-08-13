import Foundation

extension AppState {
    func isIntegrationConnected(_ type: IntegrationType) -> Bool {
        integrationCoordinator.hasIntegration(type, integrations: integrations)
    }

    public func syncIntegrationStatusFromAuth() {
        let authMappings: [(isAuthenticated: Bool, type: IntegrationType)] = [
            (AuthManager.shared.isGoogleConnected && AuthManager.shared.hasCalendarAccess, .googleCalendar),
            (AuthManager.shared.isGoogleConnected && AuthManager.shared.hasTasksAccess, .googleTasks),
            (AuthManager.shared.isNotionConnected, .notion),
            (AuthManager.shared.isTaskadeConnected, .taskade),
            (AuthManager.shared.isMicrosoftConnected && AuthManager.shared.hasMicrosoftCalendarAccess, .outlookCalendar),
            (AuthManager.shared.isMicrosoftConnected && AuthManager.shared.hasMicrosoftTodoAccess, .microsoftToDo),
            (AuthManager.shared.isTodoistConnected, .todoist),
            (AuthManager.shared.isTickTickConnected, .tickTick)
        ]
        let authenticatedTypes = authMappings.compactMap { mapping in
            mapping.isAuthenticated ? mapping.type : nil
        }

        if reconcileAuthenticatedIntegrationTypes(authenticatedTypes) {
            persistIntegrationConnections()
        }
    }

    /// Imports credentials from installs that predate persisted connection switches. Once a
    /// preference file exists (or this one-time bootstrap ran), auth proves only that access is
    /// available; it must not override the user's on/off choice.
    @discardableResult
    func reconcileAuthenticatedIntegrationTypes(_ authenticatedTypes: [IntegrationType]) -> Bool {
        guard !hasExplicitIntegrationConnectionPreferences,
              !authenticatedTypes.isEmpty else {
            return false
        }

        integrations = authenticatedTypes.reduce(integrations) { current, type in
            integrationCoordinator.setIntegrationStatus(
                integrations: current,
                type: type,
                isConnected: true
            )
        }
        hasExplicitIntegrationConnectionPreferences = true
        return true
    }

    public func syncGoogleIntegrationStatusFromAuth() {
        syncIntegrationStatusFromAuth()
    }

    /// Release-gated providers must not leave another Kirole user's remote data visible after
    /// startup. The initial-load task calls this immediately after `loadLocalData()`, before
    /// `ensureInitialLoadComplete()` can return, so tasks.json cannot restore removed rows later.
    public func purgeDisabledTickTickData(
        tickTickIsAvailable: Bool = IntegrationType.tickTick.isAvailable
    ) async throws {
        guard !tickTickIsAvailable else { return }

        tasks.removeAll { task in
            task.source == .tickTick || task.externalReference?.provider == .tickTick
        }
        setIntegrationStatus(.tickTick, isConnected: false)
        try await localStorage.saveTasks(tasks)
        updateStatistics()
    }

    public func updateIntegrationStatus(_ type: IntegrationType, isConnected: Bool) {
        hasExplicitIntegrationConnectionPreferences = true
        invalidateExternalSyncResults(for: type)
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

    var hasAnyMicrosoftIntegrationConnected: Bool {
        isIntegrationConnected(.outlookCalendar) || isIntegrationConnected(.microsoftToDo)
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
        Task { @MainActor in
            do {
                // Build the snapshot when the task actually runs. Rapid consecutive toggles can
                // otherwise let an older captured dictionary finish last and undo the latest one.
                let states = Dictionary(
                    uniqueKeysWithValues: integrations.map { ($0.type.rawValue, $0.isConnected) }
                )
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

        invalidateExternalSyncResults(for: conflictingType)
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
