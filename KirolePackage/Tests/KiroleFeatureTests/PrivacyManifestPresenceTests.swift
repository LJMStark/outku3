import Foundation
import Testing

@Suite("Privacy manifest presence")
struct PrivacyManifestPresenceTests {
    @Test("App target declares UserDefaults and collected account data")
    func appPrivacyManifestDeclaresRequiredReasonAPIs() throws {
        let source = try sourceFile(path: "Kirole/PrivacyInfo.xcprivacy")

        #expect(declaresNoTracking(source))
        #expect(source.contains("NSPrivacyAccessedAPICategoryUserDefaults"))
        #expect(source.contains("CA92.1"))
        #expect(source.contains("NSPrivacyCollectedDataTypeEmailAddress"))
        #expect(source.contains("NSPrivacyCollectedDataTypeCoarseLocation"))
        #expect(source.contains("NSPrivacyCollectedDataTypeOtherUserContent"))
    }

    @Test("DeviceActivity extension declares UserDefaults only")
    func monitorPrivacyManifestDeclaresUserDefaults() throws {
        let source = try sourceFile(path: "KiroleDeviceActivityMonitor/PrivacyInfo.xcprivacy")

        #expect(declaresNoTracking(source))
        #expect(source.contains("NSPrivacyAccessedAPICategoryUserDefaults"))
        #expect(source.contains("CA92.1"))
    }

    @Test("Feature package declares UserDefaults for LocalStorage")
    func packagePrivacyManifestDeclaresUserDefaults() throws {
        let source = try sourceFile(
            path: "KirolePackage/Sources/KiroleFeature/PrivacyInfo.xcprivacy"
        )

        #expect(declaresNoTracking(source))
        #expect(source.contains("NSPrivacyAccessedAPICategoryUserDefaults"))
        #expect(source.contains("CA92.1"))
    }

    private func declaresNoTracking(_ source: String) -> Bool {
        let compact = source.replacingOccurrences(of: "\t", with: "")
        return compact.contains("NSPrivacyTracking</key>\n<false/>")
            && !compact.contains("NSPrivacyTracking</key>\n<true/>")
    }

    private func sourceFile(path: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appending(path: path),
            encoding: .utf8
        )
    }
}
