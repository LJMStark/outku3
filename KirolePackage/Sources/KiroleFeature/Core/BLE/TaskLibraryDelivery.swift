import CryptoKit
import Foundation
import os

/// Frozen bytes and their source identity. A destination keeps at most one pending delivery;
/// replacing this value invalidates an older unsent or failed transaction without retaining a
/// queue of stale task details.
public struct TaskLibraryPendingDelivery: Sendable, Equatable, Codable {
    public let transaction: TaskLibraryTransaction
    public let sourceFingerprint: String
    public let targetRecords: [TaskLibraryRecord]
    public let phaseSourceFingerprints: [String: String]
    public let validation: TaskLibraryPendingValidation
    public let personaFingerprint: String
    let updateScope: TaskLibraryUpdateScope?
    let capturedStabilityGeneration: UInt64?

    public init(
        transaction: TaskLibraryTransaction,
        sourceFingerprint: String,
        targetRecords: [TaskLibraryRecord]? = nil,
        phaseSourceFingerprints: [String: String] = [:],
        validation: TaskLibraryPendingValidation? = nil,
        personaFingerprint: String = "",
        updateScope: TaskLibraryUpdateScope? = nil,
        capturedStabilityGeneration: UInt64? = nil
    ) {
        self.transaction = transaction
        self.sourceFingerprint = sourceFingerprint
        self.targetRecords = targetRecords ?? transaction.records
        self.phaseSourceFingerprints = phaseSourceFingerprints
        self.validation = validation ?? .completeSource(sourceFingerprint)
        self.personaFingerprint = personaFingerprint
        self.updateScope = updateScope
        self.capturedStabilityGeneration = capturedStabilityGeneration
    }

    init(
        preparedUpdate: TaskLibraryPreparedUpdate,
        updateScope: TaskLibraryUpdateScope,
        capturedStabilityGeneration: UInt64
    ) {
        self.init(
            transaction: preparedUpdate.transaction,
            sourceFingerprint: Self.fingerprint(
                records: preparedUpdate.targetRecords,
                phaseSourceFingerprints: preparedUpdate.phaseSourceFingerprints
            ),
            targetRecords: preparedUpdate.targetRecords,
            phaseSourceFingerprints: preparedUpdate.phaseSourceFingerprints,
            validation: preparedUpdate.validation,
            personaFingerprint: preparedUpdate.personaFingerprint,
            updateScope: updateScope,
            capturedStabilityGeneration: capturedStabilityGeneration
        )
    }

