import Testing
import Foundation
@testable import KiroleFeature

@Suite("CompanionTextByteBudgetTests")
struct CompanionTextByteBudgetTests {

    // MARK: - enforceByteBudget

    @Test("given text within budget, when enforced, then text is unchanged")
    func givenTextWithinBudget_whenEnforced_thenUnchanged() {
        let text = "You've got this!"

        let result = CompanionTextService.enforceByteBudget(text, maxBytes: 120)

        #expect(result == text)
    }

    @Test("given text exactly at budget, when enforced, then text is unchanged")
    func givenTextExactlyAtBudget_whenEnforced_thenUnchanged() {
        let text = String(repeating: "a", count: 120)

        let result = CompanionTextService.enforceByteBudget(text, maxBytes: 120)

        #expect(result == text)
    }

    @Test("given text over budget with sentence boundary, when enforced, then trimmed to last sentence")
    func givenOverBudgetWithSentenceBoundary_whenEnforced_thenTrimmedToLastSentence() {
        // First sentence fits, second pushes over
        let first = "Short sentence."
        let second = " " + String(repeating: "x", count: 200)
        let text = first + second

        let result = CompanionTextService.enforceByteBudget(text, maxBytes: 120)

        #expect(result == first)
        #expect(result.utf8.count <= 120)
    }

    @Test("given text over budget without sentence boundary, when enforced, then hard-truncated within budget")
    func givenOverBudgetNoSentenceBoundary_whenEnforced_thenHardTruncated() {
        let text = String(repeating: "x", count: 200)

        let result = CompanionTextService.enforceByteBudget(text, maxBytes: 120)

        #expect(result.utf8.count <= 120)
        #expect(!result.isEmpty)
    }

    @Test("given empty text, when enforced, then empty text returned")
    func givenEmptyText_whenEnforced_thenEmptyReturned() {
        let result = CompanionTextService.enforceByteBudget("", maxBytes: 120)

        #expect(result.isEmpty)
    }

    @Test("given Chinese text over budget, when enforced, then trimmed at Chinese sentence boundary")
    func givenChineseTextOverBudget_whenEnforced_thenTrimmedAtChineseSentenceBoundary() {
        // Each Chinese char is 3 bytes; "。" is also 3 bytes
        // 20 chars (60 bytes) + "。" (3 bytes) = 63 bytes — fits in 120
        // Then 30 more chars (90 bytes) — total 153 bytes > 120
        let firstSentence = String(repeating: "专", count: 20) + "。"
        let rest = String(repeating: "注", count: 30)
        let text = firstSentence + rest

        let result = CompanionTextService.enforceByteBudget(text, maxBytes: 120)

        #expect(result == firstSentence)
        #expect(result.utf8.count <= 120)
    }

    @Test("given text with exclamation mark boundary, when enforced, then trimmed at exclamation mark")
    func givenExclamationBoundary_whenEnforced_thenTrimmedAtBoundary() {
        let first = "Let's go!"
        let text = first + " " + String(repeating: "z", count: 200)

        let result = CompanionTextService.enforceByteBudget(text, maxBytes: 120)

        #expect(result == first)
    }

    @Test("given result must fit in BLE frame, when max 120 bytes enforced, then result fits BLE constraint")
    func givenBLEFrameConstraint_whenEnforced_thenFitsFrame() {
        let longText = "This is a very long companion phrase that would exceed the BLE frame limit when transmitted to the E-ink hardware device over Bluetooth Low Energy protocol!"

        let result = CompanionTextService.enforceByteBudget(longText, maxBytes: 120)

        #expect(result.utf8.count <= 120)
    }
}
