import Foundation

// MARK: - Event Category Service

/// 日历事件 AI 打标服务：把当天事件批量分类为六大类（`EventCategory`），随 DayPack
/// Events[] 的 Category 字节下发硬件（协议 §4.7，v2.5.27）。
///
/// - 缓存：结果按「标题|描述」键做内存缓存，同一事件跨 BLE sync 轮（白天每小时）
///   不重复调 LLM；仅内存——分类是廉价可再生数据，进程重启后首轮重分类即回填。
/// - 兜底链：AI 不可用/出错/回复对不齐 → 关键词启发式 → `.unknown`（固件不画图标）。
///   启发式结果**不缓存**；AI 调用失败后冷却 10 分钟再重试，恢复后自动升级分类。
///   降级必记日志（透明兜底规则）。
@MainActor
public final class EventCategoryService {
    public static let shared = EventCategoryService()

    private let openAI = OpenAIService.shared
    private var cache: [String: EventCategory] = [:]
    private var aiRetryAfter: Date?
    /// 缓存上限：当天事件 ≤8 条，正常远够；防的是长期运行下的无界增长。
    private static let cacheLimit = 512
    nonisolated static let aiFailureCooldown: TimeInterval = 10 * 60

    private init() {}

    /// Returns `summaries` with categories filled: cached hits first, ONE batched AI call for
    /// the misses, per-event keyword heuristic for whatever AI could not fill.
    public func categorized(_ summaries: [EventSummary]) async -> [EventSummary] {
        guard !summaries.isEmpty else { return [] }

        var resolved: [EventCategory?] = summaries.map { cache[Self.cacheKey(for: $0)] }
        let pendingIndices = resolved.indices.filter { resolved[$0] == nil }

        if !pendingIndices.isEmpty,
           Self.isAIRetryAllowed(retryAfter: aiRetryAfter, now: Date()),
           await openAI.isConfigured {
            let pendingEvents = pendingIndices.map { Self.classificationText(for: summaries[$0]) }
            do {
                let categories = try await openAI.classifyEventCategories(events: pendingEvents)
                aiRetryAfter = nil
                if cache.count > Self.cacheLimit { cache.removeAll() }
                for (offset, index) in pendingIndices.enumerated() {
                    resolved[index] = categories[offset]
                    cache[Self.cacheKey(for: summaries[index])] = categories[offset]
                }
            } catch {
                aiRetryAfter = Date().addingTimeInterval(Self.aiFailureCooldown)
                Log.ai.warning("Event classification AI failed (\(error.localizedDescription, privacy: .private)) — falling back to keyword heuristic for \(pendingIndices.count, privacy: .public) event(s); retrying in 10 minutes")
            }
        }

        return zip(summaries, resolved).map { summary, category in
            let resolved = category ?? EventCategory.heuristic(for: summary.title)
            // 客户拍板（2026-07-17）：归类不了的一律按「点赞/大拇指」（Administrative & Routine）
            // 展示，事件卡不留空图标；`0x00` 仍是 wire 合法值（固件不画图标），App 侧不再发送。
            return summary.withCategory(resolved == .unknown ? .admin : resolved)
        }
    }

    private static func cacheKey(for summary: EventSummary) -> String {
        summary.title + "\u{1F}" + summary.description
    }

    nonisolated static func isAIRetryAllowed(retryAfter: Date?, now: Date) -> Bool {
        guard let retryAfter else { return true }
        return now >= retryAfter
    }

    /// 分类输入：标题为主，带非空描述补充语境（"Stretch — stand up every 2 hours"）。
    private static func classificationText(for summary: EventSummary) -> String {
        summary.description.isEmpty ? summary.title : "\(summary.title) — \(summary.description)"
    }
}
