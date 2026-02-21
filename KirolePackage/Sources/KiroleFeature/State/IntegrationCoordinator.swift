import Foundation

@MainActor
final class IntegrationCoordinator {
    func hasIntegration(_ type: IntegrationType, integrations: [Integration]) -> Bool {
        integrations.first(where: { $0.type == type })?.isConnected == true
    }

    func hasAnyGoogleIntegrationConnected(integrations: [Integration]) -> Bool {
        hasIntegration(.googleCalendar, integrations: integrations) || hasIntegration(.googleTasks, integrations: integrations)
    }

    func setIntegrationStatus(
        integrations: [Integration],
        type: IntegrationType,
        isConnected: Bool
    ) -> [Integration] {
        if let index = integrations.firstIndex(where: { $0.type == type }) {
            var updated = integrations
            var item = updated[index]
            item.isConnected = isConnected
            updated[index] = item
            return updated
        }

        guard isConnected else { return integrations }

        return integrations + [Integration(
            name: type.rawValue,
            iconName: type.iconName,
            isConnected: true,
            type: type
        )]
    }

    func conflictingIntegration(for type: IntegrationType) -> IntegrationType? {
        switch type {
        case .googleCalendar:
            return .appleCalendar
        case .appleCalendar:
            return .googleCalendar
        case .googleTasks:
            return .appleReminders
        case .appleReminders:
            return .googleTasks
        default:
            return nil
        }
    }

    func cleanupDisconnectedData(
        for type: IntegrationType,
        events: [CalendarEvent],
        tasks: [TaskItem]
    ) -> (events: [CalendarEvent], tasks: [TaskItem]) {
        switch type {
        case .appleCalendar:
            return (events.filter { $0.source != .apple }, tasks)
        case .googleCalendar:
            return (events.filter { $0.source != .google }, tasks)
        case .appleReminders:
            return (events, tasks.filter { $0.source != .apple })
        case .googleTasks:
            return (events, tasks.filter { $0.source != .google })
        default:
            return (events, tasks)
        }
    }
}
