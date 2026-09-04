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

    /// 把持久化的连接开关（IntegrationType.rawValue → isConnected）应用到一组 integrations 之上。
    /// 未知 rawValue 跳过。用于启动时在 defaultIntegrations 之上恢复用户的断开/连接意图。
    func applyConnectionStates(_ states: [String: Bool], to integrations: [Integration]) -> [Integration] {
        var result = integrations
        for (rawType, isConnected) in states {
            guard let type = IntegrationType(rawValue: rawType) else { continue }
            result = setIntegrationStatus(integrations: result, type: type, isConnected: isConnected)
        }
        return result
    }

    /// Google and Apple stay mutually exclusive because an iCloud account commonly subscribes to
    /// the same Google calendar, so enabling both yields duplicate events — and the hardware wire
    /// only carries the first 8 (`ScheduleV2Codec.maxEvents`), so duplicates would evict real ones.
    ///
    /// Microsoft has no such overlap and returns `nil`: Outlook Calendar coexists with either
    /// Google or Apple.
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
        case .outlookCalendar, .microsoftToDo:
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
        case .outlookCalendar:
            return (events.filter { $0.source != .outlook }, tasks)
        case .microsoftToDo:
            return (events, tasks.filter { $0.source != .microsoftToDo })
        }
    }
}
