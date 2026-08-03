import Foundation

enum ScenarioAIError: Error, Equatable, Sendable {
    case unavailable
    case scriptExhausted
    case duplicateSuspensionID
}

enum ScenarioAIResponse: Equatable, Sendable {
    case success(String)
    case failure(ScenarioAIError)
    case suspended(id: String)
}

protocol ScenarioAITextProviding: Sendable {
    func generateText() async throws -> String
}

actor ScriptedScenarioAI: ScenarioAITextProviding {
    private var responses: [ScenarioAIResponse]
    private var suspendedRequests: [String: CheckedContinuation<String, any Error>] = [:]
    private var cancelledSuspensionIDs: Set<String> = []
    private var terminalSuspensionIDs: Set<String> = []
    private var suspensionWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    init(responses: [ScenarioAIResponse]) {
        self.responses = responses
    }

    func generateText() async throws -> String {
        try Task.checkCancellation()
        guard !responses.isEmpty else {
            throw ScenarioAIError.scriptExhausted
        }
        let response = responses.removeFirst()
        switch response {
        case .success(let text):
            return text
        case .failure(let error):
            throw error
        case .suspended(let id):
            guard suspendedRequests[id] == nil,
                  !terminalSuspensionIDs.contains(id) else {
                throw ScenarioAIError.duplicateSuspensionID
            }
            let text = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<String, any Error>) in
                    if Task.isCancelled || cancelledSuspensionIDs.remove(id) != nil {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        suspendedRequests[id] = continuation
                        let waiters = suspensionWaiters.removeValue(forKey: id) ?? []
                        waiters.forEach { $0.resume() }
                    }
                }
            } onCancel: {
                Task {
                    await self.cancel(id: id)
                }
            }
            try Task.checkCancellation()
            return text
        }
    }

    func waitUntilSuspended(id: String) async {
        guard suspendedRequests[id] == nil else { return }
        await withCheckedContinuation { continuation in
            suspensionWaiters[id, default: []].append(continuation)
        }
    }

    @discardableResult
    func cancel(id: String) -> Bool {
        guard let continuation = suspendedRequests.removeValue(forKey: id) else {
            guard !terminalSuspensionIDs.contains(id) else { return false }
            cancelledSuspensionIDs.insert(id)
            return false
        }
        terminalSuspensionIDs.insert(id)
        continuation.resume(throwing: CancellationError())
        return true
    }

    @discardableResult
    func resolve(
        id: String,
        with result: Result<String, ScenarioAIError>
    ) -> Bool {
        guard let continuation = suspendedRequests.removeValue(forKey: id) else {
            return false
        }
        terminalSuspensionIDs.insert(id)
        switch result {
        case .success(let text):
            continuation.resume(returning: text)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
        return true
    }

    func cancelAllSuspendedRequests() {
        let requests = suspendedRequests
        suspendedRequests.removeAll()
        terminalSuspensionIDs.formUnion(requests.keys)
        requests.values.forEach { $0.resume(throwing: CancellationError()) }
    }
}
