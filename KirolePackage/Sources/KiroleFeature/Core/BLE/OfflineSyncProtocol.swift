import Foundation

/// Datasets staged by one OfflineSync transaction. The v1.1 wire contract assigns DayPack to
/// bit 2 (`0x04`); `0x03` means TaskList and Schedule together, not DayPack.
public struct OfflineSyncDatasetMask: OptionSet, Sendable, Equatable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let taskList = Self(rawValue: 0x01)
    public static let schedule = Self(rawValue: 0x02)
    public static let dayPack = Self(rawValue: 0x04)
    public static let all: Self = [.taskList, .schedule, .dayPack]

    fileprivate var containsOnlyDefinedBits: Bool {
        rawValue & ~Self.all.rawValue == 0
    }
}

/// Flags reported by `STATE`. Bits 5...7 are reserved; receivers ignore them.
public struct OfflineSyncStateFlags: OptionSet, Sendable, Equatable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let dataValid = Self(rawValue: 0x01)
    public static let transactionOpen = Self(rawValue: 0x02)
    public static let needsFullSync = Self(rawValue: 0x04)
    public static let operationOverflow = Self(rawValue: 0x08)
    public static let focusSyncPending = Self(rawValue: 0x10)
    public static let definedBits: Self = [
        .dataValid, .transactionOpen, .needsFullSync, .operationOverflow, .focusSyncPending,
    ]
}

public struct OfflineSyncBegin: Sendable, Equatable {
    public let syncID: UInt32
    public let revision: UInt32
    public let validUntil: UInt32
    public let datasetMask: OfflineSyncDatasetMask

    public init(
        syncID: UInt32,
        revision: UInt32,
        validUntil: UInt32,
        datasetMask: OfflineSyncDatasetMask
    ) {
        self.syncID = syncID
        self.revision = revision
        self.validUntil = validUntil
        self.datasetMask = datasetMask
    }
}

public struct OfflineSyncOperationAck: Sendable, Equatable {
    public let bootSessionID: UInt32
    public let ackOperationID: UInt32

    public init(bootSessionID: UInt32, ackOperationID: UInt32) {
        self.bootSessionID = bootSessionID
        self.ackOperationID = ackOperationID
    }
}

public struct OfflineSyncState: Sendable, Equatable {
    public let activeRevision: UInt32
    public let validUntil: UInt32
    public let datasetMask: OfflineSyncDatasetMask
    public let stateFlags: OfflineSyncStateFlags
    public let pendingCount: UInt8
    public let bootSessionID: UInt32
    public let currentSyncID: UInt32

    public init(
        activeRevision: UInt32,
        validUntil: UInt32,
        datasetMask: OfflineSyncDatasetMask,
        stateFlags: OfflineSyncStateFlags,
        pendingCount: UInt8,
        bootSessionID: UInt32,
        currentSyncID: UInt32
    ) {
        self.activeRevision = activeRevision
        self.validUntil = validUntil
        self.datasetMask = datasetMask
        self.stateFlags = stateFlags
        self.pendingCount = pendingCount
        self.bootSessionID = bootSessionID
        self.currentSyncID = currentSyncID
    }
}

public enum OfflineSyncTargetType: UInt8, Sendable, Equatable {
    case taskList = 0x02
    case schedule = 0x03
    case dayPack = 0x10
    case offlineSync = 0x25
}

public enum OfflineSyncResultCode: UInt8, Sendable, Equatable {
    case accepted = 0x00
    case staged = 0x01
    case committed = 0x02
    case invalidState = 0x10
    case missingDataset = 0x11
    case expired = 0x12
    case invalidPayload = 0x13
    case busy = 0x14
    case internalError = 0xFF
}

public struct OfflineSyncResult: Sendable, Equatable {
    public let syncID: UInt32
    public let targetType: OfflineSyncTargetType
    public let resultCode: OfflineSyncResultCode

    public init(
        syncID: UInt32,
        targetType: OfflineSyncTargetType,
        resultCode: OfflineSyncResultCode
    ) {
        self.syncID = syncID
        self.targetType = targetType
        self.resultCode = resultCode
    }
}

public struct OfflineSyncOperationRecord: Sendable, Equatable {
    public let operationID: UInt32
    public let eventType: UInt8
    public let originalPayload: Data

