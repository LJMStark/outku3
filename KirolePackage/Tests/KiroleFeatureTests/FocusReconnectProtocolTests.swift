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
        // Nothing to arbitrate: the App must not send a FOCUS_RESOLVE.
        #expect(idleWithOperationWatermark.hasNoArbitrableFocusContent)
        // …but the byte table's rev=0 sentinel requires a zero LastOperationID,
        // so the stricter wire predicate must still reject this shape. Keeping
        // the two apart is what stops the tolerance from reaching the decoder.
        #expect(idleWithOperationWatermark.isContentEmptyIdleSnapshot == false)
        #expect(idleWithOperationWatermark.isMeaninglessIdleSnapshot == false)

        // The exact disagreement behind the 2026-09-03 disconnect loop: the
        // arbiter short-circuits to an all-zero idle verdict while the skip
        // predicate says there is content, so the App rules empty a snapshot it
        // just judged non-empty. Both predicates are now named, so the forensic
        // log reports them rather than re-deriving either.
        #expect(idleWithOperationWatermark.takesIdleShortCircuit)
        #expect(idleWithOperationWatermark.hasNoArbitrableFocusContent)
    }

    /// `FocusReconnectArbiter.decide` must branch on the same predicate the
    /// forensic log reports as `arbiterIdle`. A copy of the condition would keep
    /// logging the old answer after the short-circuit changed — a log that lies
    /// about which judgement was made is worse than no log, since it is the only
    /// BLE record a customer build carries.
    @Test("Arbiter idle short-circuit and its logged predicate stay one source")
    func arbiterIdleShortCircuitMatchesLoggedPredicate() throws {
        let watermarkOnly = FocusWireFixtures.focusState(
            sessionId: .idle,
            focusState: .idle,
            taskID: "",
            start: 0,
            elapsed: 0,
            lastOperationID: 2
        )
        let decision = FocusReconnectArbiter.decide(
            device: watermarkOnly,
            app: FocusReconnectAppSnapshot(active: nil, history: [], currentRevision: 0),
            resolveID: 7
        )

        // Short-circuit taken => all-zero idle verdict, which is what the device
        // rejected with INVALID_STATE.
        #expect(watermarkOnly.takesIdleShortCircuit)
        #expect(decision.command.focusState == .idle)
        #expect(decision.command.sessionId.isIdle)
        #expect(decision.command.elapsedSeconds == 0)
        #expect(decision.action == .none)
    }

    /// The byte table permits FocusRevision = 0 only for a fully empty idle
    /// sentinel, LastOperationID included. Tolerating the operation watermark
    /// for arbitration must not loosen that: a zero-revision snapshot carrying
    /// a watermark is still malformed and has to fail decoding.
    @Test("Zero-revision snapshot carrying an operation watermark is rejected on decode")
    func zeroRevisionWithOperationWatermarkFailsDecode() throws {
        let malformed = FocusWireFixtures.focusState(
            revision: 0,
            sessionId: .idle,
            focusState: .idle,
            taskID: "",
            start: 0,
            elapsed: 0,
            lastOperationID: 2
        )
        let payload = FocusWireFixtures.encodeFocusState(malformed)

        #expect(throws: FocusReconnectProtocolError.zeroFocusRevision) {
            _ = try FocusReconnectCodec.decodeFocusState(payload)
        }
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
