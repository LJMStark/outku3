import Foundation

extension AppState {
    func isIntegrationEnabled(_ type: IntegrationType) -> Bool {
        type.isAvailable && integrationCoordinator.hasIntegration(type, integrations: integrations)
    }

    func applePermission(for type: IntegrationType) -> AppleIntegrationPermission? {
        switch type {
        case .appleCalendar: appleCalendarPermission
        case .appleReminders: appleRemindersPermission
        default: nil
        }
    }

    /// Refreshing access never changes the user's sync preference, including an explicit disconnect.
    func refreshApplePermissions(syncRestoredAccess: Bool = false) async {
        let permissions = applePermissionProvider()
        let restoredAccess = applyApplePermissions(
            calendar: permissions.calendar,
            reminders: permissions.reminders
        )
        if syncRestoredAccess && restoredAccess {
            await syncAppleData()
        }
    }

    @discardableResult
    func applyApplePermissions(
        calendar: AppleIntegrationPermission,
        reminders: AppleIntegrationPermission
    ) -> Bool {
        let oldCalendar = appleCalendarPermission
        let oldReminders = appleRemindersPermission
        guard oldCalendar != calendar || oldReminders != reminders else { return false }
        appleCalendarPermission = calendar
        appleRemindersPermission = reminders
        invalidateExternalSyncResults(for: .appleCalendar)
        var restoredAccess = false
        for (type, old, current) in [
            (IntegrationType.appleCalendar, oldCalendar, calendar),
            (IntegrationType.appleReminders, oldReminders, reminders)
        ] {
            guard old != current else { continue }
            if current == .fullAccess {
                remoteSyncErrors.removeValue(forKey: type.rawValue)
                restoredAccess = restoredAccess || isIntegrationEnabled(type)
            } else if isIntegrationEnabled(type), current != .notDetermined {
                remoteSyncErrors[type.rawValue] = current.message(for: type)
            }
        }
        reconcileAppleChangeObserver()
        return restoredAccess
    }

    func recordApplePermissionFailure(for type: IntegrationType) {
        let message = applePermission(for: type)?.message(for: type)
            ?? "\(type.rawValue) permission could not be requested. Try again."
        lastError = message
        remoteSyncErrors[type.rawValue] = message
    }
}
