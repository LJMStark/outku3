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
    }

    @Test("AppSecrets ignores placeholder values and preserves valid values")
    func appSecretsNormalization() {
        AppSecrets.configure(
            supabaseURL: "  $(SUPABASE_URL)  ",
            supabaseAnonKey: "YOUR_SUPABASE_ANON_KEY",
            openRouterAPIKey: "   ",
            bleSharedSecret: "YOUR_BLE_SHARED_SECRET"
        )

        #expect(AppSecrets.supabaseConfig == nil)
        #expect(AppSecrets.openRouterAPIKey == nil)
        #expect(AppSecrets.bleSharedSecret == nil)

        AppSecrets.configure(
            supabaseURL: "https://example.supabase.co",
            supabaseAnonKey: "anon-key",
            openRouterAPIKey: "openrouter-key",
            bleSharedSecret: "ble-secret"
        )

        #expect(AppSecrets.supabaseConfig?.url == "https://example.supabase.co")
        #expect(AppSecrets.supabaseConfig?.anonKey == "anon-key")
        #expect(AppSecrets.openRouterAPIKey == "openrouter-key")
        #expect(AppSecrets.bleSharedSecret == "ble-secret")
    }

    private func repositoryRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // KiroleFeatureTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // KirolePackage
            .deletingLastPathComponent() // repository root
    }
}
