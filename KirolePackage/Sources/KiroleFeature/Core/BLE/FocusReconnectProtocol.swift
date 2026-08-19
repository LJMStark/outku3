import Foundation

/// 8-byte focus session key: `BootSessionId + StartOperationID`. All-zero means idle / no target.
public struct FocusSessionId: Hashable, Codable, Sendable, Equatable {
    public let bootSessionID: UInt32
    public let startOperationID: UInt32

    public static let idle = FocusSessionId(bootSessionID: 0, startOperationID: 0)

    public var isIdle: Bool {
        bootSessionID == 0 && startOperationID == 0
    }

    public init(bootSessionID: UInt32, startOperationID: UInt32) {
        self.bootSessionID = bootSessionID
        self.startOperationID = startOperationID
    }

    public init?(bytes: Data) {
        guard bytes.count == 8 else { return nil }
        self.init(
            bootSessionID: bytes.bigEndianUInt32(at: 0),
            startOperationID: bytes.bigEndianUInt32(at: 4)
        )
    }

    public var bytes: Data {
        var data = Data()
        data.appendBigEndian(bootSessionID)
        data.appendBigEndian(startOperationID)
        return data
    }

    public static func read(from data: Data, at offset: Int) -> FocusSessionId {
        FocusSessionId(
            bootSessionID: data.bigEndianUInt32(at: offset),
            startOperationID: data.bigEndianUInt32(at: offset + 4)
        )
    }
}

public enum FocusWireState: UInt8, Sendable, Equatable {
    case idle = 0x00
    case active = 0x01
    case endedPending = 0x02
}

public enum FocusStartSource: UInt8, Sendable, Equatable, Codable {
    case appEstablished = 0x00
    case deviceOffline = 0x01
}

public enum FocusDeviceEndReason: UInt8, Sendable, Equatable {
    case none = 0x00
    case complete = 0x01
    case skip = 0x02
    case appEnd = 0x03
}

public enum FocusResolveResult: UInt8, Sendable, Equatable {
    case accepted = 0x00
    case closed = 0x01
    case conflictResolved = 0x02
    case rejected = 0x03
    case internalError = 0xFF
}

public enum FocusReconnectProtocolError: Error, Sendable, Equatable {
    case invalidPayloadLength(expected: Int, actual: Int)
    case invalidFocusState(UInt8)
    case invalidStartSource(UInt8)
    case invalidEndReason(UInt8)
    case invalidResolveResult(UInt8)
    case zeroResolveID
    case invalidTaskIdLength(Int)
    case invalidTaskId
    case trailingBytes(Int)
}

/// Device → App `0x25 / 0x83` snapshot. Payload length is `37 + TaskIdLength`.
public struct OfflineFocusState: Sendable, Equatable {
    public let focusRevision: UInt32
    public let bootSessionID: UInt32
    public let sessionId: FocusSessionId
    public let focusState: FocusWireState
    public let startSource: FocusStartSource
    public let taskId: String
    public let startTimestamp: UInt32
    public let endTimestamp: UInt32
    public let elapsedSeconds: UInt32
    public let lastOperationID: UInt32
    public let endReason: FocusDeviceEndReason

    public init(
        focusRevision: UInt32,
        bootSessionID: UInt32,
        sessionId: FocusSessionId,
        focusState: FocusWireState,
        startSource: FocusStartSource,
        taskId: String,
        startTimestamp: UInt32,
        endTimestamp: UInt32,
        elapsedSeconds: UInt32,
        lastOperationID: UInt32,
        endReason: FocusDeviceEndReason
    ) {
        self.focusRevision = focusRevision
        self.bootSessionID = bootSessionID
        self.sessionId = sessionId
        self.focusState = focusState
        self.startSource = startSource
        self.taskId = taskId
        self.startTimestamp = startTimestamp
        self.endTimestamp = endTimestamp
        self.elapsedSeconds = elapsedSeconds
        self.lastOperationID = lastOperationID
        self.endReason = endReason
    }
}

/// App → Device `0x25 / 0x06` verdict. Payload is exactly 33 bytes.
public struct OfflineFocusResolve: Sendable, Equatable {
    public let resolveID: UInt32
    public let sessionId: FocusSessionId
    public let focusState: FocusWireState
    public let result: FocusResolveResult
    public let startTimestamp: UInt32
    public let endTimestamp: UInt32
    public let elapsedSeconds: UInt32
    public let focusRevision: UInt32
    public let phase: FocusPhase
    public let bottles: UInt8

