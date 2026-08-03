import Foundation

/// Gates connection-bound presentation writes until the device's offline event batch has been
/// fully replayed. The state is intentionally process-local: every BLE connection starts a fresh
/// request and a disconnect resolves all waiters as failure.
@MainActor
final class BLEEventReplayBarrier {
    struct Ticket: Equatable, Sendable {
        let connectionGeneration: UInt64
        let requestID: UInt64
    }

    typealias Sleeper = @Sendable (Duration) async throws -> Void

    private enum State {
        case idle
        case awaiting(ticket: Ticket, waiters: [CheckedContinuation<Bool, Never>])
        case resolved(ticket: Ticket, succeeded: Bool)
    }

    private let timeout: Duration
    private let sleeper: Sleeper
    private var nextRequestID: UInt64 = 0
    private var state: State = .idle
    private var timeoutTask: Task<Void, Never>?

    init(
        timeout: Duration = .seconds(15),
        sleeper: @escaping Sleeper = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.timeout = timeout
        self.sleeper = sleeper
    }

    deinit {
        timeoutTask?.cancel()
    }

    /// Opens a new fail-closed replay window before the corresponding 0x20 write begins.
    func beginRequest(connectionGeneration: UInt64) -> Ticket {
        resolveCurrent(succeeded: false)
        nextRequestID &+= 1
        let ticket = Ticket(
            connectionGeneration: connectionGeneration,
            requestID: nextRequestID
        )
        state = .awaiting(ticket: ticket, waiters: [])

        let timeout = timeout
        let sleeper = sleeper
        timeoutTask = Task { @MainActor [weak self] in
            do {
                try await sleeper(timeout)
            } catch {
                return
            }
            self?.resolve(ticket: ticket, succeeded: false)
        }
        return ticket
    }

    /// Waits for the exact request. A response from an older connection/request cannot release it.
    func wait(for ticket: Ticket) async -> Bool {
        switch state {
        case .resolved(let current, let succeeded) where current == ticket:
            return succeeded
        case .awaiting(let current, var waiters) where current == ticket:
            return await withCheckedContinuation { continuation in
                waiters.append(continuation)
                state = .awaiting(ticket: current, waiters: waiters)
            }
        default:
            return false
        }
    }

    /// Reuses the connection's in-flight or completed replay instead of issuing a second 0x20.
    /// `nil` means this connection has not opened its mandatory replay window yet.
    func waitForExistingRequest(connectionGeneration: UInt64) async -> Bool? {
        switch state {
        case .resolved(let ticket, let succeeded)
            where ticket.connectionGeneration == connectionGeneration:
            return succeeded
        case .awaiting(let ticket, _)
            where ticket.connectionGeneration == connectionGeneration:
            return await wait(for: ticket)
        default:
            return nil
        }
    }

    /// Completes the currently pending batch after parsing, state mutation and operation ACKs.
    func completeCurrentBatch(succeeded: Bool) {
        guard case .awaiting(let ticket, _) = state else { return }
        resolve(ticket: ticket, succeeded: succeeded)
    }

    func failRequest(_ ticket: Ticket) {
        resolve(ticket: ticket, succeeded: false)
    }

    func handleDisconnect() {
        resolveCurrent(succeeded: false)
        state = .idle
    }

    func isSatisfied(connectionGeneration: UInt64) -> Bool {
        guard case .resolved(let ticket, true) = state else { return false }
        return ticket.connectionGeneration == connectionGeneration
    }

    private func resolve(ticket: Ticket, succeeded: Bool) {
        guard case .awaiting(let current, let waiters) = state, current == ticket else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        state = .resolved(ticket: ticket, succeeded: succeeded)
        waiters.forEach { $0.resume(returning: succeeded) }
    }

    private func resolveCurrent(succeeded: Bool) {
        guard case .awaiting(let ticket, _) = state else {
            timeoutTask?.cancel()
            timeoutTask = nil
            return
        }
        resolve(ticket: ticket, succeeded: succeeded)
    }
}
