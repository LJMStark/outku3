import Foundation
@testable import KiroleFeature

struct SimulatedDailyContentFirmware {
    private(set) var committedVersion: DailyContentVersion?
    private(set) var committedPackage: DailyContentPackage?
    private(set) var committedState: DailyContentCommittedState?
    private var maximumEvents: Int?

    mutating func setMaximumEvents(_ count: Int?) {
        maximumEvents = count
    }

    mutating func apply(payload: Data) throws -> DailyContentCommitAcknowledgement {
        let transaction = try DailyContentCodec.decodeTransaction(payload)
        let state = try DailyContentCodec.committedState(for: transaction)
        if let maximumEvents, transaction.package.events.count > maximumEvents {
            return DailyContentCommitAcknowledgement(
                version: transaction.version,
                result: .capacityExceeded,
                contentCRC32: state.contentCRC32
            )
        }
        committedVersion = transaction.version
        committedPackage = transaction.package
        committedState = state
        return DailyContentCommitAcknowledgement(
            version: transaction.version,
            result: .committed,
            contentCRC32: state.contentCRC32
        )
    }
}
