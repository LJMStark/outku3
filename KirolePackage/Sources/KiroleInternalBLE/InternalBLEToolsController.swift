#if KIROLE_INTERNAL || KIROLE_INTERNAL_BLE_MODULE
import Foundation
@_spi(KiroleInternal) import KiroleFeature

@MainActor
final class InternalBLEToolsController: BLEInternalToolsControlling {
    static let shared = InternalBLEToolsController(
        wifiDebugCoordinator: .shared,
        shippingModeCoordinator: .shared
    )

    private let wifiDebugCoordinator: BLEWiFiDebugCoordinator
    private let shippingModeCoordinator: BLEShippingModeCoordinator

    private init(
        wifiDebugCoordinator: BLEWiFiDebugCoordinator,
        shippingModeCoordinator: BLEShippingModeCoordinator
    ) {
        self.wifiDebugCoordinator = wifiDebugCoordinator
        self.shippingModeCoordinator = shippingModeCoordinator
    }

    static func install() {
        BLEInternalToolsRuntime.install(shared)
    }

    static func installForTesting(
        wifiDebugCoordinator: BLEWiFiDebugCoordinator,
        shippingModeCoordinator: BLEShippingModeCoordinator? = nil
    ) {
        BLEInternalToolsRuntime.install(
            InternalBLEToolsController(
                wifiDebugCoordinator: wifiDebugCoordinator,
                shippingModeCoordinator: shippingModeCoordinator ?? .shared
            )
        )
    }

    static func uninstallForTesting() {
        BLEInternalToolsRuntime.uninstall()
    }

    var blocksAutomaticBLEWork: Bool {
        shippingModeCoordinator.blocksAutomaticBLEWork
    }

    var requiresBLEConnection: Bool {
        wifiDebugCoordinator.requiresBLEConnection
            || shippingModeCoordinator.requiresCurrentConnection
    }

    var expectsDeviceDisconnect: Bool {
        shippingModeCoordinator.expectsDeviceDisconnect
    }

    func handleDeviceReconnected() {
        shippingModeCoordinator.handleDeviceReconnected()
    }

    func handleConnectionEnded(intentional: Bool) {
        guard shippingModeCoordinator.expectsDeviceDisconnect else { return }
        if intentional {
            shippingModeCoordinator.handleUnconfirmedDisconnect()
        } else {
            shippingModeCoordinator.handleExpectedDisconnect()
        }
    }

    func handleLinkReset() {
        wifiDebugCoordinator.handleDisconnected()
    }

    func connectionDidBecomeReady() async {
        await wifiDebugCoordinator.queryStatus()
    }

    func consumeInboundMessage(_ message: BLEReceivedMessage) -> Bool {
        guard message.type == BLEDataType.wifiDebugMode.rawValue else { return false }
        wifiDebugCoordinator.handleResponse(payload: message.payload)
        return true
    }
}
#endif
