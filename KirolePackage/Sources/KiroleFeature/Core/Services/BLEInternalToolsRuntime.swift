import Foundation

/// Internal TestFlight installs an implementation at app startup. App Store builds leave this
/// empty, so factory/debug BLE behavior is a no-op without adding branches to normal BLE flows.
@_spi(KiroleInternal)
@MainActor
public protocol BLEInternalToolsControlling: AnyObject {
    var blocksAutomaticBLEWork: Bool { get }
    var requiresBLEConnection: Bool { get }
    var expectsDeviceDisconnect: Bool { get }

    func handleDeviceReconnected()
    func handleConnectionEnded(intentional: Bool)
    func handleLinkReset()
    func connectionDidBecomeReady() async
    func consumeInboundMessage(_ message: BLEReceivedMessage) -> Bool
}

@_spi(KiroleInternal)
@MainActor
public enum BLEInternalToolsRuntime {
    private static var controller: (any BLEInternalToolsControlling)?

    public static var blocksAutomaticBLEWork: Bool {
        controller?.blocksAutomaticBLEWork ?? false
    }

    public static var requiresBLEConnection: Bool {
        controller?.requiresBLEConnection ?? false
    }

    public static var expectsDeviceDisconnect: Bool {
        controller?.expectsDeviceDisconnect ?? false
    }

    public static func install(_ controller: any BLEInternalToolsControlling) {
        self.controller = controller
    }

    public static func uninstall() {
        controller = nil
    }

    public static func handleDeviceReconnected() {
        controller?.handleDeviceReconnected()
    }

    public static func handleConnectionEnded(intentional: Bool) {
        controller?.handleConnectionEnded(intentional: intentional)
    }

    public static func handleLinkReset() {
        controller?.handleLinkReset()
    }

    public static func connectionDidBecomeReady() async {
        await controller?.connectionDidBecomeReady()
    }

    public static func consumeInboundMessage(_ message: BLEReceivedMessage) -> Bool {
        controller?.consumeInboundMessage(message) ?? false
    }
}
