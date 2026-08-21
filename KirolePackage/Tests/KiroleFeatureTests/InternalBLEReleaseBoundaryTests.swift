import Foundation
import Testing

@Suite("Internal BLE release boundary")
struct InternalBLEReleaseBoundaryTests {
    @Test("factory BLE implementations are absent from the customer feature target")
    func factoryImplementationsAreIsolated() throws {
        let root = repositoryRoot
        let packageManifest = try read(root.appendingPathComponent("KirolePackage/Package.swift"))
        let bleService = try read(
            root.appendingPathComponent(
                "KirolePackage/Sources/KiroleFeature/Core/Services/BLEService.swift"
            )
        )
        let appBoundary = try read(root.appendingPathComponent("Kirole/InternalBuildBoundary.swift"))
        let project = try read(root.appendingPathComponent("Kirole.xcodeproj/project.pbxproj"))
        let internalController = try read(
            root.appendingPathComponent(
                "KirolePackage/Sources/KiroleInternalBLE/InternalBLEToolsController.swift"
            )
        )
        let releaseGate = try read(root.appendingPathComponent("scripts/verify-release-boundary.sh"))

        #expect(packageManifest.contains("KiroleInternalBLE"))
        #expect(
            !FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "KirolePackage/Sources/KiroleFeature/Core/Services/BLEWiFiDebugCoordinator.swift"
                ).path
            )
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "KirolePackage/Sources/KiroleFeature/Core/Services/BLEShippingModeCoordinator.swift"
                ).path
            )
        )
        #expect(bleService.contains("BLEInternalToolsRuntime"))
        #expect(!bleService.contains("BLEWiFiDebugCoordinator"))
        #expect(!bleService.contains("BLEShippingModeCoordinator"))
        #expect(!bleService.contains("sendWiFiDebugCommand"))
        #expect(!bleService.contains("sendShippingModeCommand"))
        #expect(appBoundary.contains("InternalBLEToolsController.install()"))
        #expect(project.contains("BLEWiFiDebugCoordinator.swift in Sources"))
        #expect(project.contains("BLEShippingModeCoordinator.swift in Sources"))
        #expect(project.contains("InternalBLEToolsController.swift in Sources"))
        #expect(internalController.hasPrefix("#if KIROLE_INTERNAL || KIROLE_INTERNAL_BLE_MODULE"))
        #expect(releaseGate.contains("Kirole.BLEWiFiDebugCoordinator"))
        #expect(releaseGate.contains("Kirole.BLEShippingModeCoordinator"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}
