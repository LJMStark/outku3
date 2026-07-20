import Foundation
import Testing
@testable import KiroleFeature

/// 客户 2026-07-20「页面四 每日总结」文案栈：
/// 概况点评两条硬规则（死线必提、专注>2h 必提）由兜底模板**确定性**满足；
/// 金句三分支中 fullSchedule 为客户逐字指定的固定文案，永不走 AI。
@Suite("DayPack Settlement Texts")
struct DayPackSettlementTextTests {

    // MARK: - FallbackText.settlementReview（硬规则的确定性保证）

    @Test("死线超 8 条：第 9 条起经 overflow 参数并入 review（离线兜底可见）")
    @MainActor func overflowDeadlineReachesReview() async {
        let text = await CompanionTextService.shared.generateSettlementReview(
            events: [EventSummary(time: "09:00", title: "Standup", description: "", category: .meetings)],
            overflowDeadlineTitles: ["Contract payment due"],
            focusMinutes: 0, tasksCompleted: 0, tasksTotal: 2
        )
        #expect(text.contains("Contract payment due"))
    }

    @Test("review 兜底：有死线事件必须点名")
    func reviewMentionsDeadline() {
        let text = FallbackText.settlementReview(
            deadlineTitles: ["Ship v3 launch"], focusMinutes: 0,
            tasksCompleted: 1, tasksTotal: 4
        )
        #expect(text.contains("Ship v3 launch"))
    }

    @Test("review 兜底：专注 121 分钟必须提时长（>2h 硬规则）")
    func reviewMentionsFocusAboveThreshold() {
        let text = FallbackText.settlementReview(
            deadlineTitles: [], focusMinutes: 121,
            tasksCompleted: 2, tasksTotal: 3
        )
        #expect(text.contains("2h 1m"))
    }

    @Test("review 兜底：专注恰好 120 分钟不强制提（阈值严格大于）")
    func reviewOmitsFocusAtThreshold() {
        let text = FallbackText.settlementReview(
            deadlineTitles: [], focusMinutes: 120,
            tasksCompleted: 2, tasksTotal: 3
        )
        #expect(!text.contains("focused for"))
    }

    @Test("review 兜底：完成数与总数如实呈现")
    func reviewStatesCompletionCounts() {
        let text = FallbackText.settlementReview(
            deadlineTitles: [], focusMinutes: 0,
            tasksCompleted: 3, tasksTotal: 5
        )
        #expect(text.contains("3 of 5"))
    }

    @Test("review 兜底：空日 + 双硬规则同时满足，且在 180B 预算内")
    func reviewFitsBudgetWithBothRules() {
        let text = FallbackText.settlementReview(
            deadlineTitles: ["Contract payment due"], focusMinutes: 200,
            tasksCompleted: 0, tasksTotal: 0
        )
        #expect(text.contains("Contract payment due"))
        #expect(text.contains("3h 20m"))
        #expect(text.utf8.count <= DayPackTextBudget.settlementReview)
    }

    // MARK: - 金句模板（非空、ASCII、预算内）

    @Test("金句模板（含三 IP 庆祝池与中性池）均非空、纯 ASCII、不超 120B 预算")
    func quoteTemplatesAreWireSafe() {
        let quotes = [
            FallbackText.settlementQuoteCelebration(style: .joy),
            FallbackText.settlementQuoteCelebration(style: .silas),
            FallbackText.settlementQuoteCelebration(style: .nova),
            FallbackText.settlementQuoteCelebration(style: nil),
            FallbackText.settlementQuoteOverloaded(),
            FallbackText.settlementQuoteFullSchedule()
        ]
        for quote in quotes {
            #expect(!quote.isEmpty)
            #expect(quote.utf8.count <= DayPackTextBudget.settlementQuote)
            #expect(quote.allSatisfy { $0.isASCII })
        }
    }

    @Test("review 兜底预算感知：超长死线标题被截 60B，专注句仍在 180B 内保留")
    func reviewFallbackKeepsFocusUnderBudget() {
        let longTitle = String(repeating: "Quarterly compliance filing ", count: 8) // ~224 chars
        let text = FallbackText.settlementReview(
            deadlineTitles: [longTitle], focusMinutes: 150,
            tasksCompleted: 1, tasksTotal: 4
        )
        #expect(text.utf8.count <= DayPackTextBudget.settlementReview)
        #expect(text.contains("2h 30m")) // 专注硬规则不被超长标题挤掉
    }

