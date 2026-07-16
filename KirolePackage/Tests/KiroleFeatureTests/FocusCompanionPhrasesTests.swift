import Foundation
import Testing
@testable import KiroleFeature

// 专注页伴侣陪伴语选句器：确定性轮换（同分钟段同句、跨 10 分钟档换句）、
// idle 兜底映射 warmup 池、全池非空且 ASCII 可打印（English-only UI 约束的守门测试）。
@Suite("Focus Companion Phrases")
struct FocusCompanionPhrasesTests {
    private let realPhases: [FocusPhase] = [.warmup, .building, .deep]

    @Test("Same phase and minute bucket always returns the same phrase")
    func deterministicWithinBucket() {
        for phase in realPhases {
            let first = FocusCompanionPhrases.phrase(phase: phase, elapsedMinutes: 3)
            let again = FocusCompanionPhrases.phrase(phase: phase, elapsedMinutes: 9)
            #expect(first == again, "minutes 3 and 9 share the 0-9 bucket for \(phase)")
        }
    }

    @Test("Crossing a rotation boundary moves to the next phrase in the pool")
    func rotatesAcrossBuckets() {
        for phase in realPhases {
            let pool = FocusCompanionPhrases.pool(for: phase)
            let atZero = FocusCompanionPhrases.phrase(phase: phase, elapsedMinutes: 0)
            let atTen = FocusCompanionPhrases.phrase(phase: phase, elapsedMinutes: 10)
            #expect(atZero == pool[0])
            #expect(atTen == pool[1 % pool.count])
        }
    }

    @Test("Rotation wraps around the pool instead of running out")
    func rotationWraps() {
        for phase in realPhases {
            let pool = FocusCompanionPhrases.pool(for: phase)
            let wrapped = FocusCompanionPhrases.phrase(
                phase: phase,
                elapsedMinutes: pool.count * FocusCompanionPhrases.rotationMinutes
            )
            #expect(wrapped == pool[0])
        }
    }

    @Test("Idle phase falls back to the warmup pool (first live minute)")
    func idleFallsBackToWarmup() {
        let idle = FocusCompanionPhrases.phrase(phase: .idle, elapsedMinutes: 0)
        let warmup = FocusCompanionPhrases.phrase(phase: .warmup, elapsedMinutes: 0)
        #expect(idle == warmup)
    }

    @Test("All pools are non-empty and printable ASCII", arguments: [
        FocusPhase.idle, .warmup, .building, .deep,
    ])
    func poolsAreNonEmptyPrintableASCII(phase: FocusPhase) {
        let pool = FocusCompanionPhrases.pool(for: phase)
        #expect(!pool.isEmpty)
        for phrase in pool {
            #expect(!phrase.isEmpty)
            let allPrintableASCII = phrase.unicodeScalars.allSatisfy { scalar in
                (0x20...0x7E).contains(scalar.value)
            }
            #expect(allPrintableASCII, "non-ASCII character in: \(phrase)")
        }
    }

    @Test("Negative elapsed minutes clamps instead of trapping")
    func negativeMinutesClamp() {
        let phrase = FocusCompanionPhrases.phrase(phase: .warmup, elapsedMinutes: -5)
        #expect(phrase == FocusCompanionPhrases.pool(for: .warmup)[0])
    }
}
