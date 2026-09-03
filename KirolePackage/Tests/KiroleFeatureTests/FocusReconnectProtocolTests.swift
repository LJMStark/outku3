import Foundation
import Testing
@testable import KiroleFeature

@Suite("Focus reconnect wire protocol")
struct FocusReconnectProtocolTests {
    @Test("FOCUS_STATE decodes the 37+N snapshot")
    func focusStateGoldenBytes() throws {
        let state = FocusWireFixtures.focusState()
        let payload = FocusWireFixtures.encodeFocusState(state)

        #expect(payload.count == 37 + state.taskId.utf8.count)
        #expect(try FocusReconnectCodec.decodeFocusState(payload) == state)
    }

    @Test("FOCUS_STATE accepts an idle snapshot with an empty task id")
    func focusStateIdleEmptyTask() throws {
        let state = FocusWireFixtures.focusState(
            sessionId: .idle,
            focusState: .idle,
            taskID: "",
            start: 0,
            elapsed: 0,
            lastOperationID: 0
        )
        #expect(try FocusReconnectCodec.decodeFocusState(FocusWireFixtures.encodeFocusState(state)) == state)
        let sentinel = FocusWireFixtures.idleZeroFocusState()
        #expect(
            try FocusReconnectCodec.decodeFocusState(FocusWireFixtures.encodeFocusState(sentinel))
                == sentinel
        )
    }

    @Test("FOCUS_STATE rejects unknown enums and wrong lengths")
    func focusStateRejected() {
        var short = FocusWireFixtures.encodeFocusState(FocusWireFixtures.focusState())
        short.removeLast()
        #expect(throws: FocusReconnectProtocolError.self) {
            _ = try FocusReconnectCodec.decodeFocusState(short)
        }

        var badState = FocusWireFixtures.encodeFocusState(FocusWireFixtures.focusState())
        badState[17] = 0x09
        #expect(throws: FocusReconnectProtocolError.invalidFocusState(0x09)) {
            _ = try FocusReconnectCodec.decodeFocusState(badState)
        }

        let activeZeroRevision = FocusWireFixtures.encodeFocusState(
            FocusWireFixtures.focusState(revision: 0)
        )
        #expect(throws: FocusReconnectProtocolError.zeroFocusRevision) {
            _ = try FocusReconnectCodec.decodeFocusState(activeZeroRevision)
        }
    }

    @Test("FOCUS_RESOLVE encodes the exact 33-byte verdict")
    func focusResolveGoldenBytes() throws {
        let resolve = OfflineFocusResolve(
            resolveID: 0x0A0B_0C0D,
            sessionId: FocusWireFixtures.sessionId,
            focusState: .active,
            result: .accepted,
            startTimestamp: 1_700_000_000,
            endTimestamp: 0,
            elapsedSeconds: 120,
            focusRevision: 4,
            phase: .building,
            bottles: 0
        )
        let payload = try FocusReconnectCodec.encode(resolve)
        #expect(payload.count == 33)
        #expect(payload[0] == 0x06)
        #expect(payload.bigEndianUInt32(at: 1) == 0x0A0B_0C0D)
        #expect(FocusSessionId.read(from: payload, at: 5) == FocusWireFixtures.sessionId)
        #expect(payload[13] == FocusWireState.active.rawValue)
        #expect(payload[14] == FocusResolveResult.accepted.rawValue)
        #expect(payload.bigEndianUInt32(at: 23) == 120)
        #expect(payload.bigEndianUInt32(at: 27) == 4)
        #expect(payload[31] == 2)
        #expect(payload[32] == 0)
    }

    @Test("Content-empty idle FOCUS_STATE keeps a historical revision as a valid snapshot")
    func meaninglessIdleSnapshot() {
        #expect(FocusWireFixtures.idleZeroFocusState().isMeaninglessIdleSnapshot)
        #expect(FocusWireFixtures.idleZeroFocusState().isContentEmptyIdleSnapshot)
        #expect(FocusWireFixtures.focusState().isMeaninglessIdleSnapshot == false)
        #expect(FocusWireFixtures.focusState().isContentEmptyIdleSnapshot == false)
        let idleWithRevision = FocusWireFixtures.focusState(
            sessionId: .idle,
            focusState: .idle,
            taskID: "",
            start: 0,
            elapsed: 0,
            lastOperationID: 0
        )
        #expect(idleWithRevision.isMeaninglessIdleSnapshot == false)
        #expect(idleWithRevision.isContentEmptyIdleSnapshot)

        // Reproduced 2026-09-03: a device that had just completed a focus
        // session reports an otherwise-empty idle snapshot carrying only the
        // operation watermark of that finished session. Treating the watermark
        // as content made the App send a FOCUS_RESOLVE the device answers with
        // INVALID_STATE, which tore the link down every reconnect. Byte table
        // Ver 1.3.1 §3A: this snapshot must not be resolved.
        let idleWithOperationWatermark = FocusWireFixtures.focusState(
            sessionId: .idle,
            focusState: .idle,
            taskID: "",
            start: 0,
            elapsed: 0,
            lastOperationID: 2
        )
        #expect(idleWithOperationWatermark.isContentEmptyIdleSnapshot)
    }

    @Test("FOCUS_RESOLVE payload equality ignores ResolveID")
    func resolvePayloadEqualityIgnoresResolveID() {
        let first = OfflineFocusResolve(
            resolveID: 1,
            sessionId: FocusWireFixtures.sessionId,
            focusState: .active,
            result: .accepted,
            startTimestamp: 1_700_000_000,
            endTimestamp: 0,
            elapsedSeconds: 120,
            focusRevision: 4,
            phase: .building,
            bottles: 0
        )
        let sameVerdict = first.replacingResolveID(99)
        let differentElapsed = OfflineFocusResolve(
            resolveID: 1,
            sessionId: FocusWireFixtures.sessionId,
            focusState: .active,
            result: .accepted,
            startTimestamp: 1_700_000_000,
            endTimestamp: 0,
            elapsedSeconds: 400,
            focusRevision: 4,
            phase: .building,
            bottles: 0
        )
        #expect(first.matchesPayload(of: sameVerdict))
        #expect(first.matchesPayload(of: differentElapsed) == false)
        #expect(sameVerdict.resolveID == 99)
    }

    @Test("FOCUS_RESOLVE rejects a zero ResolveID")
    func focusResolveRejectsZeroID() {
        let resolve = OfflineFocusResolve(
            resolveID: 0,
            sessionId: .idle,
            focusState: .idle,
            result: .accepted,
            startTimestamp: 0,
            endTimestamp: 0,
            elapsedSeconds: 0,
            focusRevision: 1,
            phase: .idle,
            bottles: 0
        )
        #expect(throws: FocusReconnectProtocolError.zeroResolveID) {
            _ = try FocusReconnectCodec.encode(resolve)
        }
    }

    @Test("FOCUS_RESOLVE rejects FocusRevision zero")
    func focusResolveRejectsZeroRevision() {
        let resolve = OfflineFocusResolve(
            resolveID: 1,
            sessionId: .idle,
            focusState: .idle,
            result: .accepted,
            startTimestamp: 0,
            endTimestamp: 0,
            elapsedSeconds: 0,
            focusRevision: 0,
            phase: .idle,
            bottles: 0
        )
        #expect(throws: FocusReconnectProtocolError.zeroFocusRevision) {
            _ = try FocusReconnectCodec.encode(resolve)
        }
    }

    @Test("EnterTaskIn v2 is 18+N and Complete/Skip v2 is 22+N")
    func taskOperationLengths() {
        #expect(FocusWireFixtures.enterPayload().count == 18 + FocusWireFixtures.taskID.utf8.count)
        #expect(FocusWireFixtures.endPayload().count == 22 + FocusWireFixtures.taskID.utf8.count)
    }
}
