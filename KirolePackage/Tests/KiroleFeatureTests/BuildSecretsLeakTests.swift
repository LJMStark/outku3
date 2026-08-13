import Foundation
import Testing
@testable import KiroleFeature

@Suite("BuildSecretsLeak Tests")
struct BuildSecretsLeakTests {
    @Test("Config Info.plist does not contain client secrets")
    func infoPlistDoesNotContainSecrets() throws {
        let infoPlistURL = repositoryRootURL().appending(path: "Config/Info.plist")
        let contents = try String(contentsOf: infoPlistURL, encoding: .utf8)

        #expect(!contents.contains("OPENROUTER_API_KEY"))
        #expect(!contents.contains("SUPABASE_URL"))
        #expect(!contents.contains("SUPABASE_ANON_KEY"))
        #expect(!contents.contains("BLE_SHARED_SECRET"))
        // client_secret keys are now server-side only (Supabase Edge Function secrets)
        #expect(!contents.contains("NOTION_OAUTH_CLIENT_SECRET"))
        #expect(!contents.contains("TASKADE_OAUTH_CLIENT_SECRET"))
        #expect(!contents.contains("MICROSOFT_OAUTH_CLIENT_SECRET"))
        #expect(!contents.contains("TODOIST_OAUTH_CLIENT_SECRET"))
        #expect(!contents.contains("TICKTICK_OAUTH_CLIENT_SECRET"))
        #expect(!contents.contains("DIDA_OAUTH_CLIENT_SECRET"))
    }

    @Test("App-side build config does not emit OAuth client secrets")
    func appBuildConfigDoesNotEmitOAuthClientSecrets() throws {
        let root = repositoryRootURL()
        let appSideFiles = [
            root.appending(path: "Config/scripts-generate-build-secrets.sh"),
            root.appending(path: "Config/Secrets.xcconfig.template"),
        ]

        for url in appSideFiles {
            let contents = try String(contentsOf: url, encoding: .utf8)
            #expect(!contents.contains("NOTION_OAUTH_CLIENT_SECRET"))
            #expect(!contents.contains("TASKADE_OAUTH_CLIENT_SECRET"))
            #expect(!contents.contains("notionClientSecret"))
            #expect(!contents.contains("taskadeClientSecret"))
            #expect(!contents.contains("MICROSOFT_OAUTH_CLIENT_SECRET"))
            #expect(!contents.contains("TODOIST_OAUTH_CLIENT_SECRET"))
            #expect(!contents.contains("TICKTICK_OAUTH_CLIENT_SECRET"))
            #expect(!contents.contains("DIDA_OAUTH_CLIENT_SECRET"))
            #expect(!contents.contains("TICKTICK_OAUTH_CLIENT_ID"))
            #expect(!contents.contains("DIDA_OAUTH_CLIENT_ID"))
            #expect(!contents.contains("microsoftClientSecret"))
            #expect(!contents.contains("todoistClientSecret"))
            #expect(!contents.contains("tickTickClientSecret"))
            #expect(!contents.contains("didaClientSecret"))
        }
    }

    @Test("AppSecrets ignores placeholder values and preserves valid values")
    @MainActor
    func appSecretsNormalization() {
        defer {
            AppSecrets.configure(
                supabaseURL: nil,
                supabaseAnonKey: nil,
                openRouterAPIKey: nil,
                bleSharedSecret: nil,
                notionClientId: nil,
                taskadeClientId: nil
            )
        }

        AppSecrets.configure(
            supabaseURL: "  $(SUPABASE_URL)  ",
            supabaseAnonKey: "YOUR_SUPABASE_ANON_KEY",
            openRouterAPIKey: "   ",
            bleSharedSecret: "YOUR_BLE_SHARED_SECRET",
            notionClientId: "  YOUR_NOTION_OAUTH_CLIENT_ID ",
            taskadeClientId: "YOUR_TASKADE_OAUTH_CLIENT_ID",
            microsoftClientId: "YOUR_MICROSOFT_OAUTH_CLIENT_ID",
            microsoftOAuthEnabled: false,
            todoistClientId: "YOUR_TODOIST_OAUTH_CLIENT_ID",
            todoistOAuthEnabled: false,
            tickTickOAuthEnabled: false
        )

        #expect(AppSecrets.supabaseConfig == nil)
        #expect(AppSecrets.openRouterAPIKey == nil)
        #expect(AppSecrets.bleSharedSecret == nil)
        #expect(AppSecrets.notionClientId == nil)
        #expect(AppSecrets.taskadeClientId == nil)
        #expect(AppSecrets.microsoftClientId == nil)
        #expect(AppSecrets.microsoftOAuthEnabled == false)
        #expect(AppSecrets.todoistClientId == nil)
        #expect(AppSecrets.todoistOAuthEnabled == false)
        #expect(AppSecrets.tickTickOAuthEnabled == false)

        AppSecrets.configure(
            supabaseURL: "https://example.supabase.co",
            supabaseAnonKey: "anon-key",
            openRouterAPIKey: "openrouter-key",
            bleSharedSecret: "ble-secret",
            notionClientId: "notion-client-id",
            taskadeClientId: "taskade-client-id",
            microsoftClientId: "microsoft-client-id",
            microsoftOAuthEnabled: true,
            todoistClientId: "todoist-client-id",
            todoistOAuthEnabled: true,
            tickTickOAuthEnabled: true
        )

        #expect(AppSecrets.supabaseConfig?.url == "https://example.supabase.co")
        #expect(AppSecrets.supabaseConfig?.anonKey == "anon-key")
        #expect(AppSecrets.openRouterAPIKey == "openrouter-key")
        #expect(AppSecrets.bleSharedSecret == "ble-secret")
        #expect(AppSecrets.notionClientId == "notion-client-id")
        #expect(AppSecrets.taskadeClientId == "taskade-client-id")
        #expect(AppSecrets.microsoftClientId == "microsoft-client-id")
        #expect(AppSecrets.microsoftOAuthEnabled)
        #expect(AppSecrets.todoistClientId == "todoist-client-id")
        #expect(AppSecrets.todoistOAuthEnabled)
        #expect(AppSecrets.tickTickOAuthEnabled)
    }

