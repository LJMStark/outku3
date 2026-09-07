import Foundation
import Testing
@testable import KiroleFeature

@Suite("Integration settings source policy")
struct IntegrationSettingsSourcePolicyTests {
    @Test("Apple calendar selection explicitly receives the app environment")
    func appleCalendarSheetInjectsAppEnvironment() throws {
        let source = try settingsIntegrationSource()

        #expect(source.contains(
            "AppleCalendarSelectionSheet(intent: intent)\n                .injectAppEnvironment()"
        ))
    }

    /// Guards against a retired provider quietly coming back. Microsoft was restored deliberately
    /// (Outlook Calendar); the other five stay retired and must not reappear in the model.
    @Test("Customer Settings is generated from the supported source model")
    func settingsUseTheSupportedSourceList() throws {
        let settings = try settingsIntegrationSource()
        let model = try integrationTypeSource()

        #expect(model.contains("case googleCalendar"))
        #expect(model.contains("case appleCalendar"))
        #expect(model.contains("case appleReminders"))
        #expect(model.contains("case googleTasks"))
        #expect(model.contains("case outlookCalendar"))
        #expect(!model.contains("case notion"))
        #expect(!model.contains("case taskade"))
        #expect(!model.contains("case todoist"))
        #expect(!model.contains("case tickTick"))
        // The connect list must honour the release gate, so a provider whose Azure registration and
        // real-account acceptance have not passed cannot reach customer Settings.
        #expect(settings.contains("IntegrationType.availableDisplayOrder"))
        #expect(!settings.contains("ProviderProjectSelectionSheet"))
    }

    @Test("Unavailable Apple permissions keep a connection and system-settings recovery path")
    func applePermissionRecoveryIsReachable() throws {
        let settings = try settingsIntegrationSource()
        let content = try sourceFile(path: "KirolePackage/Sources/KiroleFeature/ContentView.swift")
        #expect(settings.contains("appState.isIntegrationConnected($0.type)"))
        #expect(settings.contains("applePermissionRecovery(for: type)"))
        #expect(settings.contains("UIApplication.openSettingsURLString"))
        #expect(content.contains("await appState.refreshApplePermissions(syncRestoredAccess: true)"))
        #expect(!settings.contains("isConnected: granted"))
    }

    private func settingsIntegrationSource() throws -> String {
        try sourceFile(
            path: "KirolePackage/Sources/KiroleFeature/Views/Settings/SettingsIntegrationSection.swift"
        )
    }

    private func integrationTypeSource() throws -> String {
        try sourceFile(path: "KirolePackage/Sources/KiroleFeature/Models/Integration.swift")
    }

    private func sourceFile(path: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // KiroleFeatureTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // KirolePackage
            .deletingLastPathComponent() // repository root
        return try String(
            contentsOf: repositoryRoot.appending(path: path),
            encoding: .utf8
        )
    }
}
