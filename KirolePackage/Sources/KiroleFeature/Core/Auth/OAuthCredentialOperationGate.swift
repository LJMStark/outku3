import Foundation
import os

struct OAuthCredentialOperationTicket: Sendable, Equatable {
    fileprivate let generation: UInt64
    fileprivate let operationID: UUID
}

struct OAuthCredentialCleanupTicket: Sendable, Equatable {
    fileprivate let generation: UInt64
    fileprivate let cleanupID: UUID
}

enum OAuthCredentialOperationGateError: LocalizedError, Sendable, Equatable {
    case drainTimedOut

    var errorDescription: String? {
        switch self {
        case .drainTimedOut:
            "Credential cleanup timed out while waiting for an in-flight operation"
        }
    }
}

/// Provider-scoped generation gate for OAuth credential work. Disconnect and sign-out invalidate
/// synchronously, before their first suspension. The active-operation count lets asynchronous
/// stores drain before credential deletion is verified, so an old save cannot land after cleanup.
final class OAuthCredentialOperationGate: Sendable {
    private struct State: Sendable {
        var generation: UInt64 = 0
        var blockedGeneration: UInt64?
        var activeOperations: [UUID: UInt64] = [:]
        var activeCleanupClaims: Set<UUID> = []
        var cleanupAttemptFailed = false
        var unblockWhenOperationsDrain = false
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    func beginOperation() -> OAuthCredentialOperationTicket? {
        lock.withLock { state in
            guard state.blockedGeneration == nil else { return nil }
            let operationID = UUID()
            state.activeOperations[operationID] = state.generation
            return OAuthCredentialOperationTicket(
                generation: state.generation,
                operationID: operationID
            )
        }
    }

    func accepts(_ ticket: OAuthCredentialOperationTicket) -> Bool {
        lock.withLock {
            $0.blockedGeneration == nil && $0.generation == ticket.generation
                && $0.activeOperations[ticket.operationID] == ticket.generation
        }
    }

    func accepts(_ cleanup: OAuthCredentialCleanupTicket) -> Bool {
        lock.withLock {
            $0.generation == cleanup.generation
                && $0.blockedGeneration == cleanup.generation
                && $0.activeCleanupClaims.contains(cleanup.cleanupID)
        }
    }

    func endOperation(_ ticket: OAuthCredentialOperationTicket) {
        lock.withLock { state in
            state.activeOperations[ticket.operationID] = nil
            Self.unblockIfReady(&state)
        }
    }

    func invalidateAndBlock() -> OAuthCredentialCleanupTicket {
        lock.withLock { state in
            if state.blockedGeneration == nil {
                state.generation &+= 1
                state.blockedGeneration = state.generation
                state.cleanupAttemptFailed = false
                state.unblockWhenOperationsDrain = false
            } else if state.activeCleanupClaims.isEmpty {
                // A prior attempt failed and deliberately retained the block. The first retry owns
                // a fresh cleanup attempt for the same invalidated generation.
                state.cleanupAttemptFailed = false
                state.unblockWhenOperationsDrain = false
            }
            let cleanupID = UUID()
            state.activeCleanupClaims.insert(cleanupID)
            return OAuthCredentialCleanupTicket(
                generation: state.generation,
                cleanupID: cleanupID
            )
        }
    }

    func waitForInvalidatedOperations(
        before cleanup: OAuthCredentialCleanupTicket,
        timeout: Duration = .seconds(30)
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while lock.withLock({ state in
            state.activeOperations.values.contains { $0 < cleanup.generation }
        }) {
            try Task.checkCancellation()
            guard clock.now < deadline else {
                throw OAuthCredentialOperationGateError.drainTimedOut
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func complete(_ cleanup: OAuthCredentialCleanupTicket) {
        lock.withLock { state in
            guard state.generation == cleanup.generation,
                  state.blockedGeneration == cleanup.generation,
                  state.activeCleanupClaims.remove(cleanup.cleanupID) != nil else {
                return
            }
            guard state.activeCleanupClaims.isEmpty,
                  !state.cleanupAttemptFailed else { return }
            state.unblockWhenOperationsDrain = true
            Self.unblockIfReady(&state)
        }
    }

    func fail(_ cleanup: OAuthCredentialCleanupTicket) {
        lock.withLock { state in
            guard state.generation == cleanup.generation,
                  state.blockedGeneration == cleanup.generation,
                  state.activeCleanupClaims.remove(cleanup.cleanupID) != nil else {
                return
            }
            state.cleanupAttemptFailed = true
            state.unblockWhenOperationsDrain = false
        }
    }

    private static func unblockIfReady(_ state: inout State) {
        guard let blockedGeneration = state.blockedGeneration,
              state.activeCleanupClaims.isEmpty,
              !state.cleanupAttemptFailed,
              state.unblockWhenOperationsDrain,
              !state.activeOperations.values.contains(where: { $0 < blockedGeneration }) else {
            return
        }
        state.blockedGeneration = nil
        state.unblockWhenOperationsDrain = false
    }
}
