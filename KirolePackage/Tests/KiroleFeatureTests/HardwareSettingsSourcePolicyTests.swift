import Foundation
import Testing

@Suite("Hardware settings source policy")
struct HardwareSettingsSourcePolicyTests {
    @Test("Customer hardware settings expose the E-ink screen-size picker")
    func customerCanSelectHardwareScreenSize() throws {
        let source = try sourceFile(
            path: "KirolePackage/Sources/KiroleFeature/Views/Settings/SettingsBLESection.swift"
        )

        #expect(source.contains("screenSizeCard"))
        #expect(source.contains("Settings_BLEScreenSizePicker"))
        #expect(source.contains("bleService.hardwareScreenSize = newValue"))
    }

    @Test("Customer hardware settings hide the Display Scene status card")
    func customerHardwareSettingsOmitDisplaySceneStatusCard() throws {
        let source = try sourceFile(
            path: "KirolePackage/Sources/KiroleFeature/Views/Settings/SettingsBLESection.swift"
        )

        #expect(!source.contains("currentSceneCard"))
        #expect(!source.contains("Text(\"Display Scene\")"))
        #expect(!source.contains("scenes unlocked"))
    }

    @Test("Customer hardware settings can forget a paired device")
    func customerCanForgetPairedDevice() throws {
        let source = try sourceFile(
            path: "KirolePackage/Sources/KiroleFeature/Views/Settings/SettingsBLESection.swift"
        )

        #expect(source.contains("Forget Kirole Device"))
        #expect(source.contains("await bleService.clearTrustedDevices()"))
        #expect(source.contains("Settings_ForgetKiroleDevice"))
        #expect(source.contains("if hasStoredIdentity"))
        #expect(!source.contains("No Kirole device is remembered."))
        #expect(!source.contains(".disabled(!hasStoredIdentity)"))
    }

    @Test("Customer hardware settings refresh identity state after pairing")
    func customerPairingRefreshesIdentityState() throws {
        let source = try sourceFile(
            path: "KirolePackage/Sources/KiroleFeature/Views/Settings/SettingsBLESection.swift"
        )

        #expect(source.contains(".onChange(of: bleService.connectionState)"))
        #expect(source.contains("await refreshIdentityCounts()"))
        #expect(source.contains("bleService.connectionState.isConnected || trustedDeviceCount > 0"))
    }

    @Test("Internal focus tools observe picker dismissal without presenting another sheet")
    func internalFocusToolsDoNotDuplicatePickerSheet() throws {
        let source = try sourceFile(path: "Kirole/Internal/InternalSettingsSection.swift")

        #expect(source.contains(".onChange(of: guardService.isPickerPresented)"))
        #expect(source.contains("await testSessionCoordinator.resumeAfterPickerDismissal()"))
        #expect(!source.contains(".sheet("))
        #expect(!source.contains("pickerSheet"))
    }

    @Test("Internal tools do not duplicate customer hardware controls")
    func internalToolsDoNotDuplicateCustomerHardwareControls() throws {
        let source = try sourceFile(path: "Kirole/Internal/InternalSettingsSection.swift")

        #expect(!source.contains("screenSizeCard"))
        #expect(!source.contains("pairedDeviceCard"))
        #expect(!source.contains("Forget Kirole Device"))
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
