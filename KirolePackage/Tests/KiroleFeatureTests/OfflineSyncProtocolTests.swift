import Foundation
import Testing
@testable import KiroleFeature

@Suite("OfflineSync 0x25 wire protocol")
struct OfflineSyncProtocolTests {
    @Test("0x25 is assigned to OfflineSync and DatasetMask uses bit2 for DayPack")
    func commandAndDatasetAssignments() {
        #expect(BLEDataType.offlineSync.rawValue == 0x25)
        #expect(OfflineSyncDatasetMask.taskList.rawValue == 0x01)
        #expect(OfflineSyncDatasetMask.schedule.rawValue == 0x02)
        #expect(OfflineSyncDatasetMask.dayPack.rawValue == 0x04)
        #expect(OfflineSyncDatasetMask.all.rawValue == 0x07)
        #expect(OfflineSyncStateFlags.dataValid.rawValue == 0x01)
        #expect(OfflineSyncStateFlags.transactionOpen.rawValue == 0x02)
        #expect(OfflineSyncStateFlags.needsFullSync.rawValue == 0x04)
        #expect(OfflineSyncStateFlags.operationOverflow.rawValue == 0x08)
        #expect(OfflineSyncTargetType.taskList.rawValue == 0x02)
        #expect(OfflineSyncTargetType.schedule.rawValue == 0x03)
        #expect(OfflineSyncTargetType.dayPack.rawValue == 0x10)
        #expect(OfflineSyncTargetType.offlineSync.rawValue == 0x25)
        #expect(OfflineSyncResultCode.accepted.rawValue == 0x00)
        #expect(OfflineSyncResultCode.staged.rawValue == 0x01)
        #expect(OfflineSyncResultCode.committed.rawValue == 0x02)
        #expect(OfflineSyncResultCode.invalidState.rawValue == 0x10)
        #expect(OfflineSyncResultCode.missingDataset.rawValue == 0x11)
        #expect(OfflineSyncResultCode.expired.rawValue == 0x12)
        #expect(OfflineSyncResultCode.invalidPayload.rawValue == 0x13)
        #expect(OfflineSyncResultCode.busy.rawValue == 0x14)
        #expect(OfflineSyncResultCode.internalError.rawValue == 0xFF)
    }

