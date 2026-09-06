import Foundation

public enum MicrosoftSyncStateIOOperation: String, Sendable {
    case loadState
    case loadOutbox
    case saveOutbox
    case saveState
}

public struct MicrosoftSyncStateIOFailure: LocalizedError, Sendable {
    public let operation: MicrosoftSyncStateIOOperation
    public let result: MicrosoftSyncResult
    public let underlyingDescription: String

    public init(
        operation: MicrosoftSyncStateIOOperation,
        result: MicrosoftSyncResult,
        underlyingDescription: String
    ) {
        self.operation = operation
        self.result = result
        self.underlyingDescription = underlyingDescription
    }

    public var errorDescription: String? {
        "Microsoft sync state I/O failed during \(operation.rawValue): \(underlyingDescription)"
    }
}

public enum MicrosoftSyncError: LocalizedError, Sendable {
    case fullSyncFailed(MicrosoftSyncResult)
    case stateIOFailed(MicrosoftSyncStateIOFailure)
    case missingRemoteIdentifier
    case accountMismatch
    case staleOperation
    case accountTransitionInProgress

    public var errorDescription: String? {
        switch self {
        case .fullSyncFailed(let result):
            return result.warnings.isEmpty
                ? "Microsoft sync failed"
                : result.warnings.joined(separator: " | ")
        case .stateIOFailed(let failure):
            return failure.localizedDescription
        case .missingRemoteIdentifier:
            return "Microsoft task is missing its account, list, or task identifier"
        case .accountMismatch:
            return "Microsoft task belongs to a different signed-in account"
        case .staleOperation:
            return "Microsoft sync was cancelled because the active account changed"
        case .accountTransitionInProgress:
            return "Microsoft account authorization or disconnect is already in progress"
        }
    }

    static func isPermanentTodoWriteFailure(_ error: any Error) -> Bool {
        guard case .httpError(let statusCode, _) = error as? MicrosoftGraphError else {
            return false
        }
        return statusCode == 403 || statusCode == 404
    }
}