    @Test("fullSchedule 分支返回客户指定文案（不走 AI，离线在线一致）")
    @MainActor func fullScheduleBranchIsClientCopy() async {
        let text = await CompanionTextService.shared.generateSettlementQuote(
            branch: .fullSchedule, petName: "Waffle", petMood: .happy,
            tasksCompleted: 1, tasksTotal: 3, focusMinutes: 60
        )
        #expect(text == "When the schedule is full, plan fewer tasks to leave room for focus.")
    }

    @Test("celebration/overloaded 分支离线回退到对应模板（无 API key 环境）")
    @MainActor func aiBranchesFallBackOffline() async {
        let celebration = await CompanionTextService.shared.generateSettlementQuote(
            branch: .celebration, petName: "Waffle", petMood: .happy,
            tasksCompleted: 3, tasksTotal: 3, focusMinutes: 0
        )
        let overloaded = await CompanionTextService.shared.generateSettlementQuote(
            branch: .overloadedDay, petName: "Waffle", petMood: .happy,
            tasksCompleted: 1, tasksTotal: 3, focusMinutes: 300
        )
        #expect(!celebration.isEmpty)
        #expect(overloaded == FallbackText.settlementQuoteOverloaded())
    }

    @Test("review 编排离线走兜底且带死线（generateSettlementReview 全链路）")
    @MainActor func reviewOrchestrationOfflineFallback() async {
        let events = [
            EventSummary(time: "09:00", title: "Standup", description: "", category: .meetings),
            EventSummary(time: "15:00", title: "Launch day", description: "", category: .deadline)
        ]
        let text = await CompanionTextService.shared.generateSettlementReview(
            events: events, focusMinutes: 150, tasksCompleted: 1, tasksTotal: 2
        )
        #expect(text.contains("Launch day"))
        #expect(text.contains("2h 30m"))
    }

    // MARK: - focusDurationLabel

    @Test("时长标签：135→2h 15m、120→2h、45→45m、0→0m、负数钳为 0m")
    func focusDurationLabelFormats() {
        #expect(DayPackGenerator.focusDurationLabel(minutes: 135) == "2h 15m")
        #expect(DayPackGenerator.focusDurationLabel(minutes: 120) == "2h")
        #expect(DayPackGenerator.focusDurationLabel(minutes: 45) == "45m")
        #expect(DayPackGenerator.focusDurationLabel(minutes: 0) == "0m")
        #expect(DayPackGenerator.focusDurationLabel(minutes: -30) == "0m")
    }

    @Test("硬规则输出校验：死线未提/时长未提 → 拒收，兜底模板恒通过")
    func reviewHardRuleValidator() {
        // 死线：至少提到一个标题（大小写不敏感）
        #expect(CompanionTextService.reviewSatisfiesHardRules(
            "You wrapped up the launch deadline today.", deadlineTitles: ["Launch Deadline"], focusMinutes: 0))
        #expect(!CompanionTextService.reviewSatisfiesHardRules(
            "A busy but steady day overall.", deadlineTitles: ["Launch Deadline"], focusMinutes: 0))
        // 专注 >2h：必须出现时长标签
        #expect(CompanionTextService.reviewSatisfiesHardRules(
            "You focused for 2h 5m today.", deadlineTitles: [], focusMinutes: 125))
        #expect(!CompanionTextService.reviewSatisfiesHardRules(
            "Great focus today.", deadlineTitles: [], focusMinutes: 125))
        // 恰 120 分钟不触发规则
        #expect(CompanionTextService.reviewSatisfiesHardRules(
            "Great focus today.", deadlineTitles: [], focusMinutes: 120))
        // 兜底模板自身恒满足
        let fallback = FallbackText.settlementReview(
            deadlineTitles: ["Ship v3"], focusMinutes: 130, tasksCompleted: 1, tasksTotal: 2)
        #expect(CompanionTextService.reviewSatisfiesHardRules(
            fallback, deadlineTitles: ["Ship v3"], focusMinutes: 130))
    }

    @Test("isDisplayablePanelText：拒空、拒错误占位、拒 CJK，收正常英文")
    func displayablePanelTextGuard() {
        #expect(CompanionTextService.isDisplayablePanelText("A fine day."))
        #expect(!CompanionTextService.isDisplayablePanelText(""))
        #expect(!CompanionTextService.isDisplayablePanelText("[Error] boom"))
        #expect(!CompanionTextService.isDisplayablePanelText("今天很努力"))
    }
}
