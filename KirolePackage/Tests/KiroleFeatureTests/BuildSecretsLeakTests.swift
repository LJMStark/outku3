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
        }
    }

    @Test("AppSecrets ignores placeholder values and preserves valid values")
    func appSecretsNormalization() {
        AppSecrets.configure(
            supabaseURL: "  $(SUPABASE_URL)  ",
            supabaseAnonKey: "YOUR_SUPABASE_ANON_KEY",
            openRouterAPIKey: "   ",
            bleSharedSecret: "YOUR_BLE_SHARED_SECRET",
            notionClientId: "  YOUR_NOTION_OAUTH_CLIENT_ID ",
            taskadeClientId: "YOUR_TASKADE_OAUTH_CLIENT_ID"
        )

        #expect(AppSecrets.supabaseConfig == nil)
        #expect(AppSecrets.openRouterAPIKey == nil)
        #expect(AppSecrets.bleSharedSecret == nil)
        #expect(AppSecrets.notionClientId == nil)
        #expect(AppSecrets.taskadeClientId == nil)

        AppSecrets.configure(
            supabaseURL: "https://example.supabase.co",
            supabaseAnonKey: "anon-key",
            openRouterAPIKey: "openrouter-key",
            bleSharedSecret: "ble-secret",
            notionClientId: "notion-client-id",
            taskadeClientId: "taskade-client-id"
        )

        #expect(AppSecrets.supabaseConfig?.url == "https://example.supabase.co")
        #expect(AppSecrets.supabaseConfig?.anonKey == "anon-key")
        #expect(AppSecrets.openRouterAPIKey == "openrouter-key")
        #expect(AppSecrets.bleSharedSecret == "ble-secret")
        #expect(AppSecrets.notionClientId == "notion-client-id")
        #expect(AppSecrets.taskadeClientId == "taskade-client-id")
    }

    private func repositoryRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // KiroleFeatureTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // KirolePackage
            .deletingLastPathComponent() // repository root
    }
}
