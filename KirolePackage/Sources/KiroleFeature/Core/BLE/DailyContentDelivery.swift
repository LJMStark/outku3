import Foundation

enum DailyContentDeliveryError: LocalizedError, Sendable, Equatable {
    case sourceChanged
    case acknowledgementMismatch
    case acknowledgementTimedOut
    case rejected(DailyContentCommitResult)

    var errorDescription: String? {
        switch self {
        case .sourceChanged:
            "Daily-content source changed while preparing the transaction"
        case .acknowledgementMismatch:
            "Daily-content acknowledgement did not match the frozen transaction"
        case .acknowledgementTimedOut:
            "Daily-content commit acknowledgement timed out"
        case .rejected(let result):
            "Daily-content commit was rejected: \(result)"
        }
    }
}

/// Calls the sender with the same immutable transaction at most twice. Each call starts a new BLE
/// message at sequence zero; a half-written first attempt is never resumed.
@MainActor
struct DailyContentDeliveryRetrier {
    typealias Sender = @MainActor (DailyContentTransaction) async throws
        -> DailyContentCommitAcknowledgement
    typealias Sleeper = @MainActor (Duration) async throws -> Void

    private let retrySleeper: Sleeper

    init(retrySleeper: @escaping Sleeper = { try await Task.sleep(for: $0) }) {
        self.retrySleeper = retrySleeper
    }

    func deliver(
        _ transaction: DailyContentTransaction,
        sender: Sender
    ) async throws -> DailyContentCommitAcknowledgement {
        let expected = try DailyContentCodec.committedState(for: transaction)
        var lastError: (any Error)?
        for attempt in 1...2 {
            do {
                let acknowledgement = try await sender(transaction)
                guard acknowledgement.version == expected.version,
                      acknowledgement.contentCRC32 == expected.contentCRC32 else {
                    throw DailyContentDeliveryError.acknowledgementMismatch
                }
                guard acknowledgement.result == .committed else {
                    throw DailyContentDeliveryError.rejected(acknowledgement.result)
                }
                return acknowledgement
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as BLEPresentationDestinationError {
                throw error
            } catch {
                lastError = error
            }
            if attempt == 1 {
                try await retrySleeper(.milliseconds(500))
            }
        }
        throw lastError ?? DailyContentDeliveryError.acknowledgementTimedOut
    }
}

/// One current-connection wait for the business-level `0x24` commit result. Registering before the
/// first write prevents a fast firmware response from racing the waiter installation.
@MainActor
final class DailyContentAcknowledgementGate {
    typealias Sleeper = @MainActor (Duration) async throws -> Void

    struct Registration {
        let id: UUID
        fileprivate let stream: AsyncThrowingStream<DailyContentCommitAcknowledgement, any Error>
    }

    private struct Waiter {
        let id: UUID
        let expected: DailyContentCommittedState
        let expectedDestinationID: String
        let continuation: AsyncThrowingStream<DailyContentCommitAcknowledgement, any Error>.Continuation
    }

    private var waiter: Waiter?
    private let sleeper: Sleeper

    init(sleeper: @escaping Sleeper = { try await Task.sleep(for: $0) }) {
        self.sleeper = sleeper
    }

    func register(
        expected: DailyContentCommittedState,
        expectedDestinationID: String,
        timeout: Duration
    ) -> Registration {
        if waiter != nil { fail(BLEError.writeFailed(nil)) }
        let id = UUID()
        let pair = AsyncThrowingStream<DailyContentCommitAcknowledgement, any Error>.makeStream()
        waiter = Waiter(
            id: id,
            expected: expected,
            expectedDestinationID: expectedDestinationID,
            continuation: pair.continuation
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await sleeper(timeout)
            } catch {
                return
            }
            guard waiter?.id == id else { return }
            fail(DailyContentDeliveryError.acknowledgementTimedOut)
        }
        return Registration(id: id, stream: pair.stream)
    }

    func value(
        for registration: Registration
    ) async throws -> DailyContentCommitAcknowledgement {
        var iterator = registration.stream.makeAsyncIterator()
        guard let acknowledgement = try await iterator.next() else {
            throw CancellationError()
        }
        return acknowledgement
    }

    @discardableResult
    func receive(
        _ acknowledgement: DailyContentCommitAcknowledgement,
        destinationID: String
    ) -> Bool {
        guard let waiter,
              waiter.expectedDestinationID == destinationID,
              waiter.expected.version == acknowledgement.version,
              waiter.expected.contentCRC32 == acknowledgement.contentCRC32 else {
            return false
        }
        self.waiter = nil
        waiter.continuation.yield(acknowledgement)
        waiter.continuation.finish()
        return true
    }

    func fail(_ error: any Error) {
        guard let waiter else { return }
        self.waiter = nil
        waiter.continuation.finish(throwing: error)
    }
}
