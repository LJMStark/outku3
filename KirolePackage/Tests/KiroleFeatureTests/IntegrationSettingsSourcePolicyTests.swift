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

    @Test("Customer Settings is generated from the four-source model")
    func settingsUseTheSupportedSourceList() throws {
        let settings = try settingsIntegrationSource()
        let model = try integrationTypeSource()

        #expect(model.contains("case googleCalendar"))
        #expect(model.contains("case appleCalendar"))
        #expect(model.contains("case appleReminders"))
        #expect(model.contains("case googleTasks"))
        #expect(!model.contains("case notion"))
        #expect(!model.contains("case taskade"))
        #expect(!model.contains("case microsoftToDo"))
        #expect(!model.contains("case todoist"))
        #expect(!model.contains("case tickTick"))
        #expect(settings.contains("IntegrationType.displayOrder"))
        #expect(!settings.contains("ProviderProjectSelectionSheet"))
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
