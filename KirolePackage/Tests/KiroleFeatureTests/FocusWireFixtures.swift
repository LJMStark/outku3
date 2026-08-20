import Foundation
@testable import KiroleFeature

enum FocusWireFixtures {
    static let sessionId = FocusSessionId(bootSessionID: 0x0102_0304, startOperationID: 0x0000_0007)
    static let taskID = "task-1"
    static let timestamp: UInt32 = 1_700_000_000

    static func enterPayload(
        operationID: UInt32 = 7,
        sessionId: FocusSessionId = sessionId,
        taskID: String = taskID,
        start: UInt32 = timestamp
    ) -> Data {
        var data = Data([FocusReconnectCodec.taskOperationSubVersion])
        data.appendBigEndian(operationID)
        data.append(sessionId.bytes)
        data.append(UInt8(taskID.utf8.count))
        data.append(contentsOf: taskID.utf8)
        data.appendBigEndian(start)
        return data
    }

    static func endPayload(
        operationID: UInt32 = 8,
        sessionId: FocusSessionId = sessionId,
        taskID: String = taskID,
        end: UInt32 = timestamp + 600,
        elapsed: UInt32 = 600
    ) -> Data {
        var data = Data([FocusReconnectCodec.taskOperationSubVersion])
        data.appendBigEndian(operationID)
        data.append(sessionId.bytes)
        data.append(UInt8(taskID.utf8.count))
        data.append(contentsOf: taskID.utf8)
        data.appendBigEndian(end)
        data.appendBigEndian(elapsed)
        return data
    }

    static func focusState(
        revision: UInt32 = 3,
        bootSessionID: UInt32 = 0x0102_0304,
        sessionId: FocusSessionId = sessionId,
        focusState: FocusWireState = .active,
        startSource: FocusStartSource = .deviceOffline,
        taskID: String = taskID,
        start: UInt32 = timestamp,
        end: UInt32 = 0,
        elapsed: UInt32 = 120,
        lastOperationID: UInt32 = 7,
        endReason: FocusDeviceEndReason = .none
    ) -> OfflineFocusState {
        OfflineFocusState(
            focusRevision: revision,
            bootSessionID: bootSessionID,
            sessionId: sessionId,
            focusState: focusState,
            startSource: startSource,
            taskId: taskID,
            startTimestamp: start,
            endTimestamp: end,
            elapsedSeconds: elapsed,
            lastOperationID: lastOperationID,
            endReason: endReason
        )
    }

    /// Matches the 1.3.1 wake dump: revision/session/operation all zero, idle.
    static func idleZeroFocusState(bootSessionID: UInt32 = 7) -> OfflineFocusState {
        OfflineFocusState(
            focusRevision: 0,
            bootSessionID: bootSessionID,
            sessionId: .idle,
            focusState: .idle,
            startSource: .appEstablished,
            taskId: "",
            startTimestamp: 0,
            endTimestamp: 0,
            elapsedSeconds: 0,
            lastOperationID: 0,
            endReason: .none
        )
    }

    static func encodeFocusState(_ state: OfflineFocusState) -> Data {
        var data = Data([0x83])
        data.appendBigEndian(state.focusRevision)
        data.appendBigEndian(state.bootSessionID)
        data.append(state.sessionId.bytes)
        data.append(state.focusState.rawValue)
        data.append(state.startSource.rawValue)
        data.append(UInt8(state.taskId.utf8.count))
        data.append(contentsOf: state.taskId.utf8)
        data.appendBigEndian(state.startTimestamp)
        data.appendBigEndian(state.endTimestamp)
        data.appendBigEndian(state.elapsedSeconds)
        data.appendBigEndian(state.lastOperationID)
        data.append(state.endReason.rawValue)
        return data
    }
}