    public init(operationID: UInt32, eventType: UInt8, originalPayload: Data) {
        self.operationID = operationID
        self.eventType = eventType
        self.originalPayload = originalPayload
    }
}

public struct OfflineSyncOperationBatch: Sendable, Equatable {
    public let bootSessionID: UInt32
    public let records: [OfflineSyncOperationRecord]

    public init(bootSessionID: UInt32, records: [OfflineSyncOperationRecord]) {
        self.bootSessionID = bootSessionID
        self.records = records
    }
}

public enum OfflineSyncOutboundCommand: Sendable, Equatable {
    case begin(OfflineSyncBegin)
    case commit(syncID: UInt32)
    case abort(syncID: UInt32)
    case query
    case opAck(OfflineSyncOperationAck)
    case focusResolve(OfflineFocusResolve)
}

public enum OfflineSyncInboundMessage: Sendable, Equatable {
    case state(OfflineSyncState)
    case result(OfflineSyncResult)
    case operationBatch(OfflineSyncOperationBatch)
    case focusState(OfflineFocusState)
}

public enum OfflineSyncProtocolError: Error, Sendable, Equatable {
    case emptyPayload
    case invalidPayloadLength(expected: Int, actual: Int)
    case payloadExceedsSimpleEventLimit(Int)
    case invalidOpcode(UInt8)
    case zeroSyncID
    case invalidDatasetMask(UInt8)
    case invalidTargetType(UInt8)
    case invalidResultCode(UInt8)
    case truncatedOperationRecord(index: Int)
    case nonIncreasingOperationID(previous: UInt32, current: UInt32)
    case trailingBytes(Int)
    case invalidFocusSnapshot
    case zeroResolveID
}

/// Strict payload codec for BLE type `0x25`. It accepts only the direction-specific opcodes and
/// exact v1.1 lengths. The surrounding simple-frame Type/Length bytes remain the responsibility of
/// `BLEService` and `BLESimpleEncoder`.
public enum OfflineSyncCodec {
    private enum Opcode: UInt8 {
        case begin = 0x01
        case commit = 0x02
        case abort = 0x03
        case query = 0x04
        case opAck = 0x05
        case focusResolve = 0x06
        case state = 0x80
        case result = 0x81
        case operationBatch = 0x82
        case focusState = 0x83
    }

    public static func encode(_ command: OfflineSyncOutboundCommand) throws -> Data {
        switch command {
        case .begin(let begin):
            guard begin.syncID != 0 else { throw OfflineSyncProtocolError.zeroSyncID }
            try validateDatasetMask(begin.datasetMask)
            var payload = Data([Opcode.begin.rawValue])
            payload.appendBigEndian(begin.syncID)
            payload.appendBigEndian(begin.revision)
            payload.appendBigEndian(begin.validUntil)
            payload.append(begin.datasetMask.rawValue)
            return payload

        case .commit(let syncID):
            guard syncID != 0 else { throw OfflineSyncProtocolError.zeroSyncID }
            var payload = Data([Opcode.commit.rawValue])
            payload.appendBigEndian(syncID)
            return payload

        case .abort(let syncID):
            guard syncID != 0 else { throw OfflineSyncProtocolError.zeroSyncID }
            var payload = Data([Opcode.abort.rawValue])
            payload.appendBigEndian(syncID)
            return payload

        case .query:
            return Data([Opcode.query.rawValue])

        case .opAck(let acknowledgement):
            var payload = Data([Opcode.opAck.rawValue])
            payload.appendBigEndian(acknowledgement.bootSessionID)
            payload.appendBigEndian(acknowledgement.ackOperationID)
            return payload

        case .focusResolve(let resolve):
            do {
                return try FocusReconnectCodec.encode(resolve)
            } catch FocusReconnectProtocolError.zeroResolveID {
                throw OfflineSyncProtocolError.zeroResolveID
            }
        }
    }

