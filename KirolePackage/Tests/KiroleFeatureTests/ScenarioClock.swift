import Foundation

struct ScenarioClockAdvance: Sendable {
    let now: Date
    let resumedSleeperCount: Int
}

protocol ScenarioClock: Sendable {
    func sleep(for duration: Duration) async throws
    func latestSleeperRegistration() async -> UInt64
    func waitUntilSleeperIsScheduled(after registration: UInt64) async
    func advance(by duration: Duration) async -> ScenarioClockAdvance
}

actor MutableScenarioClock: ScenarioClock {
    private struct Sleeper {
        let deadline: Date
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct SchedulingWaiter {
        let registration: UInt64
        let continuation: CheckedContinuation<Void, Never>
    }

    private var now: Date
    private var sleepers: [UUID: Sleeper] = [:]
    private var cancelledSleeperIDs: Set<UUID> = []
    private var latestRegistration: UInt64 = 0
    private var schedulingWaiters: [SchedulingWaiter] = []

    init(now: Date) {
        self.now = now
    }

    func sleep(for duration: Duration) async throws {
        let sleeperID = UUID()
        let deadline = now.addingTimeInterval(duration.scenarioTimeInterval)
        registerSleeperScheduling()
        guard deadline > now else {
            try Task.checkCancellation()
            return
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled || cancelledSleeperIDs.remove(sleeperID) != nil {
                    continuation.resume(throwing: CancellationError())
                } else {
                    sleepers[sleeperID] = Sleeper(
                        deadline: deadline,
                        continuation: continuation
                    )
                }
            }
        } onCancel: {
            Task {
                await self.cancelSleeper(id: sleeperID)
            }
        }
        try Task.checkCancellation()
    }

    func latestSleeperRegistration() -> UInt64 {
        latestRegistration
    }

    func waitUntilSleeperIsScheduled(after registration: UInt64) async {
        guard latestRegistration <= registration else { return }
        await withCheckedContinuation { continuation in
            schedulingWaiters.append(SchedulingWaiter(
                registration: registration,
                continuation: continuation
            ))
        }
    }

    func advance(by duration: Duration) -> ScenarioClockAdvance {
        now = now.addingTimeInterval(duration.scenarioTimeInterval)
        let readyIDs = sleepers.compactMap { id, sleeper in
            sleeper.deadline <= now ? id : nil
        }
        let readySleepers = readyIDs.compactMap { sleepers.removeValue(forKey: $0) }
        readySleepers.forEach { $0.continuation.resume() }
        return ScenarioClockAdvance(now: now, resumedSleeperCount: readySleepers.count)
    }

    private func cancelSleeper(id: UUID) {
        if let sleeper = sleepers.removeValue(forKey: id) {
            sleeper.continuation.resume(throwing: CancellationError())
        } else {
            cancelledSleeperIDs.insert(id)
        }
    }

    private func registerSleeperScheduling() {
        latestRegistration &+= 1
        let readyWaiters = schedulingWaiters.filter {
            $0.registration < latestRegistration
        }
        schedulingWaiters.removeAll {
            $0.registration < latestRegistration
        }
        readyWaiters.forEach { $0.continuation.resume() }
    }
}

private extension Duration {
    var scenarioTimeInterval: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
