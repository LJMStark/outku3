import Foundation

enum BLEConnectionAttemptPhase: Equatable, Sendable {
    case awaitingLink
    case discoveringServices
    case discoveringCharacteristics
    case enablingNotifications
    case handshaking
    case ready
    case cancelling
}

enum BLEConnectionAttemptOrigin: Equatable, Sendable {
    case requested
    case pendingReconnect

    var usesLinkTimeout: Bool {
        self == .requested
    }

    var startsSetupRetryRoundAfterReadinessFailure: Bool {
        self == .pendingReconnect
    }
}

enum BLERequestedCancellationDisposition: Equatable, Sendable {
    case ignore
    case finishLocally
    case cancelPeripheral
}

struct BLEConnectionAttempt: Equatable, Sendable {
    let generation: UInt64
    let peripheralID: UUID
    let origin: BLEConnectionAttemptOrigin
    var phase: BLEConnectionAttemptPhase
    var didEstablishLink = false
    var suppressesAutomaticRecovery = false

    var shouldStartSetupRetryRound: Bool {
        origin.startsSetupRetryRoundAfterReadinessFailure
            && !suppressesAutomaticRecovery
    }

    var keepsRetryRoundActiveAfterFailure: Bool {
        !suppressesAutomaticRecovery
    }

    /// Before the continuation is installed, no CoreBluetooth request exists and therefore no
    /// delegate callback is guaranteed. After installation, the delegate owns final cleanup.
    func requestedCancellationDisposition(
        completionPending: Bool
    ) -> BLERequestedCancellationDisposition {
        guard origin == .requested,
              phase != .ready,
              phase != .cancelling else { return .ignore }
        return completionPending ? .cancelPeripheral : .finishLocally
    }

    /// Setup failures stay inside the ten-attempt round. Only failures on an already-ready
    /// transport may be exposed immediately as a connection error.
    var exposesTransportErrorImmediately: Bool {
        phase == .ready
    }

    /// A normal setup cancellation finishes through the attempt continuation. DeviceWake timeout
    /// cancellation is different: didDisconnect must continue into the known-peripheral recovery
    /// branch that owns the next retry round.
    func shouldFinishAsSetupFailure(hasDeviceWakeRecovery: Bool) -> Bool {
        phase != .ready && !hasDeviceWakeRecovery
    }

    func accepts(
        generation: UInt64,
        peripheralID: UUID,
        phase expectedPhase: BLEConnectionAttemptPhase
    ) -> Bool {
        self.generation == generation
            && self.peripheralID == peripheralID
            && phase == expectedPhase
    }
}

struct BLEConnectionCompletionLatch {
    private var completion: ((Result<Void, BLEError>) -> Void)?

    var isPending: Bool { completion != nil }

    mutating func install(_ completion: @escaping (Result<Void, BLEError>) -> Void) {
        precondition(self.completion == nil)
        self.completion = completion
    }

    @discardableResult
    mutating func resolve(_ result: Result<Void, BLEError>) -> Bool {
        guard let completion else { return false }
        self.completion = nil
        completion(result)
        return true
    }
}

enum BLEConnectionAttemptTimeout {
    static let link: Duration = .seconds(15)
    static let readiness: Duration = .seconds(15)
    static let handshake: Duration = .seconds(5)
}

enum BLEConnectionRetryPolicy {
    static let maximumAttempts = 10
    static let delays: [Duration] = [
        .seconds(1),
        .seconds(2),
        .seconds(4),
        .seconds(8),
        .seconds(15),
        .seconds(30),
        .seconds(30),
        .seconds(30),
        .seconds(30),
    ]

    static func delay(afterFailedAttempt attempt: Int) -> Duration? {
        guard attempt >= 1, attempt < maximumAttempts else { return nil }
        return delays[attempt - 1]
    }
}

enum BLEConnectionRetryPublicationPolicy {
    static func shouldPublishFinalError(
        ownsRound: Bool,
        isIntentionalDisconnect: Bool
    ) -> Bool {
        ownsRound && !isIntentionalDisconnect
    }
}

enum BLEPostDisconnectRecoveryOwner: Equatable, Sendable {
    case none
    case bluetoothPowerCycle
    case deviceWakeTimeout
}

enum BLEPostDisconnectRecoveryPolicy {
    static func owner(
        shouldResumeAfterBluetoothPowerCycle: Bool,
        hasDeviceWakeRecoveryPeripheral: Bool
    ) -> BLEPostDisconnectRecoveryOwner {
        if shouldResumeAfterBluetoothPowerCycle { return .bluetoothPowerCycle }
        if hasDeviceWakeRecoveryPeripheral { return .deviceWakeTimeout }
        return .none
    }
}

@MainActor
enum BLEConnectionRetryRunner {
    static func run(
        startingAttempt: Int = 1,
        connect: @escaping @MainActor () async throws -> Void,
        wait: @escaping @MainActor (Duration) async throws -> Void,
        willWait: @escaping @MainActor (Duration) -> Void = { _ in },
        didWait: @escaping @MainActor () -> Void = {},
        didCancel: @escaping @MainActor () -> Void = {},
        shouldStop: @escaping @MainActor () -> Bool = { false }
    ) async throws {
        precondition((1...BLEConnectionRetryPolicy.maximumAttempts).contains(startingAttempt))
        var lastError: BLEError = .connectionFailed(nil)

        for attemptNumber in startingAttempt...BLEConnectionRetryPolicy.maximumAttempts {
            do {
                try Task.checkCancellation()
                try await connect()
                return
            } catch is CancellationError {
                didCancel()
                throw CancellationError()
            } catch let error as BLEError {
                switch error {
                case .unauthorizedDevice, .connectionInProgress, .bluetoothNotAvailable,
                     .shippingModeActive:
                    throw error
                default:
                    lastError = error
                }
            } catch {
                lastError = .connectionFailed(error)
            }

            guard !shouldStop() else { throw BLEError.disconnected }
            guard let delay = BLEConnectionRetryPolicy.delay(afterFailedAttempt: attemptNumber) else {
                break
            }
            willWait(delay)
            do {
                try await wait(delay)
            } catch is CancellationError {
                didCancel()
                throw CancellationError()
            }
            guard !shouldStop() else { throw BLEError.disconnected }
            didWait()
        }

        throw lastError
    }
}

struct BLEPreReadyMessageBuffer {
    enum AppendResult: Equatable {
        case accepted
        case overflow
    }

    private static let maximumMessageCount = 8
    private static let maximumByteCount = 8 * 1024

    private var messages: [BLEReceivedMessage] = []
    private var byteCount = 0

    mutating func append(_ message: BLEReceivedMessage) -> AppendResult {
        let nextCount = messages.count + 1
        let nextBytes = byteCount + message.payload.count + 1
        guard nextCount <= Self.maximumMessageCount,
              nextBytes <= Self.maximumByteCount else {
            return .overflow
        }
        messages.append(message)
        byteCount = nextBytes
        return .accepted
    }

    mutating func drain() -> [BLEReceivedMessage] {
        let drained = messages
        messages = []
        byteCount = 0
        return drained
    }

    mutating func removeAll() {
        messages = []
        byteCount = 0
    }
}