    @Test("Outbound messages encode exact v1.1 big-endian payloads")
    func outboundGoldenBytes() throws {
        let begin = try OfflineSyncCodec.encode(.begin(OfflineSyncBegin(
            syncID: 0x0102_0304,
            revision: 0x1112_1314,
            validUntil: 0x2122_2324,
            datasetMask: [.taskList, .dayPack]
        )))
        #expect(begin == Data([
            0x01,
            0x01, 0x02, 0x03, 0x04,
            0x11, 0x12, 0x13, 0x14,
            0x21, 0x22, 0x23, 0x24,
            0x05,
        ]))
        #expect(try OfflineSyncCodec.encode(.commit(syncID: 0x0102_0304)) == Data([
            0x02, 0x01, 0x02, 0x03, 0x04,
        ]))
        #expect(try OfflineSyncCodec.encode(.abort(syncID: 0x1112_1314)) == Data([
            0x03, 0x11, 0x12, 0x13, 0x14,
        ]))
        #expect(try OfflineSyncCodec.encode(.query) == Data([0x04]))
        #expect(try OfflineSyncCodec.encode(.opAck(OfflineSyncOperationAck(
            bootSessionID: 0x3132_3334,
            ackOperationID: 0x4142_4344
        ))) == Data([
            0x05,
            0x31, 0x32, 0x33, 0x34,
            0x41, 0x42, 0x43, 0x44,
        ]))
    }

    @Test("Transaction commands reject zero SyncId and BEGIN rejects reserved DatasetMask bits")
    func beginValidation() {
        #expect(throws: OfflineSyncProtocolError.self) {
            _ = try OfflineSyncCodec.encode(.begin(OfflineSyncBegin(
                syncID: 0,
                revision: 1,
                validUntil: 2,
                datasetMask: .taskList
            )))
        }
        #expect(throws: OfflineSyncProtocolError.self) {
            _ = try OfflineSyncCodec.encode(.begin(OfflineSyncBegin(
                syncID: 1,
                revision: 1,
                validUntil: 2,
                datasetMask: OfflineSyncDatasetMask(rawValue: 0x08)
            )))
        }
        #expect(throws: OfflineSyncProtocolError.zeroSyncID) {
            _ = try OfflineSyncCodec.encode(.commit(syncID: 0))
        }
        #expect(throws: OfflineSyncProtocolError.zeroSyncID) {
            _ = try OfflineSyncCodec.encode(.abort(syncID: 0))
        }
    }

    @Test("STATE strictly decodes all fields and ignores reserved StateFlags bits")
    func stateDecoding() throws {
        let payload = Data([
            0x80,
            0x01, 0x02, 0x03, 0x04,
            0x11, 0x12, 0x13, 0x14,
            0x07,
            0xF5,
            0x40,
            0x21, 0x22, 0x23, 0x24,
            0x31, 0x32, 0x33, 0x34,
        ])

        #expect(try OfflineSyncCodec.decodeInbound(payload) == .state(OfflineSyncState(
            activeRevision: 0x0102_0304,
            validUntil: 0x1112_1314,
            datasetMask: .all,
            stateFlags: [.dataValid, .needsFullSync],
            pendingCount: 0x40,
            bootSessionID: 0x2122_2324,
            currentSyncID: 0x3132_3334
        )))
    }

    @Test("RESULT strictly decodes supported target types and result codes")
    func resultDecoding() throws {
        let payload = Data([
            0x81,
            0x01, 0x02, 0x03, 0x04,
            0x25,
            0x02,
        ])

        #expect(try OfflineSyncCodec.decodeInbound(payload) == .result(OfflineSyncResult(
            syncID: 0x0102_0304,
            targetType: .offlineSync,
            resultCode: .committed
        )))
    }

    @Test("OP_BATCH strictly decodes increasing records including empty original payload")
    func operationBatchDecoding() throws {
        let payload = Data([
            0x82,
            0x01, 0x02, 0x03, 0x04,
            0x02,
            0x00, 0x00, 0x00, 0x07, 0x11, 0x02, 0xAA, 0xBB,
            0x00, 0x00, 0x00, 0x09, 0x12, 0x00,
        ])

        #expect(try OfflineSyncCodec.decodeInbound(payload) == .operationBatch(
            OfflineSyncOperationBatch(
                bootSessionID: 0x0102_0304,
                records: [
                    OfflineSyncOperationRecord(
                        operationID: 7,
                        eventType: 0x11,
                        originalPayload: Data([0xAA, 0xBB])
                    ),
                    OfflineSyncOperationRecord(
                        operationID: 9,
                        eventType: 0x12,
                        originalPayload: Data()
                    ),
                ]
            )
        ))
    }

    @Test("OP_BATCH accepts an exact empty batch")
    func emptyOperationBatchDecoding() throws {
        let payload = Data([0x82, 0x01, 0x02, 0x03, 0x04, 0x00])

        #expect(try OfflineSyncCodec.decodeInbound(payload) == .operationBatch(
            OfflineSyncOperationBatch(bootSessionID: 0x0102_0304, records: [])
        ))
    }

    @Test(
        "Inbound decoder rejects wrong lengths, unknown values, reserved DatasetMask bits and outbound opcodes",
        arguments: [
            Data(),
            Data([0x80]),
            Data(repeating: 0, count: 21),
            Data([0x80] + Array(repeating: 0, count: 8) + [0x08] + Array(repeating: 0, count: 10)),
            Data([0x81, 0, 0, 0, 1, 0x01, 0x00]),
            Data([0x81, 0, 0, 0, 1, 0x25, 0x03]),
            Data([0x01] + Array(repeating: 0, count: 13)),
            Data([0x7F]),
        ]
    )
    func malformedInboundRejected(payload: Data) {
        #expect(throws: OfflineSyncProtocolError.self) {
            _ = try OfflineSyncCodec.decodeInbound(payload)
        }
    }

    @Test(
        "OP_BATCH rejects truncated records, Count mismatch, non-increasing IDs and tail bytes",
        arguments: [
            Data([0x82, 0, 0, 0, 1, 1]),
            Data([0x82, 0, 0, 0, 1, 0, 0xFF]),
            Data([0x82, 0, 0, 0, 1, 1, 0, 0, 0, 1, 0x11, 2, 0xAA]),
            Data([
                0x82, 0, 0, 0, 1, 2,
                0, 0, 0, 2, 0x11, 0,
                0, 0, 0, 2, 0x12, 0,
            ]),
            Data([
                0x82, 0, 0, 0, 1, 2,
                0, 0, 0, 3, 0x11, 0,
                0, 0, 0, 2, 0x12, 0,
            ]),
        ]
    )
    func malformedOperationBatchRejected(payload: Data) {
        #expect(throws: OfflineSyncProtocolError.self) {
            _ = try OfflineSyncCodec.decodeInbound(payload)
        }
    }

    @Test("OP_BATCH rejects a payload larger than the one-byte simple-event length")
    func oversizedOperationBatchRejected() {
        var payload = Data([0x82, 0, 0, 0, 1, 1, 0, 0, 0, 1, 0x11, 0xF4])
        payload.append(Data(repeating: 0xAA, count: 244))
        #expect(payload.count == 256)

        #expect(throws: OfflineSyncProtocolError.self) {
            _ = try OfflineSyncCodec.decodeInbound(payload)
        }
    }
}