    @Test("Build secrets generator restores the Todoist HTTPS metadata client ID")
    func todoistMetadataURLSurvivesXCConfigCommentParsing() throws {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appending(path: "kirole-build-secrets-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        let configDirectory = temporaryRoot.appending(path: "Config")
        let appDirectory = temporaryRoot.appending(path: "Kirole")
        try fileManager.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        try "TODOIST_OAUTH_CLIENT_ID = https:$()//example.com/.well-known/todoist.json\n"
            .write(
                to: configDirectory.appending(path: "Secrets.xcconfig"),
                atomically: true,
                encoding: .utf8
            )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            repositoryRootURL()
                .appending(path: "Config/scripts-generate-build-secrets.sh")
                .path,
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["SRCROOT"] = temporaryRoot.path
        environment["SUPABASE_URL"] = "https://example.supabase.co"
        environment["SUPABASE_ANON_KEY"] = "test-anon-key"
        environment["OPENAI_BASE_URL"] = "https://openrouter.ai/api/v1"
        environment["OPENAI_MODEL"] = "test-model"
        environment["FALLBACK_API_KEY"] = "test-fallback"
        // This is what Xcode exports after interpreting the URL's `//` as a comment.
        environment["TODOIST_OAUTH_CLIENT_ID"] = "https:"
        process.environment = environment
        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        let generated = try String(
            contentsOf: appDirectory.appending(path: "BuildSecrets.generated.swift"),
            encoding: .utf8
        )
        #expect(generated.contains(
            "https://example.com/.well-known/todoist.json"
        ))
    }

    @Test("Build secrets generator accepts an absent optional Todoist setting")
    func missingOptionalTodoistSettingDoesNotFailGeneration() throws {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appending(path: "kirole-build-secrets-optional-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        let configDirectory = temporaryRoot.appending(path: "Config")
        let appDirectory = temporaryRoot.appending(path: "Kirole")
        try fileManager.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        try "// Optional provider settings intentionally absent.\n"
            .write(
                to: configDirectory.appending(path: "Secrets.xcconfig"),
                atomically: true,
                encoding: .utf8
            )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            repositoryRootURL()
                .appending(path: "Config/scripts-generate-build-secrets.sh")
                .path,
        ]
        var environment = ProcessInfo.processInfo.environment
        environment["SRCROOT"] = temporaryRoot.path
        environment["SUPABASE_URL"] = "https://example.supabase.co"
        environment["SUPABASE_ANON_KEY"] = "test-anon-key"
        environment["OPENAI_BASE_URL"] = "https://openrouter.ai/api/v1"
        environment["OPENAI_MODEL"] = "test-model"
        environment["FALLBACK_API_KEY"] = "test-fallback"
        environment["TODOIST_OAUTH_CLIENT_ID"] = nil
        process.environment = environment
        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        let generated = try String(
            contentsOf: appDirectory.appending(path: "BuildSecrets.generated.swift"),
            encoding: .utf8
        )
        #expect(generated.contains("static let todoistClientId = \"\""))
        #expect(generated.contains("static let microsoftOAuthEnabled = \"0\" == \"1\""))
        #expect(generated.contains("static let todoistOAuthEnabled = \"0\" == \"1\""))
    }

    private func repositoryRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // KiroleFeatureTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // KirolePackage
            .deletingLastPathComponent() // repository root
    }
}
