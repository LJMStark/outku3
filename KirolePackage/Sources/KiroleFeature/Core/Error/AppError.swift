import Foundation

public enum AppError: LocalizedError, Sendable {
    case persistence(operation: String, target: String, underlying: String)
    case sync(component: String, underlying: String)
    case configuration(String)
    case bleSecurity(String)
    case unsupportedProtocol(version: UInt8)
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .persistence(let operation, let target, let underlying):
            return "Persistence failed (\(operation), \(target)): \(underlying)"
        case .sync(let component, let underlying):
            return "Sync failed (\(component)): \(underlying)"
        case .configuration(let message):
            return "Configuration error: \(message)"
        case .bleSecurity(let message):
            return "BLE security error: \(message)"
        case .unsupportedProtocol(let version):
            return "Unsupported BLE protocol version: \(version)"
        case .unknown(let message):
            return message
        }
    }
}
