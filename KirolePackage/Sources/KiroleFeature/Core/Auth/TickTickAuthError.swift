import Foundation

public enum TickTickAuthError: LocalizedError, Sendable, Equatable {
    case invalidConfiguration
    case secureBackendRequired
    case unsupportedRegion
    case unsupportedSystemVersion
    case kiroleSignInRequired
    case invalidURL
    case invalidCallback
    case missingCallback
    case notAuthenticated
    case credentialDeletionFailed
    case reauthorizationRequired
    case authorizationExpired
    case authorizationConflict
    case deliveryAcknowledgementFailed
    case rateLimited
    case regionMismatch
    case accountMismatch
    case credentialOperationInvalidated
    case serverCleanupPending
    case invalidResponse
    case backendRejected(status: Int, code: String)
    case providerRejected

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "TickTick OAuth server configuration is incomplete"
        case .secureBackendRequired: "TickTick connection is unavailable until the secure OAuth server is deployed"
        case .unsupportedRegion: "This TickTick service region is not available yet"
        case .unsupportedSystemVersion: "TickTick sign-in requires iOS 17.4 or later"
        case .kiroleSignInRequired: "Sign in to Kirole before connecting TickTick"
        case .invalidURL: "TickTick OAuth URL is invalid"
        case .invalidCallback: "TickTick returned an unexpected OAuth result"
        case .missingCallback: "TickTick did not return an OAuth result"
        case .notAuthenticated: "TickTick is not connected"
        case .credentialDeletionFailed: "TickTick credentials could not be removed"
        case .reauthorizationRequired: "TickTick authorization expired; reconnect the account"
        case .authorizationExpired: "TickTick authorization expired before it could finish"
        case .authorizationConflict: "This TickTick authorization was already used or replaced"
        case .deliveryAcknowledgementFailed: "TickTick connected, but secure token delivery could not be confirmed; try again"
        case .rateLimited: "Too many TickTick connection attempts; try again later"
        case .regionMismatch: "TickTick returned data for the wrong service region"
        case .accountMismatch: "This TickTick connection belongs to a different Kirole account"
        case .credentialOperationInvalidated: "This TickTick credential operation is no longer current"
        case .serverCleanupPending: "TickTick was removed from this device; server cleanup will expire automatically"
        case .invalidResponse: "TickTick OAuth server returned an invalid response"
        case .backendRejected(let status, let code): "TickTick OAuth server rejected the request (HTTP \(status), \(code))"
        case .providerRejected: "TickTick authorization was not approved"
        }
    }
}
