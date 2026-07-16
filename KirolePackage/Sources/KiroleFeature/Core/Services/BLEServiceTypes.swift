import Foundation

public struct BLEDevice: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let rssi: Int
    public var isConnected: Bool

    public init(id: UUID, name: String, rssi: Int, isConnected: Bool = false) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.isConnected = isConnected
    }
}

public enum BLEConnectionState: Sendable, Equatable {
    case disconnected
    case scanning
    case connecting
    case connected
    case error(String)

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

public enum BLESecurityMode: Sendable, Equatable {
    case development
    case secure

    public var displayTitle: String {
        switch self {
        case .development:
            return "Development Mode"
        case .secure:
            return "Secure Mode"
        }
    }

    public var detailText: String {
        switch self {
        case .development:
            return "Unsigned BLE transport is enabled for pre-integration development."
        case .secure:
            return "BLE v2 secure handshake and signed envelopes are enabled."
        }
    }

    public var sourceText: String {
        switch self {
        case .development:
            return "Source: BLE_SHARED_SECRET not configured"
        case .secure:
            return "Source: BLE_SHARED_SECRET configured"
        }
    }
}

public enum BLEError: LocalizedError, Sendable {
    case bluetoothNotAvailable
    case deviceNotFound
    case unauthorizedDevice
    case connectionTimeout
    case connectionFailed(Error?)
    case notConnected
    case serviceNotFound
    case characteristicNotFound
    case writeFailed(Error?)
    case securityHandshakeFailed(String)
    case disconnected
    case writeTimeout
    case scanAlreadyInProgress
    case connectionInProgress

    public var errorDescription: String? {
        switch self {
        case .bluetoothNotAvailable:
            return "Bluetooth is not available"
        case .deviceNotFound:
            return "Device not found"
        case .unauthorizedDevice:
            return "Unauthorized BLE device"
        case .connectionTimeout:
            return "Connection timed out"
        case .connectionFailed(let error):
            return "Connection failed: \(error?.localizedDescription ?? "Unknown error")"
        case .notConnected:
            return "Not connected to device"
        case .serviceNotFound:
            return "BLE service not found"
        case .characteristicNotFound:
            return "BLE characteristic not found"
        case .writeFailed(let error):
            return "Write failed: \(error?.localizedDescription ?? "Unknown error")"
        case .securityHandshakeFailed(let reason):
            return "BLE security handshake failed: \(reason)"
        case .disconnected:
            return "Device disconnected"
        case .writeTimeout:
            return "BLE write timed out"
        case .scanAlreadyInProgress:
            return "A BLE scan is already in progress"
        case .connectionInProgress:
            return "A BLE connection is already in progress"
        }
    }
}
