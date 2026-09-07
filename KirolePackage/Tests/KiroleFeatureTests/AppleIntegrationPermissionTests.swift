import EventKit
import Foundation
import Testing
@testable import KiroleFeature

@Suite("Apple integration permissions")
struct AppleIntegrationPermissionTests {
    @Test("Only full access makes an enabled integration connected", arguments: [
        EKAuthorizationStatus.notDetermined, .denied, .restricted, .writeOnly, .fullAccess
    ])
    @MainActor
    func effectiveConnection(status: EKAuthorizationStatus) {
        let state = AppState.makeForTesting()
        state.appleCalendarPermission = AppleIntegrationPermission(status)
        state.appleRemindersPermission = AppleIntegrationPermission(status)

        #expect(state.isIntegrationEnabled(.appleCalendar))
        #expect(state.isIntegrationEnabled(.appleReminders))
        #expect(state.isIntegrationConnected(.appleCalendar) == (status == .fullAccess))
        #expect(state.isIntegrationConnected(.appleReminders) == (status == .fullAccess))
        #expect(state.connectedExternalSyncTargets().contains(.apple) == (status == .fullAccess))
    }

    @Test("Restoring system access does not revive a disconnected provider")
    @MainActor
    func preservesDisconnect() {
        let state = AppState.makeForTesting()
        state.appleCalendarPermission = .denied
        state.appleRemindersPermission = .denied
        state.integrations = state.integrationCoordinator.applyConnectionStates([
            IntegrationType.appleCalendar.rawValue: false,
            IntegrationType.appleReminders.rawValue: false
        ], to: state.integrations)
        state.hasExplicitIntegrationConnectionPreferences = true

        let shouldSync = state.applyApplePermissions(calendar: .fullAccess, reminders: .fullAccess)

        #expect(!shouldSync)
        #expect(!state.isIntegrationConnected(.appleCalendar))
        #expect(!state.isIntegrationConnected(.appleReminders))
        #expect(!state.isIntegrationEnabled(.appleCalendar))
        #expect(!state.isIntegrationEnabled(.appleReminders))
    }

    @Test("Restored permission resumes enabled sync and clears its permission failure")
    @MainActor
    func restoresEnabledConnection() {
        let state = AppState.makeForTesting()
        state.appleCalendarPermission = .denied
        state.remoteSyncErrors["Apple Calendar"] = "Access is off"
        state.remoteSyncErrors["Google"] = "Google failure"

        #expect(state.applyApplePermissions(calendar: .fullAccess, reminders: .fullAccess))
        #expect(state.isIntegrationConnected(.appleCalendar))
        #expect(state.remoteSyncErrors["Apple Calendar"] == nil)
        #expect(state.remoteSyncErrors["Google"] == "Google failure")
        #expect(!state.applyApplePermissions(calendar: .fullAccess, reminders: .fullAccess))
    }

    @Test("Revocation preserves sync intent but invalidates an in-flight Apple result")
    @MainActor
    func revokesAccess() {
        let state = AppState.makeForTesting()
        let generation = state.externalSyncGeneration(for: .apple)

        #expect(!state.applyApplePermissions(calendar: .denied, reminders: .fullAccess))
        #expect(state.isIntegrationEnabled(.appleCalendar))
        #expect(!state.isIntegrationConnected(.appleCalendar))
        #expect(state.isIntegrationConnected(.appleReminders))
        #expect(!state.canCommitExternalSync(.apple, generation: generation))
        #expect(state.remoteSyncErrors["Apple Calendar"]?.contains("Settings") == true)
        #expect(state.remoteSyncErrors["Apple Calendar"]?.contains("network") == false)
    }

    @Test("Foreground refresh uses current system access without overwriting the sync choice")
    @MainActor
    func refreshesPermissionProvider() async {
        let state = AppState.makeForTesting()
        state.applePermissionProvider = { (.denied, .notDetermined) }
        await state.refreshApplePermissions()
        #expect(!state.isIntegrationConnected(.appleCalendar))
        #expect(!state.isIntegrationConnected(.appleReminders))
        #expect(state.isIntegrationEnabled(.appleCalendar))
        state.integrations = state.integrationCoordinator.applyConnectionStates([
            IntegrationType.appleCalendar.rawValue: false
        ], to: state.integrations)
        state.applePermissionProvider = { (.fullAccess, .fullAccess) }
        await state.refreshApplePermissions()
        #expect(!state.isIntegrationConnected(.appleCalendar))
        #expect(state.isIntegrationConnected(.appleReminders))
    }

    @Test("Disconnecting a denied Apple integration clears only its own sync failure",
          arguments: [IntegrationType.appleCalendar, .appleReminders])
    @MainActor
    func disconnectClearsPermissionFailure(type: IntegrationType) async {
        let state = AppState.makeForTesting()
        state.applePermissionProvider = { (.denied, .denied) }
        await state.refreshApplePermissions()
        state.remoteSyncWarnings[type.rawValue] = "Previous sync warning"
        state.remoteSyncErrors["Google"] = "Google failure"

        state.updateIntegrationStatus(type, isConnected: false)
        await state.refreshApplePermissions()

        #expect(!state.isIntegrationEnabled(type))
        #expect(state.remoteSyncErrors[type.rawValue] == nil)
        #expect(state.remoteSyncWarnings[type.rawValue] == nil)
        #expect(state.remoteSyncErrors["Google"] == "Google failure")
    }

    @Test("Recovery distinguishes a pending prompt, denial, restrictions and write-only access")
    func recoveryActions() {
        #expect(!AppleIntegrationPermission.notDetermined.needsSettings)
        #expect(!AppleIntegrationPermission.fullAccess.needsSettings)
        #expect(AppleIntegrationPermission.denied.needsSettings)
        #expect(AppleIntegrationPermission.restricted.needsSettings)
        #expect(AppleIntegrationPermission.writeOnly.needsSettings)
        #expect(AppleIntegrationPermission.restricted.message(for: .appleCalendar)?.contains("device management") == true)
        #expect(AppleIntegrationPermission.writeOnly.message(for: .appleCalendar)?.contains("Full Access") == true)
        #expect(AppleIntegrationPermission.fullAccess.message(for: .appleCalendar) == nil)
    }
}
