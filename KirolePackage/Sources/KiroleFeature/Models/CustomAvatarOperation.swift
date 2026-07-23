import Foundation

/// User-visible state for the single custom-avatar operation owned by `AppState`.
/// Transport completion and firmware persistence are deliberately separate phases.
public enum CustomAvatarOperationState: Sendable, Equatable {
    case idle
    case preparing
    case transferring(sentBytes: Int, totalBytes: Int)
    case validating
    case committing
    case erasing
    case success
    case interrupted(String)
    case failed(String)

    public var isInProgress: Bool {
        switch self {
        case .preparing, .transferring, .validating, .committing, .erasing:
            return true
        case .idle, .success, .interrupted, .failed:
            return false
        }
    }

    public var canCancel: Bool {
        switch self {
        case .preparing, .transferring, .validating:
            return true
        case .idle, .committing, .erasing, .success, .interrupted, .failed:
            return false
        }
    }
}

public enum CustomAvatarOperationKind: String, Sendable, Codable, Equatable {
    case apply
    case eraseExact
    case eraseAll
}

public enum PendingCustomAvatarPhase: String, Sendable, Codable, Equatable {
    case preparing
    case prepared
    case transferring
    case awaitingValidation
    case awaitingAbortResult
    case awaitingCommitResult
    case awaitingEraseResult
}

extension PendingCustomAvatarOperation {
    var requiresPriorityBLEFlush: Bool {
        kind == .eraseExact || kind == .eraseAll || phase == .awaitingAbortResult
    }
}

/// The active selection before an avatar operation starts. Identity is not changed until
/// firmware confirms `committed`, so this snapshot is both recovery evidence and rollback data.
public struct CustomAvatarSelectionSnapshot: Sendable, Codable, Equatable {
    public let builtInCharacter: CompanionCharacter
    public let customCompanionID: UUID?
    public let intimacyStage: IntimacyStage

    public init(
        builtInCharacter: CompanionCharacter,
        customCompanionID: UUID?,
        intimacyStage: IntimacyStage
    ) {
        self.builtInCharacter = builtInCharacter
        self.customCompanionID = customCompanionID
        self.intimacyStage = intimacyStage
    }

    public init(profile: UserProfile) {
        self.init(
            builtInCharacter: profile.companionCharacter,
            customCompanionID: profile.customCompanionId,
            intimacyStage: profile.intimacyStage
        )
    }
}

/// One durable avatar transaction. Image bytes stay in the two fixed candidate files rather
/// than being embedded in JSON; this keeps offline erase markers small and writes atomic.
public struct PendingCustomAvatarOperation: Sendable, Codable, Equatable {
    public var kind: CustomAvatarOperationKind
    public var phase: PendingCustomAvatarPhase
    public let operationID: UInt32
    public let avatarID: UUID?
    public let deviceID: UUID?
    public var fileCRC32: UInt32
    public var fileLength: Int
    public let candidateCompanion: CustomCompanion?
    public let candidatePreviewFileName: String?
    public let candidateImageFileName: String?
    public let oldSelection: CustomAvatarSelectionSnapshot
    public let startedAt: Date

    public init(
        kind: CustomAvatarOperationKind,
        phase: PendingCustomAvatarPhase,
        operationID: UInt32,
        avatarID: UUID?,
        deviceID: UUID?,
        fileCRC32: UInt32,
        fileLength: Int,
        candidateCompanion: CustomCompanion?,
        candidatePreviewFileName: String?,
        candidateImageFileName: String?,
        oldSelection: CustomAvatarSelectionSnapshot,
        startedAt: Date = Date()
    ) {
        self.kind = kind
        self.phase = phase
        self.operationID = operationID
        self.avatarID = avatarID
        self.deviceID = deviceID
        self.fileCRC32 = fileCRC32
        self.fileLength = fileLength
        self.candidateCompanion = candidateCompanion
        self.candidatePreviewFileName = candidatePreviewFileName
        self.candidateImageFileName = candidateImageFileName
        self.oldSelection = oldSelection
        self.startedAt = startedAt
    }
}

public enum CustomAvatarOperationError: LocalizedError, Sendable, Equatable {
    case deviceNotConnected
    case operationInProgress
    case companionNotFound
    case missingAvatarData
    case commitAlreadyStarted
    case confirmationTimedOut
    case wrongDevice
    case deviceRejected(String)

    public var errorDescription: String? {
        switch self {
        case .deviceNotConnected:
            return "Connect your Kirole device before changing its companion image."
        case .operationInProgress:
            return "Another companion image operation is still in progress."
        case .companionNotFound:
            return "This custom companion no longer exists."
        case .missingAvatarData:
            return "The companion image is missing or invalid."
        case .commitAlreadyStarted:
            return "The device is already applying the image and can no longer cancel."
        case .confirmationTimedOut:
            return "The device did not confirm the companion image operation."
        case .wrongDevice:
            return "Reconnect the Kirole device that started this companion image operation."
        case .deviceRejected(let reason):
            return reason
        }
    }
}
