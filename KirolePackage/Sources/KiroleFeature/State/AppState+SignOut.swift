import Foundation

extension AppState {
    /// Removes data obtained from external providers and persists disconnected switches before
    /// AuthManager is allowed to replace the current Kirole identity.
    public func prepareProviderDataForSignOut() async throws {
        // Invalidate before the first persistence await. A provider request that resumes during
        // sign-out may finish, but it can no longer commit the previous identity's snapshot.
        invalidateAllExternalSyncResults()
        let retainedTasks = tasks.filter { !$0.isProviderBackedSnapshot }
        let retainedEvents = events.filter { !$0.isProviderBackedSnapshot }
        let disconnectedIntegrations = integrations.map { integration in
            var disconnected = integration
            disconnected.isConnected = false
            return disconnected
        }
        let connectionStates = Dictionary(
            uniqueKeysWithValues: disconnectedIntegrations.map { ($0.type.rawValue, false) }
        )

        try await localStorage.saveTasks(retainedTasks)
        try await localStorage.saveEvents(retainedEvents)
        try await localStorage.saveIntegrationConnections(connectionStates)
        try await localStorage.saveIntegrationSyncTimes([:])

        tasks = retainedTasks
        events = retainedEvents
        integrations = disconnectedIntegrations
        hasExplicitIntegrationConnectionPreferences = true
        integrationLastSyncedAt = [:]
        remoteSyncErrors = [:]
        remoteSyncWarnings = [:]
        updateStatistics()
        await appleSyncEngine.stopObservingChanges()
    }
}

private extension TaskItem {
    var isProviderBackedSnapshot: Bool {
        if externalReference != nil { return true }

        switch source {
        case .apple:
            return appleReminderId != nil || appleExternalId != nil || appleListId != nil
        case .google:
            return true
        }
    }
}

private extension CalendarEvent {
    var isProviderBackedSnapshot: Bool {
        if externalReference != nil { return true }

        switch source {
        case .apple:
            return appleEventId != nil || appleCalendarId != nil
        case .google:
            return true
        }
    }
}