    private static func fingerprint(
        records: [TaskLibraryRecord],
        phaseSourceFingerprints: [String: String]
    ) -> String {
        var framed = Data()
        for record in records {
            let value = "\(record.taskID)|\(record.order)|\(record.title)|\(record.detail)|"
                + "\(record.dueTimestamp.map(String.init) ?? "")|\(record.priority.rawValue)|"
                + "\(phaseSourceFingerprints[record.taskID] ?? "")"
            let bytes = Data(value.utf8)
            var length = UInt64(bytes.count).bigEndian
            Swift.withUnsafeBytes(of: &length) { framed.append(contentsOf: $0) }
            framed.append(bytes)
        }
        return SHA256.hash(data: framed)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

public enum TaskLibraryDeliveryError: LocalizedError, Sendable, Equatable {
    case acknowledgementMismatch
    case acknowledgementTimedOut
    case rejected(TaskLibraryCommitResult)

    public var errorDescription: String? {
        switch self {
        case .acknowledgementMismatch:
            return "Task-library acknowledgement did not match the frozen transaction"
        case .acknowledgementTimedOut:
            return "Task-library commit acknowledgement timed out"
        case .rejected(let result):
            return "Task-library commit was rejected: \(result.diagnosticName)"
        }
    }
}

public enum TaskLibraryDeliveryDiagnostic: Sendable, Equatable {
    case preparing(version: TaskLibraryVersion)
    case attempt(number: Int, version: TaskLibraryVersion)
    case retry(version: TaskLibraryVersion)
    case committed(version: TaskLibraryVersion)
    case pendingReconnect(version: TaskLibraryVersion)

    var message: String {
        switch self {
        case .preparing(let version):
            return "prepare \(version.diagnosticLabel)"
        case .attempt(let number, let version):
            return "attempt=\(number) \(version.diagnosticLabel)"
        case .retry(let version):
            return "retry-from-byte-zero \(version.diagnosticLabel)"
        case .committed(let version):
            return "committed \(version.diagnosticLabel)"
        case .pendingReconnect(let version):
            return "pending-next-connection \(version.diagnosticLabel)"
        }
    }
}

/// Sends the same immutable transaction at most twice. Each sender invocation is a new complete
/// transport attempt; the BLE sender therefore allocates a fresh message and begins at sequence 0.
@MainActor
struct TaskLibraryDeliveryRetrier {
    typealias Sender = @MainActor (TaskLibraryTransaction) async throws
        -> TaskLibraryCommitAcknowledgement
    typealias Sleeper = @MainActor (Duration) async throws -> Void
    typealias DiagnosticSink = @MainActor (TaskLibraryDeliveryDiagnostic) -> Void

    private let retrySleeper: Sleeper
    private let diagnosticSink: DiagnosticSink

    init(
        retrySleeper: @escaping Sleeper = { try await Task.sleep(for: $0) },
        diagnosticSink: @escaping DiagnosticSink = TaskLibraryDeliveryLogger.record
    ) {
        self.retrySleeper = retrySleeper
        self.diagnosticSink = diagnosticSink
    }

    func deliver(
        _ transaction: TaskLibraryTransaction,
        sender: Sender
    ) async throws -> TaskLibraryCommitAcknowledgement {
        let expected = try TaskLibraryCodec.committedState(for: transaction)
        diagnosticSink(.preparing(version: transaction.version))
        var lastError: (any Error)?

        for attempt in 1...2 {
            diagnosticSink(.attempt(number: attempt, version: transaction.version))
            do {
                let acknowledgement = try await sender(transaction)
                guard acknowledgement.version == expected.version,
                      acknowledgement.contentCRC32 == expected.contentCRC32 else {
                    throw TaskLibraryDeliveryError.acknowledgementMismatch
                }
                guard acknowledgement.result == .committed else {
                    throw TaskLibraryDeliveryError.rejected(acknowledgement.result)
                }
                diagnosticSink(.committed(version: transaction.version))
                return acknowledgement
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as BLEPresentationDestinationError {
                throw error
            } catch let error as BLEError {
                if case .staleTaskSnapshot = error {
                    throw error
                }
                lastError = error
            } catch {
                lastError = error
            }

            if attempt == 1 {
                diagnosticSink(.retry(version: transaction.version))
                try await retrySleeper(.milliseconds(500))
            }
        }

        diagnosticSink(.pendingReconnect(version: transaction.version))
        throw lastError ?? TaskLibraryDeliveryError.acknowledgementTimedOut
    }
}

private enum TaskLibraryDeliveryLogger {
    private static let logger = Logger(
        subsystem: "com.kirole.app",
        category: "BLETaskLibrary"
    )

    static func record(_ diagnostic: TaskLibraryDeliveryDiagnostic) {
        switch diagnostic {
        case .pendingReconnect:
            logger.error("\(diagnostic.message, privacy: .public)")
        default:
            logger.info("\(diagnostic.message, privacy: .public)")
        }
    }
}

enum TaskLibrarySourceFingerprint {
    /// Fingerprints today's device-library source. The local day is part of the digest, so a
    /// pending delivery frozen yesterday can never validate (and be resent as-is) after midnight —
    /// membership is day-dependent since v2.16.0's today-only library (2026-08-04).
    ///
    /// Only covers what actually reaches the wire (`TaskLibraryMembership.members`, capped at 20).
    /// Digesting tasks that never ship would make editing task #21 invalidate every frozen pending
    /// delivery while the encoded bytes stay byte-for-byte identical.
    static func make(
        tasks: [TaskItem],
        userProfile: UserProfile,
        customCompanions: [CustomCompanion],
        now: Date,
        calendar: Calendar
    ) -> String {
        let included = TaskLibraryMembership.members(of: tasks, on: now, calendar: calendar)
        let localDay = DailyContentDate(date: now, calendar: calendar)
        var parts = [
            "day=\(localDay.year)-\(localDay.month)-\(localDay.day)",
            "records=\(included.count)"
        ]
        for (index, task) in included.enumerated() {
            parts.append("order=\(index)")
            parts.append("id=\(task.hardwareIdentifier)")
            parts.append("title=\(task.title)")
            parts.append("notes=\(task.notes ?? "")")
            parts.append("due=\(task.dueDate?.timeIntervalSince1970.bitPattern ?? 0)")
            parts.append("todayDisplay=\(task.todayDisplayDate?.timeIntervalSince1970.bitPattern ?? 0)")
            parts.append("priority=\(task.priority.rawValue)")
        }

        if let customID = userProfile.customCompanionId {
            let revision = customCompanions
                .first(where: { $0.id == customID })?
                .updatedAt.timeIntervalSinceReferenceDate.bitPattern ?? 0
            parts.append("persona=custom|\(customID.uuidString)|\(revision)")
        } else {
            parts.append(
                "persona=built-in|\(userProfile.companionCharacter.rawValue)|\(userProfile.intimacyStage.rawValue)"
            )
        }

        var framed = Data()
        for part in parts {
            let bytes = Data(part.utf8)
            var length = UInt64(bytes.count).bigEndian
            Swift.withUnsafeBytes(of: &length) { framed.append(contentsOf: $0) }
            framed.append(bytes)
        }
        return SHA256.hash(data: framed)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

/// One current-connection wait for the business-level 0x23 result. Registration is synchronous,
/// so it is installed before the first BLE byte is written and cannot miss a fast firmware reply.
@MainActor
final class TaskLibraryAcknowledgementGate {
    typealias Sleeper = @MainActor (Duration) async throws -> Void

    struct Registration {
        let id: UUID
        let expected: TaskLibraryCommittedState
        let expectedDestinationID: String
        fileprivate let stream: AsyncThrowingStream<TaskLibraryCommitAcknowledgement, any Error>
    }

    private struct Waiter {
        let id: UUID
        let expected: TaskLibraryCommittedState
        let expectedDestinationID: String
        let continuation: AsyncThrowingStream<TaskLibraryCommitAcknowledgement, any Error>.Continuation
    }

    private var waiter: Waiter?
    private let sleeper: Sleeper

    init(
        sleeper: @escaping Sleeper = { try await Task.sleep(for: $0) }
    ) {
        self.sleeper = sleeper
    }

    func register(
        expected: TaskLibraryCommittedState,
        expectedDestinationID: String,
        timeout: Duration
    ) -> Registration {
        if waiter != nil {
            fail(BLEError.writeFailed(nil))
        }
        let id = UUID()
        let pair = AsyncThrowingStream<TaskLibraryCommitAcknowledgement, any Error>.makeStream()
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
            fail(TaskLibraryDeliveryError.acknowledgementTimedOut)
        }
        return Registration(
            id: id,
            expected: expected,
            expectedDestinationID: expectedDestinationID,
            stream: pair.stream
        )
    }

    func value(
        for registration: Registration
    ) async throws -> TaskLibraryCommitAcknowledgement {
        var iterator = registration.stream.makeAsyncIterator()
        guard let acknowledgement = try await iterator.next() else {
            throw CancellationError()
        }
        return acknowledgement
    }

    @discardableResult
    func receive(
        _ acknowledgement: TaskLibraryCommitAcknowledgement,
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

private extension TaskLibraryVersion {
    var diagnosticLabel: String {
        "epoch=\(epoch) revision=\(revision)"
    }
}

private extension TaskLibraryCommitResult {
    var diagnosticName: String {
        switch self {
        case .committed: "committed"
        case .invalidPayload: "invalidPayload"
        case .checksumMismatch: "checksumMismatch"
        case .capacityExceeded: "capacityExceeded"
        case .unsupportedVersion: "unsupportedVersion"
        case .baseMismatch: "baseMismatch"
        case .internalError: "internalError"
        }
    }
}
