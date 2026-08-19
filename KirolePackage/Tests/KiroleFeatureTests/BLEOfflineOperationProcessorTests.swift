import Foundation
import Testing
@testable import KiroleFeature

@MainActor
@Suite("OfflineSync operation processing")
struct BLEOfflineOperationProcessorTests {
    @MainActor
    final class ApplyRecorder {
        var operationIDs: [UInt32] = []
    }

    private func completePayload(operationID: UInt32, taskID: String = "task-1") -> Data {
        return FocusWireFixtures.endPayload(
            operationID: operationID,
            taskID: taskID,
            end: 1_786_396_800,
            elapsed: 0
        )
    }

    @Test("Exact retry is applied once but remains acknowledgement-safe")
    func duplicateIsNotReapplied() async {
        let ledger = OfflineOperationLedger(persistenceEnabled: false)
        let recorder = ApplyRecorder()
        let record = OfflineSyncOperationRecord(
            operationID: 7,
            eventType: EventLogType.completeTask.rawByte,
            originalPayload: completePayload(operationID: 7)
        )

        let first = await BLEOfflineOperationProcessor.process(
            record,
            deviceID: "device-a",
            bootSessionID: 11,
            ledger: ledger
        ) { event, _ in
            recorder.operationIDs.append(event.operationID ?? 0)
            return true
        }
        let retry = await BLEOfflineOperationProcessor.process(
            record,
            deviceID: "device-a",
            bootSessionID: 11,
            ledger: ledger
        ) { event, _ in
            recorder.operationIDs.append(event.operationID ?? 0)
            return true
        }

        #expect(first)
        #expect(retry)
        #expect(recorder.operationIDs == [7])
    }

    @Test("Same OperationID in a new BootSession is a different operation")
    func bootSessionScopesIdentity() async {
        let ledger = OfflineOperationLedger(persistenceEnabled: false)
        let recorder = ApplyRecorder()
        let record = OfflineSyncOperationRecord(
            operationID: 9,
            eventType: EventLogType.completeTask.rawByte,
            originalPayload: completePayload(operationID: 9)
        )

        for bootSessionID: UInt32 in [1, 2] {
            #expect(await BLEOfflineOperationProcessor.process(
                record,
                deviceID: "device-a",
                bootSessionID: bootSessionID,
                ledger: ledger
            ) { event, _ in
                recorder.operationIDs.append(event.operationID ?? 0)
                return true
            })
        }

        #expect(recorder.operationIDs == [9, 9])
    }

    @Test("Outer and original Complete/Skip OperationIDs must match")
    func rejectsMismatchedNestedIdentity() async {
        let ledger = OfflineOperationLedger(persistenceEnabled: false)
        let record = OfflineSyncOperationRecord(
            operationID: 10,
            eventType: EventLogType.completeTask.rawByte,
            originalPayload: completePayload(operationID: 11)
        )

        let accepted = await BLEOfflineOperationProcessor.process(
            record,
            deviceID: "device-a",
            bootSessionID: 1,
            ledger: ledger
        ) { _, _ in
            Issue.record("A mismatched operation must not reach the business mutation")
            return true
        }

        #expect(!accepted)
    }

    @Test("Unsupported offline events are skipped without blocking later supported operations")
    func skipsUnsupportedEvent() async {
        let ledger = OfflineOperationLedger(persistenceEnabled: false)
        let recorder = ApplyRecorder()
        let unsupported = OfflineSyncOperationRecord(
            operationID: 12,
            eventType: EventLogType.deviceWake.rawByte,
            originalPayload: Data([80])
        )
        let supported = OfflineSyncOperationRecord(
            operationID: 13,
            eventType: EventLogType.completeTask.rawByte,
            originalPayload: completePayload(operationID: 13)
        )

        let skipped = await BLEOfflineOperationProcessor.process(
            unsupported,
            deviceID: "device-a",
            bootSessionID: 1,
            ledger: ledger
        ) { _, _ in
            Issue.record("An unsupported event must not reach the business mutation")
            return true
        }
        let applied = await BLEOfflineOperationProcessor.process(
            supported,
            deviceID: "device-a",
            bootSessionID: 1,
            ledger: ledger
        ) { event, _ in
            recorder.operationIDs.append(event.operationID ?? 0)
            return true
        }

        #expect(skipped)
        #expect(applied)
        #expect(recorder.operationIDs == [13])
    }

    @Test("Reminder operations require the exact 4-byte timestamp payload")
    func rejectsMalformedReminderPayload() async {
        let ledger = OfflineOperationLedger(persistenceEnabled: false)

        for payload in [Data([0x01, 0x02, 0x03]), Data(repeating: 0, count: 5)] {
            let record = OfflineSyncOperationRecord(
                operationID: UInt32(payload.count),
                eventType: EventLogType.reminderAcknowledged.rawByte,
                originalPayload: payload
            )
            #expect(!(await BLEOfflineOperationProcessor.process(
                record,
                deviceID: "device-a",
                bootSessionID: 1,
                ledger: ledger
            ) { _, _ in
                Issue.record("Malformed reminder payload must not reach the business mutation")
                return true
            }))
        }
    }
}