    public init(
        resolveID: UInt32,
        sessionId: FocusSessionId,
        focusState: FocusWireState,
        result: FocusResolveResult,
        startTimestamp: UInt32,
        endTimestamp: UInt32,
        elapsedSeconds: UInt32,
        focusRevision: UInt32,
        phase: FocusPhase,
        bottles: UInt8
    ) {
        self.resolveID = resolveID
        self.sessionId = sessionId
        self.focusState = focusState
        self.result = result
        self.startTimestamp = startTimestamp
        self.endTimestamp = endTimestamp
        self.elapsedSeconds = elapsedSeconds
        self.focusRevision = focusRevision
        self.phase = phase
        self.bottles = bottles
    }
}

public enum FocusReconnectCodec {
    public static let focusStatusSubVersion: UInt8 = 0x02
    public static let taskOperationSubVersion: UInt8 = 0x02
    public static let resolvePayloadLength = 33
    public static let focusStateFixedLength = 37

    public static func encode(_ resolve: OfflineFocusResolve) throws -> Data {
        guard resolve.resolveID != 0 else { throw FocusReconnectProtocolError.zeroResolveID }
        var payload = Data([0x06])
        payload.appendBigEndian(resolve.resolveID)
        payload.append(resolve.sessionId.bytes)
        payload.append(resolve.focusState.rawValue)
        payload.append(resolve.result.rawValue)
        payload.appendBigEndian(resolve.startTimestamp)
        payload.appendBigEndian(resolve.endTimestamp)
        payload.appendBigEndian(resolve.elapsedSeconds)
        payload.appendBigEndian(resolve.focusRevision)
        payload.append(resolve.phase.wireByte)
        payload.append(resolve.bottles)
        return payload
    }

    public static func decodeFocusState(_ payload: Data) throws -> OfflineFocusState {
        guard payload.count >= focusStateFixedLength else {
            throw FocusReconnectProtocolError.invalidPayloadLength(
                expected: focusStateFixedLength,
                actual: payload.count
            )
        }
        guard payload[0] == 0x83 else {
            throw FocusReconnectProtocolError.invalidPayloadLength(
                expected: focusStateFixedLength,
                actual: payload.count
            )
        }

        let taskIdLength = Int(payload[19])
        guard (0...36).contains(taskIdLength) else {
            throw FocusReconnectProtocolError.invalidTaskIdLength(taskIdLength)
        }
        let expected = focusStateFixedLength + taskIdLength
        guard payload.count == expected else {
            throw FocusReconnectProtocolError.invalidPayloadLength(
                expected: expected,
                actual: payload.count
            )
        }

        let taskIdData = payload.subdata(in: 20..<(20 + taskIdLength))
        let taskId: String
        if taskIdLength == 0 {
            taskId = ""
        } else {
            guard let decoded = String(data: taskIdData, encoding: .utf8) else {
                throw FocusReconnectProtocolError.invalidTaskId
            }
            taskId = decoded
        }

        guard let focusState = FocusWireState(rawValue: payload[17]) else {
            throw FocusReconnectProtocolError.invalidFocusState(payload[17])
        }
        guard let startSource = FocusStartSource(rawValue: payload[18]) else {
            throw FocusReconnectProtocolError.invalidStartSource(payload[18])
        }
        let endReasonByte = payload[36 + taskIdLength]
        guard let endReason = FocusDeviceEndReason(rawValue: endReasonByte) else {
            throw FocusReconnectProtocolError.invalidEndReason(endReasonByte)
        }

        return OfflineFocusState(
            focusRevision: payload.bigEndianUInt32(at: 1),
            bootSessionID: payload.bigEndianUInt32(at: 5),
            sessionId: FocusSessionId.read(from: payload, at: 9),
            focusState: focusState,
            startSource: startSource,
            taskId: taskId,
            startTimestamp: payload.bigEndianUInt32(at: 20 + taskIdLength),
            endTimestamp: payload.bigEndianUInt32(at: 24 + taskIdLength),
            elapsedSeconds: payload.bigEndianUInt32(at: 28 + taskIdLength),
            lastOperationID: payload.bigEndianUInt32(at: 32 + taskIdLength),
            endReason: endReason
        )
    }
}

public extension FocusPhase {
    var wireByte: UInt8 {
        switch self {
        case .idle: 0
        case .warmup: 1
        case .building: 2
        case .deep: 3
        }
    }

    static func fromSegmentSeconds(_ seconds: UInt32) -> FocusPhase {
        from(elapsedMinutes: Int(seconds / 60))
    }
}

public extension FocusDeviceEndReason {
    var focusEndReason: FocusEndReason? {
        switch self {
        case .none: nil
        case .complete: .completed
        case .skip: .skipped
        case .appEnd: .manual
        }
    }
}
