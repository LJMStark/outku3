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
        #expect(!contents.contains("NOTION_OAUTH_CLIENT_SECRET"))
        #expect(!contents.contains("TASKADE_OAUTH_CLIENT_SECRET"))
    }

    @Test("AppSecrets ignores placeholder values and preserves valid values")
    func appSecretsNormalization() {
        AppSecrets.configure(
            supabaseURL: "  $(SUPABASE_URL)  ",
            supabaseAnonKey: "YOUR_SUPABASE_ANON_KEY",
            openRouterAPIKey: "   ",
            bleSharedSecret: "YOUR_BLE_SHARED_SECRET",
            notionClientId: "  YOUR_NOTION_OAUTH_CLIENT_ID ",
            notionClientSecret: " $(NOTION_OAUTH_CLIENT_SECRET) ",
            taskadeClientId: "YOUR_TASKADE_OAUTH_CLIENT_ID",
            taskadeClientSecret: " $(TASKADE_OAUTH_CLIENT_SECRET) "
        )

        #expect(AppSecrets.supabaseConfig == nil)
        #expect(AppSecrets.openRouterAPIKey == nil)
        #expect(AppSecrets.bleSharedSecret == nil)
        #expect(AppSecrets.notionClientId == nil)
        #expect(AppSecrets.notionClientSecret == nil)
        #expect(AppSecrets.taskadeClientId == nil)
        #expect(AppSecrets.taskadeClientSecret == nil)

        AppSecrets.configure(
            supabaseURL: "https://example.supabase.co",
            supabaseAnonKey: "anon-key",
            openRouterAPIKey: "openrouter-key",
            bleSharedSecret: "ble-secret",
            notionClientId: "notion-client-id",
            notionClientSecret: "notion-client-secret",
            taskadeClientId: "taskade-client-id",
            taskadeClientSecret: "taskade-client-secret"
        )

        #expect(AppSecrets.supabaseConfig?.url == "https://example.supabase.co")
        #expect(AppSecrets.supabaseConfig?.anonKey == "anon-key")
        #expect(AppSecrets.openRouterAPIKey == "openrouter-key")
        #expect(AppSecrets.bleSharedSecret == "ble-secret")
        #expect(AppSecrets.notionClientId == "notion-client-id")
        #expect(AppSecrets.notionClientSecret == "notion-client-secret")
        #expect(AppSecrets.taskadeClientId == "taskade-client-id")
        #expect(AppSecrets.taskadeClientSecret == "taskade-client-secret")
    }

    private func repositoryRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // KiroleFeatureTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // KirolePackage
            .deletingLastPathComponent() // repository root
    }
}
