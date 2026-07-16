import Foundation
import Testing
@testable import KiroleFeature

// 专注页伴侣陪伴语选句器：按内置角色 × 阶段分池（联审 2026-07-16 F8），自定义伴侣
// （character == nil）回退中性池。钉住：确定性轮换（同分钟段同句、跨 10 分钟档换句）、
// idle 兜底映射 warmup 池、全池非空且 ASCII 可打印（English-only UI 守门）、角色分池确实生效。
@Suite("Focus Companion Phrases")
struct FocusCompanionPhrasesTests {
    private let realPhases: [FocusPhase] = [.warmup, .building, .deep]
    /// nil = 自定义伴侣（中性池）。
    private let characters: [CompanionCharacter?] = [.joy, .silas, .nova, nil]

    @Test("Same character, phase and minute bucket always returns the same phrase")
    func deterministicWithinBucket() {
        for character in characters {
            for phase in realPhases {
                let first = FocusCompanionPhrases.phrase(character: character, phase: phase, elapsedMinutes: 3)
                let again = FocusCompanionPhrases.phrase(character: character, phase: phase, elapsedMinutes: 9)
                #expect(first == again, "minutes 3 and 9 share the 0-9 bucket for \(String(describing: character))/\(phase)")
            }
        }
    }

    @Test("Crossing a rotation boundary moves to the next phrase in the pool")
    func rotatesAcrossBuckets() {
        for character in characters {
            for phase in realPhases {
                let pool = FocusCompanionPhrases.pool(character: character, phase: phase)
                let atZero = FocusCompanionPhrases.phrase(character: character, phase: phase, elapsedMinutes: 0)
                let atTen = FocusCompanionPhrases.phrase(character: character, phase: phase, elapsedMinutes: 10)
                #expect(atZero == pool[0])
                #expect(atTen == pool[1 % pool.count])
            }
        }
    }

    @Test("Rotation wraps around the pool instead of running out")
    func rotationWraps() {
        for character in characters {
            for phase in realPhases {
                let pool = FocusCompanionPhrases.pool(character: character, phase: phase)
                let wrapped = FocusCompanionPhrases.phrase(
                    character: character,
                    phase: phase,
                    elapsedMinutes: pool.count * FocusCompanionPhrases.rotationMinutes
                )
                #expect(wrapped == pool[0])
            }
        }
    }

    @Test("Idle phase falls back to the warmup pool (first live minute)")
    func idleFallsBackToWarmup() {
        for character in characters {
            let idle = FocusCompanionPhrases.phrase(character: character, phase: .idle, elapsedMinutes: 0)
            let warmup = FocusCompanionPhrases.phrase(character: character, phase: .warmup, elapsedMinutes: 0)
            #expect(idle == warmup)
        }
    }

    @Test("All pools are non-empty and printable ASCII", arguments: [
        FocusPhase.idle, .warmup, .building, .deep,
    ])
    func poolsAreNonEmptyPrintableASCII(phase: FocusPhase) {
        for character in characters {
            let pool = FocusCompanionPhrases.pool(character: character, phase: phase)
            #expect(!pool.isEmpty)
            for phrase in pool {
                #expect(!phrase.isEmpty)
                let allPrintableASCII = phrase.unicodeScalars.allSatisfy { scalar in
                    (0x20...0x7E).contains(scalar.value)
                }
                #expect(allPrintableASCII, "non-ASCII character in: \(phrase)")
            }
        }
    }

    @Test("Built-in characters get distinct persona pools; custom falls back to neutral")
    func characterPoolsAreDistinct() {
        for phase in realPhases {
            let joy = FocusCompanionPhrases.pool(character: .joy, phase: phase)
            let silas = FocusCompanionPhrases.pool(character: .silas, phase: phase)
            let nova = FocusCompanionPhrases.pool(character: .nova, phase: phase)
            let neutral = FocusCompanionPhrases.pool(character: nil, phase: phase)

            #expect(joy != silas)
            #expect(silas != nova)
            #expect(joy != nova)
            #expect(neutral != joy && neutral != silas && neutral != nova)
        }
    }

    @Test("Nova never says the warm neutral praise lines (persona guard)")
    func novaStaysRestrained() {
        // 联审 F8 的具体反例：克制人设不该出现中性池的示爱式赞美。
        let bannedForNova = ["Proud of you. Truly.", "I've got your back."]
        for phase in [FocusPhase.warmup, .building, .deep] {
            let pool = FocusCompanionPhrases.pool(character: .nova, phase: phase)
            for banned in bannedForNova {
                #expect(!pool.contains(banned))
            }
        }
    }

    @Test("Negative elapsed minutes clamps instead of trapping")
    func negativeMinutesClamp() {
        let phrase = FocusCompanionPhrases.phrase(character: .joy, phase: .warmup, elapsedMinutes: -5)
        #expect(phrase == FocusCompanionPhrases.pool(character: .joy, phase: .warmup)[0])
    }
}
