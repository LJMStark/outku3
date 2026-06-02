import Foundation

public enum ExternalEditingError: LocalizedError, Sendable {
    case missingRemoteIdentifier(String)
    case integrationReadOnly(String)

    public var errorDescription: String? {
        switch self {
        case .missingRemoteIdentifier(let platform):
            return "This \(platform) item is missing its remote ID. Refresh sync and try again."
        case .integrationReadOnly(let platform):
            return "\(platform) is read-only in Kirole. Edit it in \(platform) instead."
        }
    }
}
