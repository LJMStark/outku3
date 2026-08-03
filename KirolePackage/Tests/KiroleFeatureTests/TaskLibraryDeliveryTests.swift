import Foundation
import Testing
@testable import KiroleFeature

@Suite("Task-library durable delivery")
struct TaskLibraryDeliveryTests {
    @MainActor
    @Test("The first failure retries the exact transaction once from a fresh send")
    func retriesExactTransactionOnce() async throws {
        let transaction = makeDeliveryTransaction(revision: 1, title: "Retry me")
        var sent: [TaskLibraryTransaction] = []
        var diagnostics: [TaskLibraryDeliveryDiagnostic] = []
        var attempt = 0
        let retrier = TaskLibraryDeliveryRetrier(
            retrySleeper: { _ in },
            diagnosticSink: { diagnostics.append($0) }
        )

        let acknowledgement = try await retrier.deliver(transaction) { frozen in
            sent.append(frozen)
            attempt += 1
            if attempt == 1 {
                throw TestDeliveryError.writeFailed
            }
            return try committedAcknowledgement(for: frozen)
        }

        #expect(acknowledgement.result == .committed)
        #expect(sent == [transaction, transaction])
        #expect(diagnostics == [
            .preparing(version: transaction.version),
            .attempt(number: 1, version: transaction.version),
            .retry(version: transaction.version),
            .attempt(number: 2, version: transaction.version),
            .committed(version: transaction.version)
        ])
    }

    @MainActor
    @Test("A second failure stops the round and marks the frozen version pending reconnect")
    func secondFailureStopsAndKeepsPending() async throws {
        let transaction = makeDeliveryTransaction(revision: 2, title: "Keep pending")
        var sent: [TaskLibraryTransaction] = []
        var diagnostics: [TaskLibraryDeliveryDiagnostic] = []
        let retrier = TaskLibraryDeliveryRetrier(
            retrySleeper: { _ in },
            diagnosticSink: { diagnostics.append($0) }
        )

        await #expect(throws: TestDeliveryError.writeFailed) {
            try await retrier.deliver(transaction) { frozen in
                sent.append(frozen)
                throw TestDeliveryError.writeFailed
            }
        }

        #expect(sent == [transaction, transaction])
        #expect(diagnostics.last == .pendingReconnect(version: transaction.version))
    }

    @MainActor
    @Test("Capacity rejection is explicit and never reported as a partial success")
    func capacityFailureIsExplicit() async throws {
        let transaction = makeDeliveryTransaction(revision: 3, title: "Too large")
        let expectedState = try TaskLibraryCodec.committedState(for: transaction)
        var attempts = 0
        let retrier = TaskLibraryDeliveryRetrier(retrySleeper: { _ in })

        await #expect(throws: TaskLibraryDeliveryError.rejected(.capacityExceeded)) {
            try await retrier.deliver(transaction) { frozen in
                attempts += 1
                return TaskLibraryCommitAcknowledgement(
                    version: frozen.version,
                    result: .capacityExceeded,
                    contentCRC32: expectedState.contentCRC32
                )
            }
        }

        #expect(attempts == 2)
    }

    @Test("A changed task or built-in persona produces a new pending-source fingerprint")
    func sourceFingerprintTracksDeviceVisibleInputs() {
        let original = [TaskItem(id: "task", title: "Original", notes: "First note")]
        let edited = [TaskItem(id: "task", title: "Edited", notes: "First note")]
        let profile = UserProfile(companionCharacter: .joy, intimacyStage: .acquaintance)

        let baseline = TaskLibrarySourceFingerprint.make(
            tasks: original,
            userProfile: profile,
            customCompanions: []
        )
        let repeated = TaskLibrarySourceFingerprint.make(
            tasks: original,
            userProfile: profile,
            customCompanions: []
        )
        let taskChanged = TaskLibrarySourceFingerprint.make(
            tasks: edited,
            userProfile: profile,
            customCompanions: []
        )
        let personaChanged = TaskLibrarySourceFingerprint.make(
            tasks: original,
            userProfile: UserProfile(
                companionCharacter: .joy,
                intimacyStage: .familiar
            ),
            customCompanions: []
        )

        #expect(baseline == repeated)
        #expect(baseline != taskChanged)
        #expect(baseline != personaChanged)
    }

    @Test("A new pending version replaces the previous one for only that destination")
    func pendingDeliveryPersistsLatestPerDestination() async throws {
        try await SharedPersistenceTestLock.shared.withLock {
            let destination = "test-task-library-pending-\(UUID().uuidString)"
            let first = TaskLibraryPendingDelivery(
                transaction: makeDeliveryTransaction(revision: 4, title: "Old pending"),
                sourceFingerprint: "old"
            )
            let latest = TaskLibraryPendingDelivery(
                transaction: makeDeliveryTransaction(revision: 5, title: "Latest pending"),
                sourceFingerprint: "latest"
            )

            do {
                try await LocalStorage.shared.saveTaskLibraryPendingDelivery(
                    first,
                    for: destination
                )
                try await LocalStorage.shared.saveTaskLibraryPendingDelivery(
                    latest,
                    for: destination
                )

                #expect(try await LocalStorage.shared.loadTaskLibraryPendingDelivery(
                    for: destination
                ) == latest)
            } catch {
                try? await LocalStorage.shared.removeTaskLibraryPendingDelivery(for: destination)
                throw error
            }
            try await LocalStorage.shared.removeTaskLibraryPendingDelivery(for: destination)
        }
    }

    @MainActor
    @Test("The acknowledgement gate ignores another transaction and resolves the exact one")
    func acknowledgementGateMatchesVersionAndCRC() async throws {
        let transaction = makeDeliveryTransaction(revision: 6, title: "Await ACK")
        let expected = try TaskLibraryCodec.committedState(for: transaction)
        let gate = TaskLibraryAcknowledgementGate(
            sleeper: { _ in try await Task.sleep(for: .seconds(86_400)) }
        )
        let registration = gate.register(
            expected: expected,
            expectedDestinationID: "device-a",
            timeout: .seconds(5)
        )
        let wrong = TaskLibraryCommitAcknowledgement(
            version: expected.version,
            result: .committed,
            contentCRC32: expected.contentCRC32 ^ 1
        )
        let matching = try committedAcknowledgement(for: transaction)

        #expect(!gate.receive(matching, destinationID: "device-b"))
        #expect(!gate.receive(wrong, destinationID: "device-a"))
        #expect(gate.receive(matching, destinationID: "device-a"))
        #expect(try await gate.value(for: registration) == matching)
    }

    @MainActor
    @Test("Disconnect fails the current acknowledgement wait without losing its frozen identity")
    func acknowledgementGateFailsOnDisconnect() async throws {
        let transaction = makeDeliveryTransaction(revision: 7, title: "Disconnect")
        let expected = try TaskLibraryCodec.committedState(for: transaction)
        let gate = TaskLibraryAcknowledgementGate(
            sleeper: { _ in try await Task.sleep(for: .seconds(86_400)) }
        )
        let registration = gate.register(
            expected: expected,
            expectedDestinationID: "device-a",
            timeout: .seconds(5)
        )

        gate.fail(BLEError.disconnected)

        await #expect(throws: BLEError.self) {
            try await gate.value(for: registration)
        }
        #expect(registration.expected == expected)
    }

    @MainActor
    @Test("A missing business acknowledgement fails after the bounded wait")
    func acknowledgementGateTimesOut() async throws {
        let transaction = makeDeliveryTransaction(revision: 8, title: "Timeout")
        let expected = try TaskLibraryCodec.committedState(for: transaction)
        let gate = TaskLibraryAcknowledgementGate(sleeper: { _ in })
        let registration = gate.register(
            expected: expected,
            expectedDestinationID: "device-a",
            timeout: .seconds(5)
        )

        await #expect(throws: TaskLibraryDeliveryError.acknowledgementTimedOut) {
            try await gate.value(for: registration)
        }
    }
}

private enum TestDeliveryError: Error {
    case writeFailed
}

private func makeDeliveryTransaction(
    revision: UInt32,
    title: String
) -> TaskLibraryTransaction {
    TaskLibraryTransaction(
        version: TaskLibraryVersion(epoch: 1, revision: revision),
        records: [TaskLibraryRecord(
            taskID: "task-18",
            order: 0,
            title: title,
            detail: "",
            phaseTexts: .localFallback
        )]
    )
}

private func committedAcknowledgement(
    for transaction: TaskLibraryTransaction
) throws -> TaskLibraryCommitAcknowledgement {
    let state = try TaskLibraryCodec.committedState(for: transaction)
    return TaskLibraryCommitAcknowledgement(
        version: state.version,
        result: .committed,
        contentCRC32: state.contentCRC32
    )
}
