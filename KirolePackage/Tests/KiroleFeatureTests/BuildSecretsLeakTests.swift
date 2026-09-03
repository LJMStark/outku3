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
        #expect(!contents.contains("OAUTH_CLIENT_SECRET"))
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
            #expect(!contents.contains("OAUTH_CLIENT_SECRET"))
            #expect(!contents.contains("OAUTH_CLIENT_ID"))
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
                bleSharedSecret: nil
            )
        }

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

    // The BLE secure channel is gated by firmware readiness, not by release channel
    // (BLE protocol §3.3 / §4.17, AGENTS.md "Release Channel Policy"). The switch is
    // BLE_SECURE_CHANNEL_ENABLED; these tests pin both of its sides.

    @Test(
        "Every configuration ships plaintext BLE while the firmware-readiness switch is off",
        arguments: ["InternalRelease", "AppStoreRelease"]
    )
    func secureChannelDisabledClearsBLESharedSecret(configuration: String) throws {
        let result = try runBuildSecretsGenerator(
            configuration: configuration,
            bleSharedSecret: "must-not-enter-any-build",
            secureChannelEnabled: "0"
        )
        let generatedSecrets = try #require(result.generatedSecrets)

        #expect(result.terminationStatus == 0)
        #expect(generatedSecrets.contains("static let bleSharedSecret = \"\""))
        #expect(!generatedSecrets.contains("must-not-enter-any-build"))
    }

    /// An absent switch must behave like `0`: firmware that was never handed a secret
    /// cannot answer a signed channel, so plaintext is the safe default.
    @Test("A missing firmware-readiness switch defaults to plaintext BLE")
    func absentSecureChannelSwitchDefaultsToPlaintext() throws {
        let result = try runBuildSecretsGenerator(
            configuration: "AppStoreRelease",
            bleSharedSecret: "must-not-enter-any-build",
            secureChannelEnabled: nil
        )
        let generatedSecrets = try #require(result.generatedSecrets)

        #expect(result.terminationStatus == 0)
        #expect(generatedSecrets.contains("static let bleSharedSecret = \"\""))
    }

    @Test("AppStoreRelease keeps the configured BLE shared secret once the switch is on")
    func appStoreReleaseEmbedsBLESharedSecret() throws {
        let result = try runBuildSecretsGenerator(
            configuration: "AppStoreRelease",
            bleSharedSecret: "app-store-security-secret",
            secureChannelEnabled: "1"
        )
        let generatedSecrets = try #require(result.generatedSecrets)

        #expect(result.terminationStatus == 0)
        #expect(generatedSecrets.contains(
            "static let bleSharedSecret = \"app-store-security-secret\""
        ))
    }

    @Test("AppStoreRelease device builds fail closed when the switch is on but the secret is empty")
    func appStoreReleaseRejectsMissingBLESharedSecret() throws {
        let result = try runBuildSecretsGenerator(
            configuration: "AppStoreRelease",
            bleSharedSecret: "",
            secureChannelEnabled: "1"
        )

        #expect(result.terminationStatus != 0)
        #expect(result.generatedSecrets == nil)
    }

    @Test("Xcode always regenerates secrets when switching release channels")
    func buildSecretsPhaseAlwaysRuns() throws {
        let projectURL = repositoryRootURL().appending(path: "Kirole.xcodeproj/project.pbxproj")
        let contents = try String(contentsOf: projectURL, encoding: .utf8)
        let phaseStart = try #require(contents.range(
            of: "8BF0E0012EF0000000A0C001 /* Generate Build Secrets */ = {"
        ))
        let phaseEnd = try #require(contents.range(
            of: "\n\t\t};",
            range: phaseStart.upperBound..<contents.endIndex
        ))
        let phase = contents[phaseStart.lowerBound..<phaseEnd.upperBound]

        #expect(phase.contains("alwaysOutOfDate = 1;"))
    }

    @Test("BLE handshake failures remain retryable instead of blacklisting the device")
    func handshakeFailureDoesNotPersistDeviceBlacklist() throws {
        let serviceURL = repositoryRootURL().appending(
            path: "KirolePackage/Sources/KiroleFeature/Core/Services/BLEService.swift"
        )
        let contents = try String(contentsOf: serviceURL, encoding: .utf8)
        let handlerStart = try #require(contents.range(
            of: "ErrorReporter.log(error, context: \"BLEService.didUpdateValueFor\")"
        ))
        let handlerEnd = try #require(contents.range(
            of: "\n            }\n        }\n    }\n}",
            range: handlerStart.upperBound..<contents.endIndex
        ))
        let handler = contents[handlerStart.lowerBound..<handlerEnd.upperBound]

        #expect(handler.contains("cancelConnectionAttempt("))
        #expect(handler.contains("cancelPeripheralConnection("))
        #expect(!handler.contains("deviceIdentityStore.block("))
    }

    /// `secureChannelEnabled: nil` omits the variable entirely, exercising the
    /// "switch not configured yet" path (must default to plaintext).
    private func runBuildSecretsGenerator(
        configuration: String,
        bleSharedSecret: String,
        secureChannelEnabled: String?
    ) throws -> (terminationStatus: Int32, generatedSecrets: String?) {
        let fileManager = FileManager.default
        let temporaryRoot = fileManager.temporaryDirectory
            .appending(path: "BuildSecretsLeakTests.\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: temporaryRoot) }

        try fileManager.createDirectory(
            at: temporaryRoot.appending(path: "Config"),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: temporaryRoot.appending(path: "Kirole"),
            withIntermediateDirectories: true
        )
        try "BLE_SHARED_SECRET =\n".write(
            to: temporaryRoot.appending(path: "Config/Secrets.xcconfig"),
            atomically: true,
            encoding: .utf8
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            repositoryRootURL()
                .appending(path: "Config/scripts-generate-build-secrets.sh")
                .path()
        ]
        var overrides = [
            "SRCROOT": temporaryRoot.path(),
            "CONFIGURATION": configuration,
            "PLATFORM_NAME": "iphoneos",
            "BLE_SHARED_SECRET": bleSharedSecret,
        ]
        // The inherited environment must not leak a real switch value into the
        // "switch absent" case, so remove the key rather than passing it empty.
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "BLE_SECURE_CHANNEL_ENABLED")
        if let secureChannelEnabled {
            overrides["BLE_SECURE_CHANNEL_ENABLED"] = secureChannelEnabled
        }
        process.environment = environment.merging(overrides) { _, override in override }

        try process.run()
        process.waitUntilExit()

        let generatedURL = temporaryRoot.appending(path: "Kirole/BuildSecrets.generated.swift")
        let generatedSecrets = fileManager.fileExists(atPath: generatedURL.path())
            ? try String(contentsOf: generatedURL, encoding: .utf8)
            : nil
        return (process.terminationStatus, generatedSecrets)
    }

    private func repositoryRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // KiroleFeatureTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // KirolePackage
            .deletingLastPathComponent() // repository root
    }
}
