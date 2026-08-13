import Foundation
import Testing
@testable import KiroleFeature

@Suite("Integration settings source policy")
struct IntegrationSettingsSourcePolicyTests {
    @Test("Presented integration sheets explicitly receive the app environment")
    func integrationSheetsInjectAppEnvironment() throws {
        let source = try settingsIntegrationSource()

        #expect(source.contains(
            "AppleCalendarSelectionSheet(intent: intent)\n                .injectAppEnvironment()"
        ))
        #expect(source.contains(
            "ProviderProjectSelectionSheet(target: target)\n                .injectAppEnvironment()"
        ))
    }

    @Test("TickTick China settings copy remains English-only")
    func tickTickChinaCopyIsEnglishOnly() throws {
        #expect(ProviderProjectSelectionTarget.tickTick(.china).title == "Choose TickTick China Projects")

        let source = try settingsIntegrationSource()
        #expect(source.contains("TickTick China — Coming Soon"))
        #expect(source.contains("Choose TickTick China projects"))
        #expect(!source.contains("滴答清单（中国）— Coming Soon"))
        #expect(!source.contains("选择滴答清单项目"))
    }

    @Test("Todoist remains unavailable until its release gate is enabled")
    func todoistHasAReleaseGate() throws {
        let source = try integrationTypeSource()

        #expect(source.contains("case .todoist: AppSecrets.todoistOAuthEnabled"))
    }

    @Test("Microsoft integrations remain unavailable until their release gate is enabled")
    func microsoftHasAReleaseGate() throws {
        let source = try integrationTypeSource()

        #expect(source.contains(
            "case .outlookCalendar, .microsoftToDo: AppSecrets.microsoftOAuthEnabled"
        ))
    }

    /// Notion and Taskade exchange their OAuth code through Supabase Edge Functions that are not
    /// deployed, so a present client ID would still fail every connect. The gate must be explicit.
    @Test("Notion and Taskade remain unavailable until their release gates are enabled")
    func notionAndTaskadeHaveReleaseGates() throws {
        let source = try integrationTypeSource()

        #expect(source.contains("case .notion: AppSecrets.notionOAuthEnabled"))
        #expect(source.contains("case .taskade: AppSecrets.taskadeOAuthEnabled"))
    }

    @Test("A gated integration row shows Coming Soon instead of Experimental")
    func gatedRowsDropTheExperimentalTag() throws {
        let source = try settingsIntegrationSource()

        #expect(source.contains(
            "if !type.isAvailable {\n                        Text(\"[Coming Soon]\")"
        ))
        #expect(source.contains(
            "} else if type.isExperimental {\n                        Text(\"[Experimental]\")"
        ))
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