    public static func decodeInbound(_ payload: Data) throws -> OfflineSyncInboundMessage {
        guard let opcodeByte = payload.first else { throw OfflineSyncProtocolError.emptyPayload }
        guard let opcode = Opcode(rawValue: opcodeByte) else {
            throw OfflineSyncProtocolError.invalidOpcode(opcodeByte)
        }

        switch opcode {
        case .state:
            return .state(try decodeState(payload))
        case .result:
            return .result(try decodeResult(payload))
        case .operationBatch:
            return .operationBatch(try decodeOperationBatch(payload))
        case .focusState:
            do {
                return .focusState(try FocusReconnectCodec.decodeFocusState(payload))
            } catch {
                throw OfflineSyncProtocolError.invalidFocusSnapshot
            }
        case .begin, .commit, .abort, .query, .opAck, .focusResolve:
            throw OfflineSyncProtocolError.invalidOpcode(opcodeByte)
        }
    }

    private static func decodeState(_ payload: Data) throws -> OfflineSyncState {
        try requireExactLength(payload, 20)
        let datasetMask = OfflineSyncDatasetMask(rawValue: payload[9])
        try validateDatasetMask(datasetMask)
        return OfflineSyncState(
            activeRevision: payload.bigEndianUInt32(at: 1),
            validUntil: payload.bigEndianUInt32(at: 5),
            datasetMask: datasetMask,
            stateFlags: OfflineSyncStateFlags(
                rawValue: payload[10] & OfflineSyncStateFlags.definedBits.rawValue
            ),
            pendingCount: payload[11],
            bootSessionID: payload.bigEndianUInt32(at: 12),
            currentSyncID: payload.bigEndianUInt32(at: 16)
        )
    }

    private static func decodeResult(_ payload: Data) throws -> OfflineSyncResult {
        try requireExactLength(payload, 7)
        guard let targetType = OfflineSyncTargetType(rawValue: payload[5]) else {
            throw OfflineSyncProtocolError.invalidTargetType(payload[5])
        }
        guard let resultCode = OfflineSyncResultCode(rawValue: payload[6]) else {
            throw OfflineSyncProtocolError.invalidResultCode(payload[6])
        }
        return OfflineSyncResult(
            syncID: payload.bigEndianUInt32(at: 1),
            targetType: targetType,
            resultCode: resultCode
        )
    }

    private static func decodeOperationBatch(_ payload: Data) throws -> OfflineSyncOperationBatch {
        guard payload.count <= UInt8.max else {
            throw OfflineSyncProtocolError.payloadExceedsSimpleEventLimit(payload.count)
        }
        guard payload.count >= 6 else {
            throw OfflineSyncProtocolError.invalidPayloadLength(expected: 6, actual: payload.count)
        }

        let declaredCount = Int(payload[5])
        var cursor = 6
        var records: [OfflineSyncOperationRecord] = []
        records.reserveCapacity(declaredCount)
        var previousOperationID: UInt32?

        for index in 0..<declaredCount {
            guard payload.count - cursor >= 6 else {
                throw OfflineSyncProtocolError.truncatedOperationRecord(index: index)
            }
            let operationID = payload.bigEndianUInt32(at: cursor)
            let eventType = payload[cursor + 4]
            let originalPayloadLength = Int(payload[cursor + 5])
            cursor += 6
            guard payload.count - cursor >= originalPayloadLength else {
                throw OfflineSyncProtocolError.truncatedOperationRecord(index: index)
            }
            if let previousOperationID, operationID <= previousOperationID {
                throw OfflineSyncProtocolError.nonIncreasingOperationID(
                    previous: previousOperationID,
                    current: operationID
                )
            }
            let originalPayload = payload.subdata(
                in: cursor..<(cursor + originalPayloadLength)
            )
            records.append(OfflineSyncOperationRecord(
                operationID: operationID,
                eventType: eventType,
                originalPayload: originalPayload
            ))
            previousOperationID = operationID
            cursor += originalPayloadLength
        }

        guard cursor == payload.count else {
            throw OfflineSyncProtocolError.trailingBytes(payload.count - cursor)
        }
        return OfflineSyncOperationBatch(
            bootSessionID: payload.bigEndianUInt32(at: 1),
            records: records
        )
    }

    private static func validateDatasetMask(_ mask: OfflineSyncDatasetMask) throws {
        guard mask.containsOnlyDefinedBits else {
            throw OfflineSyncProtocolError.invalidDatasetMask(mask.rawValue)
        }
    }

    private static func requireExactLength(_ payload: Data, _ expected: Int) throws {
        guard payload.count == expected else {
            throw OfflineSyncProtocolError.invalidPayloadLength(
                expected: expected,
                actual: payload.count
            )
        }
    }
}
